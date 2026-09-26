# frozen_string_literal: true

module Wordcraft
  # Word and phrase frequency analysis with stopword support.
  #
  #   text = File.read('article.txt')
  #   freq = Wordcraft::Frequency.new(text, stopwords: true)
  #   freq.top(5)        # => [["text", 14], ["analysis", 9], ...]
  #   freq.phrases(2, 5) # => [["text analysis", 6], ...]
  #
  # Two token streams are maintained internally:
  #
  #   * +@all_tokens+   -- every word in the text, lowercased, cleaned
  #   * +@tokens+       -- the subset surviving stopword/min-length filters
  #
  # Phrase analysis runs over the filtered stream by default so that the top
  # phrases are content phrases ("text analysis", not "of the analysis"); pass
  # +keep_stopwords: true+ to analyse the raw stream instead.
  class Frequency
    attr_reader :text, :all_tokens, :tokens, :counts, :total_words

    # @param text [String] raw text to analyse
    # @param stopwords [Boolean, Set<String>] +true+ uses the embedded list,
    #   +false+ disables filtering, a Set uses a custom list
    # @param stopwords_file [String, nil] path to a custom stopword list
    #   (one word per line); takes precedence over the embedded list
    # @param min_length [Integer] drop words shorter than this (>= 1)
    # @raise [Wordcraft::FileNotFoundError] when +stopwords_file+ is missing
    # @raise [Wordcraft::ParseError] when the custom stopword file is empty
    def initialize(text, stopwords: true, stopwords_file: nil, min_length: 1)
      @text = text.to_s
      @min_length = [min_length.to_i, 1].max
      @stopword_set = build_stopword_set(stopwords, stopwords_file)
      @all_tokens = Tokenizer.words(@text, downcase: true).map { |w| Tokenizer.clean_word(w) }.reject(&:empty?)
      @tokens = @all_tokens.reject { |w| filter_out?(w) }
      @counts = @tokens.tally
      @total_words = @tokens.length
    end

    # Number of distinct words that survived the filters.
    #
    # @return [Integer]
    def unique_words
      @counts.size
    end

    # Top +k+ words by descending count (ties broken alphabetically).
    #
    # @param k [Integer] how many entries to return
    # @return [Array<Array(String, Integer)>] [word, count] pairs
    def top(k = 10)
      ranked.first(k)
    end

    # Top +k+ n-gram phrases.
    #
    # @param n [Integer] phrase length in words (>= 1)
    # @param k [Integer] how many phrases to return
    # @param keep_stopwords [Boolean] analyse the raw token stream instead
    #   of the filtered one
    # @return [Array<Array(String, Integer)>] [phrase, count] pairs
    def phrases(n = 2, k = 10, keep_stopwords: false)
      source = keep_stopwords ? @all_tokens : @tokens
      Tokenizer.ngrams(source, n).tally.sort_by { |gram, count| [-count, gram] }.first(k)
    end

    # Words co-occurring with +word+ inside a symmetric window.
    #
    # @param word [String] the target word (case-insensitive)
    # @param window [Integer] tokens considered on each side
    # @param k [Integer] how many neighbours to return
    # @return [Array<Array(String, Integer)>] [neighbour, count] pairs
    def co_occurrence(word, window: 2, k: 15)
      target = word.to_s.downcase
      neighbours = []
      limit = window.to_i
      @all_tokens.each_with_index do |token, index|
        next unless token == target

        lo = [index - limit, 0].max
        hi = [index + limit, @all_tokens.length - 1].min
        (lo..hi).each do |j|
          neighbours << @all_tokens[j] unless j == index
        end
      end
      neighbours.reject { |w| w == target }
                .tally
                .sort_by { |w, c| [-c, w] }
                .first(k)
    end

    # Absolute frequency of one word (0 when absent or filtered out).
    #
    # @param word [String] the word to look up
    # @return [Integer]
    def frequency(word)
      @counts.fetch(word.to_s.downcase, 0)
    end

    # Relative frequency of one word across filtered tokens.
    #
    # @param word [String] the word to look up
    # @return [Float] count / total_words (0.0 for an empty text)
    def relative_frequency(word)
      return 0.0 if @total_words.zero?

      frequency(word).to_f / @total_words
    end

    # Frequency-of-frequency distribution: how many words occur exactly once,
    # twice, and so on.
    #
    # @return [Hash{Integer=>Integer}] count => number_of_words
    def distribution
      @counts.values.tally.sort.to_h
    end

    # Words that occur exactly once (hapax legomena).
    #
    # @return [Array<String>] alphabetically sorted
    def hapax_legomena
      @counts.select { |_w, c| c == 1 }.keys.sort
    end

    # Share of the token stream covered by the top +k+ words.
    #
    # @param k [Integer] number of top words to consider
    # @return [Float] 0.0..1.0
    def coverage(k = 10)
      return 0.0 if @total_words.zero?

      covered = ranked.first(k).sum { |_w, c| c }
      covered.to_f / @total_words
    end

    # Type-token ratio of the filtered stream.
    #
    # @return [Float] unique / total (0.0 for an empty text)
    def lexical_diversity
      return 0.0 if @total_words.zero?

      unique_words.to_f / @total_words
    end

    # Serializable snapshot of the analysis.
    #
    # @param k [Integer] how many top entries to embed
    # @return [Hash] JSON-safe hash
    def to_h(k = 10)
      {
        total_words: @total_words,
        unique_words: unique_words,
        lexical_diversity: lexical_diversity.round(4),
        top_words: top(k),
        top_bigrams: phrases(2, k).map { |gram, c| [gram, c] },
        distribution: distribution,
        hapax_count: hapax_legomena.size
      }
    end

    private

    # Ranking helper memoised for repeated +top+/+coverage+ calls.
    def ranked
      @ranked ||= @counts.sort_by { |word, count| [-count, word] }
    end

    def filter_out?(word)
      return true if word.length < @min_length

      @stopword_set ? @stopword_set.include?(word) : false
    end

    def build_stopword_set(stopwords, stopwords_file)
      if stopwords_file
        Data.load_stopwords(stopwords_file)
      elsif stopwords == true
        Data::STOPWORD_SET
      elsif stopwords.is_a?(Set)
        stopwords
      else
        nil
      end
    end
  end
end
