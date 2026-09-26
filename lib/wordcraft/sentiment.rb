# frozen_string_literal: true

require 'set'

module Wordcraft
  # Lexicon-based sentiment analysis with negation handling and intensifiers.
  #
  # The scorer walks each sentence token by token and keeps a small state:
  #
  #   * a negation window -- when a negator ("not", "never", "isn't", ...) is
  #     seen, the next scored word inside the window has its value flipped;
  #   * an intensity factor -- intensifiers ("very", "extremely", ...) multiply
  #     the value of the next scored word (stackable, capped at 3.0), while
  #     diminishers ("slightly", "fairly", ...) multiply by a factor < 1;
  #   * a contrast reset -- the token "but" clears both, modelling the pivot
  #     that typically cancels the preceding clause's stance.
  #
  #   s = Wordcraft::Sentiment.new
  #   s.analyze('The film was not very good.')[:polarity] # => :negative
  #   s.analyze('An excellent, wonderful release!')[:score] # => 6.0
  #
  # The overall polarity threshold is deliberately conservative: a raw score
  # of at most +/-0.5 counts as neutral, so single weak hits do not dominate.
  class Sentiment
    # Tokens following a negator within this distance are flipped.
    DEFAULT_NEGATION_WINDOW = 3

    # Upper bound for stacked intensifier factors.
    MAX_INTENSITY = 3.0

    # Minimum absolute raw score for a non-neutral verdict.
    POLARITY_THRESHOLD = 0.5

    attr_reader :negation_window

    # @param positive [Hash{String=>Numeric}] override for {Data::POSITIVE}
    # @param negative [Hash{String=>Numeric}] override for {Data::NEGATIVE}
    # @param modifiers [Hash{String=>Float}] override for intensifiers and
    #   diminishers merged together
    # @param negators [Array<String>, Set<String>] override for {Data::NEGATORS}
    # @param negation_window [Integer] tokens a negation stays active for
    def initialize(positive: nil, negative: nil, modifiers: nil, negators: nil,
                   negation_window: DEFAULT_NEGATION_WINDOW)
      @positive = positive || Data::POSITIVE
      @negative = negative || Data::NEGATIVE
      @modifiers = modifiers || Data::MODIFIERS
      @negators = negators ? Set.new(negators.map(&:to_s)) : Data::NEGATOR_SET
      @negation_window = [negation_window.to_i, 1].max
    end

    # Full sentiment analysis of a text, with a per-sentence breakdown.
    #
    # @param text [String] raw text
    # @return [Hash] JSON-safe hash with overall scores and sentence details
    def analyze(text)
      sentences = Tokenizer.sentences(text.to_s)
      breakdown = sentences.map { |sentence| analyze_sentence(sentence) }
      raw = breakdown.sum { |b| b[:score] }
      positive_hits = breakdown.flat_map { |b| b[:positive] }
      negative_hits = breakdown.flat_map { |b| b[:negative] }
      scored = positive_hits.length + negative_hits.length
      words = breakdown.sum { |b| b[:word_count] }

      {
        score: raw.round(2),
        normalized: normalized_score(raw, scored).round(3),
        polarity: classify(raw),
        word_count: words,
        scored_word_count: scored,
        positive_count: positive_hits.length,
        negative_count: negative_hits.length,
        positive_hits: positive_hits,
        negative_hits: negative_hits,
        sentence_count: breakdown.length,
        sentences: breakdown
      }
    end

    # Overall polarity of a text.
    #
    # @param text [String] raw text
    # @return [Symbol] :positive, :negative or :neutral
    def polarity(text)
      classify(analyze(text)[:score])
    end

    # Raw sentiment score of a text.
    #
    # @param text [String] raw text
    # @return [Float] sum of scored word values
    def score(text)
      analyze(text)[:score]
    end

    # Analyses one sentence (used for the breakdown and for testing).
    #
    # @param sentence [String] a single sentence
    # @return [Hash] score, hit lists and token count
    def analyze_sentence(sentence)
      tokens = Tokenizer.words(sentence, downcase: true)
      result = score_tokens(tokens)
      {
        text: sentence,
        score: result[:score].round(2),
        positive: result[:positive],
        negative: result[:negative],
        word_count: tokens.length
      }
    end

    # Scores a raw token stream through the negation/intensifier state
    # machine. Exposed as a public method so custom pipelines can reuse it.
    #
    # @param tokens [Array<String>] lowercased word tokens
    # @return [Hash] :score (Float), :positive and :negative hit arrays
    def score_tokens(tokens)
      score = 0.0
      positive = []
      negative = []
      negation = 0
      intensity = 1.0

      tokens.each do |token|
        if @negators.include?(token)
          negation = @negation_window
          intensity = 1.0
        elsif (factor = @modifiers[token])
          intensity = [intensity * factor, MAX_INTENSITY].min
        elsif token == 'but'
          negation = 0
          intensity = 1.0
        elsif (weight = lookup(token))
          value = weight * intensity
          value = -value if negation.positive?
          score += value
          if value >= 0.0
            positive << token
          else
            negative << token
          end
          negation = 0
          intensity = 1.0
        elsif negation.positive?
          negation -= 1
        end
      end

      { score: score, positive: positive, negative: negative }
    end

    private

    def lookup(word)
      return @positive[word] if @positive.key?(word)
      return @negative[word] if @negative.key?(word)

      nil
    end

    def classify(raw)
      if raw > POLARITY_THRESHOLD
        :positive
      elsif raw < -POLARITY_THRESHOLD
        :negative
      else
        :neutral
      end
    end

    def normalized_score(raw, scored)
      return 0.0 if scored.zero?

      raw / scored
    end
  end
end
