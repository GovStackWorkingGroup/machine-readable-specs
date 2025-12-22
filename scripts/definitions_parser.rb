#!/usr/bin/env ruby
# frozen_string_literal: true

# Build a consolidated JSON definitions file from YAML terms.
#
# Reads YAML entries from data/specs/wallet/terminology and produces
# data/specs/wallet/definitions.json as an array of term definitions.
#
# Each JSON entry:
# {
#   "urn": "urn:govstack:term:NOT IMPLEMENTED",
#   "uri": "https://wallet.govstack.global/spec/1/term/n",
#   "term": "...",
#   "definition": "...",
#   "definitionFormat": "text/markdown"
# }
#
# The base spec URI is derived from wallet.yml if available, falling back to
# https://wallet.govstack.global/spec/1.

require 'optparse'
require 'pathname'
require 'fileutils'
require 'yaml'
require 'json'

$stdout.sync = true

ROOT = Pathname.new(File.expand_path('..', __dir__))
DEFAULT_TERMS_DIR = ROOT.join('data', 'specs', 'wallet', 'terminology')
DEFAULT_WALLET_YML = ROOT.join('data', 'specs', 'wallet', 'wallet.yml')
DEFAULT_OUT = ROOT.join('data', 'specs', 'wallet', 'definitions.json')

class DefinitionsParserCLI
  def initialize(argv)
    @argv = argv.dup
  end

  def run
    cmd = @argv.shift
    case cmd
    when 'parse' then cmd_parse(@argv)
    else
      abort 'Usage: definitions_parser.rb parse [--terms-dir DIR] [--wallet FILE] [--out FILE]'
    end
  end

  private

  def cmd_parse(argv)
    options = {
      terms_dir: DEFAULT_TERMS_DIR.to_s,
      wallet: DEFAULT_WALLET_YML.to_s,
      out: DEFAULT_OUT.to_s
    }

    opt = OptionParser.new do |o|
      o.on('--terms-dir DIR', 'Directory containing YAML term definitions') { |v| options[:terms_dir] = v }
      o.on('--wallet FILE', 'Wallet YAML file to derive base spec URI') { |v| options[:wallet] = v }
      o.on('--out FILE', 'Output JSON file (default: data/specs/wallet/definitions.json)') { |v| options[:out] = v }
    end
    opt.parse!(argv)

    terms_dir = Pathname.new(options[:terms_dir])
    wallet_file = Pathname.new(options[:wallet])
    out_file = Pathname.new(options[:out])

    abort "Terms directory not found: #{terms_dir}" unless terms_dir.directory?

    base_spec_uri = derive_base_spec_uri(wallet_file)
    base_spec_uri ||= 'https://wallet.govstack.global/spec/1'

    yaml_files = Dir.glob(terms_dir.join('*.yml')).sort
    abort "No YAML term files found in #{terms_dir}" if yaml_files.empty?

    entries = []
    yaml_files.each_with_index do |path, idx|
      data = safe_load_yaml(File.read(path))
      term = data['term'].to_s
      definition = data['definition'].to_s
      definition_format = (data['definitionFormat'] || 'text/markdown').to_s
      # Remove any leading blank lines from the definition
      definition = definition.gsub(/\A(?:\r\n|\r|\n)+/, '')

      n = idx + 1
      uri = [base_spec_uri.sub(%r{/*$}, ''), 'term', n].join('/')

      entries << {
        'urn' => 'urn:govstack:term:NOT IMPLEMENTED',
        'uri' => uri,
        'term' => term,
        'definition' => definition,
        'definitionFormat' => definition_format
      }
    end

    FileUtils.mkdir_p(out_file.dirname)
    File.write(out_file, JSON.pretty_generate(entries))
    out_rel = begin
      out_file.expand_path.relative_path_from(ROOT)
    rescue
      out_file.to_s
    end
    puts "Wrote #{entries.size} definitions to #{out_rel}"
  end

  def derive_base_spec_uri(wallet_file)
    return nil unless wallet_file.exist?
    data = safe_load_yaml(wallet_file.read)
    # Try common keys where spec URI might be stored
    base = data['spec-uri'] || data['spec_uri'] || data['base_uri'] || data['uri']
    return base if base && !base.to_s.empty?
    # If version is present, compose default
    ver = data['version'] || data['spec_version']
    ver = ver.to_s.strip
    return "https://wallet.govstack.global/spec/#{ver}" unless ver.empty?
    nil
  end

  def safe_load_yaml(text)
    YAML.safe_load(text, aliases: true) || {}
  rescue
    {}
  end
end

DefinitionsParserCLI.new(ARGV).run if __FILE__ == $PROGRAM_NAME
