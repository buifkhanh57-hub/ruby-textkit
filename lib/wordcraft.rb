# frozen_string_literal: true

module Wordcraft
  # Library entry point.
  #
  # Requiring this single file loads the complete toolkit:
  #
  #   require 'wordcraft'
  #   Wordcraft::Tokenizer.words('Hello there!')
  #   Wordcraft::Readability.new(text).summary
  #   Wordcraft::Sentiment.new.analyze(text)[:polarity]
  #
  # Only Ruby standard-library dependencies are used (set, json, csv,
  # optparse, bigdecimal), so the gem installs with zero external gems.
  require 'set'
  require 'json'
  require 'csv'
  require 'optparse'
  require 'bigdecimal'

  require_relative 'wordcraft/version'
  require_relative 'wordcraft/errors'
  require_relative 'wordcraft/data/stopwords'
  require_relative 'wordcraft/data/lexicon'
  require_relative 'wordcraft/tokenizer'
  require_relative 'wordcraft/frequency'
  require_relative 'wordcraft/readability'
  require_relative 'wordcraft/sentiment'
  require_relative 'wordcraft/stats'
  require_relative 'wordcraft/transform'
  require_relative 'wordcraft/stemmer'
  require_relative 'wordcraft/keywords'
  require_relative 'wordcraft/compare'
  require_relative 'wordcraft/puzzles'
  require_relative 'wordcraft/report'
  require_relative 'wordcraft/cli'

  # Library metadata reused by the gemspec and the CLI banner.
  NAME = 'wordcraft'

  module_function

  # One-call convenience analysers: runs every analyser once and returns a
  # JSON-serialisable hash combining all results.
  #
  # @param text [String] raw text
  # @param top [Integer] number of top words to embed
  # @param stopwords [Boolean] filter stopwords for the frequency section
  # @return [Hash] keys: :meta, :stats, :readability, :sentiment, :frequency
  def self.analyze(text, top: 10, stopwords: true)
    stats = TextStats.new(text)
    readability = Readability.new(text)
    sentiment = Sentiment.new.analyze(text)
    frequency = Frequency.new(text, stopwords: stopwords)

    {
      meta: {
        generator: "wordcraft #{VERSION}",
        characters: stats.characters,
        words: stats.word_count,
        sentences: stats.sentence_count,
        paragraphs: stats.paragraph_count
      },
      stats: stats.to_h,
      readability: readability.summary,
      sentiment: sentiment,
      frequency: {
        total_words: frequency.total_words,
        unique_words: frequency.unique_words,
        top_words: frequency.top(top)
      }
    }
  end

  # Absolute path of the installed library directory.
  #
  # @return [String]
  def self.root
    File.expand_path('..', __dir__)
  end
end
