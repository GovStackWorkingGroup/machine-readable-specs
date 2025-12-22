#!/usr/bin/env ruby
# frozen_string_literal: true

# Parse Markdown files declaring namespace: urn:govstack:spec:kdf
# and produce a JSON file with:
# - order: array of identifiers
# - functionalities: array of {identifier, title, level, content}
#
# Identifier rule: identifier = spec-uri + "/kdf/" + number
# Content: verbatim text after YAML front matter ends
#
# Usage:
#   bundle exec ruby scripts/kdf_parser.rb parse \
#     --root data/specs/wallet/kdf \
#     --out data/specs/wallet/functionalities.json
#   # Optional: --namespace urn:govstack:spec:kdf (default)

require 'json'
require 'yaml'
require 'optparse'
require 'pathname'
require 'fileutils'

$stdout.sync = true

ROOT = Pathname.new(File.expand_path('..', __dir__))
DEFAULT_NAMESPACE = 'urn:govstack:spec:kdf'

class KDFParserCLI
  def initialize(argv)
    @argv = argv.dup
  end

  def run
    cmd = @argv.shift
    case cmd
    when 'parse' then cmd_parse(@argv)
    else
      abort 'Usage: kdf_parser.rb parse --root <dir> --out <file> [--namespace urn:govstack:spec:kdf]'
    end
  end

  private

  def cmd_parse(argv)
    options = { root: ROOT.join('data', 'specs').to_s, out: ROOT.join('data', 'specs', 'functionalities.json').to_s, namespace: DEFAULT_NAMESPACE }
    opt = OptionParser.new do |o|
      o.on('--root DIR', 'Root directory to search for .md files (default: data/specs)') { |v| options[:root] = v }
      o.on('--out FILE', 'Output JSON file (default: data/specs/functionalities.json)') { |v| options[:out] = v }
      o.on('--namespace NS', 'Namespace to match (default: urn:govstack:spec:kdf)') { |v| options[:namespace] = v }
    end
    opt.parse!(argv)

    root_dir = Pathname.new(options[:root])
    abort "Root directory not found: #{root_dir}" unless root_dir.exist?

    md_files = Dir.glob(root_dir.join('**', '*.md')).sort
    indexed = []

    md_files.each do |path|
      fm, content = parse_front_matter_and_body(File.read(path))
      next unless fm && fm['namespace'] == options[:namespace]
      number = fm['number']
      spec_uri = fm['spec-uri'] || fm['spec_uri']
      title = fm['title']
      level = fm['level']
      reqs = Array(fm['requirements'])

      next if spec_uri.nil? || number.nil?
      ident = build_identifier(spec_uri, number)

      func = {
        'identifier' => ident,
        'title' => title.to_s,
        'level' => level.to_s,
        'content' => content.to_s
      }

      unless reqs.empty?
        func['requirements'] = reqs.filter_map do |r|
          next unless r.is_a?(Hash)
          rnum = r['number']
          rlev = r['level']
          rdesc = r['description']
          rop = r['operationId']
          next if rnum.nil?
          {
            'identifier' => [ident, 'req', rnum.to_s].join('/'),
            'level' => rlev.to_s,
            'description' => markdown_to_html(rdesc.to_s),
            'operationId' => rop.to_s
          }
        end
      end

      # Store alongside a natural sort key derived from the front-matter number
      indexed << [natural_key(number), func]
    end

    # Sort by natural numeric order of 'number' (handles 1..11 and tokens like 6_1)
    functionalities = indexed.sort_by { |k, _f| k }.map { |_, f| f }
    order = functionalities.map { |f| f['identifier'] }

    output = {
      'order' => order,
      'functionalities' => functionalities
    }

    FileUtils.mkdir_p(File.dirname(options[:out]))
    File.write(options[:out], JSON.pretty_generate(output))
    out_rel = begin
      Pathname.new(options[:out]).expand_path.relative_path_from(ROOT)
    rescue
      options[:out]
    end
    puts "Wrote #{functionalities.size} functionalities to #{out_rel}"
  end

  def parse_front_matter_and_body(text)
    # Expect YAML front matter delimited by --- on its own line at the start
    return [nil, text] unless text.start_with?('---')
    # Find the closing --- after the opening
    lines = text.lines
    return [nil, text] if lines[0].strip != '---'
    # Locate the next line that is exactly ---
    closing_index = nil
    lines.each_with_index do |line, idx|
      next if idx == 0
      if line.strip == '---'
        closing_index = idx
        break
      end
    end
    return [nil, text] unless closing_index
    yaml_str = lines[1..(closing_index - 1)].join
    body = lines[(closing_index + 1)..-1].join
    begin
      fm = YAML.safe_load(yaml_str, aliases: true)
    rescue => _e
      fm = nil
    end
    [fm, body]
  end

  def build_identifier(spec_uri, number)
    base = spec_uri.to_s.sub(%r{/*$}, '')
    num = number.to_s
    # Ensure number formatting (e.g., 6_1.md yields "6_1") stays intact
    [base, 'kdf', num].join('/')
  end

  def natural_key(value)
    return [value] if value.is_a?(Numeric)
    s = value.to_s
    nums = s.scan(/\d+/).map(&:to_i)
    return nums unless nums.empty?
    [Float::INFINITY, s]
  end

  # Very lightweight Markdown to HTML for inline links [text](url)
  # Extend as needed; keeps other text verbatim
  def markdown_to_html(text)
    return '' if text.nil?
    # Convert [label](url) to <a href="url">label</a>
    html = text.gsub(/\[([^\]]+)\]\(([^)]+)\)/, '<a href="\2">\1</a>')
    html
  end
end

KDFParserCLI.new(ARGV).run if __FILE__ == $PROGRAM_NAME
