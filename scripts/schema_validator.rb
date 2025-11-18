#!/usr/bin/env ruby
# frozen_string_literal: true

# Alternative validator using the json-schema gem instead of json_schemer
# Usage examples:
#   bundle exec ruby scripts/schema_validator_json_schema.rb list-schemas
#   bundle exec ruby scripts/schema_validator_json_schema.rb validate specification samples/specification.json
#   bundle exec ruby scripts/schema_validator_json_schema.rb validate person samples/person.json

require 'json'
require 'yaml'
require 'optparse'
require 'pathname'
require 'json-schema'
require 'addressable/uri'

# Ensure stdout is unbuffered so success messages always appear, even when run via tools/CI
$stdout.sync = true

ROOT = Pathname.new(File.expand_path('..', __dir__))
SCHEMAS_DIR = ROOT.join('schemas')

class JsonSchemaValidatorCLI
  def initialize(argv)
    @argv = argv.dup
  end

  def run
    cmd = @argv.shift
    case cmd
    when 'list-schemas' then list_schemas
    when 'validate'     then cmd_validate(@argv)
    when 'template'     then cmd_template(@argv)
    when 'generate-templates' then cmd_generate_templates(@argv)
    else
      warn "Unknown or missing command. Supported: list-schemas, validate, template, generate-templates"
      exit 1
    end
  end

  private

  def list_schemas
    Dir.glob(SCHEMAS_DIR.join('*.json')).sort.each do |path|
      puts File.basename(path)
    end
  end

  def cmd_validate(argv)
    options = { }
    opt = OptionParser.new do |o|
      o.on('--summary-only', 'Print only requirements summary, skip validation') { options[:summary_only] = true }
    end
    opt.parse!(argv)

    schema_name_or_path = argv.shift or abort 'Usage: validate <schema-name|path> <data-path> [<data-path> ...]'
    data_paths = argv
    abort 'Provide one or more data files to validate' if data_paths.empty?

    # Load all schemas and register them with json-schema by their $id and friendly paths
    registry = preload_schema_registry

    schema_path = schema_path_for(schema_name_or_path)
    puts "Validating #{data_paths.length} file#{data_paths.length == 1 ? '' : 's'} against schema: #{File.basename(schema_path)}"

  raw_schema = JSON.parse(File.read(schema_path))
  raw_schema = ensure_meta_schema(raw_schema)

    # Print requirements summary (best-effort allOf flattening)
    summary = merge_all_of(raw_schema) || raw_schema
    req_list = Array(summary['required']).map(&:to_s)
    puts "Requirements: #{req_list.empty? ? 'none' : req_list.join(', ')}"

    return if options[:summary_only]

    all_ok = true
    total_errors = 0

    data_paths.each do |p|
      begin
        obj = load_data(p)
        # Use fully_validate to collect errors; errors_as_objects for structured info
  errors = JSON::Validator.fully_validate(raw_schema, obj, errors_as_objects: true)
        if errors.empty?
          puts "OK: #{p}"
        else
          all_ok = false
          total_errors += errors.length
          puts "FAIL: #{p}"
          errors.first(10).each do |e|
            fragment = e[:fragment]
            message = e[:message]
            failed = e[:failed_attribute]
            puts "  - #{failed} at #{fragment} #{message}"
          end
        end
      rescue JSON::Schema::SchemaError => e
        all_ok = false
        puts "ERROR: #{p} -> Schema error: #{e.message}"
      rescue => e
        all_ok = false
        puts "ERROR: #{p} -> #{e.class}: #{e.message}"
      end
    end

    if all_ok
      puts "All OK (#{data_paths.length} file#{data_paths.length == 1 ? '' : 's'})"
      exit 0
    else
      puts "Validation failed (#{total_errors} error#{total_errors == 1 ? '' : 's'} across #{data_paths.length} file#{data_paths.length == 1 ? '' : 's'})"
      exit 2
    end
  end

  def preload_schema_registry
    Dir.glob(SCHEMAS_DIR.join('*.json')).sort.each do |schema_path|
      begin
        schema = JSON.parse(File.read(schema_path))
        schema = ensure_meta_schema(schema)
        add_schema_aliases(schema, schema_path)
      rescue => e
        warn "WARN: Skipping schema registry load for #{File.basename(schema_path)}: #{e.message}"
      end
    end
  end

  def add_schema_aliases(schema, schema_path)
    # Primary ID from $id if present
    primary_id = schema['$id']
    basename = File.basename(schema_path, '.json')

    # Helper to add a schema under a given URI
    add = lambda do |uri_str|
      next if uri_str.nil? || uri_str.empty?
      begin
        uri = Addressable::URI.parse(uri_str)
        JSON::Validator.add_schema(JSON::Schema.new(schema, uri))
      rescue => _e
        # ignore duplicate or invalid URI entries
      end
    end

    add.call(primary_id)
    # Friendly aliases to match common $ref forms in this repo
    add.call("https://example.com/schemas/#{basename}") unless primary_id == "https://example.com/schemas/#{basename}"
    add.call("/schemas/#{basename}")
    add.call("/schemas/#{basename}.json")

    # Also register the local file path as a file:// URI for good measure
    add.call(Pathname.new(schema_path).realpath.to_s)
  end

  def schema_path_for(name_or_path)
    path = name_or_path
    unless File.exist?(path)
      candidate = SCHEMAS_DIR.join("#{name_or_path}.json").to_s
      path = candidate if File.exist?(candidate)
    end
    abort "Schema not found: #{name_or_path}" unless File.exist?(path)
    path
  end

  def load_data(path)
    case File.extname(path).downcase
    when '.yaml', '.yml' then YAML.safe_load(File.read(path), permitted_classes: [Date, Time], aliases: true)
    when '.json' then JSON.parse(File.read(path))
    else
      abort "Unsupported data file type: #{path} (use .yaml/.yml or .json)"
    end
  end

  # Simple top-level allOf flattener for summary purposes only (not a full JSON Schema merger)
  def merge_all_of(schema)
    return schema unless schema.is_a?(Hash)
    return schema unless schema['allOf'].is_a?(Array)

    merged_props = {}
    merged_required = []

    schema['allOf'].each do |component|
      c = deref_if_ref(component)
      if c['properties']
        merged_props.merge!(c['properties'])
      end
      if c['required']
        merged_required |= c['required']
      end
    end

    if schema['properties']
      merged_props.merge!(schema['properties'])
    end
    if schema['required']
      merged_required |= schema['required']
    end

    {
      'type' => schema['type'] || 'object',
      'properties' => merged_props,
      'required' => merged_required
    }
  end

  def deref_if_ref(node)
    return node unless node.is_a?(Hash) && node['$ref']
    ref = node['$ref']
    # Try to resolve by local basename through schemas dir
    begin
      u = Addressable::URI.parse(ref)
      name = File.basename(u.path)
      name = name.end_with?('.json') ? name : "#{name}.json"
      local_path = SCHEMAS_DIR.join(name)
      if File.exist?(local_path)
        return JSON.parse(File.read(local_path))
      end
    rescue
      # ignore and fall back below
    end
    node
  end

  # json-schema gem does not auto-fetch draft 2020-12 meta-schema; we can ignore meta validation by removing $schema
  # or downgrade to draft-07 (which it supports). We'll strip unknown $schema to avoid fatal errors.
  def ensure_meta_schema(schema)
    return schema unless schema.is_a?(Hash)
    if schema['$schema'] && schema['$schema'].include?('2020-12')
      # Remove to skip meta-schema validation entirely
      schema = schema.dup
      schema.delete('$schema')
    end
    schema
  end

  # ---------------- Template Generation ----------------

  def cmd_template(argv)
    options = { format: 'yaml', include_optional: false }
    opt = OptionParser.new do |o|
      o.on('--format FORMAT', %w[yaml json], 'Output format (yaml|json) default: yaml') { |v| options[:format] = v }
      o.on('--include-optional', 'Include non-required properties') { options[:include_optional] = true }
    end
    opt.parse!(argv)

    schema_name_or_path = argv.shift or abort 'Usage: template <schema-name|path> [--format yaml|json] [--include-optional]'
    schema_path = schema_path_for(schema_name_or_path)
    raw = ensure_meta_schema(JSON.parse(File.read(schema_path)))
    merged = merge_all_of(raw)
    tmpl = build_template(merged, include_optional: options[:include_optional])
    if options[:format] == 'json'
      puts JSON.pretty_generate(tmpl)
    else
      puts YAML.dump(tmpl)
    end
  end

  def cmd_generate_templates(argv)
    options = { out_dir: ROOT.join('templates').to_s, only: nil, include_optional: true }
    opt = OptionParser.new do |o|
      o.on('--out-dir DIR', 'Output directory (default: templates/)') { |v| options[:out_dir] = v }
      o.on('--only FORMAT', %w[json yml], 'Generate only one format: json or yml') { |v| options[:only] = v }
      o.on('--required-only', 'Generate templates with only required properties') { options[:include_optional] = false }
    end
    opt.parse!(argv)
    FileUtils.mkdir_p(options[:out_dir])
    count = 0
    Dir.glob(SCHEMAS_DIR.join('*.json')).sort.each do |schema_path|
      begin
        raw = ensure_meta_schema(JSON.parse(File.read(schema_path)))
        merged = merge_all_of(raw)
        tmpl = build_template(merged, include_optional: options[:include_optional])
        base = File.basename(schema_path, '.json')
        if options[:only].nil? || options[:only] == 'json'
          File.write(File.join(options[:out_dir], "#{base}.json"), JSON.pretty_generate(tmpl))
        end
        if options[:only].nil? || options[:only] == 'yml'
          File.write(File.join(options[:out_dir], "#{base}.yml"), YAML.dump(tmpl))
        end
        count += 1
      rescue => e
        warn "WARN: template generation skipped for #{File.basename(schema_path)}: #{e.message}"
      end
    end
    which = case options[:only]
            when 'json' then 'JSON'
            when 'yml' then 'YML'
            else 'JSON and YML'
            end
    mode = options[:include_optional] ? 'all fields' : 'required only'
    rel_out = begin
      Pathname.new(options[:out_dir]).relative_path_from(ROOT)
    rescue
      options[:out_dir]
    end
    puts "Generated #{which} templates (#{mode}) for #{count} schema#{count == 1 ? '' : 's'} into #{rel_out}"
  end

  # Build a template hash from a merged schema (object root assumed)
  def build_template(schema, include_optional: false)
    return {} unless schema.is_a?(Hash)
    if schema['type'] == 'object'
      props = schema['properties'] || {}
      required = Array(schema['required'])
      keys = include_optional ? props.keys : required
      result = {}
      keys.each do |k|
        sub = props[k]
        result[k] = default_for(sub, include_optional: include_optional)
      end
      result
    elsif schema['type'] == 'array'
      []
    else
      default_for(schema, include_optional: include_optional)
    end
  end

  def default_for(subschema, include_optional: false)
    return nil unless subschema.is_a?(Hash)
    return subschema['default'] if subschema.key?('default')
    if subschema['enum']&.any?
      return subschema['enum'].first
    end
    case subschema['type']
    when 'string' then ''
    when 'integer' then 0
    when 'number' then 0
    when 'boolean' then false
    when 'array'
      items = subschema['items']
      if items
        [default_for(items, include_optional: include_optional)].compact
      else
        []
      end
    when 'object'
      build_template(subschema, include_optional: include_optional)
    else
      nil
    end
  end
end

JsonSchemaValidatorCLI.new(ARGV).run if __FILE__ == $PROGRAM_NAME
