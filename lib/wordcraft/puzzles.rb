# frozen_string_literal: true

module Wordcraft
  # Word puzzles and lexical games.
  #
  #   * anagram detection and grouping (sorted-signature method)
  #   * palindrome detection over word lists
  #   * shortest word ladders via breadth-first search
  #   * rhyme suggestions grouped by phonetic-ish suffix
  #   * small extras: acronyms, pangram checks, letter frequencies
  #
  # Everything works on plain lowercase strings; input words are normalised
  # defensively so callers may pass mixed-case lists.
  module Puzzles
    # Compact built-in dictionary for word ladders. Curated so that the
    # classic "cold -> warm" chain exists (cold-cord-card-ward-warm) while
    # no shorter bridge does, and so that most four-letter words have at
    # least two neighbours.
    DEFAULT_LADDER_WORDS = %w[
      cold cord card ward warm worm word
      bold told gold fold mold bond
      band bend bind find fund fond
      hand land lend sand send sent
      cent dent rent bent lent vent
      went tent text next
      care core bore born corn coin
      join loin main rain pain gain
      cart part port pert
      take make mare mark park
      pace face fact pack back bake
      cake date gate gave cave
      fire firm form fork fort
      more move mode code cope rope
      same sale salt malt melt belt
      bolt boat coat cost most
      team tear year bear beat best
      test rest
      good wood mood moon soon
      ring rink rank tank
      sing sink silk sill
      mild mile mine line fine
      wing wind mind kind king
      past
    ].freeze

    # Normalised, de-duplicated view of {DEFAULT_LADDER_WORDS}: guaranteed
    # lowercase, letters only, no repeats.
    DEFAULT_LADDER_SET = DEFAULT_LADDER_WORDS
                         .map { |w| w.downcase.gsub(/[^a-z]/, '') }
                         .reject(&:empty?)
                         .uniq
                         .freeze

    module_function

    # ------------------------------------------------------------------
    # Anagrams
    # ------------------------------------------------------------------

    # Canonical anagram signature: lowercase letters, sorted.
    #
    # @param word [String]
    # @return [String]
    def anagram_key(word)
      word.to_s.downcase.chars.select { |ch| ch.match?(/[a-z]/) }.sort.join
    end

    # @param a [String] first word
    # @param b [String] second word
    # @return [Boolean] true when the words are anagrams of each other
    def anagrams?(a, b)
      key_a = anagram_key(a)
      key_b = anagram_key(b)
      !key_a.empty? && key_a == key_b && a.to_s.downcase != b.to_s.downcase
    end

    # Groups words by anagram signature.
    #
    # @param words [Array<String>] candidate words
    # @param min_length [Integer] ignore shorter words
    # @return [Hash{String=>Array<String>}] signature => words; only groups
    #   with two or more members are returned; each group is alphabetised
    def anagram_groups(words, min_length: 1)
      groups = words.map(&:to_s)
                    .select { |w| w.length >= min_length }
                    .group_by { |w| anagram_key(w) }
                    .select { |_key, members| members.length > 1 && !_key.empty? }
      groups.each_with_object({}) do |(key, members), result|
        result[key] = members.map(&:downcase).sort.uniq
      end
    end

    # ------------------------------------------------------------------
    # Palindromes
    # ------------------------------------------------------------------

    # Tests a single word or phrase (spaces/punctuation ignored).
    #
    # @param text [String]
    # @return [Boolean]
    def palindrome?(text)
      s = text.to_s.downcase.gsub(/[^a-z0-9]/, '')
      s.length > 1 && s == s.reverse
    end

    # Words (or phrases) from a list that read the same both ways.
    #
    # @param words [Array<String>] candidates
    # @param min_length [Integer] minimum normalised length
    # @return [Array<String>] palindromes in input order, unique
    def palindromes(words, min_length: 3)
      words.map(&:to_s)
           .select do |w|
             s = w.downcase.gsub(/[^a-z0-9]/, '')
             s.length >= min_length && s == s.reverse
           end
           .uniq
    end

    # ------------------------------------------------------------------
    # Word ladders (BFS)
    # ------------------------------------------------------------------

    # Shortest word ladder between two same-length words.
    #
    # A ladder changes exactly one letter per step, and every intermediate
    # word must belong to the dictionary. Breadth-first search guarantees
    # the shortest chain; +max_depth+ bounds the work on pathological graphs.
    #
    # @param start_word [String] e.g. "cold"
    # @param target_word [String] e.g. "warm"
    # @param dictionary [Array<String>, Set<String>, nil] word list; defaults
    #   to the built-in four-letter dictionary
    # @param max_depth [Integer] maximum ladder length to explore
    # @return [Array<String>, nil] the full chain including both endpoints,
    #   or nil when no ladder exists within the limits
    # @raise [Wordcraft::LadderError] when the endpoints are empty or have
    #   different lengths
    def word_ladder(start_word, target_word, dictionary: nil, max_depth: 20)
      start = start_word.to_s.downcase.gsub(/[^a-z]/, '')
      target = target_word.to_s.downcase.gsub(/[^a-z]/, '')
      raise LadderError, 'ladder words must not be empty' if start.empty? || target.empty?
      raise LadderError, "length mismatch: '#{start}' (#{start.length}) vs '#{target}' (#{target.length})" if start.length != target.length

      return [start] if start == target

      source = dictionary || DEFAULT_LADDER_SET
      dict = source.map { |w| w.to_s.downcase.gsub(/[^a-z]/, '') }
                   .reject(&:empty?)
                   .uniq - [start]
      dict.select! { |w| w.length == start.length }

      queue = [[start]]
      visited = { start => true }
      limit = [max_depth.to_i, 2].max

      until queue.empty?
        path = queue.shift
        last = path.last
        return path if last == target
        next if path.length >= limit

        one_letter_neighbors(last, dict).each do |neighbour|
          next if visited.key?(neighbour)

          visited[neighbour] = true
          queue.push(path + [neighbour])
        end
      end
      nil
    end

    # All dictionary words differing from +word+ by exactly one letter.
    #
    # @param word [String] reference word
    # @param candidates [Array<String>] dictionary words
    # @return [Array<String>] neighbours in dictionary order
    def one_letter_neighbors(word, candidates)
      reference = word.chars
      candidates.select do |candidate|
        next false if candidate == word || candidate.length != reference.length

        diff = 0
        candidate.chars.each_with_index do |ch, index|
          diff += 1 if ch != reference[index]
          break if diff > 1
        end
        diff == 1
      end
    end

    # ------------------------------------------------------------------
    # Rhymes
    # ------------------------------------------------------------------

    # Suffix used for rhyme grouping: the last +depth+ letters.
    #
    # @param word [String]
    # @param depth [Integer] suffix length (>= 1)
    # @return [String]
    def rhyme_suffix(word, depth: 3)
      base = word.to_s.downcase.gsub(/[^a-z]/, '')
      depth = [depth.to_i, 1].max
      base.length <= depth ? base : base[-depth..]
    end

    # Words from a candidate list that rhyme with +word+ (shared suffix).
    #
    # @param word [String] reference word
    # @param candidates [Array<String>] words to search
    # @param depth [Integer] suffix length for the rhyme test
    # @return [Array<String>] rhymes, alphabetised, excluding the reference
    def rhymes(word, candidates, depth: 3)
      suffix = rhyme_suffix(word, depth: depth)
      return [] if suffix.empty?

      base = word.to_s.downcase.gsub(/[^a-z]/, '')
      candidates.map { |c| c.to_s.downcase.gsub(/[^a-z]/, '') }
                .uniq
                .select { |c| c != base && c.end_with?(suffix) }
                .sort
    end

    # Groups a word list into rhyme families.
    #
    # @param candidates [Array<String>] words to group
    # @param depth [Integer] suffix length
    # @param min_size [Integer] only families with this many words are kept
    # @return [Hash{String=>Array<String>}] suffix => words
    def rhyme_families(candidates, depth: 3, min_size: 2)
      words = candidates.map { |c| c.to_s.downcase.gsub(/[^a-z]/, '') }.uniq.sort
      groups = words.group_by { |w| rhyme_suffix(w, depth: depth) }
      groups.select { |_suffix, members| members.length >= min_size }
    end

    # ------------------------------------------------------------------
    # Extras
    # ------------------------------------------------------------------

    # Builds an acronym from a phrase (first letter of each word).
    #
    # @param phrase [String]
    # @param skip_stopwords [Boolean] ignore small filler words
    # @return [String] uppercase acronym
    def acronym(phrase, skip_stopwords: false)
      words = phrase.to_s.scan(/[A-Za-z0-9]+/)
      words.reject! { |w| Data.stopword?(w) } if skip_stopwords
      words.map { |w| w[0].upcase }.join
    end

    # @param text [String] candidate pangram
    # @return [Boolean] true when every letter a-z appears at least once
    def pangram?(text)
      text.to_s.downcase.scan(/[a-z]/).uniq.length == 26
    end

    # Letter frequency of a text, descending by count.
    #
    # @param text [String]
    # @param k [Integer] how many letters to return
    # @return [Array<Array(String, Integer)>] [letter, count] pairs
    def letter_frequency(text, k = 26)
      text.to_s.downcase.scan(/[a-z]/).tally.sort_by { |_ch, c| [-c, ch] }.first(k)
    end

    # Finds words containing a double letter ("ll", "ss", ...).
    #
    # @param words [Array<String>]
    # @return [Array<String>] matching words, unique, input order
    def double_letter_words(words)
      words.select { |w| w.to_s.downcase.match?(/([a-z])\1/) }.uniq
    end
  end
end
