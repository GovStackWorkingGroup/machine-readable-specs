#!/usr/bin/env ruby
# frozen_string_literal: true

# Parse a terminology Markdown file and emit individual YAML definition files.
#
# Each definition YAML structure:
#   namespace: urn:govstack:term
#   term: <heading text>
#   definition: >
#     <markdown body as-is>
#   definitionFormat: text/markdown
#
# Usage:
#   ruby scripts/terminology_parser.rb parse \
#     --source data/specs/wallet/contents/3-terminology.md \
#     --out-dir data/specs/wallet/terminology \
#     [--namespace urn:govstack:term]

require 'optparse'
require 'pathname'
require 'fileutils'

$stdout.sync = true

ROOT = Pathname.new(File.expand_path('..', __dir__))
DEFAULT_NAMESPACE = 'urn:govstack:term'

class TerminologyParserCLI
  def initialize(argv)
    @argv = argv.dup
  end

  def run
    cmd = @argv.shift
    case cmd
    when 'parse' then cmd_parse(@argv)
    else
      abort 'Usage: terminology_parser.rb parse --source <file.md> --out-dir <dir> [--namespace urn:govstack:term]'
    end
  end

  private

  def cmd_parse(argv)
    options = {
      source: ROOT.join('data', 'specs', 'wallet', 'contents', '3-terminology.md').to_s,
      out_dir: ROOT.join('data', 'specs', 'wallet', 'terminology').to_s,
      namespace: DEFAULT_NAMESPACE
    }

    opt = OptionParser.new do |o|
      o.on('--source FILE', 'Terminology Markdown file to parse') { |v| options[:source] = v }
      o.on('--out-dir DIR', 'Directory to write YAML definition files') { |v| options[:out_dir] = v }
      o.on('--namespace NS', 'Namespace to include in each YAML (default: urn:govstack:term)') { |v| options[:namespace] = v }
    end
    opt.parse!(argv)

    source = Pathname.new(options[:source])
    abort "Source file not found: #{source}" unless source.exist?

    text = source.read
    text = strip_front_matter(text)
    entries = split_sections(text)

    FileUtils.mkdir_p(options[:out_dir])

    count = 0
    entries.each do |term, body|
      next if term.nil? || term.strip.empty?
      yaml = build_yaml(options[:namespace], term, body)
      fname = File.join(options[:out_dir], slugify(term) + '.yml')
      File.write(fname, yaml)
      count += 1
    end

    out_rel = begin
      Pathname.new(options[:out_dir]).expand_path.relative_path_from(ROOT)
    rescue
      options[:out_dir]
    end
    puts "Wrote #{count} definitions to #{out_rel}"
  end

  def strip_front_matter(text)
    return text unless text.start_with?('---')
    lines = text.lines
    return text if lines[0].strip != '---'
    closing_index = nil
    lines.each_with_index do |line, idx|
      next if idx == 0
      if line.strip == '---'
        closing_index = idx
        break
      end
    end
    return text unless closing_index
    lines[(closing_index + 1)..-1].join
  end

  # Split text into sections keyed by markdown heading starting with "###"
  # Returns array of [term, body]
  def split_sections(text)
    entries = []
    current_term = nil
    current_lines = []

    text.each_line do |line|
      if line.start_with?('### ')
        # Flush previous entry
        if current_term
          body = current_lines.join.rstrip
          body = body.sub(/^\n/, '')
          entries << [current_term, body]
          current_lines = []
        end
        current_term = normalize_term(line.sub(/^###\s+/, '').strip)
      else
        # Skip the main H1 title line
        if line.start_with?('# ')
          next
        else
          current_lines << line
        end
      end
    end
    # Flush last
    if current_term
      body = current_lines.join.rstrip
      body = body.sub(/^\n/, '')
      entries << [current_term, body]
    end
    entries
  end

  def normalize_term(raw)
    # Remove surrounding emphasis markers like **Term**
    s = raw.strip
    s = s.gsub(/^\*\*|\*\*$/, '')
    # Remove leading/trailing asterisks or spaces
    s = s.gsub(/^\*+\s*|\s*\*+$/, '')
    s
  end

  def slugify(term)
    s = term.downcase
    s = s.gsub(/[^a-z0-9]+/, '-')
    s = s.gsub(/-+/, '-')
    s = s.gsub(/^-|-$/, '')
    s
  end

  def build_yaml(namespace, term, body)
    # Use folded style for definition with ">" and indent body by two spaces
    folded = body.split("\n").map { |ln| ln.rstrip.empty? ? '' : ln.rstrip }.join("\n  ")
    <<~YAML
    namespace: #{namespace}
    term: #{term}
    definition: >
      #{body.rstrip.gsub("\n", "\n  ")}
    definitionFormat: text/markdown
    YAML
  end
end

TerminologyParserCLI.new(ARGV).run if __FILE__ == $PROGRAM_NAME
