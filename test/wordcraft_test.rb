# frozen_string_literal: true

require 'minitest/autorun'
require 'json'
require 'tempfile'
require_relative '../lib/wordcraft'

# Full unit suite for the Wordcraft toolkit.
#
# Run with:
#
#   rake test                     # or
#   ruby -Ilib -Itest test/wordcraft_test.rb
#
# Only Ruby standard libraries are required (minitest ships with Ruby).
class WordcraftTest < Minitest::Test
  include Wordcraft # brings Tokenizer, UsageError, Compare, ... into scope

  SAMPLE = 'Hello world. Hello there.'

  # ------------------------------------------------------------------
  # Tokenizer
  # ------------------------------------------------------------------

  def test_tokenizer_words
    assert_equal %w[Hello there], Tokenizer.words('Hello there!')
    assert_equal ["it's", 'a', 'well-known', 'fact'],
                 Tokenizer.words("It's a well-known fact", downcase: true)
  end

  def test_tokenizer_sentences_are_abbreviation_and_decimal_aware
    assert_equal ['Hi there.', 'How are you?'], Tokenizer.sentences('Hi there. How are you?')
    assert_equal ['It costs 3.14 dollars.'], Tokenizer.sentences('It costs 3.14 dollars.')
    assert_equal ['Dr. Smith arrived.'], Tokenizer.sentences('Dr. Smith arrived.')
  end

  def test_tokenizer_paragraphs
    assert_equal ['One.', 'Two.', 'Three.'], Tokenizer.paragraphs("One.\n\nTwo.\n\nThree.")
  end

  def test_tokenizer_ngrams
    assert_equal ['a b', 'b c'], Tokenizer.ngrams(%w[a b c], 2)
    assert_raises(UsageError) { Tokenizer.ngrams(%w[a b], 0) }
  end

  def test_tokenizer_syllable_heuristic
    assert_equal 2, Tokenizer.syllables('table')
    assert_equal 1, Tokenizer.syllables('makes')
    assert_equal 1, Tokenizer.syllables('cat')
    assert_equal 2, Tokenizer.syllables('idea') # documented quirk
    assert_equal 0, Tokenizer.syllables('')
  end

  def test_tokenizer_char_counts_and_normalization
    counts = Tokenizer.char_counts('Hi! 42')
    assert_equal 2, counts[:letters]
    assert_equal 2, counts[:digits]
    assert_equal 1, counts[:punctuation]
    assert_equal 1, counts[:spaces]
    assert_equal '"Hi"--ok...', Tokenizer.normalize("\u201CHi\u201D\u2014ok\u2026")
    assert_equal "don't", Tokenizer.clean_word("'don't'")
  end

  # ------------------------------------------------------------------
  # Frequency
  # ------------------------------------------------------------------

  def test_frequency_top_and_counts
    freq = Frequency.new('the cat sat on the mat. the cat.')
    assert_equal [['cat', 2], ['mat', 1], ['sat', 1]], freq.top(3)
    assert_equal 4, freq.total_words
    assert_equal 3, freq.unique_words
    assert_in_delta 0.75, freq.lexical_diversity
    assert_in_delta 0.5, freq.relative_frequency('cat')
    assert_equal 0, freq.frequency('the') # stopword-filtered stream
  end

  def test_frequency_without_stopwords
    freq = Frequency.new('the cat sat on the mat. the cat.', stopwords: false)
    assert_equal [['the', 3], ['cat', 2]], freq.top(2)
    assert_equal 8, freq.total_words
  end

  def test_frequency_phrases_distribution_and_cooccurrence
    freq = Frequency.new('the cat sat on the mat. the cat.')
    assert_equal [['cat sat', 1], ['mat cat', 1]], freq.phrases(2, 2)
    assert_equal({ 1 => 2, 2 => 1 }, freq.distribution)
    assert_equal %w[mat sat], freq.hapax_legomena
    assert_in_delta 0.5, freq.coverage(1)
    assert_equal [['the', 2], ['sat', 1]], freq.co_occurrence('cat', window: 1)
  end

  # ------------------------------------------------------------------
  # TextStats
  # ------------------------------------------------------------------

  def test_text_stats_counts
    stats = TextStats.new(SAMPLE)
    assert_equal 4, stats.word_count
    assert_equal 3, stats.unique_words
    assert_equal 2, stats.sentence_count
    assert_equal 1, stats.paragraph_count
    assert_equal 25, stats.characters
    assert_equal 23, stats.characters_without_spaces
    assert_equal 5.0, stats.avg_word_length
    assert_equal 2.0, stats.avg_sentence_length
    assert_in_delta 0.75, stats.lexical_diversity
    assert_in_delta 1.5, stats.root_ttr
    assert_equal 'Hello', stats.longest_word
    assert_equal({ 5 => 4 }, stats.word_length_histogram)
    assert_equal({ 2 => 2 }, stats.sentence_length_histogram)
  end

  def test_text_stats_to_h_is_json_safe
    hash = TextStats.new(SAMPLE).to_h
    assert_equal 4, hash[:words]
    assert_equal 5.0, hash[:avg_word_length]
    assert JSON.parse(JSON.generate(hash))
  end

  # ------------------------------------------------------------------
  # Readability
  # ------------------------------------------------------------------

  def test_readability_counters
    r = Readability.new('Hello world. Hi there again.')
    assert_equal 5, r.word_count
    assert_equal 2, r.sentence_count
    assert_equal 8, r.syllable_count
    assert_equal 0, r.polysyllable_count
  end

  def test_readability_formulas_match_hand_computed_values
    r = Readability.new('Hello world. Hi there again.')
    # ASL = 5/2 = 2.5, ASW = 8/5 = 1.6, letters = 22
    assert_in_delta 68.94, r.flesch, 0.01                # 206.835 - 1.015*2.5 - 84.6*1.6
    assert_in_delta 4.27, r.flesch_kincaid_grade, 0.01   # 0.39*2.5 + 11.8*1.6 - 15.59
    assert_in_delta 1.0, r.gunning_fog, 0.01             # 0.4*(2.5 + 0)
    assert_in_delta 3.13, r.smog, 0.01                   # 1.0430*sqrt(0) + 3.1291
    assert_in_delta -1.77, r.coleman_liau, 0.01          # 0.0588*440 - 0.296*40 - 15.8
    assert_in_delta 0.54, r.ari, 0.01                    # 4.71*22/5 + 1.25 - 21.43
  end

  def test_readability_summary_bands_and_consensus
    summary = Readability.new('Hello world. Hi there again.').summary
    assert_equal 68.94, summary[:flesch]
    assert_equal 'plain English (8th-9th grade)', summary[:flesch_band]
    assert_in_delta 1.0, summary[:consensus_grade], 0.01 # median of the five grades
    assert_equal '1st-2nd grade', summary[:consensus_band]
    assert_equal 5, summary[:counts][:words]
  end

  def test_readability_insufficient_data_returns_nil_scores
    r = Readability.new('')
    assert_nil r.flesch
    assert_nil r.consensus_grade
    assert_equal 'insufficient data', Readability.flesch_band(nil)
  end

  # ------------------------------------------------------------------
  # Sentiment
  # ------------------------------------------------------------------

  def test_sentiment_scores_and_polarity
    s = Sentiment.new
    assert_equal 3.0, s.analyze('excellent')[:score]
    assert_equal :positive, s.analyze('excellent')[:polarity]
    assert_in_delta(-1.0, s.analyze('good but terrible')[:score])
    assert_equal :negative, s.analyze('good but terrible')[:polarity]
    assert_equal :neutral, s.analyze('')[:polarity]
  end

  def test_sentiment_negation_and_intensifiers
    s = Sentiment.new
    result = s.score_tokens(%w[not good])
    assert_in_delta(-2.0, result[:score])
    assert_equal %w[good], result[:negative]
    # "not very good": good (2) * very (1.75) = 3.5, flipped by the negator
    assert_in_delta(-3.5, s.score_tokens(%w[not very good])[:score])
    assert_equal :negative, s.polarity('The film was not very good.')
  end

  def test_sentiment_normalized_score
    s = Sentiment.new
    assert_in_delta 3.0, s.analyze('excellent excellent')[:normalized]
    assert_equal 0.0, s.analyze('')['score']
    assert_equal 6.0, s.analyze('An excellent, wonderful release!')[:score]
  end

  # ------------------------------------------------------------------
  # Transform
  # ------------------------------------------------------------------

  def test_transform_case_and_identifiers
    assert_equal 'HELLO', Transform.upper('hello')
    assert_equal 'AbC', Transform.swap('aBc')
    assert_equal 'hello_world_example', Transform.snake_case('Hello World Example')
    assert_equal 'hello-world-example', Transform.kebab_case('Hello World Example')
    assert_equal 'helloWorld', Transform.camel_case('hello world')
    assert_equal 'HelloWorld', Transform.pascal_case('hello world')
  end

  def test_transform_title_sentence_slug_and_cleanup
    assert_equal 'The Lord of the Rings', Transform.title_case('the lord of the rings')
    assert_equal 'Hello there. Ok', Transform.sentence_case('hello there. ok')
    assert_equal 'hello-world', Transform.slugify('Héllo — World!')
    assert_equal 'cafe', Transform.strip_accents('café')
    assert_equal 'Hello world', Transform.strip_html('<p>Hello <b>world</b></p>')
    assert_equal "one two\nthree", Transform.wrap('one two three', width: 7)
    assert_equal 'abcd...', Transform.truncate('abcdefghij', 7)
    assert_equal 'a b', Transform.collapse_whitespace("a \t b")
  end

  def test_transform_lite_stemmer
    assert_equal 'study', Transform.stem('studies')
    assert_equal 'run', Transform.stem('running')
    assert_equal 'make', Transform.stem('making')
    assert_equal 'cat run', Transform.stem_text('Cats running')
  end

  # ------------------------------------------------------------------
  # Stemmer (full Porter)
  # ------------------------------------------------------------------

  def test_porter_stemmer_known_words
    assert_equal 'run', Stemmer.stem('running')
    assert_equal 'relat', Stemmer.stem('relational')
    assert_equal 'happi', Stemmer.stem('happiness')
    assert_equal 'cat', Stemmer.stem('cats')
    assert_equal 'connect', Stemmer.stem('connections')
    assert_equal 'control', Stemmer.stem('controlled')
    assert_equal 'bus', Stemmer.stem('bus')     # -us is protected
    assert_equal 'day', Stemmer.stem('day')     # revised 1c keeps the y
    assert_equal 'agreed', Stemmer.stem('agreed')
  end

  def test_porter_stemmer_explain_trace
    trace = Stemmer.explain('controlled')
    assert_equal 'control', trace[:stem]
    assert_equal [{ step: '1b', before: 'controlled', after: 'controll' },
                  { step: '5b', before: 'controll', after: 'control' }], trace[:steps]
  end

  def test_porter_stemmer_skips_short_and_non_alpha_words
    assert_equal 'x2y', Stemmer.stem('X2y')
    assert_equal 'cat   run', Stemmer.stem_text('CAT   running') # layout preserved
  end

  # ------------------------------------------------------------------
  # Keywords
  # ------------------------------------------------------------------

  def test_rake_extraction
    rows = Keywords.rake('The quick brown fox. The lazy dog', top: 5)
    assert_equal [['quick brown fox', 6.0], ['lazy dog', 2.0]], rows
  end

  def test_tfidf_extraction_over_sentences
    rows = Keywords.tfidf('the cat sat. the cat ran. dogs bark', unit: :sentence, top: 3)
    assert_equal [['cat', 1.2877], ['bark', 0.8466], ['dogs', 0.8466]], rows
  end

  def test_tfidf_over_paragraphs
    rows = Keywords.tfidf("the cat sat\n\ndogs bark", unit: :paragraph, top: 2)
    assert_equal [['bark', 0.7027], ['cat', 0.7027]], rows
  end

  def test_keywords_dispatch_and_reusable_extractor
    assert_raises(UsageError) { Keywords.extract('x', method: 'bogus') }

    extractor = Keywords::Extractor.new
    extractor.add('quick brown fox').add('The lazy dog')
    assert_equal [['quick brown fox', 6.0], ['lazy dog', 2.0]], extractor.top(2)
  end

  # ------------------------------------------------------------------
  # Compare
  # ------------------------------------------------------------------

  def test_jaccard
    assert_in_delta 0.5, Compare.jaccard('a b c', 'b c d')
    assert_in_delta 1.0, Compare.jaccard('', '')
    assert_in_delta 0.0, Compare.jaccard('', 'word')
    assert_equal Compare.word_set('The Cat'), Compare.word_set('the cat!')
  end

  def test_cosine
    assert_in_delta 0.8, Compare.cosine('a b a', 'a b b')
    assert_in_delta 1.0, Compare.cosine('same text', 'same text')
    assert_in_delta 0.0, Compare.cosine('a', 'b')
  end

  def test_dice_bigram
    assert_in_delta 0.6667, Compare.dice('one two three four', 'one two three five'), 0.001
    assert Compare.word_bigrams('hello world today').include?('hello world')
    assert_empty Compare.word_bigrams('hello')
  end

  def test_levenshtein_dynamic_programming
    assert_equal 3, Compare.levenshtein('kitten', 'sitting')
    assert_equal 2, Compare.levenshtein('flaw', 'lawn')
    assert_equal 0, Compare.levenshtein('same', 'same')
    assert_equal 3, Compare.levenshtein('', 'abc')
    assert_in_delta 0.5714, Compare.levenshtein_similarity('kitten', 'sitting'), 0.001
  end

  def test_levenshtein_respects_cell_budget
    assert_raises(UsageError) { Compare.levenshtein('a' * 200, 'b' * 200, max_cells: 100) }
  end

  def test_compare_texts_aggregate
    a = 'The quick brown fox jumps over the lazy dog'
    b = 'The quick brown cat jumps over the lazy dog'
    result = Compare.compare_texts(a, b)
    assert_in_delta 0.7778, result[:jaccard], 0.0001
    assert_in_delta 0.9091, result[:cosine], 0.0001
    assert_in_delta 0.75, result[:dice], 0.0001
    assert_equal 3, result[:levenshtein]
    assert_in_delta 0.9302, result[:levenshtein_similarity], 0.0001
    assert_equal 9, result[:words_a]
    assert_equal 7, result[:shared_words]
    assert_equal 8, result[:unique_a]
  end

  # ------------------------------------------------------------------
  # Puzzles
  # ------------------------------------------------------------------

  def test_anagrams
    assert Puzzles.anagrams?('listen', 'silent')
    refute Puzzles.anagrams?('cat', 'cat') # identical words are not anagrams
    groups = Puzzles.anagram_groups(%w[silent listen cat act])
    assert_equal({ 'eilnst' => %w[listen silent], 'act' => %w[act cat] }, groups)
  end

  def test_palindromes
    assert Puzzles.palindrome?('Racecar')
    refute Puzzles.palindrome?('hello')
    assert_equal %w[level noon], Puzzles.palindromes(%w[level noon hello], min_length: 4)
  end

  def test_word_ladder_bfs
    assert_equal %w[cold cord card ward warm], Puzzles.word_ladder('cold', 'warm')
    assert_equal %w[cat cot cog dog],
                 Puzzles.word_ladder('cat', 'dog', dictionary: %w[cat cot cog dog])
    assert_equal ['cold'], Puzzles.word_ladder('cold', 'cold')
    assert_raises(LadderError) { Puzzles.word_ladder('cat', 'dogs') }
  end

  def test_rhymes
    assert_equal 'ght', Puzzles.rhyme_suffix('light')
    assert_equal %w[bright night sight], Puzzles.rhymes('light', %w[bright bit sight night])
    families = Puzzles.rhyme_families(%w[light sight bright bit fit])
    assert_equal({ 'ght' => %w[bright light sight], 'bit' => %w[bit fit] }, families)
  end

  def test_puzzle_extras
    assert_equal 'FBI', Puzzles.acronym('Federal Bureau of Investigation', skip_stopwords: true)
    assert Puzzles.pangram?('The quick brown fox jumps over the lazy dog!')
    refute Puzzles.pangram?('hello')
    assert_equal [['a', 2], ['b', 2]], Puzzles.letter_frequency('abab')
    assert_equal ['hello'], Puzzles.double_letter_words(%w[hello world])
  end

  # ------------------------------------------------------------------
  # Report
  # ------------------------------------------------------------------

  def test_report_renders_markdown_json_and_csv
    report = Report.new(SAMPLE, title: 'T', top: 2)
    markdown = report.render(:markdown)
    assert markdown.start_with?("## T\n")
    assert_includes markdown, '| metric |'

    parsed = JSON.parse(report.render(:json))
    assert_equal %w[frequency meta readability sentiment stats], parsed.keys.sort
    assert_equal 4, parsed['meta']['words']

    assert_instance_of String, report.render(:csv)
    assert_instance_of String, report.render(:text)
  end

  # ------------------------------------------------------------------
  # Library surface, errors and version
  # ------------------------------------------------------------------

  def test_analyze_convenience_pipeline
    result = Wordcraft.analyze(SAMPLE, top: 3)
    assert_equal 4, result[:meta][:words]
    assert_equal 'wordcraft 1.0.0', result[:meta][:generator]
    assert_equal [['hello', 2], ['there', 1], ['world', 1]], result[:frequency][:top_words]
  end

  def test_error_exit_codes_and_formatting
    assert_equal 2, UsageError.new('bad').exit_code
    assert_equal 66, FileNotFoundError.new('missing.txt').exit_code
    assert_equal 1, Wordcraft::Error.new('boom').exit_code
    assert_equal 'wordcraft: bad', Errors.format(UsageError.new('bad'))
    assert_equal 66, Errors.exit_code_for(FileNotFoundError.new('x'))
  end

  def test_version_metadata
    assert_equal '1.0.0', Wordcraft::VERSION
    assert_equal 'wordcraft 1.0.0 (Quill)', Version.label
    assert_equal 'MIT', Version::LICENSE
  end

  # ------------------------------------------------------------------
  # CLI
  # ------------------------------------------------------------------

  def test_cli_exit_codes
    assert_output(/wordcraft 1\.0\.0/) { assert_equal 0, CLI.run(['version']) }
    assert_output(/Commands:/) { assert_equal 0, CLI.run(['help']) }
    assert_equal 2, CLI.run(['nosuchcommand'])
    assert_equal 66, CLI.run(['stats', '/definitely/not/here.txt'])
    assert_equal 2, CLI.run(['transform']) # --to is required, no stdin read
    assert_equal 2, CLI.run(['compare'])   # two inputs are required
  end

  def test_cli_stats_json_from_temp_file
    Tempfile.create('wordcraft_test') do |file|
      file.write(SAMPLE)
      file.flush
      out = capture_io do
        assert_equal 0, CLI.run(['stats', file.path, '--format', 'json'])
      end.first
      parsed = JSON.parse(out)
      assert_equal 4, parsed['words']
      assert_equal 2.0, parsed['avg_sentence_length']
    end
  end

  def test_cli_frequency_table_and_unknown_metric
    Tempfile.create('wordcraft_test') do |file|
      file.write('the cat sat. the cat.')
      file.flush
      out = capture_io do
        assert_equal 0, CLI.run(['freq', file.path, '--top', '1'])
      end.first
      assert_includes out, 'cat'
      assert_includes out, '1 row(s)'
    end
    assert_equal 2, CLI.run(['compare', 'a.txt', 'b.txt', '--metrics', 'bogus'])
  end

  def test_cli_keywords_and_compare_outputs
    file_a = Tempfile.new('wordcraft_a')
    file_b = Tempfile.new('wordcraft_b')
    begin
      file_a.write('The quick brown fox jumps over the lazy dog')
      file_a.close
      file_b.write('The quick brown cat jumps over the lazy dog')
      file_b.close

      kw = capture_io do
        assert_equal 0, CLI.run(['keywords', file_a.path, '-m', 'rake', '-t', '2'])
      end.first
      assert_includes kw, 'quick brown fox'

      cmp = capture_io do
        assert_equal 0, CLI.run(['compare', file_a.path, file_b.path])
      end.first
      assert_includes cmp, 'jaccard'
      assert_includes cmp, 'Text comparison'
    ensure
      file_a.unlink
      file_b.unlink
    end
  end
end
