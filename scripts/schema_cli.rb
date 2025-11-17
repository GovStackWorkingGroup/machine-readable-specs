#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple CLI to generate templates and validate data files against JSON Schemas in ./schemas
# Usage examples:
#   bundle exec ruby scripts/schema_cli.rb list-schemas
#   bundle exec ruby scripts/schema_cli.rb template project --format yaml > data/project.yml
#   bundle exec ruby scripts/schema_cli.rb validate project data/project.yml

require 'json'
require 'yaml'
require 'optparse'
require 'pathname'
require 'json_schemer'
require 'fileutils'

# Ensure stdout is unbuffered so success messages always appear, even when run via tools/CI
$stdout.sync = true

# Resolve project root independent of current working directory
# Using File.expand_path with __dir__ ensures we anchor resolution at this file's directory
ROOT = Pathname.new(File.expand_path('..', __dir__))
SCHEMAS_DIR = ROOT.join('schemas')
TEMPLATES_DIR = ROOT.join('templates')

class SchemaCLI
  def initialize(argv)
    @argv = argv.dup
  end

  def run
    cmd = @argv.shift
    case cmd
    when 'list-schemas' then list_schemas
    when 'template'     then cmd_template(@argv)
    when 'validate'     then cmd_validate(@argv)
    when 'generate-templates' then cmd_generate_templates(@argv)
    else
      warn "Unknown or missing command. Supported: list-schemas, template, validate, generate-templates"
      exit 1
    end
  end

  private

  def list_schemas
    Dir.glob(SCHEMAS_DIR.join('*.json')).sort.each do |path|
      puts File.basename(path)
    end
  end

  def cmd_template(argv)
    options = { format: 'yaml' }
    opt = OptionParser.new do |o|
      o.on('--format FORMAT', %w[yaml json], 'Output format (yaml|json), default: yaml') { |v| options[:format] = v }
      o.on('--include-optional', 'Include non-required properties (default: required only)') { options[:include_optional] = true }
    end
    opt.parse!(argv)

    schema_name_or_path = argv.shift or abort 'Usage: template <schema-name|path> [--format yaml|json] [--include-optional]'
    schema = load_schema(schema_name_or_path)

    template = build_template(schema, include_optional: options[:include_optional])

    if options[:format] == 'json'
      puts JSON.pretty_generate(template)
    else
      puts YAML.dump(template)
    end
  end

  # Generate templates for all schemas into templates/<name>.json and/or templates/<name>.yml
  # Options:
  #   --only json | yml  (default: both)
  #   --out-dir DIR      (default: templates/)
  def cmd_generate_templates(argv)
    options = { out_dir: TEMPLATES_DIR.to_s, only: nil }
    opt = OptionParser.new do |o|
      o.on('--only FORMAT', %w[json yml], 'Generate only one format: json or yml (default: both)') { |v| options[:only] = v }
      o.on('--out-dir DIR', 'Output directory for generated templates (default: templates/)') { |v| options[:out_dir] = v }
    end
    opt.parse!(argv)

    FileUtils.mkdir_p(options[:out_dir])
    schema_paths = Dir.glob(SCHEMAS_DIR.join('*.json')).sort
    count = 0
    schema_paths.each do |schema_path|
      schema = JSON.parse(File.read(schema_path))
      name = File.basename(schema_path, '.json')
      # Always include all fields so templates are complete
      template_obj = build_template(schema, include_optional: true)

      # Write JSON template
      if options[:only].nil? || options[:only] == 'json'
        File.write(File.join(options[:out_dir], "#{name}.json"), JSON.pretty_generate(template_obj))
      end

      # Write YAML template
      if options[:only].nil? || options[:only] == 'yml'
        File.write(File.join(options[:out_dir], "#{name}.yml"), YAML.dump(template_obj))
      end
      count += 1
    end
    generated = case options[:only]
                when 'json' then 'JSON'
                when 'yml' then 'YML'
                else 'JSON and YML'
                end
    rel_out = begin
      Pathname.new(options[:out_dir]).relative_path_from(ROOT)
    rescue
      Pathname.new(options[:out_dir])
    end
    puts "Generated #{generated} templates for #{count} schema#{count == 1 ? '' : 's'} into #{rel_out}"
  end

  def cmd_validate(argv)
    schema_name_or_path = argv.shift or abort 'Usage: validate <schema-name|path> <data-path> [<data-path> ...]'
    data_paths = argv
    abort 'Provide one or more data files to validate' if data_paths.empty?

    # Build a resolver that maps https://example.com/schemas/<name> to local schemas/<name>.json
    http_resolver = JSONSchemer::CachedResolver.new do |uri|
      u = URI(uri)
      if %w[http https].include?(u.scheme)
        name = File.basename(u.path)
        local = SCHEMAS_DIR.join("#{name}.json")
        return JSON.parse(File.read(local)) if File.exist?(local)
      end
      nil
    end

    schema_path = schema_path_for(schema_name_or_path)
    puts "Validating #{data_paths.length} file#{data_paths.length == 1 ? '' : 's'} against schema: #{File.basename(schema_path)}"
    $stdout.flush
    begin
      schemer = JSONSchemer.schema(Pathname.new(schema_path), ref_resolver: http_resolver)
    rescue => e
      puts "ERROR: failed to load schema #{schema_path} -> #{e.class}: #{e.message}"
      $stdout.flush
      exit 2
    end

    all_ok = true
    total_errors = 0
    data_paths.each do |p|
      begin
        obj = load_data(p)
        if schemer.valid?(obj)
          puts "OK: #{p}"
          $stdout.flush
        else
          all_ok = false
          errors = schemer.validate(obj).to_a
          total_errors += errors.length
          puts "FAIL: #{p}"
          $stdout.flush
          errors.each do |e|
            pointer = e['data_pointer']
            type = e['type']
            details = e['details'] || {}
            puts "  - #{type} at #{pointer} #{details.inspect}"
            $stdout.flush
          end
        end
      rescue => e
        all_ok = false
        puts "ERROR: #{p} -> #{e.class}: #{e.message}"
        $stdout.flush
      end
    end

    if all_ok
      puts "All OK (#{data_paths.length} file#{data_paths.length == 1 ? '' : 's'})"
      $stdout.flush
      exit 0
    else
      puts "Validation failed (#{total_errors} error#{total_errors == 1 ? '' : 's'} across #{data_paths.length} file#{data_paths.length == 1 ? '' : 's'})"
      $stdout.flush
      exit 2
    end
  end

  def load_schema(name_or_path)
    path = name_or_path
    unless File.exist?(path)
      # infer from name like 'project' -> schemas/project-schema.json
      candidate = SCHEMAS_DIR.join("#{name_or_path}.json").to_s
      path = candidate if File.exist?(candidate)
    end
    abort "Schema not found: #{name_or_path}" unless File.exist?(path)

    JSON.parse(File.read(path))
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

  def resolve_ref(uri)
    # Resolve refs relative to schemas directory if local file ref without scheme
    u = URI(uri)

    # Helper to build local path from a ref-like path
    to_local = lambda do |path|
      return nil unless path && !path.empty?
      # Strip leading slashes and directories; use basename to avoid nested paths outside schemas/
      name = File.basename(path)
      name = name.end_with?('.json') ? name : "#{name}.json"
      SCHEMAS_DIR.join(name).to_s
    end

    # Case 1: Relative refs (no scheme) like "person.json" or "publication"
    if u.scheme.nil?
      local_path = to_local.call(u.path)
      return JSON.parse(File.read(local_path)) if local_path && File.exist?(local_path)
    end

    # Case 2: HTTP(S) refs that point to canonical IDs (e.g., https://example.com/schemas/person)
    if %w[http https].include?(u.scheme) && u.path
      local_path = to_local.call(u.path)
      return JSON.parse(File.read(local_path)) if local_path && File.exist?(local_path)
    end

    nil
  end

  def build_template(schema, include_optional: false)
    type = schema['type']
    case type
    when 'object'
      props = schema['properties'] || {}
      required = Array(schema['required'])
      keys = include_optional ? props.keys : required
      result = {}
      keys.each do |k|
        subschema = props[k]
        if subschema
          result[k] = default_for(subschema, include_optional: include_optional)
        else
          result[k] = nil
        end
      end
      result
    when 'array'
      []
    else
      default_for(schema, include_optional: include_optional)
    end
  end

  def default_for(subschema, include_optional: false)
    return subschema['default'] if subschema.is_a?(Hash) && subschema.key?('default')

    # Prefer enum first value when present
    if subschema['enum']&.any?
      return subschema['enum'].first
    end

    # Support oneOf with consts
    if subschema['oneOf']&.all? { |s| s.is_a?(Hash) && s.key?('const') }
      return subschema['oneOf'].first['const']
    end

    case subschema['type']
    when 'string' then ''
    when 'integer' then 0
    when 'number' then 0
    when 'boolean' then false
    when 'array'
      items = subschema['items']
      min_items = subschema['minItems'].to_i
      if items
        Array.new([min_items, 0].max) { default_for(items, include_optional: include_optional) }
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

SchemaCLI.new(ARGV).run if __FILE__ == $PROGRAM_NAME
