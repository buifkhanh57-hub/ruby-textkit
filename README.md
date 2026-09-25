# ruby-textkit

`TextKit` — a small Ruby module of text-processing helpers:

- `word_count`, `most_common_words` (with Vietnamese-aware unicode regex)
- `slugify`, `snake_to_camel`, `initials`
- `wrap` (greedy line wrapping), `palindromes`

## Usage
```bash
ruby lib/textkit.rb "Văn bản mẫu để thử nghiệm"
bin/textkit "hello world of ruby"
```

Or require it in your own code:
```ruby
require_relative 'lib/textkit'
TextKit.word_count('one two three') # => 3
```
