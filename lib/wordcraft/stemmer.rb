# frozen_string_literal: true

module Wordcraft
  # Porter-lite English stemmer with explicit rule tables.
  #
  # This is a faithful, compact re-implementation of the classic Porter
  # stemming algorithm (M.F. Porter, 1980) organised around declarative rule
  # tables rather than scattered conditionals, which makes every step easy to
  # audit and to extend. A few guards are deliberately tightened compared to
  # the original so that very short words are never mangled:
  #
  #   * only words of three or more ASCII letters are stemmed at all;
  #   * the plural rule refuses words ending in "-us", "-is" and "-ss"
  #     ("bus", "this", "class" survive);
  #   * step 1c uses the revised "y preceded by a consonant" condition, so
  #     "day" and "convey" keep their "y".
  #
  #   Wordcraft::Stemmer.stem('running')      # => "run"
  #   Wordcraft::Stemmer.stem('relational')   # => "relat"
  #   Wordcraft::Stemmer.stem('happiness')    # => "happi"
  #   Wordcraft::Stemmer.explain('controlled')[:steps]
  #   # => [{step: "1b", before: "controlled", after: "controll"},
  #   #     {step: "5b", before: "controll",  after: "control"}]
  #
  # The output is a stem, not a dictionary lemma: "studies" becomes "studi",
  # exactly as in the published algorithm. That is fine for frequency
  # grouping, where consistency matters more than prettiness.
  module Stemmer
    # Vowel letters for the measure computation ("y" is handled dynamically).
    VOWELS = %w[a e i o u].freeze

    # Consonants that may not end a *o (CVC) sequence in step 1b / 5a.
    STOP_ENDINGS = %w[w x y].freeze

    # Doubled consonants that collapse after removing "-ing" / "-ed".
    # "ll", "ss" and "ff" are excluded, following the original paper.
    DOUBLE_CONSONANTS = %w[bb dd gg mm nn pp rr tt].freeze

    # Letters that may precede "-ion" for the step 4 deletion rule.
    ION_PRECEDERS = %w[s t].freeze

    # Order in which the steps are applied (and reported by {explain}).
    STEP_ORDER = %w[1a 1b 1c 2 3 4 5a 5b].freeze

    # Step 1a plurals are handled inline in {step1a}: the "-sses"/"-ies"
    # cases come first, "-ss"/"-us"/"-is" are protected, and a bare "-s" is
    # only dropped from words of four letters or more.

    # Step 2: doubled suffixes, applied when the stem has a positive measure.
    # Order matters: longer suffixes first, "ization" before "ation".
    RULES_2 = [
      ['ational', 'ate'], ['tional', 'tion'], ['enci', 'ence'], ['anci', 'ance'],
      ['izer', 'ize'], ['abli', 'able'], ['alli', 'al'], ['entli', 'ent'],
      ['eli', 'e'], ['ousli', 'ous'], ['ization', 'ize'], ['ation', 'ate'],
      ['ator', 'ate'], ['alism', 'al'], ['iveness', 'ive'], ['fulness', 'ful'],
      ['ousness', 'ous'], ['aliti', 'al'], ['iviti', 'ive'], ['biliti', 'ble'],
      ['logi', 'log']
    ].freeze

    # Step 3: suffix replacements that map derivatives onto a shared core.
    RULES_3 = [
      ['icate', 'ic'], ['ative', ''], ['alize', 'al'], ['iciti', 'ic'],
      ['ical', 'ic'], ['ful', ''], ['ness', '']
    ].freeze

    # Step 4: residual suffixes deleted when the stem has measure > 1.
    # "-ion" additionally requires a preceding "s" or "t" (see {step4}).
    RULES_4 = %w[
      al ance ence er ic able ible ant ement ment ent ion ou ism
      ate iti ous ive ize
    ].freeze

    module_function

    # Stems a single word.
    #
    # Non-letters and short words are returned (lowercased) unchanged, so the
    # method is safe to apply to arbitrary tokens.
    #
    # @param word [String] a single word
    # @return [String] the stem
    def stem(word)
      w = prepare(word)
      return w unless stemmable?(w)

      STEP_ORDER.reduce(w) { |current, step| run_step(step, current) }
    end

    # Stems a list of words, order-preserving.
    #
    # @param words [Array<String>] word tokens
    # @return [Array<String>] stems
    def stem_words(words)
      words.map { |w| stem(w) }
    end

    # Stems every whitespace-delimited chunk of a text, keeping the
    # whitespace layout intact.
    #
    # @param text [String] raw text
    # @return [String] text with every word replaced by its stem
    def stem_text(text)
      text.to_s.split(/(\s+)/).map { |chunk| chunk.match?(/\s/) ? chunk : stem(chunk) }.join
    end

    # Full derivation of a word: the final stem plus the trace of every step
    # that changed something. Useful for debugging rules and for teaching.
    #
    # @param word [String] a single word
    # @return [Hash] keys: :original, :stem, :steps
    #   (:steps is an array of {step:, before:, after:} hashes)
    def explain(word)
      w = prepare(word)
      trace = []
      return { original: w, stem: w, steps: trace } unless stemmable?(w)

      current = w
      STEP_ORDER.each do |step|
        result = run_step(step, current)
        next if result == current

        trace << { step: step, before: current, after: result }
        current = result
      end
      { original: w, stem: current, steps: trace }
    end

    # ------------------------------------------------------------------
    # Conditions from the Porter paper
    # ------------------------------------------------------------------

    # Only words of 3+ ASCII letters take part in stemming.
    def stemmable?(word)
      word.match?(/\A[a-z]{3,}\z/)
    end

    # Lowercases and coerces the input.
    def prepare(word)
      word.to_s.downcase
    end

    # @param char [String] one character
    # @return [Boolean] true for a e i o u
    def vowel?(char)
      VOWELS.include?(char)
    end

    # @param char [String] one character
    # @return [Boolean] true for anything that is not a e i o u
    def consonant?(char)
      !vowel?(char)
    end

    # The *v* test: does the stem contain a vowel? ("y" counts, matching the
    # paper's dynamic treatment closely enough for real English words.)
    #
    # @param stem [String] candidate stem
    # @return [Boolean]
    def contains_vowel?(stem)
      stem.match?(/[aeiouy]/)
    end

    # Classification of one letter for the measure computation. "y" is a
    # vowel when the preceding letter is a consonant, a consonant otherwise.
    #
    # @param char [String] the letter to classify
    # @param previous [String, nil] the letter before it (nil at word start)
    # @return [Symbol] :vowel or :consonant
    def kind_of(char, previous)
      return :vowel if vowel?(char)
      return :consonant if char != 'y'

      previous && consonant?(previous) ? :vowel : :consonant
    end

    # Sequence of :vowel / :consonant kinds for a stem.
    #
    # @param stem [String]
    # @return [Array<Symbol>]
    def shape(stem)
      previous = nil
      stem.chars.map do |char|
        kind = kind_of(char, previous)
        previous = char
        kind
      end
    end

    # Porter's measure m: the number of VC sequences in the stem
    # (form: [C](VC)^m[V]). "tree" -> 0, "trouble" -> 1, "oaten" -> 2.
    #
    # @param stem [String]
    # @return [Integer]
    def measure(stem)
      kinds = shape(stem)
      count = 0
      kinds.each_cons(2) { |a, b| count += 1 if a == :vowel && b == :consonant }
      count
    end

    # The *o test: the stem ends consonant-vowel-consonant and the final
    # consonant is not w, x or y ("hop" yes, "hown" no, "toad" no).
    #
    # @param stem [String]
    # @return [Boolean]
    def cvc?(stem)
      return false if stem.length < 3

      last = stem[-1]
      consonant?(stem[-3]) && vowel?(stem[-2]) && consonant?(last) && !STOP_ENDINGS.include?(last)
    end

    # ------------------------------------------------------------------
    # The steps
    # ------------------------------------------------------------------

    # Dispatches one named step (used by {stem} and {explain}).
    #
    # @param step [String] one of {STEP_ORDER}
    # @param word [String] current word form
    # @return [String] word after the step
    def run_step(step, word)
      case step
      when '1a' then step1a(word)
      when '1b' then step1b(word)
      when '1c' then step1c(word)
      when '2' then step2(word)
      when '3' then step3(word)
      when '4' then step4(word)
      when '5a' then step5a(word)
      when '5b' then step5b(word)
      else word
      end
    end

    # Step 1a: plurals. "caresses" -> "caress", "ponies" -> "poni",
    # "cats" -> "cat"; "-ss", "-us", "-is" and 3-letter words are kept.
    def step1a(word)
      return word[0...-4] + 'ss' if word.end_with?('sses')
      return word[0...-3] + 'i' if word.end_with?('ies') && word.length > 3
      return word if word.end_with?('ss')
      return word[0...-1] if word.end_with?('s') && !word.end_with?('us', 'is') && word.length > 3

      word
    end

    # Step 1b: "-eed" -> "-ee" when the stem has a positive measure;
    # "-ed" / "-ing" dropped when the stem contains a vowel, followed by
    # the cleanup rules (at/bl/iz -> ate/ble/ize, doubled consonant collapse,
    # and a final "e" restoration for m=1 CVC stems).
    def step1b(word)
      if word.end_with?('eed')
        stem = word[0...-3]
        return measure(stem).positive? ? stem + 'ee' : word
      end

      stem = strip_ing_or_ed(word)
      return word if stem.nil?

      cleanup_after_1b(stem)
    end

    # Applies "-ed" / "-ing" removal when the remaining stem has a vowel.
    # Internal helper of {step1b}; returns nil when no rule fired.
    def strip_ing_or_ed(word)
      if word.end_with?('ing') && word.length > 4
        candidate = word[0...-3]
        return candidate if contains_vowel?(candidate)
      elsif word.end_with?('ed') && word.length > 3
        candidate = word[0...-2]
        return candidate if contains_vowel?(candidate)
      end
      nil
    end

    # Post-processing shared by the "-ed" / "-ing" deletions.
    # Internal helper of {step1b}.
    def cleanup_after_1b(stem)
      return stem + 'e' if stem.end_with?('at', 'bl', 'iz')

      return stem[0...-1] if stem.length >= 2 && stem[-1] == stem[-2] &&
                             DOUBLE_CONSONANTS.include?(stem[-2, 2])

      return stem + 'e' if measure(stem) == 1 && cvc?(stem)

      stem
    end

    # Step 1c (revised condition): "y" -> "i" when the stem contains a vowel
    # and the "y" follows a consonant. "happy" -> "happi", "sky" -> "sky",
    # "day" -> "day".
    def step1c(word)
      return word unless word.end_with?('y')
      return word unless word.length > 2

      stem = word[0...-1]
      return word unless contains_vowel?(stem)
      return word if vowel?(stem[-1])

      stem + 'i'
    end

    # Step 2: double suffix replacements from {RULES_2} with m(stem) > 0.
    def step2(word)
      apply_rules(word, RULES_2)
    end

    # Step 3: suffix replacements from {RULES_3} with m(stem) > 0.
    def step3(word)
      apply_rules(word, RULES_3)
    end

    # Step 4: delete residual suffixes ({RULES_4}) when m(stem) > 1;
    # "-ion" only goes when a "s" or "t" precedes it.
    def step4(word)
      RULES_4.each do |suffix|
        next unless word.end_with?(suffix)

        stem = word[0...-suffix.length]
        if suffix == 'ion'
          return stem if measure(stem) > 1 && ION_PRECEDERS.include?(stem[-1])

          return word
        end

        return stem if measure(stem) > 1

        return word
      end
      word
    end

    # Step 5a: drop a final "e" when m > 1, or when m == 1 and the stem is
    # not CVC ("probate" -> "probat", "rate" -> "rate", "cease" -> "ceas").
    def step5a(word)
      return word unless word.end_with?('e')

      stem = word[0...-1]
      m = measure(stem)
      return stem if m > 1
      return stem if m == 1 && !cvc?(stem)

      word
    end

    # Step 5b: collapse a final "-ll" when m(stem) > 1
    # ("controll" -> "control", "roll" -> "roll").
    def step5b(word)
      return word unless word.length > 2
      return word unless word[-1] == word[-2] && word[-1] == 'l'
      return word unless measure(word[0...-1]) > 1

      word[0...-1]
    end

    # Applies a [suffix, replacement] table: the first matching rule fires,
    # and only when the stem has a positive measure -- otherwise the step
    # leaves the word untouched (Porter's "longest match wins" semantics).
    #
    # @param word [String] current word form
    # @param rules [Array<Array(String, String)>] ordered rule table
    # @return [String]
    def apply_rules(word, rules)
      rules.each do |suffix, replacement|
        next unless word.end_with?(suffix)

        stem = word[0...-suffix.length]
        return stem + replacement if measure(stem).positive?

        return word
      end
      word
    end
  end
end
