# frozen_string_literal: true

# ruby-textkit — text processing helpers in idiomatic Ruby.
module TextKit
  module_function

  def word_count(text)
    text.scan(/[\p{L}\p{N}'’-]+/).size
  end

  def slugify(text)
    text
      .downcase
      .gsub(/[^a-z0-9\s-]/, '')
      .strip
      .tr_s(' \s_-', '-')
      .gsub(/^-+|-+$/, '')
  end

  def initials(full_name)
    full_name.split(/\s+/).map { |part| part[0].upcase }.join('.')
  end

  def wrap(text, width = 72)
    raise ArgumentError, 'width must be positive' if width <= 0
    words = text.split(/\s+/)
    lines = []
    current = +''
    words.each do |word|
      if !current.empty? && current.length + 1 + word.length > width
        lines << current
        current = +''
      end
      current = current.empty? ? word : "#{current} #{word}"
    end
    lines << current unless current.empty?
    lines.join("\n")
  end

  def palindromes(words)
    words.select do |w|
      clean = w.downcase.gsub(/[^a-z]/, '')
      !clean.empty? && clean == clean.reverse
    end.uniq
  end

  def most_common_words(text, top = 5)
    stop = %w[the a an and or of to in on for with is are was were be been it this that]
    text
      .downcase
      .scan(/[\p{L}'’-]+/)
      .reject { |w| stop.include?(w) || w.length < 2 }
      .tally
      .sort_by { |_word, count| [-count, _word] }
      .first(top)
      .to_h
  end

  def snake_to_camel(snake)
    snake.split('_').each_with_index
         .map { |part, i| i.zero? ? part : part.capitalize }
         .join
  end
end

# CLI mode: ruby lib/textkit.rb "some text"
if __FILE__ == $PROGRAM_NAME
  require 'json'

  sample = ARGV[0] || 'Hà Nội buổi sáng, sương giăng mờ ảo trên mặt hồ. Hà Nội đẹp!'

  puts JSON.pretty_generate(
    word_count: TextKit.word_count(sample),
    slug: TextKit.slugify(sample),
    top_words: TextKit.most_common_words(sample, 3),
    initials: TextKit.initials('Nguyen Thi Khanh'),
    snake_to_camel: TextKit.snake_to_camel('my_variable_name'),
    palindromes: TextKit.palindromes(%w[madam level ruby noon rails])
  )
end
