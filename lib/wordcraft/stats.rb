# frozen_string_literal: true

require 'bigdecimal'

module Wordcraft
  # Structural statistics for a text: counts, averages, lexical diversity and
  # length distributions.
  #
  #   stats = Wordcraft::TextStats.new(text)
  #   stats.words            # => 128
  #   stats.lexical_diversity # => 0.6328
  #   stats.to_h             # => full snapshot
  #
  # Averages are computed with {BigDecimal} so that repeated divisions over
  # long documents do not accumulate floating-point drift before the final
  # conversion back to Float.
  class TextStats
    attr_reader :text, :words, :sentences, :paragraphs

    # @param text [String] raw text to profile
    def initialize(text)
      @text = text.to_s
      @paragraphs = Tokenizer.paragraphs(@text)
      @sentences = Tokenizer.sentences(@text)
      @words = Tokenizer.words(@text).map { |w| Tokenizer.clean_word(w) }.reject(&:empty?)
      @counts = Tokenizer.char_counts(@text)
      @sentence_words = @sentences.map { |s| Tokenizer.words(s).length }
      @word_counts_memo = {}
    end

    # @return [Integer] total character count including whitespace
    def characters
      @text.length
    end

    # @return [Integer] characters excluding all whitespace
    def characters_without_spaces
      characters - @counts[:spaces]
    end

    # @return [Integer] alphabetic characters
    def letters
      @counts[:letters]
    end

    # @return [Integer] digit characters
    def digits
      @counts[:digits]
    end

    # @return [Integer] punctuation characters
    def punctuation
      @counts[:punctuation]
    end

    # @return [Integer] whitespace characters
    def spaces
      @counts[:spaces]
    end

    # @return [Integer] newline-terminated lines
    def lines
      @text.empty? ? 0 : @text.each_line.count
    end

    # @return [Integer] number of words
    def word_count
      @words.length
    end
    alias words_count word_count

    # @return [Integer] number of distinct words (case-insensitive)
    def unique_words
      @word_counts_memo[:unique] ||= downcased_words.uniq.length
    end

    # @return [Integer] number of sentences
    def sentence_count
      @sentences.length
    end

    # @return [Integer] number of paragraphs
    def paragraph_count
      @paragraphs.length
    end

    # Average word length in characters.
    #
    # @return [Float] 0.0 for an empty text
    def avg_word_length
      return 0.0 if @words.empty?

      (BigDecimal(word_chars_sum.to_s) / word_count).to_f
    end

    # Average sentence length in words.
    #
    # @return [Float] 0.0 for a text without sentences
    def avg_sentence_length
      return 0.0 if sentence_count.zero?

      (BigDecimal(word_count.to_s) / sentence_count).to_f
    end

    # Average sentence length in characters (including spaces).
    #
    # @return [Float] 0.0 for a text without sentences
    def avg_sentence_chars
      return 0.0 if sentence_count.zero?

      total = @sentences.sum(&:length)
      (BigDecimal(total.to_s) / sentence_count).to_f
    end

    # Average paragraph length in sentences.
    #
    # @return [Float] 0.0 for a text without paragraphs
    def avg_paragraph_sentences
      return 0.0 if paragraph_count.zero?

      per_paragraph = @paragraphs.map { |p| Tokenizer.sentences(p).length }
      (BigDecimal(per_paragraph.sum.to_s) / paragraph_count).to_f
    end

    # Standard type-token ratio: unique / total.
    #
    # @return [Float] 0.0 for an empty text
    def lexical_diversity
      return 0.0 if word_count.zero?

      (BigDecimal(unique_words.to_s) / word_count).to_f
    end

    # Root type-token ratio (Guiraud's index): unique / sqrt(total).
    # Compares texts of different lengths more fairly than plain TTR.
    #
    # @return [Float] 0.0 for an empty text
    def root_ttr
      return 0.0 if word_count.zero?

      unique_words / Math.sqrt(word_count)
    end

    # Corrected type-token ratio: unique / sqrt(2 * total).
    #
    # @return [Float] 0.0 for an empty text
    def corrected_ttr
      return 0.0 if word_count.zero?

      unique_words / Math.sqrt(2.0 * word_count)
    end

    # Share of words that occur exactly once.
    #
    # @return [Float] 0.0 for an empty text
    def hapax_ratio
      return 0.0 if word_count.zero?

      hapax_count.to_f / word_count
    end

    # @return [Integer] number of words occurring exactly once
    def hapax_count
      @word_counts_memo[:hapax] ||= downcased_words.tally.values.count { |c| c == 1 }
    end

    # Longest word by character length (first one wins on ties).
    #
    # @return [String, nil]
    def longest_word
      @words.max_by(&:length)
    end

    # Shortest word by character length (first one wins on ties).
    #
    # @return [String, nil]
    def shortest_word
      @words.min_by(&:length)
    end

    # Longest sentence by word count (first one wins on ties).
    #
    # @return [String, nil]
    def longest_sentence
      pairs = @sentences.zip(@sentence_words)
      best = pairs.max_by { |_s, n| n }
      best&.first
    end

    # Word-length histogram: {3=>12, 4=>9, ...}.
    #
    # @return [Hash{Integer=>Integer}] length => count, sorted by length
    def word_length_histogram
      @word_counts_memo[:histogram] ||=
        @words.map(&:length).tally.sort.to_h
    end

    # Sentence-length histogram in words.
    #
    # @return [Hash{Integer=>Integer}] word_count => occurrences, sorted
    def sentence_length_histogram
      @word_counts_memo[:sentence_histogram] ||=
        @sentence_words.tally.sort.to_h
    end

    # Most frequent punctuation characters.
    #
    # @param k [Integer] how many entries to return
    # @return [Array<Array(String, Integer)>] [char, count] pairs
    def top_punctuation(k = 5)
      @text.scan(/[[:punct:]]/).tally.sort_by { |_ch, c| [-c, ch] }.first(k)
    end

    # Serializable snapshot of every metric.
    #
    # @return [Hash] JSON-safe hash with scalar values and small hashes
    def to_h
      {
        characters: characters,
        characters_without_spaces: characters_without_spaces,
        letters: letters,
        digits: digits,
        spaces: spaces,
        punctuation: punctuation,
        lines: lines,
        words: word_count,
        unique_words: unique_words,
        sentences: sentence_count,
        paragraphs: paragraph_count,
        avg_word_length: round2(avg_word_length),
        avg_sentence_length: round2(avg_sentence_length),
        avg_sentence_chars: round2(avg_sentence_chars),
        avg_paragraph_sentences: round2(avg_paragraph_sentences),
        lexical_diversity: round2(lexical_diversity),
        root_ttr: round2(root_ttr),
        corrected_ttr: round2(corrected_ttr),
        hapax_count: hapax_count,
        hapax_ratio: round2(hapax_ratio),
        longest_word: longest_word,
        shortest_word: shortest_word,
        longest_sentence: longest_sentence,
        word_length_histogram: word_length_histogram,
        sentence_length_histogram: sentence_length_histogram,
        top_punctuation: top_punctuation(5)
      }
    end

    private

    def downcased_words
      @word_counts_memo[:downcased] ||= @words.map(&:downcase)
    end

    def word_chars_sum
      @word_counts_memo[:char_sum] ||= @words.join.length
    end

    def round2(value)
      value.is_a?(Float) ? value.round(2) : value
    end
  end
end
