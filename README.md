# Wordcraft

> A stdlib-only Ruby text-analysis toolkit — frequency, readability, sentiment,
> statistics, keyword extraction, document similarity, transforms and word
> puzzles, behind one small `wordcraft` command.

![Version](https://img.shields.io/badge/version-1.0.0%20(Quill)-blue)
![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.0-red)
![Dependencies](https://img.shields.io/badge/dependencies-0-brightgreen)
![Tests](https://img.shields.io/badge/tests-minitest%20%C3%97%2047-orange)
![License](https://img.shields.io/badge/license-MIT-lightgrey)
![Platform](https://img.shields.io/badge/platform-POSIX%20%7C%20Windows-informational)

---

## Overview

**Wordcraft** is a Ruby gem and command-line tool for analysing plain text.
It bundles the analyses that usually require half a dozen different scripts or
online tools into one dependency-free package:

* word / phrase frequency with stopword filtering,
* six classical readability formulas,
* lexicon-based sentiment with negation and intensifier handling,
* structural statistics (counts, averages, lexical diversity, histograms),
* a full Porter stemmer and a lightweight stemmer,
* RAKE and TF-IDF keyword extraction,
* document similarity (Jaccard, cosine, Dice, Levenshtein),
* text transforms (case, slug, identifiers, HTML stripping, wrapping),
* word puzzles (anagrams, palindromes, word ladders, rhymes).

Use it as a CLI over files or pipes, or `require 'wordcraft'` and call the
same machinery from Ruby. The runtime has **zero external gems** — everything
is built on the Ruby standard library (`set`, `json`, `csv`, `optparse`,
`bigdecimal`), which makes installation trivial and audits easy.

The library is deliberately transparent: every lexicon is a readable Ruby
file, every formula is documented next to its implementation, and every
heuristic (syllable counting, stemming quirks, RAKE scoring) states its known
limitations in place rather than hiding them.

## Features

* **Frequency analysis** — top words and n-gram phrases, custom stopword
  lists, minimum word length, co-occurrence windows, hapax legomena,
  frequency-of-frequency distributions and coverage ratios.
* **Readability** — Flesch Reading Ease, Flesch-Kincaid Grade, Gunning Fog,
  SMOG, Coleman-Liau and ARI, each with band interpretation and a robust
  median "consensus grade". Missing data yields `nil`, never a crash.
* **Sentiment** — hand-curated lexicon (~650 entries, weights 1–3), negation
  window of 3 tokens, stackable intensifiers (capped at 3.0), `but` as a
  contrast reset, per-sentence breakdown in every result.
* **Statistics** — characters/words/sentences/paragraphs, averages computed
  with `BigDecimal` to avoid drift, three type-token ratios (plain, root,
  corrected), word- and sentence-length histograms, top punctuation.
* **Transforms** — 18 operations: case conversions, title/sentence case,
  slugify with accent folding, snake/camel/pascal/kebab identifiers, HTML
  stripping with entity decoding, greedy wrap, truncation, stemming.
* **Porter stemmer** — the classic 1980 algorithm organised as auditable
  rule tables, with an `explain` mode that returns the full step-by-step
  derivation of any word.
* **Keywords** — RAKE phrase scoring (degree/frequency word scores) and
  TF-IDF term weighting over paragraph- or sentence-sized pseudo-documents
  with smoothed idf.
* **Similarity** — Jaccard over word sets, cosine over term-frequency
  vectors, Dice over word-bigram sets, and character-level Levenshtein
  distance via a memory-safe two-row DP with a configurable cell budget.
* **Puzzles** — anagram grouping by sorted signature, palindrome detection,
  BFS shortest word ladders with a built-in four-letter dictionary, rhyme
  families by suffix, acronyms, pangram checks, letter frequencies.
* **Four output formats** — every analysis command renders as aligned text
  tables, GitHub-flavoured Markdown, pretty JSON or RFC 4180 CSV.
* **Disciplined CLI** — BSD-style exit codes (`0/1/2/66`), per-command
  `--help`, stdin-aware input handling, and invalid input reported as
  errors instead of stack traces.

## Requirements

| Dependency | Version | Notes                             |
| ---------- | ------- | --------------------------------- |
| Ruby       | ≥ 3.0   | the only hard requirement         |
| minitest   | ≥ 5.0   | development only, ships with Ruby |
| rake       | ≥ 13.0  | development only                  |

Wordcraft uses no compiled extensions, no native gems and no network access
at runtime. It runs on Linux, macOS and Windows.

## Installation

### From source (gem build)

```bash
git clone https://github.com/buifkhanh57-hub/wordcraft
cd wordcraft
gem build wordcraft.gemspec          # -> wordcraft-1.0.0.gem
gem install wordcraft-1.0.0.gem
wordcraft version                    # wordcraft 1.0.0 (Quill)
```

### As a library without installing

```bash
cd wordcraft
ruby -Ilib -e 'require "wordcraft"; puts Wordcraft::Version.label'
```

### Development setup

```bash
cd wordcraft
rake test        # run the minitest suite
rake about       # print name, version and summary
```

The executable lives in `bin/wordcraft`; a gem installation puts it on your
`PATH`. From a source checkout you can run it directly with
`ruby -Ilib bin/wordcraft <command> ...`.

## Quick Start

```bash
# 1. Top words of a document, stopwords filtered
wordcraft freq article.txt --top 15

# 2. Readability of a chapter
wordcraft readability chapter.txt

# 3. Sentiment of a review
wordcraft sentiment review.txt

# 4. Compare two drafts
wordcraft compare draft-v1.txt draft-v2.txt

# 5. Extract keywords (RAKE)
wordcraft keywords article.txt -m rake -t 8

# 6. Everything at once as JSON
wordcraft report article.txt --format json > report.json
```

A quick library taste:

```ruby
require 'wordcraft'

text = 'The quick brown fox jumps over the lazy dog. The dog barks!'

Wordcraft::Tokenizer.words(text, downcase: true).tally
# => {"the"=>2, "quick"=>1, "brown"=>1, ...}

Wordcraft::Readability.new(text).summary[:consensus_grade]
# => 0.52 (median of the five grade estimates)

Wordcraft::Sentiment.new.analyze(text)[:polarity]
# => :positive

Wordcraft::Compare.levenshtein('kitten', 'sitting')
# => 3
```

## Usage

### Subcommands

| Command       | Purpose                                                              |
| ------------- | -------------------------------------------------------------------- |
| `freq`        | word / phrase n-gram frequency with stopword filtering               |
| `readability` | Flesch, Flesch-Kincaid, Gunning Fog, SMOG, Coleman-Liau, ARI         |
| `sentiment`   | lexicon-based polarity with negation and intensifiers                |
| `stats`       | counts, averages, lexical diversity and length distributions         |
| `transform`   | 18 text transforms (case, slug, identifiers, strip, wrap, stem, ...) |
| `puzzles`     | anagrams, palindromes, word ladders (BFS), rhymes, pangrams          |
| `keywords`    | RAKE and TF-IDF keyword extraction                                   |
| `compare`     | Jaccard / cosine / Dice similarity and Levenshtein distance          |
| `report`      | combined stats + readability + sentiment + frequency report          |
| `help`        | global help                                                          |
| `version`     | version banner                                                       |

### Global conventions

* Input is a single FILE argument, `-` for stdin, or piped input.
* `-f, --format FMT` selects `text` (default), `markdown`, `json` or `csv`.
* Every subcommand accepts `-h, --help` with its own option list.
* Exit codes: `0` success, `1` unexpected failure, `2` usage error,
  `66` input file missing or unreadable.

### Example: frequency

```console
$ wordcraft freq sample.txt --top 3
Top words
word   count
-----  -----
hello  2
there  1
world  1
3 row(s)
```

```console
$ wordcraft freq sample.txt -n 2 --top 2 --no-stopwords
Top 2-gram phrases
phrase       count
-----------  -----
hello world  1
world hello  1
2 row(s)
```

### Example: stats

```console
$ wordcraft stats sample.txt
Text statistics
===============
  characters:                    25
  characters_without_spaces:     23
  letters:                       20
  digits:                         0
  spaces:                         2
  punctuation:                    2
  lines:                          1
  words:                          4
  unique_words:                   3
  sentences:                      2
  paragraphs:                     1
  avg_word_length:                5.00
  avg_sentence_length:            2.00
  ...
```

### Example: readability

```console
$ wordcraft readability sample.txt
READABILITY
===========
  words:                            4
  sentences:                        2
  syllables:                        7
  polysyllables:                    0

  Flesch Reading Ease               56.76   fairly difficult (10th-12th grade)
  Flesch-Kincaid Grade               5.84   5th-6th grade
  ...
  Consensus: 3.12 (3rd-4th grade)
```

### Example: sentiment

```console
$ wordcraft sentiment review.txt
SENTIMENT
=========
  polarity:              positive
  raw score:             6.00
  normalized:            3.00
  scored words:          2
  positive hits:         excellent, wonderful
  negative hits:

Per sentence:
  [  +6.00] An excellent, wonderful release!
```

### Example: keywords

```console
$ wordcraft keywords article.txt -m rake -t 2
Keywords (rake)
keyword                score
---------------------  -----
quick brown fox jumps  12.00
lazy dog                2.00
2 row(s)
```

```console
$ wordcraft keywords thesis.txt -m tfidf --unit paragraph -t 3
Keywords (tfidf)
keyword     score
----------  -----
cassowary   1.2877
rainforest  0.8466
canopy      0.8466
3 row(s)
```

### Example: compare

```console
$ wordcraft compare v1.txt v2.txt
Text comparison
metric    value
-------  -----
jaccard   0.78
cosine    0.91
dice      0.75
3 row(s)

$ wordcraft compare v1.txt v2.txt --metrics levenshtein
Text comparison
metric                  value
----------------------  -----
levenshtein_distance    3
levenshtein_similarity  0.93
2 row(s)
```

`--metrics` accepts any comma list of `jaccard, cosine, dice, levenshtein`.
Levenshtein is opt-in because it is character-level and quadratic; a cell
budget (`--max-cells`, default 10,000,000) refuses absurdly large inputs
with a usage error instead of hanging.

### Example: transform

```console
$ echo 'Héllo — World!' | wordcraft transform --to slug
hello-world

$ echo 'the lord of the rings' | wordcraft transform --to title
The Lord of the Rings

$ echo 'running cats' | wordcraft transform --to stem
run cat
```

### Example: puzzles

```console
$ wordcraft puzzles -m ladder --word cold --target warm
Ladder 'cold' -> 'warm'
step  word
----  ----
1     cold
2     cord
3     card
4     ward
5     warm
5 row(s)
```

### Example: report (JSON)

```console
$ wordcraft report sample.txt --format json
{
  "meta": {
    "title": "Wordcraft Text Report",
    "generator": "wordcraft 1.0.0",
    "characters": 25,
    "words": 4,
    "sentences": 2,
    "paragraphs": 1
  },
  "stats": { ... },
  "readability": { ... },
  "sentiment": { ... },
  "frequency": { ... }
}
```

## Methodology Reference

| Metric | Formula (as implemented) | Notes |
| ------ | ------------------------ | ----- |
| Flesch Reading Ease | `206.835 - 1.015*ASL - 84.6*ASW` | higher = easier |
| Flesch-Kincaid Grade | `0.39*ASL + 11.8*ASW - 15.59` | US grade level |
| Gunning Fog | `0.4 * (ASL + 100*poly/words)` | poly = 3+ syllables |
| SMOG | `1.0430*sqrt(poly*30/sentences) + 3.1291` | simplified variant |
| Coleman-Liau | `0.0588*L - 0.296*S - 15.8` | per 100 words |
| ARI | `4.71*chars/words + 0.5*ASL - 21.43` | chars = letters+digits |
| Syllables | contiguous `[aeiouy]+` groups with `-es/-ed/-e` corrections | documented heuristic |
| Porter stem | 8 steps (1a–5b), longest-match wins, `m` = VC measure | faithful 1980 rules |
| RAKE word score | `degree(w) / frequency(w)` | degree = co-memberships |
| RAKE phrase score | sum of member word scores | stopwords split phrases |
| TF-IDF | `tf * (ln((1+N)/(1+df)) + 1)` | smoothed idf, summed |
| Jaccard | `\|A∩B\| / \|A∪B\|` over word sets | both empty → 1.0 |
| Cosine | `dot(a,b) / (\|a\|*\|b\|)` over TF vectors | length-insensitive |
| Dice | `2\|A∩B\| / (\|A\|+\|B\|)` over word bigrams | order-sensitive |
| Levenshtein | unit-cost insert/delete/substitute, two-row DP | O(n·m) time, O(min) space |

`ASL` = words/sentences, `ASW` = syllables/words. Every formula returns
`nil` rather than raising when the text has no words or no sentences.

## Project Structure

```
wordcraft/
├── bin/
│   └── wordcraft                  (14)   executable wrapper -> Wordcraft::CLI.run
├── lib/
│   ├── wordcraft.rb               (81)   entry point: requires, Wordcraft.analyze, root
│   └── wordcraft/
│       ├── cli.rb                (716)   OptionParser wiring, 11 subcommands, tables
│       ├── compare.rb            (226)   Jaccard, cosine, Dice bigram, Levenshtein DP
│       ├── errors.rb             (101)   Error hierarchy + sysexits exit codes
│       ├── frequency.rb          (186)   Frequency: top words, n-grams, co-occurrence
│       ├── keywords.rb           (248)   Keywords: RAKE engine + TF-IDF
│       ├── puzzles.rb            (274)   anagrams, palindromes, BFS ladders, rhymes
│       ├── readability.rb        (272)   six formulas + bands + consensus grade
│       ├── report.rb             (287)   combined report, text/md/json/csv renderers
│       ├── sentiment.rb          (176)   negation/intensifier state machine
│       ├── stats.rb              (262)   TextStats: counts, ratios, histograms
│       ├── stemmer.rb            (375)   Porter 1980 stemmer with explain() trace
│       ├── tokenizer.rb          (251)   words, sentences, paragraphs, n-grams, syllables
│       ├── transform.rb          (454)   18 pure string transforms + lite stemmer
│       ├── version.rb            (39)    gem identity (1.0.0 "Quill")
│       └── data/
│           ├── lexicon.rb       (1058)   sentiment lexicon: POSITIVE/NEGATIVE/MODIFIERS/NEGATORS
│           └── stopwords.rb      (532)   ~460 stopword list + Set view + loader
├── test/
│   └── wordcraft_test.rb         (469)   minitest suite (34 tests)
├── .gitignore                            build/editor noise
├── LICENSE                               MIT
├── README.md                             this file
├── Rakefile                              rake test / rake about
└── wordcraft.gemspec                     gem packaging (bin + lib + data)
```

Line counts are exact for the shipped files.

## Architecture

Wordcraft is layered so that the CLI is I/O-thin and every computation is a
pure, testable module function or small class:

```
                 ┌──────────────────────────────────────────┐
                 │              bin/wordcraft               │  process boundary
                 └────────────────────┬─────────────────────┘
                                      ▼
                 ┌──────────────────────────────────────────┐
                 │               Wordcraft::CLI             │  parsing, dispatch,
                 │  (OptionParser, exit codes, renderers)   │  output formats
                 └───────┬─────────┬─────────┬─────────┬────┘
                         ▼         ▼         ▼         ▼
      ┌────────────┐ ┌──────────┐ ┌────────┐ ┌───────────┐ ┌──────────┐
      │ Frequency  │ │Readability│ │Sentiment│ │ TextStats │ │ Puzzles  │  analysis layer
      └─────┬──────┘ └────┬─────┘ └───┬────┘ └─────┬─────┘ └────┬─────┘
            │             │           │            │            │
            ▼             ▼           ▼            ▼            ▼
      ┌────────────────────────────────────────────────────────────────┐
      │                Tokenizer · Transform · Stemmer                 │  text primitives
      │                Keywords · Compare · Errors                     │  utilities
      └───────────────────────────────┬────────────────────────────────┘
                                      ▼
      ┌────────────────────────────────────────────────────────────────┐
      │                    Data: lexicon + stopwords                   │  embedded tables
      └────────────────────────────────────────────────────────────────┘
```

Key design decisions:

1. **Stdlib only.** No runtime gems: `set` for fast stopword lookup, `json`
   and `csv` for output, `optparse` for the CLI, `bigdecimal` for drift-free
   averages. Installation and air-gapped use stay trivial.
2. **One normalisation pass.** Smart quotes, dashes and ellipses are folded
   to ASCII (`Tokenizer.normalize`) before any scanning, so the same regexes
   work on text pasted from word processors or terminals.
3. **Errors as values.** `UsageError` (2), `FileNotFoundError` (66) and the
   base `Error` (1) carry their own exit codes; the CLI has exactly one
   rescue path that formats any exception through `Errors.format`.
4. **Modules over classes.** Stateless algorithms (Tokenizer, Transform,
   Stemmer, Compare, Puzzles, Keywords) are `module_function` namespaces;
   stateful analyses (Frequency, Readability, Sentiment, TextStats, Report)
   are small immutable-after-init classes.
5. **Reporters are separate from analysers.** Each analysis returns
   JSON-safe hashes; the CLI and `Report` only render. Adding a format
   never touches a formula.
6. **Auditable heuristics.** The syllable counter, the lite stemmer and the
   ladder dictionary document their quirks next to the code, and the Porter
   stemmer can dump its full derivation with `Stemmer.explain`.

## Testing

The minitest suite in `test/wordcraft_test.rb` covers every module with
hand-verified expectations (Levenshtein `kitten→sitting = 3`, Jaccard
`{a,b,c}/{b,c,d} = 0.5`, Flesch of a hand-counted sample `68.94`, the exact
`cold→cord→card→ward→warm` ladder, RAKE scores `6.0/2.0`, TF-IDF values to
4 decimals, exit codes `0/2/66`, JSON round-trips, temp-file CLI runs):

```bash
rake test
# or
ruby -Ilib -Itest test/wordcraft_test.rb
```

47 tests across 13 module suites, all stdlib-based, no network, no fixtures
beyond `Tempfile`. Because every expectation is computed by hand from the
documented formulas, the suite doubles as an executable specification of
the maths.

## FAQ

**Why another text tool?**
Because most small tasks (top words, readability grade, similarity of two
drafts) do not justify a pandas stack or an NLP service. Wordcraft is one
binary, zero dependencies, and deterministic — same input, same output.

**Is the sentiment lexicon large enough?**
It is ~650 curated entries with ordinal weights. It is designed for
transparent, explainable scoring of prose, not for benchmark-topping
accuracy. You can inject your own lexicons via `Sentiment.new(positive: ...,
negative: ..., modifiers: ..., negators: ...)`.

**Why does `stem` return "happi" and "studi"?**
That is authentic Porter behaviour — the algorithm produces *stems*, not
dictionary lemmas. For grouping word frequencies this is a feature
(consistency matters more than prettiness).

**Why is Levenshtein opt-in in `compare`?**
It is character-level and O(n·m): fine for paragraphs, hostile for books.
The word-level metrics (Jaccard/cosine/Dice) are the sensible default for
documents. When requested, a cell budget (`--max-cells`) refuses inputs
whose DP table would exceed 10 million cells.

**Are the readability scores reliable on short texts?**
They are computed exactly as documented, but any formula over 4 words is a
rough estimate. Texts without sentence terminators yield `nil` scores and
an "insufficient data" band instead of fake precision.

**Does it handle languages other than English?**
Tokenisation, statistics and the set-based similarity metrics are
language-agnostic (Unicode-aware word chars, accent folding for slugs).
Syllables, stemming, stopwords and the sentiment lexicon are English-only
by design; custom stopword lists (`--stopwords-file`) cover simpler cases.

**Can I use it in a pipeline?**
Yes — every command reads stdin, every text output is plain text, and JSON
output is `JSON.parse`-clean. Exit codes follow sysexits so `set -e`-style
scripts behave predictably.

**How do I add a transform or a puzzle?**
Transforms are one pure function in `Transform` plus one line in
`CLI::TRANSFORMS` and `CLI#apply_transform`; puzzles follow the same
pattern with `PUZZLE_MODES`. The CLI validates enumerations, so wiring is
a table edit, not logic.

## Roadmap

* More languages: portable stopword packs and a Spanish/Portuguese syllable
  heuristic.
* Optional n-gram collocation scoring (log-likelihood) next to raw counts.
* A `similarity --pairwise dir/*.txt` mode comparing many documents at once.
* Streaming report rendering for very large corpora (constant memory).
* An `explain` mode for readability (show which words drove each formula).
* Prebuilt gem releases on RubyGems and a GitHub Actions test matrix
  (3.0 / 3.2 / head).

## License

MIT — see [LICENSE](LICENSE). Wordcraft is free software; use it, fork it,
ship it.

---
**by Bui Bao Khanh**
