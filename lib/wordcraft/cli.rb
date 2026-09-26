# frozen_string_literal: true

require 'optparse'
require 'json'
require 'csv'

module Wordcraft
  # Command-line interface.
  #
  #   wordcraft <command> [file|-] [options]
  #
  # Commands: freq, readability, sentiment, stats, transform, puzzles,
  # keywords, compare, report, help, version. Every analysis command reads
  # from a file or from stdin ("-"), every command understands +--help+, and
  # all of them return meaningful exit codes:
  #
  #   0   success
  #   1   unexpected failure
  #   2   usage error (unknown command, bad option, missing argument)
  #  66   input file missing or unreadable
  #
  # The class is deliberately I/O-thin: parsing happens here, all analysis
  # lives in dedicated modules/classes, which keeps the CLI testable through
  # {CLI.run} without spawning a process.
  class CLI
    # Exit status constants (BSD sysexits conventions).
    EXIT_OK = 0
    EXIT_FAILURE = 1
    EXIT_USAGE = 2
    EXIT_NOINPUT = 66

    # Every subcommand understood by the executable.
    COMMANDS = %w[
      freq readability sentiment stats transform puzzles keywords
      compare report help version
    ].freeze

    # Output formats shared by the analysis commands.
    FORMATS = %w[text markdown json csv].freeze

    # Transformations offered by +wordcraft transform --to NAME+.
    TRANSFORMS = %w[
      upper lower title sentence swap slug snake camel pascal kebab
      strip-html strip-punct strip-accents wrap stem reverse collapse truncate
    ].freeze

    # Modes offered by +wordcraft puzzles --mode MODE+.
    PUZZLE_MODES = %w[anagram palindrome ladder rhyme families acronym pangram].freeze

    class << self
      # Runs the CLI and returns the process exit code (never exits itself).
      #
      # @param argv [Array<String>] argument vector (defaults to ARGV)
      # @return [Integer] exit code
      def run(argv = ARGV)
        new(argv).execute
      rescue Wordcraft::Error => e
        warn Errors.format(e)
        e.exit_code
      rescue OptionParser::ParseError => e
        warn "wordcraft: #{e.message}"
        EXIT_USAGE
      rescue StandardError => e
        warn Errors.format(e)
        EXIT_FAILURE
      end
    end

    # @param argv [Array<String>] raw argument vector
    def initialize(argv)
      @argv = argv.dup
    end

    # Dispatches to the requested subcommand.
    #
    # @return [Integer] exit code
    def execute
      command = @argv.shift
      if command.nil? || %w[help --help -h].include?(command)
        print_global_help
        return command.nil? ? EXIT_USAGE : EXIT_OK
      end
      return print_version if %w[version --version -v].include?(command)

      unless COMMANDS.include?(command)
        warn "wordcraft: unknown command '#{command}'"
        warn "Run 'wordcraft help' to see the available subcommands."
        return EXIT_USAGE
      end

      send("cmd_#{command}")
    end

    private

    # ----------------------------------------------------------------
    # Input handling
    # ----------------------------------------------------------------

    # Reads the input text: a file path, "-" or bare stdin.
    #
    # @param args [Array<String>] positional arguments left after option parsing
    # @return [String] scrubbed UTF-8 text
    # @raise [Wordcraft::FileNotFoundError] when the path does not exist
    def read_input(args)
      path = args.first
      if path.nil? || path == '-'
        warn '(reading text from stdin; press Ctrl-D to finish)' if $stdin.tty?
        data = $stdin.read
      else
        raise FileNotFoundError, "input file not found: #{path}" unless File.file?(path)

        begin
          data = File.read(path, encoding: 'UTF-8')
        rescue SystemCallError => e
          raise FileNotFoundError, "cannot read #{path}: #{e.message}"
        end
      end
      data.scrub
    end

    # Like {#read_input} but tolerates "no input at all" (returns an empty
    # string instead of blocking when stdin is a terminal). Used by the
    # puzzles command, whose dictionaries may come from options alone.
    def read_input_optional(args)
      return '' if args.empty? && $stdin.tty?

      read_input(args)
    end

    # Loads a plain word list (one word per line) from disk.
    #
    # @param path [String] dictionary file path
    # @return [Array<String>] lowercase, unique words
    def load_word_list(path)
      raise FileNotFoundError, "dictionary file not found: #{path}" unless File.file?(path)

      words = []
      File.foreach(path) do |line|
        word = line.strip.downcase
        words << word unless word.empty? || word.start_with?('#')
      end
      words.uniq
    end

    # ----------------------------------------------------------------
    # Subcommand: freq
    # ----------------------------------------------------------------

    def cmd_freq
      opts, args = parse_options('freq') do |o, h|
        o.on('-t', '--top N', Integer, 'Show top N entries (default 10)') { |v| h[:top] = v }
        o.on('-n', '--ngram N', Integer, 'Phrase size, 1 = single words') { |v| h[:ngram] = v }
        o.on('--min-length N', Integer, 'Drop words shorter than N (default 1)') { |v| h[:min_length] = v }
        o.on('--[no-]stopwords', 'Filter stopwords (default: yes)') { |v| h[:stopwords] = v }
        o.on('--stopwords-file PATH', 'Custom stopword list, one word per line') { |v| h[:stopwords_file] = v }
        o.on('-f', '--format FMT', FORMATS, 'Output format') { |v| h[:format] = v }
      end
      return EXIT_OK if help_requested?(opts, 'freq')

      freq = Frequency.new(read_input(args),
                           stopwords: opts[:stopwords],
                           stopwords_file: opts[:stopwords_file],
                           min_length: opts[:min_length])
      if opts[:ngram] > 1
        rows = freq.phrases(opts[:ngram], opts[:top])
        emit_table(opts[:format], "Top #{opts[:ngram]}-gram phrases", %w[phrase count], rows)
      else
        emit_table(opts[:format], 'Top words', %w[word count], freq.top(opts[:top]))
      end
      EXIT_OK
    end

    # ----------------------------------------------------------------
    # Subcommand: readability
    # ----------------------------------------------------------------

    def cmd_readability
      opts, args = parse_options('readability') do |o, h|
        o.on('-f', '--format FMT', FORMATS, 'Output format') { |v| h[:format] = v }
      end
      return EXIT_OK if help_requested?(opts, 'readability')

      r = Readability.new(read_input(args))
      case opts[:format].to_s.downcase
      when 'json'
        puts JSON.pretty_generate(r.summary)
      when 'csv'
        print csv_table(%w[formula score interpretation], r.formula_rows)
      when 'markdown', 'md'
        puts markdown_table('Readability', %w[formula score interpretation], r.formula_rows)
      else
        counts = r.summary[:counts]
        puts 'READABILITY'
        puts '=' * 11
        puts format('  %-26s %s', 'words:', counts[:words])
        puts format('  %-26s %s', 'sentences:', counts[:sentences])
        puts format('  %-26s %s', 'syllables:', counts[:syllables])
        puts format('  %-26s %s', 'polysyllables:', counts[:polysyllables])
        puts
        r.formula_rows.each do |label, score, band|
          puts format('  %-26s %8s   %s', label, display(score), band)
        end
        puts
        puts "  Consensus: #{display(r.summary[:consensus_grade])} (#{r.summary[:consensus_band]})"
      end
      EXIT_OK
    end

    # ----------------------------------------------------------------
    # Subcommand: sentiment
    # ----------------------------------------------------------------

    def cmd_sentiment
      opts, args = parse_options('sentiment') do |o, h|
        o.on('-f', '--format FMT', FORMATS, 'Output format') { |v| h[:format] = v }
        o.on('--max-sentences N', Integer, 'Sentences shown in text mode (default 10)') { |v| h[:max_sentences] = v }
      end
      return EXIT_OK if help_requested?(opts, 'sentiment')

      result = Sentiment.new.analyze(read_input(args))
      case opts[:format].to_s.downcase
      when 'json'
        puts JSON.pretty_generate(result)
      when 'csv'
        rows = sentiment_csv_rows(result)
        print csv_table(%w[key value], rows)
      when 'markdown', 'md'
        puts markdown_table('Sentiment', %w[metric value], sentiment_pairs(result))
      else
        puts 'SENTIMENT'
        puts '=' * 9
        sentiment_pairs(result).each do |key, value|
          puts format('  %-22s %s', "#{key}:", display(value))
        end
        puts
        puts 'Per sentence:'
        shown = result[:sentences].first(opts[:max_sentences] || 10)
        shown.each do |sent|
          puts format('  [%+7.2f] %s', sent[:score], sent[:text])
        end
      end
      EXIT_OK
    end

    def sentiment_pairs(result)
      [
        ['polarity', result[:polarity].to_s],
        ['raw score', result[:score]],
        ['normalized', result[:normalized]],
        ['scored words', result[:scored_word_count]],
        ['positive hits', result[:positive_hits].join(', ')],
        ['negative hits', result[:negative_hits].join(', ')]
      ]
    end

    def sentiment_csv_rows(result)
      rows = sentiment_pairs(result).map { |k, v| [k.to_s.tr(' ', '_'), v] }
      result[:sentences].each_with_index do |sent, index|
        rows << ["sentence_#{index + 1}_score", sent[:score]]
        rows << ["sentence_#{index + 1}_positive", sent[:positive].join(', ')]
        rows << ["sentence_#{index + 1}_negative", sent[:negative].join(', ')]
        rows << ["sentence_#{index + 1}_text", sent[:text]]
      end
      rows
    end

    # ----------------------------------------------------------------
    # Subcommand: stats
    # ----------------------------------------------------------------

    def cmd_stats
      opts, args = parse_options('stats') do |o, h|
        o.on('-f', '--format FMT', FORMATS, 'Output format') { |v| h[:format] = v }
      end
      return EXIT_OK if help_requested?(opts, 'stats')

      stats = TextStats.new(read_input(args))
      pairs = stats.to_h.to_a
      emit_kv(opts[:format], 'Text statistics', pairs)
      EXIT_OK
    end

    # ----------------------------------------------------------------
    # Subcommand: transform
    # ----------------------------------------------------------------

    def cmd_transform
      opts, args = parse_options('transform') do |o, h|
        o.on('-t', '--to NAME', TRANSFORMS, "Transformation to apply (required)") { |v| h[:to] = v }
        o.on('--width N', Integer, 'Line width for wrap (default 80)') { |v| h[:width] = v }
        o.on('--sep S', 'Separator for slug (default "-")') { |v| h[:sep] = v }
        o.on('--indent S', 'Indent string for wrap') { |v| h[:indent] = v }
        o.on('--max N', Integer, 'Maximum length for truncate (default 80)') { |v| h[:max] = v }
      end
      return EXIT_OK if help_requested?(opts, 'transform')

      unless opts[:to]
        raise UsageError, "transform requires --to (one of #{TRANSFORMS.join(', ')})"
      end

      puts apply_transform(read_input(args), opts)
      EXIT_OK
    end

    # Applies the requested transformation to the whole input text.
    #
    # @param text [String] input text
    # @param opts [Hash] parsed options
    # @return [String] transformed text
    def apply_transform(text, opts)
      case opts[:to]
      when 'upper' then Transform.upper(text)
      when 'lower' then Transform.lower(text)
      when 'title' then Transform.title_case(text)
      when 'sentence' then Transform.sentence_case(text)
      when 'swap' then Transform.swap(text)
      when 'slug' then Transform.slugify(text, sep: opts[:sep])
      when 'snake' then Transform.snake_case(text)
      when 'camel' then Transform.camel_case(text)
      when 'pascal' then Transform.pascal_case(text)
      when 'kebab' then Transform.kebab_case(text)
      when 'strip-html' then Transform.strip_html(text)
      when 'strip-punct' then Transform.strip_punctuation(text)
      when 'strip-accents' then Transform.strip_accents(text)
      when 'wrap' then Transform.wrap(text, width: opts[:width], indent: opts[:indent])
      when 'stem' then Transform.stem_text(text)
      when 'reverse' then Transform.reverse(text)
      when 'collapse' then Transform.collapse_whitespace(text)
      when 'truncate' then Transform.truncate(text, opts[:max] || 80)
      else
        raise UsageError, "unknown transform: #{opts[:to]}"
      end
    end

    # ----------------------------------------------------------------
    # Subcommand: puzzles
    # ----------------------------------------------------------------

    def cmd_puzzles
      opts, args = parse_options('puzzles') do |o, h|
        o.on('-m', '--mode MODE', PUZZLE_MODES, 'Puzzle to run (required)') { |v| h[:mode] = v }
        o.on('--word WORD', 'Reference word (ladder start / rhyme target)') { |v| h[:word] = v }
        o.on('--target WORD', 'Ladder target word') { |v| h[:target] = v }
        o.on('--dict FILE', 'Dictionary file, one word per line') { |v| h[:dict] = v }
        o.on('--min-length N', Integer, 'Minimum word length (default 1)') { |v| h[:min_length] = v }
        o.on('--depth N', Integer, 'Rhyme suffix depth (default 3)') { |v| h[:depth] = v }
        o.on('--max-depth N', Integer, 'Maximum ladder length (default 20)') { |v| h[:max_depth] = v }
        o.on('-f', '--format FMT', FORMATS, 'Output format') { |v| h[:format] = v }
      end
      return EXIT_OK if help_requested?(opts, 'puzzles')

      unless opts[:mode]
        raise UsageError, "puzzles requires --mode (one of #{PUZZLE_MODES.join(', ')})"
      end

      text = read_input_optional(args)
      words = opts[:dict] ? load_word_list(opts[:dict]) : vocabulary_of(text)
      run_puzzle(opts, text, words)
      EXIT_OK
    end

    # Tokenises raw text into a cleaned, unique vocabulary.
    def vocabulary_of(text)
      Tokenizer.words(text, downcase: true)
               .map { |w| Tokenizer.clean_word(w) }
               .reject(&:empty?)
               .uniq
    end

    # Dispatches the requested puzzle mode. All modes print their own
    # output and leave the exit code at EXIT_OK.
    def run_puzzle(opts, text, words)
      case opts[:mode]
      when 'anagram'
        groups = Puzzles.anagram_groups(words, min_length: opts[:min_length])
        rows = groups.map { |_key, members| [members.join(', '), members.length] }
        emit_table(opts[:format], 'Anagram groups', %w[group size], rows.sort)
      when 'palindrome'
        found = Puzzles.palindromes(words, min_length: opts[:min_length])
        rows = found.map { |w| [w, w.length] }
        emit_table(opts[:format], 'Palindromes', %w[word length], rows)
      when 'ladder'
        run_ladder(opts)
      when 'rhyme'
        raise UsageError, 'rhyme requires --word' unless opts[:word]

        found = Puzzles.rhymes(opts[:word], words, depth: opts[:depth])
        emit_table(opts[:format], "Rhymes for '#{opts[:word]}'", %w[word], found.map { |w| [w] })
      when 'families'
        families = Puzzles.rhyme_families(words, depth: opts[:depth], min_size: 2)
        rows = families.map { |suffix, members| [suffix, members.join(', '), members.length] }
        emit_table(opts[:format], 'Rhyme families', %w[suffix words size], rows.sort)
      when 'acronym'
        raise UsageError, 'acronym needs some input text' if text.empty?

        puts Puzzles.acronym(text, skip_stopwords: true)
      when 'pangram'
        raise UsageError, 'pangram needs some input text' if text.empty?

        puts Puzzles.pangram?(text) ? 'pangram: yes' : 'pangram: no'
      end
    end

    # Runs the word-ladder puzzle and prints the chain (or a miss).
    def run_ladder(opts)
      unless opts[:word] && opts[:target]
        raise UsageError, 'ladder requires --word START and --target TARGET'
      end

      dictionary = opts[:dict] ? load_word_list(opts[:dict]) : nil
      path = Puzzles.word_ladder(opts[:word], opts[:target],
                                 dictionary: dictionary, max_depth: opts[:max_depth])
      if path.nil?
        puts "No ladder found between '#{opts[:word]}' and '#{opts[:target]}'"
      else
        rows = path.each_with_index.map { |word, index| [index + 1, word] }
        emit_table(opts[:format], "Ladder '#{opts[:word]}' -> '#{opts[:target]}'", %w[step word], rows)
      end
    end

    # ----------------------------------------------------------------
    # Subcommand: keywords
    # ----------------------------------------------------------------

    # Keyword extraction (RAKE or TF-IDF) over the input text.
    def cmd_keywords
      opts, args = parse_options('keywords') do |o, h|
        o.on('-m', '--method NAME', %w[rake tfidf],
             'Extraction method: rake or tfidf (default rake)') { |v| h[:method] = v }
        o.on('-t', '--top N', Integer, 'Show top N keywords (default 10)') { |v| h[:top] = v }
        o.on('--min-freq N', Integer,
             'RAKE: drop phrases seen fewer than N times (default 1)') { |v| h[:min_freq] = v }
        o.on('--unit NAME', %w[paragraph sentence],
             'TF-IDF pseudo-document unit (default paragraph)') { |v| h[:unit] = v }
        o.on('-f', '--format FMT', FORMATS, 'Output format') { |v| h[:format] = v }
      end
      return EXIT_OK if help_requested?(opts, 'keywords')

      method = (opts[:method] || 'rake').to_s.downcase
      extract_options = { top: opts[:top] }
      case method
      when 'rake'
        extract_options[:min_frequency] = opts[:min_freq] if opts[:min_freq]
      when 'tfidf'
        extract_options[:unit] = (opts[:unit] || 'paragraph').to_s
      end

      rows = Keywords.extract(read_input(args), method: method, **extract_options)
      emit_table(opts[:format], "Keywords (#{method})", %w[keyword score], rows)
      EXIT_OK
    end

    # ----------------------------------------------------------------
    # Subcommand: compare
    # ----------------------------------------------------------------

    # Pairwise similarity of two documents (Jaccard, cosine, Dice and the
    # optional character-level Levenshtein distance).
    def cmd_compare
      opts, args = parse_options('compare') do |o, h|
        o.on('-m', '--metrics LIST', Array,
             'Comma list of metrics (default jaccard,cosine,dice)') { |v| h[:metrics] = v }
        o.on('--max-cells N', Integer,
             "Levenshtein DP cell budget (default #{Compare::DEFAULT_MAX_CELLS})") { |v| h[:max_cells] = v }
        o.on('-f', '--format FMT', FORMATS, 'Output format') { |v| h[:format] = v }
      end
      return EXIT_OK if help_requested?(opts, 'compare')

      metrics = parse_metrics(opts[:metrics])
      text_a, text_b = read_compare_inputs(args)
      emit_table(opts[:format], 'Text comparison', %w[metric value],
                 comparison_rows(text_a, text_b, metrics, opts[:max_cells]))
      EXIT_OK
    end

    # Reads both comparison inputs: two file arguments, or stdin followed by
    # one file. Internal helper of {cmd_compare}.
    def read_compare_inputs(args)
      if args.length >= 2
        [read_input([args[0]]), read_input([args[1]])]
      elsif args.length == 1 && !$stdin.tty?
        [$stdin.read, read_input(args)]
      else
        raise UsageError,
              'compare requires two inputs: FILE_A FILE_B, or piped stdin plus one FILE'
      end
    end

    # Validates the --metrics list. Internal helper of {cmd_compare}.
    def parse_metrics(requested)
      metrics = (requested || %w[jaccard cosine dice]).map { |m| m.to_s.strip.downcase }
      metrics.each do |metric|
        next if Compare::METRICS.include?(metric)

        raise UsageError,
              "unknown metric: #{metric} (expected one of #{Compare::METRICS.join(', ')})"
      end
      metrics.uniq
    end

    # [metric, value] rows for the compare table. Internal helper of
    # {cmd_compare}; the Levenshtein pair is computed on whitespace-
    # collapsed, lowercased texts via {Compare.normalize_string}.
    def comparison_rows(text_a, text_b, metrics, max_cells)
      cells = max_cells || Compare::DEFAULT_MAX_CELLS
      rows = []
      metrics.each do |metric|
        case metric
        when 'jaccard' then rows << ['jaccard', Compare.jaccard(text_a, text_b)]
        when 'cosine' then rows << ['cosine', Compare.cosine(text_a, text_b)]
        when 'dice' then rows << ['dice', Compare.dice(text_a, text_b)]
        when 'levenshtein'
          a = Compare.normalize_string(text_a)
          b = Compare.normalize_string(text_b)
          rows << ['levenshtein_distance', Compare.levenshtein(a, b, max_cells: cells)]
          rows << ['levenshtein_similarity',
                   Compare.levenshtein_similarity(a, b, max_cells: cells)]
        end
      end
      rows
    end

    # ----------------------------------------------------------------
    # Subcommand: report
    # ----------------------------------------------------------------

    def cmd_report
      opts, args = parse_options('report') do |o, h|
        o.on('--title TITLE', 'Report heading') { |v| h[:title] = v }
        o.on('-t', '--top N', Integer, 'Top entries per section (default 10)') { |v| h[:top] = v }
        o.on('-n', '--ngram N', Integer, 'Phrase size for the frequency section') { |v| h[:ngram] = v }
        o.on('--[no-]stopwords', 'Filter stopwords in frequency section (default: yes)') { |v| h[:stopwords] = v }
        o.on('-f', '--format FMT', FORMATS, 'Output format') { |v| h[:format] = v }
      end
      return EXIT_OK if help_requested?(opts, 'report')

      report = Report.new(read_input(args),
                          title: opts[:title],
                          top: opts[:top],
                          ngram: opts[:ngram],
                          stopwords: opts[:stopwords],
                          format: opts[:format])
      output = report.render
      output += "\n" unless output.end_with?("\n")
      print output
      EXIT_OK
    end

    # ----------------------------------------------------------------
    # Help and version
    # ----------------------------------------------------------------

    def print_version
      puts Version.label
      EXIT_OK
    end

    def print_global_help
      puts <<~HELP
        #{Version.label} -- #{Version::SUMMARY}

        Usage:
          wordcraft <command> [file|-] [options]

        Commands:
          freq         word / phrase n-gram frequency with stopword filtering
          readability  Flesch, Flesch-Kincaid, Gunning Fog, SMOG, Coleman-Liau, ARI
          sentiment    lexicon-based polarity with negation and intensifiers
          stats        counts, averages, lexical diversity and distributions
          transform    case, slug, snake/camel/kebab, HTML strip, wrap, stemming
          puzzles      anagrams, palindromes, word ladders (BFS), rhymes
          keywords     RAKE and TF-IDF keyword extraction
          compare      Jaccard / cosine / Dice similarity, Levenshtein distance
          report       combined text / markdown / json / csv report
          help         show this help
          version      show version information

        Common options:
          -f, --format FMT   text | markdown | json | csv
          -h, --help         per-command help

        Input:
          A single FILE argument reads that file; "-" or no argument reads stdin.
          Piped input is detected automatically, e.g.:
            cat alice.txt | wordcraft stats
            wordcraft freq examples/alice_excerpt.txt --top 15
            wordcraft transform chapter.txt --to slug | head -1

        Exit codes: 0 success, 1 failure, 2 usage error, 66 missing input file.
      HELP
      EXIT_OK
    end

    # ----------------------------------------------------------------
    # Option plumbing and output helpers
    # ----------------------------------------------------------------

    # Builds an OptionParser for a subcommand, parses @argv and returns
    # [opts, leftover_args]. A requested +--help+ is reported through
    # opts[:help]; parse errors are converted to {Wordcraft::UsageError}.
    #
    # @param command [String] subcommand name for banner/messages
    # @yieldparam parser [OptionParser] add command-specific options here
    # @yieldparam opts [Hash] defaults, filled by the flags
    def parse_options(command)
      opts = { format: 'text', top: 10, ngram: 1, min_length: 1, stopwords: true,
               width: 80, indent: '', sep: '-', depth: 3, max_depth: 20,
               title: 'Wordcraft Text Report' }
      parser = OptionParser.new do |o|
        o.banner = "Usage: wordcraft #{command} [file|-] [options]"
        o.separator ''
        o.separator 'Options:'
        yield o, opts
        o.separator ''
        o.on('-h', '--help', 'Show this help message') { opts[:help] = true }
      end
      args = parser.parse!(@argv)
      opts[:parser] = parser
      [opts, args]
    rescue OptionParser::ParseError => e
      warn "wordcraft #{command}: #{e.message}"
      warn "Run 'wordcraft #{command} --help' for usage."
      raise UsageError, "#{command}: #{e.message}"
    end

    # Prints the per-command help when the user asked for it.
    #
    # @return [Boolean] true when help was printed
    def help_requested?(opts, _command)
      return false unless opts[:help]

      puts opts[:parser].to_s
      true
    end

    # Renders a [label, value] table in the requested format.
    def emit_kv(format, title, pairs)
      case format.to_s.downcase
      when 'json'
        puts JSON.pretty_generate(title => pairs.to_h)
      when 'csv'
        print csv_table(%w[key value], pairs)
      when 'markdown', 'md'
        puts markdown_table(title, %w[metric value], pairs)
      else
        puts title
        puts '=' * title.length
        pairs.each do |key, value|
          puts format('  %-28s %s', "#{key}:", display(value))
        end
      end
    end

    # Renders a [headers, rows] table in the requested format.
    def emit_table(format, title, headers, rows)
      case format.to_s.downcase
      when 'json'
        puts JSON.pretty_generate('title' => title, 'headers' => headers, 'rows' => rows)
      when 'csv'
        print csv_table(headers, rows)
      when 'markdown', 'md'
        puts markdown_table(title, headers, rows)
      else
        puts text_table(title, headers, rows)
      end
    end

    # RFC 4180-safe CSV rendering via the csv standard library.
    def csv_table(headers, rows)
      CSV.generate do |csv|
        csv << headers
        rows.each { |row| csv << row }
      end
    end

    def markdown_table(title, headers, rows)
      md = String.new
      md << "## #{title}\n\n"
      md << "| #{headers.join(' | ')} |\n"
      md << "| #{headers.map { |_h| '---' }.join(' | ')} |\n"
      rows.each do |row|
        md << "| #{row.map { |cell| display(cell) }.join(' | ')} |\n"
      end
      md
    end

    def text_table(title, headers, rows)
      widths = headers.each_with_index.map do |header, index|
        cells = rows.map { |row| display(row[index]).length }
        [display(header).length, cells.max || 0].max
      end
      out = String.new
      out << title << "\n"
      out << table_line(headers, widths) << "\n"
      out << widths.map { |w| '-' * w }.join('  ') << "\n"
      rows.each { |row| out << table_line(row, widths) << "\n" }
      out << "#{rows.length} row(s)\n"
      out
    end

    def table_line(cells, widths)
      cells.each_with_index.map { |cell, i| display(cell).ljust(widths[i]) }.join('  ').rstrip
    end

    # Formats a cell value for terminal output.
    def display(value)
      case value
      when nil then 'n/a'
      when Float then format('%.2f', value)
      when Symbol then value.to_s
      else value.to_s
      end
    end
  end
end
