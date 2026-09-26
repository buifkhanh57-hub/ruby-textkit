# frozen_string_literal: true

module Wordcraft
  # Low-level text segmentation utilities.
  #
  # {Tokenizer} is the foundation every other module builds upon. It turns raw
  # text into words, sentences, paragraphs and n-grams, and provides the
  # syllable-counting heuristic used by the readability formulas.
  #
  # The implementation is deliberately "unicode-lite": smart quotes, dashes and
  # ellipses are folded down to their ASCII equivalents before any scanning
  # happens, so the same regexes behave identically on text pasted from Word,
  # LaTeX PDFs or plain ASCII terminals.
  module Tokenizer
    # Sentinel character temporarily substituted for a "." that must NOT be
    # treated as a sentence boundary (abbreviations, decimals). Chosen
    # because it virtually never appears in real prose.
    MARKER = "\u0001"

    # Smart punctuation folded to ASCII before scanning.
    SMART_MAP = {
      "\u2018" => "'",   # left single quote
      "\u2019" => "'",   # right single quote
      "\u201A" => "'",   # single low quote
      "\u201B" => "'",   # single high-reversed quote
      "\u201C" => '"',   # left double quote
      "\u201D" => '"',   # right double quote
      "\u201E" => '"',   # double low quote
      "\u2013" => '-',   # en dash
      "\u2014" => '--',  # em dash
      "\u2212" => '-',   # minus sign
      "\u2026" => '...', # horizontal ellipsis
      "\u00A0" => ' ',   # no-break space
      "\u2007" => ' ',   # figure space
      "\u2009" => ' ',   # thin space
      "\u200B" => '',    # zero width space
      "\u00AD" => ''     # soft hyphen
    }.freeze

    # Abbreviations whose trailing period must not end a sentence.
    # Matched case-insensitively on a word boundary immediately before a dot.
    ABBREVIATIONS = %w[
      mr mrs ms dr prof sr jr st mt ft gen col sgt capt lt cpt rev hon
      pres gov sen rep del asst dept univ inst acad assoc
      etc eg ie cf al vs vid viz no nos vol vols ch chap pp p m fig eq ex
      jan feb mar apr jun jul aug sep sept oct nov dec
    ].freeze

    # Compiled abbreviation pattern, e.g. /\b(?:mr|mrs|dr|...)\./i
    ABBREV_RE = /\b(?:#{ABBREVIATIONS.join('|')})\./i.freeze

    # "3.14"-style decimals: the dot sits between two digits.
    DECIMAL_RE = /(\d)\.(\d)/.freeze

    # A word starts with a letter and continues with letters, apostrophes and
    # hyphens ("don't", "well-known", "can't-stop"). Digits are deliberately
    # excluded so that frequency analysis focuses on lexical items.
    WORD_RE = /[[:alpha:]][[:alpha:]\-']*/.freeze

    # Vowel characters (incl. y) for the syllable heuristic.
    VOWELS = 'aeiouy'.freeze

    # Sentence terminator characters.
    TERMINATORS = '.!?'.freeze

    module_function

    # Folds smart punctuation down to ASCII equivalents.
    #
    # @param text [String] any text
    # @return [String] text with curly quotes, dashes, ellipses normalised
    def normalize(text)
      s = text.to_s
      SMART_MAP.each { |from, to| s = s.gsub(from, to) }
      s
    end

    # Extracts word tokens.
    #
    # Tokens keep their internal apostrophes and hyphens ("isn't",
    # "mother-in-law"). Trailing possessives are NOT stripped here -- use
    # {clean_word} when a bare lexeme is required.
    #
    # @param text [String] raw text
    # @param downcase [Boolean] return lowercased tokens
    # @return [Array<String>] word tokens in order of appearance
    def words(text, downcase: false)
      list = normalize(text).scan(WORD_RE)
      list.map!(&:downcase) if downcase
      list
    end

    # Strips leading/trailing apostrophes and hyphens from a token.
    #
    # @param word [String] a raw token
    # @return [String] cleaned token (possibly empty)
    def clean_word(word)
      word.to_s.gsub(/\A['\-]+|['\-]+\z/, '')
    end

    # Splits text into sentences, abbreviation-aware.
    #
    # Handles the common failure cases of naive splitting:
    #   * "Dr. Smith arrived."        -- abbreviation, not a boundary
    #   * "It costs 3.14 dollars."    -- decimal point, not a boundary
    #   * 'He said "Stop!" and left.' -- terminator inside quotes is kept
    #     attached to the sentence (boundaries require following whitespace)
    #
    # @param text [String] raw text
    # @return [Array<String>] sentences, whitespace-collapsed, in order
    def sentences(text)
      s = normalize(text).gsub(/\r\n?/, "\n")
      s = s.gsub(DECIMAL_RE) { "#{Regexp.last_match(1)}#{MARKER}#{Regexp.last_match(2)}" }
      s = s.gsub(ABBREV_RE) { "#{Regexp.last_match(0)[0..-2]}#{MARKER}" }
      parts = s.split(/(?<=[.!?])["')\]}]*\s+/)
      parts.map { |p| p.gsub(MARKER, '.').gsub(/\s+/, ' ').strip }.reject(&:empty?)
    end

    # Splits text into paragraphs (blocks separated by blank lines).
    #
    # @param text [String] raw text
    # @return [Array<String>] paragraphs, trimmed, in order
    def paragraphs(text)
      normalize(text).gsub(/\r\n?/, "\n")
                     .split(/\n[ \t]*\n/)
                     .map { |p| p.gsub(/[ \t]+/, ' ').strip }
                     .reject(&:empty?)
    end

    # Builds n-grams from a list of tokens.
    #
    # @param tokens [Array<String>] token stream
    # @param n [Integer] gram size (must be >= 1)
    # @param joiner [String] string used to join the tokens of a gram
    # @return [Array<String>] n-grams in order
    # @raise [Wordcraft::UsageError] when n is smaller than 1
    def ngrams(tokens, n, joiner: ' ')
      raise UsageError, "n-gram size must be >= 1 (got #{n})" if n < 1

      tokens.each_cons(n).map { |gram| gram.join(joiner) }
    end

    # Convenience wrapper: n-grams straight from raw text.
    #
    # @param text [String] raw text
    # @param n [Integer] gram size
    # @param downcase [Boolean] lowercase tokens before joining
    # @return [Array<String>] n-grams
    def ngrams_from_text(text, n, downcase: true)
      ngrams(words(text, downcase: downcase), n)
    end

    # Number of words in every sentence, preserving order.
    #
    # @param text [String] raw text
    # @return [Array<Integer>] word counts, one per sentence
    def words_per_sentence(text)
      sentences(text).map { |s| words(s).length }
    end

    # Character classification counts.
    #
    # Categories are mutually exclusive and evaluated in priority order:
    # letters, digits, whitespace, punctuation, everything else.
    #
    # @param text [String] raw text
    # @return [Hash{Symbol=>Integer}] counts keyed by category
    def char_counts(text)
      counts = { letters: 0, digits: 0, spaces: 0, punctuation: 0, other: 0 }
      text.to_s.each_char do |ch|
        key = case ch
              when /[[:alpha:]]/ then :letters
              when /[[:digit:]]/ then :digits
              when /\s/ then :spaces
              when /[[:punct:]]/ then :punctuation
              else :other
              end
        counts[key] += 1
      end
      counts
    end

    # Heuristic English syllable count for a single word.
    #
    # Algorithm (documented honestly -- it is a heuristic):
    #   1. keep letters only, lowercase everything;
    #   2. words of 3 letters or fewer are counted as 1 syllable;
    #   3. trailing "-es"/"-ed" preceded by a consonant are removed
    #      ("makes" -> "mak", "walked" -> "walk");
    #   4. a trailing silent "e" is removed unless the word ends in
    #      consonant+"le" ("table", "little" keep their final syllable);
    #   5. syllables = number of contiguous vowel groups ([aeiouy]+).
    #
    # Known systematic quirks (accepted, and identical across every call):
    #   * "-want-ed"-type endings lose a syllable;
    #   * "idea" counts as 2, "house(s)" as 1.
    #
    # @param word [String] a single word (punctuation tolerated)
    # @return [Integer] syllable estimate, 0 only for empty input
    def syllables(word)
      w = word.to_s.downcase.scan(/[a-z]+/).join
      return 0 if w.empty?
      return 1 if w.length <= 3

      if w.end_with?('es') && w.length >= 4 && !VOWELS.include?(w[-3])
        w = w[0..-3]
      elsif w.end_with?('ed') && w.length >= 4 && !VOWELS.include?(w[-3])
        w = w[0..-3]
      elsif w.end_with?('e') && !w.end_with?('le') && !VOWELS.include?(w[-2])
        w = w[0..-2]
      end

      count = w.scan(/[aeiouy]+/).length
      count >= 1 ? count : 1
    end

    # Total syllables across a word list.
    #
    # @param words [Array<String>] word tokens
    # @return [Integer] summed syllable estimate
    def syllable_count(words)
      words.sum { |w| syllables(w) }
    end

    # Syllable estimate per word, order-preserving.
    #
    # @param words [Array<String>] word tokens
    # @return [Array<Integer>] one estimate per word
    def syllable_map(words)
      words.map { |w| syllables(w) }
    end

    # Number of words with three or more syllables ("polysyllables").
    # Used by SMOG and Gunning Fog.
    #
    # @param words [Array<String>] word tokens
    # @return [Integer] count of polysyllabic words
    def polysyllable_count(words)
      words.sum { |w| syllables(w) >= 3 ? 1 : 0 }
    end

    # Splits text into sentences and returns them paired with their tokens.
    #
    # @param text [String] raw text
    # @param downcase [Boolean] lowercase the extracted tokens
    # @return [Array<Array>] pairs of [sentence_string, token_array]
    def sentences_with_words(text, downcase: true)
      sentences(text).map { |s| [s, words(s, downcase: downcase)] }
    end
  end
end
