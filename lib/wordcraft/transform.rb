# frozen_string_literal: true

module Wordcraft
  # Text transformation utilities: case conversion, identifier casing,
  # slugification, HTML stripping, word wrapping, accent folding and a
  # lightweight English stemmer.
  #
  # All methods are pure functions on strings -- no state, no I/O -- so they
  # compose freely inside pipelines:
  #
  #   Wordcraft::Transform.snake_case('Hello World Example') # => "hello_world_example"
  #   Wordcraft::Transform.slugify('Héllo — World!')          # => "hello-world"
  module Transform
    # Words kept lowercase in {title_case} unless they open or close a title.
    SMALL_WORDS = %w[
      a an the and but or nor for so yet at by in of on to up as
    ].freeze

    # Common HTML entities (numeric entities are decoded generically).
    NAMED_ENTITIES = {
      '&nbsp;' => ' ',
      '&lt;' => '<',
      '&gt;' => '>',
      '&quot;' => '"',
      '&apos;' => "'",
      '&rsquo;' => "'",
      '&lsquo;' => "'",
      '&ldquo;' => '"',
      '&rdquo;' => '"',
      '&ndash;' => '-',
      '&mdash;' => '--',
      '&hellip;' => '...',
      '&copy;' => '(c)',
      '&reg;' => '(r)',
      '&trade;' => '(tm)'
    }.freeze

    # Latin-1 style accents folded to plain ASCII by {strip_accents}.
    ACCENTS = {
      'à' => 'a', 'á' => 'a', 'â' => 'a', 'ã' => 'a', 'ä' => 'a', 'å' => 'a',
      'è' => 'e', 'é' => 'e', 'ê' => 'e', 'ë' => 'e',
      'ì' => 'i', 'í' => 'i', 'î' => 'i', 'ï' => 'i',
      'ò' => 'o', 'ó' => 'o', 'ô' => 'o', 'õ' => 'o', 'ö' => 'o',
      'ù' => 'u', 'ú' => 'u', 'û' => 'u', 'ü' => 'u',
      'ý' => 'y', 'ÿ' => 'y', 'ñ' => 'n', 'ç' => 'c', 'š' => 's', 'ž' => 'z',
      'æ' => 'ae', 'œ' => 'oe', 'ß' => 'ss',
      'À' => 'A', 'Á' => 'A', 'Â' => 'A', 'Ã' => 'A', 'Ä' => 'A', 'Å' => 'A',
      'È' => 'E', 'É' => 'E', 'Ê' => 'E', 'Ë' => 'E',
      'Ì' => 'I', 'Í' => 'I', 'Î' => 'I', 'Ï' => 'I',
      'Ò' => 'O', 'Ó' => 'O', 'Ô' => 'O', 'Õ' => 'O', 'Ö' => 'O',
      'Ù' => 'U', 'Ú' => 'U', 'Û' => 'U', 'Ü' => 'U',
      'Ý' => 'Y', 'Ñ' => 'N', 'Ç' => 'C', 'Š' => 'S', 'Ž' => 'Z',
      'Æ' => 'AE', 'Œ' => 'OE'
    }.freeze

    # Identifier-casing styles supported by {convert_identifier}.
    IDENTIFIER_STYLES = %w[snake camel pascal kebab upper_camel].freeze

    module_function

    # ------------------------------------------------------------------
    # Case conversions
    # ------------------------------------------------------------------

    # Uppercases everything.
    #
    # @param text [String]
    # @return [String]
    def upper(text)
      text.to_s.upcase
    end

    # Lowercases everything.
    #
    # @param text [String]
    # @return [String]
    def lower(text)
      text.to_s.downcase
    end

    # Swaps the case of every character.
    #
    # @param text [String]
    # @return [String]
    def swap(text)
      text.to_s.swapcase
    end

    # Title-cases text, keeping small words lowercase except at the
    # beginning and the end (Chicago-lite style).
    #
    # @example
    #   title_case('the lord of the rings') # => "The Lord of the Rings"
    # @param text [String]
    # @return [String]
    def title_case(text)
      words = text.to_s.split(/\s+/)
      return '' if words.empty?

      last = words.length - 1
      words.each_with_index.map do |word, index|
        if index != 0 && index != last && SMALL_WORDS.include?(word.downcase)
          word.downcase
        else
          word.capitalize
        end
      end.join(' ')
    end

    # Sentence-cases text: lowercase everything, then capitalise the first
    # letter after a sentence boundary.
    #
    # @param text [String]
    # @return [String]
    def sentence_case(text)
      s = text.to_s.downcase
      s.gsub(/(^|[.!?]\s+)([a-z])/) { "#{Regexp.last_match(1)}#{Regexp.last_match(2).upcase}" }
    end

    # ------------------------------------------------------------------
    # Identifier casing
    # ------------------------------------------------------------------

    # Converts text to snake_case.
    #
    # @param text [String] any casing ("Hello World", "fooBarBaz", "kebab-case")
    # @return [String]
    def snake_case(text)
      identifier(text, '_')
    end

    # Converts text to kebab-case (lowercase-hyphenated).
    #
    # @param text [String]
    # @return [String]
    def kebab_case(text)
      identifier(text, '-')
    end

    # Converts text to lowerCamelCase.
    #
    # @param text [String]
    # @return [String]
    def camel_case(text)
      parts = text.to_s.scan(/[A-Za-z0-9]+/)
      return '' if parts.empty?

      parts.each_with_index.map do |part, index|
        index.zero? ? part.downcase : part.capitalize
      end.join
    end

    # Converts text to UpperCamelCase (PascalCase).
    #
    # @param text [String]
    # @return [String]
    def pascal_case(text)
      parts = text.to_s.scan(/[A-Za-z0-9]+/)
      return '' if parts.empty?

      parts.map(&:capitalize).join
    end

    # Alias of {pascal_case} for readers who prefer the UpperCamel name.
    #
    # @param text [String]
    # @return [String]
    def upper_camel_case(text)
      pascal_case(text)
    end

    # Converts text into one of the supported identifier styles.
    #
    # @param text [String]
    # @param style [String] one of {IDENTIFIER_STYLES}
    # @return [String]
    # @raise [Wordcraft::UsageError] for an unknown style
    def convert_identifier(text, style)
      case style.to_s.downcase
      when 'snake' then snake_case(text)
      when 'kebab' then kebab_case(text)
      when 'camel' then camel_case(text)
      when 'pascal', 'upper_camel' then pascal_case(text)
      else
        raise UsageError, "unknown identifier style: #{style} (expected one of #{IDENTIFIER_STYLES.join(', ')})"
      end
    end

    # ------------------------------------------------------------------
    # Slugification
    # ------------------------------------------------------------------

    # Slugifies text for URLs or filenames: accents folded, smart punctuation
    # normalised, every non-alphanumeric run collapsed into one separator.
    #
    # @param text [String]
    # @param sep [String] single separator string (default "-")
    # @param lowercase [Boolean] lowercase the result
    # @return [String] slug with no leading/trailing separator
    # @raise [Wordcraft::UsageError] when +sep+ is empty
    def slugify(text, sep: '-', lowercase: true)
      raise UsageError, 'slug separator must not be empty' if sep.to_s.empty?

      s = strip_accents(text.to_s)
      s = s.downcase if lowercase
      s = s.gsub(/[^A-Za-z0-9]+/, sep)
      s = s.split(sep, -1).reject(&:empty?).join(sep)
      s
    end

    # ------------------------------------------------------------------
    # HTML stripping
    # ------------------------------------------------------------------

    # Removes HTML markup: drops +<script>+ and +<style>+ blocks entirely,
    # strips comments, removes remaining tags and decodes the common named
    # and numeric entities.
    #
    # @param html [String] possibly malformed HTML
    # @param collapse_whitespace [Boolean] squash runs of whitespace
    # @return [String] plain text
    def strip_html(html, collapse_whitespace: true)
      s = html.to_s
      s = s.gsub(%r{<script\b[^>]*>.*?</script\s*>}im, ' ')
      s = s.gsub(%r{<style\b[^>]*>.*?</style\s*>}im, ' ')
      s = s.gsub(%r{<!--.*?-->}m, ' ')
      s = s.gsub(/<!\[CDATA\[.*?\]\]>/m, ' ')
      s = s.gsub(/<!DOCTYPE[^>]*>/i, ' ')
      s = s.gsub(%r{</?[a-zA-Z][^>]*>}, ' ')
      s = decode_entities(s)
      return s if collapse_whitespace == false

      s.gsub(/[ \t\r\n]+/, ' ').strip
    end

    # Decodes named entities and decimal/hex numeric character references.
    #
    # @param text [String]
    # @return [String]
    def decode_entities(text)
      s = text.to_s
      s = s.gsub(/&#x([0-9a-fA-F]+);/) do
        code = Regexp.last_match(1).to_i(16)
        valid_codepoint?(code) ? code.chr(Encoding::UTF_8) : ' '
      end
      s = s.gsub(/&#(\d+);/) do
        code = Regexp.last_match(1).to_i
        valid_codepoint?(code) ? code.chr(Encoding::UTF_8) : ' '
      end
      NAMED_ENTITIES.each { |entity, replacement| s = s.gsub(entity, replacement) }
      s.gsub('&amp;', '&') # must be last: keeps "&amp;lt;" as "&lt;"
    end

    # ------------------------------------------------------------------
    # Whitespace, wrapping and cleanup
    # ------------------------------------------------------------------

    # Greedy word wrap that preserves paragraph breaks.
    #
    # Words longer than +width+ are never split; each gets its own line.
    #
    # @param text [String]
    # @param width [Integer] maximum line width (>= 1)
    # @param indent [String] prefix prepended to every line
    # @return [String] wrapped text with "\n" line breaks
    # @raise [Wordcraft::UsageError] when width is smaller than 1
    def wrap(text, width: 80, indent: '')
      raise UsageError, 'wrap width must be >= 1' if width.to_i < 1

      width = width.to_i
      paragraphs = text.to_s.gsub(/\r\n?/, "\n").split(/\n[ \t]*\n/)
      paragraphs.map { |p| wrap_paragraph(p, width, indent) }.join("\n\n")
    end

    # Wraps a single paragraph (a block without blank lines).
    # Internal helper of {wrap}.
    #
    # @param paragraph [String]
    # @param width [Integer]
    # @param indent [String]
    # @return [String]
    def wrap_paragraph(paragraph, width, indent)
      words = paragraph.split(/\s+/)
      return '' if words.empty?

      lines = []
      current = nil
      words.each do |word|
        if current.nil?
          current = indent.dup << word
        elsif current.length + 1 + word.length <= width
          current << ' ' << word
        else
          lines << current
          current = indent.dup << word
        end
      end
      lines << current
      lines.join("\n")
    end

    # Collapses runs of spaces/tabs and normalises space around newlines.
    #
    # @param text [String]
    # @return [String]
    def collapse_whitespace(text)
      s = text.to_s.gsub(/[ \t]+/, ' ')
      s = s.gsub(/ ?\n ?/, "\n")
      s.gsub(/\n{3,}/, "\n\n").strip
    end

    # Removes all punctuation (word-internal apostrophes are kept).
    #
    # @param text [String]
    # @return [String]
    def strip_punctuation(text)
      text.to_s.gsub(/(?<=\w)['’](?=\w)/, "\u0001")
               .gsub(/[^\p{Word}\s\u0001]/, '')
               .gsub("\u0001", "'")
    end

    # Folds accented characters to their ASCII base letters.
    #
    # @param text [String]
    # @return [String]
    def strip_accents(text)
      text.to_s.chars.map { |ch| ACCENTS.fetch(ch, ch) }.join
    end

    # Truncates text to at most +max+ characters, appending a suffix.
    #
    # @param text [String]
    # @param max [Integer] maximum total length including the suffix
    # @param suffix [String] appended to shortened text
    # @return [String]
    def truncate(text, max, suffix: '...')
      s = text.to_s
      max = max.to_i
      return s if max <= 0 || s.length <= max

      keep = max - suffix.length
      return suffix if keep <= 0

      s[0, keep].strip + suffix
    end

    # Reverses the text character by character.
    #
    # @param text [String]
    # @return [String]
    def reverse(text)
      text.to_s.reverse
    end

    # ------------------------------------------------------------------
    # Lightweight stemming
    # ------------------------------------------------------------------

    # A small, deterministic suffix-stripping stemmer ("stemming lite").
    #
    # Rules (applied to the first matching suffix, longest first):
    #   * "-ies"  -> "y"      studies -> study
    #   * "-ied"  -> "y"      carried -> carry
    #   * "-sses" -> "ss"     classes -> class
    #   * "-xes/-ches/-shes/-zes" -> drop "es"   boxes -> box
    #   * "-s"    -> drop     cats -> cat (but "class", "bus" keep their s)
    #   * "-ing"  -> drop, collapse doubled consonants, restore a final
    #                silent "e" when the pattern fits   running -> run,
    #                making -> make, loving -> love
    #   * "-ed"   -> drop, collapse doubled consonants walked -> walk,
    #                stopped -> stop
    #   * "-ly"   -> drop     quickly -> quick
    #   * "-ness" / "-ment" -> drop when a 4+ letter base remains
    #
    # The result is a crude lexeme candidate, not a linguistic lemma --
    # "writ" from "writing" is accepted. It is stable, allocation-free and
    # good enough for frequency grouping.
    #
    # @param word [String] a single word (non-letters are returned as-is)
    # @return [String]
    def stem(word)
      w = word.to_s.downcase
      return w if w.length <= 3 || w !~ /\A[a-z]+\z/

      base = nil
      if w.end_with?('ies') && w.length >= 5
        return w[0..-4] + 'y'
      elsif w.end_with?('ied') && w.length >= 5
        return w[0..-4] + 'y'
      elsif w.end_with?('sses') && w.length >= 6
        return w[0..-3]
      elsif w.end_with?('xes', 'ches', 'shes', 'zes')
        return w[0..-3] if w.length >= 5
      elsif w.end_with?('s') && !w.end_with?('ss', 'us', 'is') && w.length >= 4
        return w[0..-2]
      elsif w.end_with?('ing') && w.length >= 6
        base = restore_after_drop(w[0..-4], true)
      elsif w.end_with?('ed') && w.length >= 5
        allow_e = !VOWEL_RE.match?(w[-3])
        base = restore_after_drop(w[0..-3], allow_e)
      elsif w.end_with?('ly') && w.length >= 5
        return w[0..-3]
      elsif w.end_with?('ness') && w.length >= 8
        return w[0..-5]
      elsif w.end_with?('ment') && w.length >= 8
        return w[0..-5]
      end

      base || w
    end

    # Stems every word of a text while preserving whitespace and punctuation.
    #
    # @param text [String]
    # @return [String]
    def stem_text(text)
      text.to_s.split(/(\s+)/).map { |chunk| chunk.match?(/\s/) ? chunk : stem(chunk) }.join
    end

    # Shared implementation for snake/kebab casing. Internal helper.
    def identifier(text, joiner)
      s = text.to_s
      s = s.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
      s = s.gsub(/([a-z\d])([A-Z])/, '\1_\2')
      s = s.gsub(/[^A-Za-z0-9]+/, '_')
      parts = s.split('_').reject(&:empty?).map(&:downcase)
      parts.join(joiner)
    end

    # Post-processing shared by the "-ing" and "-ed" rules. Internal helper.
    #
    # @param base [String] stem after suffix removal
    # @param allow_e [Boolean] whether a silent "e" may be restored
    # @return [String]
    def restore_after_drop(base, allow_e)
      doubled = false
      if base.length >= 3 && base[-1] == base[-2] && !%w[ll ss ff].include?(base[-2, 2])
        base = base[0..-2]
        doubled = true
      end
      if allow_e && !doubled && base.length >= 2 &&
         VOWEL_RE.match?(base[-2]) && !VOWEL_RE.match?(base[-1]) && base[-1] != 'x'
        base = base + 'e'
      end
      base
    end

    def valid_codepoint?(code)
      code >= 32 && code <= 0x10FFFF && !(0xD800..0xDFFF).cover?(code)
    end

    VOWEL_RE = /[aeiouy]/.freeze
  end
end
