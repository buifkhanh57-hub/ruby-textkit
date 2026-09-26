# frozen_string_literal: true

require 'set'

module Wordcraft
  # Text-similarity and string-distance toolkit.
  #
  # Four classic metrics are provided, each operating on two documents (or
  # two plain strings):
  #
  #   * {jaccard}  -- Jaccard coefficient over word sets:
  #                   |A ∩ B| / |A ∪ B|. 1.0 means identical vocabularies.
  #
  #   * {cosine}   -- cosine similarity over term-frequency vectors:
  #                   dot(A, B) / (|A| * |B|). Angle between the two
  #                   frequency profiles, insensitive to document length.
  #
  #   * {dice}     -- Dice coefficient over word bigram sets:
  #                   2|A ∩ B| / (|A| + |B|). Sensitive to shared word
  #                   order, which the set-based Jaccard ignores.
  #
  #   * {levenshtein} -- classic edit distance via a two-row dynamic
  #                   programming table (insert / delete / substitute, all
  #                   cost 1). O(n*m) time, O(min(n, m)) space; a cell
  #                   budget guards against accidental quadratic blowups.
  #
  # All set/vector metrics normalise through {Tokenizer}: words are
  # lowercased, cleaned and de-duplicated, so 'The Cat' and 'the cat!' are
  # identical inputs. Empty-versus-empty inputs are scored 1.0 (vacuously
  # identical) and empty-versus-nonempty 0.0, for every metric.
  #
  #   a = 'The quick brown fox jumps over the lazy dog'
  #   b = 'The quick brown cat jumps over the lazy dog'
  #   Wordcraft::Compare.compare_texts(a, b)
  #   # => { jaccard: 0.7778, cosine: 0.9091, dice: 0.75,
  #   #      levenshtein: 3, levenshtein_similarity: 0.9302, ... }
  module Compare
    # Metrics that operate on whole documents (word-level). +levenshtein+
    # is character-level and therefore opt-in for CLI use.
    METRICS = %w[jaccard cosine dice levenshtein].freeze

    # Default Levenshtein cell budget: the largest n*m product the DP table
    # will accept before refusing the computation (10 million cells).
    DEFAULT_MAX_CELLS = 10_000_000

    module_function

    # Lowercased, cleaned word vocabulary of a text.
    #
    # @param text [String] raw text
    # @return [Set<String>] unique word set
    def word_set(text)
      Tokenizer.words(text.to_s, downcase: true)
               .map { |w| Tokenizer.clean_word(w) }
               .reject(&:empty?)
               .to_set
    end

    # Term-frequency vector of a text.
    #
    # @param text [String] raw text
    # @return [Hash{String=>Integer}] word => occurrence count
    def term_vector(text)
      Tokenizer.words(text.to_s, downcase: true)
               .map { |w| Tokenizer.clean_word(w) }
               .reject(&:empty?)
               .tally
    end

    # Word-bigram set of a text (adjacent token pairs, order-sensitive).
    #
    # @param text [String] raw text
    # @return [Set<String>] 'word1 word2' pairs
    def word_bigrams(text)
      tokens = Tokenizer.words(text.to_s, downcase: true)
                        .map { |w| Tokenizer.clean_word(w) }
                        .reject(&:empty?)
      tokens.each_cons(2).map { |pair| pair.join(' ') }.to_set
    end

    # Jaccard coefficient of the two word sets.
    #
    # @param text_a [String] first document
    # @param text_b [String] second document
    # @return [Float] 0.0..1.0 (1.0 when both inputs are empty)
    def jaccard(text_a, text_b)
      set_a = word_set(text_a)
      set_b = word_set(text_b)
      return 1.0 if set_a.empty? && set_b.empty?
      return 0.0 if set_a.empty? || set_b.empty?

      (set_a & set_b).size.to_f / (set_a | set_b).size
    end

    # Cosine similarity of the two term-frequency vectors.
    #
    # @param text_a [String] first document
    # @param text_b [String] second document
    # @return [Float] 0.0..1.0 for non-negative term counts
    #   (1.0 when both inputs are empty)
    def cosine(text_a, text_b)
      vec_a = term_vector(text_a)
      vec_b = term_vector(text_b)
      return 1.0 if vec_a.empty? && vec_b.empty?
      return 0.0 if vec_a.empty? || vec_b.empty?

      dot = 0.0
      vec_a.each do |term, count_a|
        count_b = vec_b[term]
        dot += count_a * count_b if count_b
      end
      norm_a = Math.sqrt(vec_a.values.sum { |c| c * c }.to_f)
      norm_b = Math.sqrt(vec_b.values.sum { |c| c * c }.to_f)
      return 0.0 if norm_a.zero? || norm_b.zero?

      dot / (norm_a * norm_b)
    end

    # Dice coefficient over the word-bigram sets of both documents.
    #
    # @param text_a [String] first document
    # @param text_b [String] second document
    # @return [Float] 0.0..1.0 (1.0 when both inputs are empty)
    def dice(text_a, text_b)
      bigrams_a = word_bigrams(text_a)
      bigrams_b = word_bigrams(text_b)
      return 1.0 if bigrams_a.empty? && bigrams_b.empty?
      return 0.0 if bigrams_a.empty? || bigrams_b.empty?

      shared = (bigrams_a & bigrams_b).size
      (2.0 * shared) / (bigrams_a.size + bigrams_b.size)
    end

    # Levenshtein edit distance (insert / delete / substitute, unit costs)
    # computed with a two-row dynamic programming table.
    #
    # The comparison is case-sensitive; callers usually pre-normalise with
    # +Compare.normalize_string+ (the CLI does). Raises {UsageError} when
    # the input pair would exceed the cell budget.
    #
    # @param text_a [String] first string
    # @param text_b [String] second string
    # @param max_cells [Integer] maximum n*m product allowed
    # @return [Integer] minimum number of single-character edits
    # @raise [Wordcraft::UsageError] when the DP table would be too large
    def levenshtein(text_a, text_b, max_cells: DEFAULT_MAX_CELLS)
      a = text_a.to_s
      b = text_b.to_s
      if a.length * b.length > max_cells.to_i
        raise UsageError,
              "levenshtein inputs too large: #{a.length} x #{b.length} characters " \
              "(budget #{max_cells} cells); shorten the texts or drop the " \
              'levenshtein metric'
      end
      return b.length if a.empty?
      return a.length if b.empty?

      previous = (0..b.length).to_a
      a.each_char.with_index(1) do |char_a, i|
        current = [i]
        b.each_char.with_index(1) do |char_b, j|
          substitution = previous[j - 1] + (char_a == char_b ? 0 : 1)
          current << [previous[j] + 1, current[j - 1] + 1, substitution].min
        end
        previous = current
      end
      previous.last
    end

    # Normalised Levenshtein similarity: 1 - distance / max(lengths).
    #
    # @param text_a [String] first string
    # @param text_b [String] second string
    # @param max_cells [Integer] forwarded to {levenshtein}
    # @return [Float] 0.0..1.0 (1.0 when both inputs are empty)
    def levenshtein_similarity(text_a, text_b, max_cells: DEFAULT_MAX_CELLS)
      a = text_a.to_s
      b = text_b.to_s
      longest = [a.length, b.length].max
      return 1.0 if longest.zero?

      1.0 - (levenshtein(a, b, max_cells: max_cells).to_f / longest)
    end

    # Case-folded, whitespace-collapsed view of a string -- the exact
    # normalisation the CLI applies before {levenshtein}.
    #
    # @param text [String] raw text
    # @return [String] lowercased text with collapsed whitespace
    def normalize_string(text)
      text.to_s.downcase.gsub(/\s+/, ' ').strip
    end

    # One-call comparison used by +wordcraft compare+: every document
    # metric plus the character-level Levenshtein pair, all rounded for
    # serialisation.
    #
    # @param text_a [String] first document
    # @param text_b [String] second document
    # @param max_cells [Integer] cell budget forwarded to {levenshtein}
    # @param normalize [Boolean] apply {normalize_string} before the
    #   Levenshtein computation (set +false+ for case-sensitive distances)
    # @return [Hash] JSON-safe snapshot:
    #   :jaccard, :cosine, :dice, :levenshtein, :levenshtein_similarity,
    #   :words_a, :words_b, :shared_words, :unique_a, :unique_b
    def compare_texts(text_a, text_b, max_cells: DEFAULT_MAX_CELLS, normalize: true)
      a = normalize ? normalize_string(text_a) : text_a.to_s
      b = normalize ? normalize_string(text_b) : text_b.to_s
      set_a = word_set(a)
      set_b = word_set(b)

      {
        jaccard: jaccard(a, b).round(4),
        cosine: cosine(a, b).round(4),
        dice: dice(a, b).round(4),
        levenshtein: levenshtein(a, b, max_cells: max_cells),
        levenshtein_similarity: levenshtein_similarity(a, b, max_cells: max_cells).round(4),
        words_a: term_vector(a).values.sum,
        words_b: term_vector(b).values.sum,
        shared_words: (set_a & set_b).size,
        unique_a: set_a.size,
        unique_b: set_b.size
      }
    end
  end
end
