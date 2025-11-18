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
    else
      warn "Unknown or missing command. Supported: list-schemas, validate"
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
end

JsonSchemaValidatorCLI.new(ARGV).run if __FILE__ == $PROGRAM_NAME
