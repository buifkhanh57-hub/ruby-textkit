# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'wordcraft/version'

Gem::Specification.new do |spec|
  spec.name = 'wordcraft'
  spec.version = Wordcraft::Version::VERSION
  spec.authors = ['Bui Bao Khanh']
  spec.email = ['buifkhanh57-hub@users.noreply.github.com']

  spec.summary = Wordcraft::Version::SUMMARY
  spec.description = <<-DESCRIPTION
    A stdlib-only Ruby text-analysis toolkit: word and n-gram frequency,
    six readability formulas, lexicon-based sentiment, structural text
    statistics, case/slug/HTML transforms, a full Porter stemmer, RAKE and
    TF-IDF keyword extraction, document similarity (Jaccard, cosine, Dice,
    Levenshtein) and word puzzles -- driven by a single `wordcraft` CLI or
    used as a library.
  DESCRIPTION
  spec.homepage = Wordcraft::Version::HOMEPAGE
  spec.license = Wordcraft::Version::LICENSE

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/releases"
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.required_ruby_version = '>= 3.0'

  spec.files = Dir.glob('lib/**/*.rb') +
               %w[LICENSE README.md Rakefile]
  spec.bindir = 'bin'
  spec.executables = %w[wordcraft]
  spec.require_paths = ['lib']

  # The runtime has zero dependencies; only the test-suite tooling below.
  spec.add_development_dependency 'minitest', '~> 5.0'
  spec.add_development_dependency 'rake', '~> 13.0'
end
