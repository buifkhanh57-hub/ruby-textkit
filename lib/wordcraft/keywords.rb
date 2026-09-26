# frozen_string_literal: true

require 'set'

module Wordcraft
  # Keyword extraction: RAKE-style phrase scoring and TF-IDF term weighting.
  #
  # Two complementary algorithms are provided:
  #
  #   * {Keywords.rake} -- the Rapid Automatic Keyword Extraction heuristic
  #     (Rose et al., 2010). Text is split into candidate phrases at
  #     stopwords and punctuation, every word receives a degree/frequency
  #     score, and each phrase is scored as the sum of its members' scores.
  #     Excellent for surfacing multi-word keyphrases from a single document.
  #
  #   * {Keywords.tfidf} -- classic Term Frequency * Inverse Document
  #     Frequency. The input text is treated as a collection of
  #     pseudo-documents (paragraphs or sentences), terms are weighted by how
  #     concentrated they are in individual pseudo-documents, and the scores
  #     are summed across the collection. Useful for single terms that
  #     dominate specific parts of a long document.
  #
  #   Wordcraft::Keywords.rake('The quick brown fox ...', top: 5)
  #   # => [["quick brown fox", 8.0], ...]
  #
  #   Wordcraft::Keywords.tfidf(long_article, top: 10, unit: :paragraph)
  #   # => [["cassowary", 1.4055], ...]
  module Keywords
    # Default number of keywords returned.
    DEFAULT_TOP = 10

    # Default minimum phrase frequency for the RAKE filter.
    DEFAULT_MIN_FREQUENCY = 1

    # Pseudo-document units accepted by {Keywords.tfidf}.
    UNITS = %w[paragraph sentence].freeze

    # Shared empty set used when stopword filtering is disabled.
    EMPTY_STOPWORD_SET = Set.new.freeze

    module_function

    # Dispatches to the requested extraction algorithm.
    #
    # @param text [String] raw text
    # @param method [Symbol, String] +:rake+ or +:tfidf+
    # @param options [Hash] forwarded to the chosen algorithm
    # @return [Array<Array(String, Float)>] [keyword, score] pairs
    # @raise [Wordcraft::UsageError] for an unknown method
    def extract(text, method: :rake, **options)
      case method.to_s.downcase
      when 'rake' then rake(text, **options)
      when 'tfidf' then tfidf(text, **options)
      else
        raise UsageError, "unknown keyword method: #{method} (expected rake or tfidf)"
      end
    end

    # RAKE keyword extraction over one text.
    #
    # @param text [String] raw text
    # @param top [Integer] how many phrases to return
    # @param stopwords [Set<String>, nil] phrase delimiters; nil disables
    #   stopword splitting (punctuation still splits)
    # @param min_frequency [Integer] drop phrases seen fewer than N times
    # @return [Array<Array(String, Float)>] [phrase, score] pairs, best first
    def rake(text, top: DEFAULT_TOP, stopwords: Data::STOPWORD_SET,
             min_frequency: DEFAULT_MIN_FREQUENCY)
      extractor = Extractor.new(stopwords: stopwords)
      extractor.add(text)
      extractor.top(top, min_frequency: min_frequency)
    end

    # TF-IDF keyword extraction over paragraph- or sentence-sized
    # pseudo-documents. A term's score is the sum over pseudo-documents of
    # tf * idf, with the smoothed idf variant
    # ln((1 + N) / (1 + df)) + 1 so that scores never go negative.
    #
    # @param text [String] raw text
    # @param top [Integer] how many terms to return
    # @param stopwords [Set<String>, nil] terms excluded from the vectors
    # @param unit [Symbol, String] :paragraph or :sentence
    # @return [Array<Array(String, Float)>] [term, score] pairs, best first
    # @raise [Wordcraft::UsageError] for an unknown unit
    def tfidf(text, top: DEFAULT_TOP, stopwords: Data::STOPWORD_SET, unit: :paragraph)
      documents = split_documents(text, unit).map { |doc| term_counts(doc, stopwords) }
      documents.reject!(&:empty?)
      return [] if documents.empty?

      doc_count = documents.size
      document_frequency = Hash.new(0)
      documents.each do |counts|
        counts.each_key { |term| document_frequency[term] += 1 }
      end

      totals = Hash.new(0.0)
      documents.each do |counts|
        total = counts.values.sum.to_f
        next if total.zero?

        counts.each do |term, count|
          tf = count / total
          idf = Math.log((1 + doc_count).to_f / (1 + document_frequency[term])) + 1.0
          totals[term] += tf * idf
        end
      end

      totals.map { |term, score| [term, score.round(4)] }
            .sort_by { |term, score| [-score, term] }
            .first(top)
    end

    # Splits raw text into pseudo-documents for {tfidf}.
    #
    # @param text [String] raw text
    # @param unit [Symbol, String] :paragraph or :sentence
    # @return [Array<String>] non-empty document units
    # @raise [Wordcraft::UsageError] for an unknown unit
    def split_documents(text, unit)
      documents = case unit.to_s.downcase
                  when 'paragraph' then Tokenizer.paragraphs(text.to_s)
                  when 'sentence' then Tokenizer.sentences(text.to_s)
                  else
                    raise UsageError,
                          "unknown keyword unit: #{unit} (expected #{UNITS.join(' or ')})"
                  end
      documents.reject(&:empty?)
    end

    # Term-frequency hash for one document unit.
    #
    # @param document [String] a paragraph or sentence
    # @param stopwords [Set<String>, nil] terms to exclude
    # @return [Hash{String=>Integer}] term => count
    def term_counts(document, stopwords)
      tokens = Tokenizer.words(document, downcase: true)
                       .map { |w| Tokenizer.clean_word(w) }
                       .reject(&:empty?)
      tokens.reject! { |w| stopwords.include?(w) } if stopwords
      tokens.tally
    end

    # Reusable RAKE engine. Collects candidate phrases across any number of
    # {add} calls, then scores them on demand -- handy when keywords should
    # be computed over a stream of documents.
    class Extractor
      attr_reader :candidates

      # @param stopwords [Set<String>, nil] phrase delimiters; nil disables
      #   stopword splitting
      def initialize(stopwords: Data::STOPWORD_SET)
        @stopwords = stopwords || EMPTY_STOPWORD_SET
        @candidates = []
        @word_scores = nil
      end

      # Feeds one text into the candidate pool.
      #
      # @param text [String] raw text
      # @return [self] for chaining
      def add(text)
        Tokenizer.sentences(text.to_s).each do |sentence|
          @candidates.concat(candidate_phrases(sentence))
        end
        @word_scores = nil
        self
      end

      # All candidate phrases, flattened and joined.
      #
      # @return [Array<String>] one entry per candidate occurrence
      def phrases
        @phrases ||= @candidates.map { |phrase| phrase.join(' ') }
      end

      # RAKE word scores: degree(w) / frequency(w), where degree accumulates
      # the co-membership count (phrase length minus one) of every candidate
      # the word appears in.
      #
      # @return [Hash{String=>Float}]
      def word_scores
        @word_scores ||= begin
          frequency = Hash.new(0)
          degree = Hash.new(0)
          @candidates.each do |phrase|
            phrase.each do |word|
              frequency[word] += 1
              degree[word] += phrase.length - 1
            end
          end
          scores = {}
          frequency.each_key do |word|
            scores[word] = frequency[word].zero? ? 0.0 : degree[word].to_f / frequency[word]
          end
          scores
        end
      end

      # Ranks unique phrases by summed word score. Ties prefer the more
      # frequent phrase, then the alphabetically smaller one.
      #
      # @param k [Integer] how many phrases to return
      # @param min_frequency [Integer] drop phrases seen fewer than N times
      # @return [Array<Array(String, Float)>] [phrase, score] pairs
      def top(k = DEFAULT_TOP, min_frequency: DEFAULT_MIN_FREQUENCY)
        min = [min_frequency.to_i, 1].max
        counts = phrases.tally
        counts.select { |_phrase, count| count >= min }
              .map { |phrase, count| [phrase, phrase_score(phrase), count] }
              .sort_by { |phrase, score, count| [-score, -count, phrase] }
              .first(k)
              .map { |phrase, score, _count| [phrase, score.round(4)] }
      end

      private

      # Sum of the member word scores for one phrase.
      def phrase_score(phrase)
        phrase.split(' ').sum { |word| word_scores.fetch(word, 0.0) }
      end

      # Splits one sentence into candidate phrases: maximal runs of
      # non-stopword tokens. Punctuation and digits are dropped by the
      # tokeniser; a stopword (or the sentence end) closes a phrase.
      def candidate_phrases(sentence)
        groups = []
        current = []
        sentence.scan(/[\p{Word}']+/) do |token|
          word = Tokenizer.clean_word(token.downcase)
          if word.empty?
            next
          elsif stopword?(word)
            groups << current unless current.empty?
            current = []
          else
            current << word
          end
        end
        groups << current unless current.empty?
        groups
      end

      def stopword?(word)
        @stopwords.include?(word)
      end
    end
  end
end
