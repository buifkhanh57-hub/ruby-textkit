# frozen_string_literal: true

module Wordcraft
  # Gem identity information.
  #
  # Version data lives in its own file so that +wordcraft.gemspec+ can read it
  # without loading (and paying the parse cost of) the entire library. Keep
  # this module dependency-free: only plain constants are allowed here.
  module Version
    # Semantic version components.
    MAJOR = 1
    MINOR = 0
    PATCH = 0

    # Full version string, e.g. +"1.0.0"+.
    VERSION = [MAJOR, MINOR, PATCH].join('.').freeze

    # Human-readable release codename (kept stable across patch releases).
    CODENAME = 'Quill'.freeze

    # Short summary used by the gemspec, +gem search+ and the CLI banner.
    SUMMARY = 'Professional text-analysis toolkit: frequency, readability, ' \
              'sentiment, statistics, transforms and word puzzles'.freeze

    # Homepage used by the gemspec and the help banner.
    HOMEPAGE = 'https://github.com/buifkhanh57-hub/wordcraft'.freeze

    # SPDX license identifier.
    LICENSE = 'MIT'.freeze

    # @return [String] e.g. "wordcraft 1.0.0 (Quill)"
    def self.label
      "wordcraft #{VERSION} (#{CODENAME})"
    end
  end

  # Convenience alias so callers may simply write +Wordcraft::VERSION+.
  VERSION = Version::VERSION
end
