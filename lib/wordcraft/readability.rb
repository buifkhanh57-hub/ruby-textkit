# frozen_string_literal: true

module Wordcraft
  # Classical readability formulas.
  #
  # All six formulas operate on the same precomputed counters:
  #
  #   * words            -- alphabetic tokens
  #   * sentences        -- abbreviation-aware segmentation
  #   * syllables        -- heuristic syllable estimate per word
  #   * polysyllables    -- words with 3+ syllables
  #   * letters          -- alphabetic characters
  #   * characters       -- letters + digits (ARI convention)
  #
  # Formula constants (standard, textbook values):
  #
  #   Flesch Reading Ease   206.835 - 1.015*ASL - 84.6*ASW
  #   Flesch-Kincaid Grade  0.39*ASL + 11.8*ASW - 15.59
  #   Gunning Fog           0.4*(ASL + 100*complex_words/words)
  #   SMOG (simplified)     1.0430*sqrt(polysyl*30/sentences) + 3.1291
  #   Coleman-Liau          0.0588*L - 0.296*S - 15.8      (per 100 words)
  #   ARI                   4.71*chars/words + 0.5*ASL - 21.43
  #
  # where ASL = words/sentences and ASW = syllables/words.
  #
  # Every formula returns +nil+ (not an exception) when the text is too small
  # to evaluate, and callers decide how to render that case.
  class Readability
    # Formula identifiers offered by {#scores}.
    FORMULAS = %i[flesch flesch_kincaid gunning_fog smog coleman_liau ari].freeze

    attr_reader :text, :sentences, :words

    # @param text [String] raw text to assess
    def initialize(text)
      @text = text.to_s
      @sentences = Tokenizer.sentences(@text)
      @words = Tokenizer.words(@text, downcase: true)
      @sentence_count = @sentences.length
      @word_count = @words.length
      @syllable_counts = Tokenizer.syllable_map(@words)
      @syllable_total = @syllable_counts.sum
      @polysyllables = @syllable_counts.count { |s| s >= 3 }
      char_info = Tokenizer.char_counts(@text)
      @letters = char_info[:letters]
      @characters = char_info[:letters] + char_info[:digits]
    end

    # @return [Integer] number of words
    def word_count
      @word_count
    end

    # @return [Integer] number of sentences
    def sentence_count
      @sentence_count
    end

    # @return [Integer] summed syllable estimate
    def syllable_count
      @syllable_total
    end

    # @return [Integer] words with three or more syllables
    def polysyllable_count
      @polysyllables
    end

    # Average sentence length (words per sentence).
    #
    # @return [Float, nil]
    def avg_sentence_length
      return nil if @sentence_count.zero?

      @word_count.to_f / @sentence_count
    end

    # Average word length in syllables.
    #
    # @return [Float, nil]
    def avg_syllables_per_word
      return nil if @word_count.zero?

      @syllable_total.to_f / @word_count
    end

    # Flesch Reading Ease (higher = easier; 0-100 typical range).
    #
    # @return [Float, nil] nil when there are no words or sentences
    def flesch
      return nil if unusable?

      206.835 - (1.015 * avg_sentence_length) - (84.6 * avg_syllables_per_word)
    end

    # Flesch-Kincaid Grade Level (US school grade).
    #
    # @return [Float, nil]
    def flesch_kincaid_grade
      return nil if unusable?

      (0.39 * avg_sentence_length) + (11.8 * avg_syllables_per_word) - 15.59
    end

    # Gunning Fog index. "Complex" words are those with three or more
    # syllables (the standard simplified variant).
    #
    # @return [Float, nil]
    def gunning_fog
      return nil if unusable?

      complex_ratio = 100.0 * @polysyllables / @word_count
      0.4 * (avg_sentence_length + complex_ratio)
    end

    # SMOG index (Simple Measure of Gobbledygook), simplified variant:
    # 1.0430 * sqrt(polysyllables * 30 / sentences) + 3.1291.
    # The original McLaughlin protocol samples 30 sentences; this variant
    # rescales the polysyllable count instead, which is the common
    # implementation choice for short texts.
    #
    # @return [Float, nil]
    def smog
      return nil if @sentence_count.zero?

      1.0430 * Math.sqrt(@polysyllables * (30.0 / @sentence_count)) + 3.1291
    end

    # Coleman-Liau index. Uses letters per 100 words (L) and sentences per
    # 100 words (S) -- the only formula driven by character counts rather
    # than syllable estimates.
    #
    # @return [Float, nil]
    def coleman_liau
      return nil if unusable?

      l = 100.0 * @letters / @word_count
      s = 100.0 * @sentence_count / @word_count
      (0.0588 * l) - (0.296 * s) - 15.8
    end

    # Automated Readability Index. Characters here means letters + digits,
    # following the original S.E. Smith (1967) definition.
    #
    # @return [Float, nil]
    def ari
      return nil if unusable?

      (4.71 * @characters.to_f / @word_count) + (0.5 * avg_sentence_length) - 21.43
    end
    alias automated_readability_index ari

    # All grade-level formulas at once.
    #
    # @return [Hash{Symbol=>Float,nil}]
    def scores
      {
        flesch_kincaid: flesch_kincaid_grade,
        gunning_fog: gunning_fog,
        smog: smog,
        coleman_liau: coleman_liau,
        ari: ari
      }
    end

    # Median of the five grade-level scores -- a robust "consensus" estimate.
    #
    # @return [Float, nil]
    def consensus_grade
      values = scores.values.compact.sort
      return nil if values.empty?

      mid = values.length / 2
      if values.length.odd?
        values[mid]
      else
        (values[mid - 1] + values[mid]) / 2.0
      end
    end

    # Interprets a Flesch Reading Ease score.
    #
    # @param score [Float, nil]
    # @return [String] human-readable band label
    def self.flesch_band(score)
      return 'insufficient data' if score.nil?

      case score
      when 90.. then 'very easy (5th grade)'
      when 80...90 then 'easy (6th grade)'
      when 70...80 then 'fairly easy (7th grade)'
      when 60...70 then 'plain English (8th-9th grade)'
      when 50...60 then 'fairly difficult (10th-12th grade)'
      when 30...50 then 'difficult (college)'
      when 10...30 then 'very difficult (college graduate)'
      else 'extremely difficult (professional)'
      end
    end

    # Interprets a grade-level score (FK, Fog, SMOG, Coleman-Liau, ARI).
    #
    # @param grade [Float, nil]
    # @return [String] human-readable band label
    def self.grade_band(grade)
      return 'insufficient data' if grade.nil?

      case grade
      when -Float::INFINITY...1.0 then 'below 1st grade'
      when 1.0...3.0 then '1st-2nd grade'
      when 3.0...5.0 then '3rd-4th grade'
      when 5.0...7.0 then '5th-6th grade'
      when 7.0...9.0 then '7th-8th grade (middle school)'
      when 9.0...13.0 then '9th-12th grade (high school)'
      when 13.0...16.0 then 'college'
      when 16.0...19.0 then 'college graduate'
      else 'post-graduate / professional'
      end
    end

    # Full serializable snapshot, including every formula and its band.
    #
    # @return [Hash] JSON-safe hash
    def summary
      cg = consensus_grade
      {
        counts: {
          words: @word_count,
          sentences: @sentence_count,
          syllables: @syllable_total,
          polysyllables: @polysyllables,
          letters: @letters,
          characters: @characters,
          avg_sentence_length: round2(avg_sentence_length),
          avg_syllables_per_word: round2(avg_syllables_per_word)
        },
        flesch: round2(flesch),
        flesch_band: self.class.flesch_band(flesch),
        flesch_kincaid_grade: round2(flesch_kincaid_grade),
        gunning_fog: round2(gunning_fog),
        smog: round2(smog),
        coleman_liau: round2(coleman_liau),
        ari: round2(ari),
        consensus_grade: round2(cg),
        consensus_band: self.class.grade_band(cg)
      }
    end

    # Flat [label, value, band] rows used by the CLI table renderer.
    #
    # @return [Array<Array(String, Object, String)>]
    def formula_rows
      [
        ['Flesch Reading Ease', round2(flesch), self.class.flesch_band(flesch)],
        ['Flesch-Kincaid Grade', round2(flesch_kincaid_grade), self.class.grade_band(flesch_kincaid_grade)],
        ['Gunning Fog', round2(gunning_fog), self.class.grade_band(gunning_fog)],
        ['SMOG', round2(smog), self.class.grade_band(smog)],
        ['Coleman-Liau', round2(coleman_liau), self.class.grade_band(coleman_liau)],
        ['ARI', round2(ari), self.class.grade_band(ari)]
      ]
    end

    private

    def unusable?
      @word_count.zero? || @sentence_count.zero?
    end

    def round2(value)
      value.is_a?(Float) ? value.round(2) : value
    end
  end
end
