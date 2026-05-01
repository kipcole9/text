# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.5.0] — 2026-05-02

### Added

* `Text.Phonetic.NYSIIS` — New York State Identification and Intelligence System phonetic encoding (Taft, 1970). Designed as a Soundex successor for English personal-name matching; produces pronounceable letter codes rather than digits and is more discriminating than Soundex on common name variations.

* `Text.Phonetic.Cologne` — Kölner Phonetik (Postel, 1969), the German-language counterpart to Soundex. Optimized for German spelling variants — `Müller` / `Mueller` / `Muller` and `Meyer` / `Mayer` / `Maier` / `Meier` collapse to single codes.

* `Text.Phonetic.DoubleMetaphone` — Lawrence Philips' Double Metaphone (2000), the de-facto standard for fuzzy English-name matching with non-Anglo origins. Returns a `{primary, alternate}` code pair so the same Anglicised name can match across multiple plausible pronunciations (e.g. `Smith` ↔ `Schmidt`, `Catherine` ↔ `Katherine`). Handles Germanic, Italian, Spanish, French, Greek, and Slavic patterns.

* `match?/2` (and `match?/3` where options apply) on every `Text.Phonetic.*` module for direct equality comparison without manual `encode/2 == encode/2` boilerplate. `Text.Phonetic.DoubleMetaphone.match?/3` checks all four primary/alternate combinations.

* `Text.Clean.unaccent/1` — strip diacritics and fold non-decomposable Latin letters (`Þ` → `Th`, `ß` → `ss`, `Æ` → `AE`, `ł` → `l`, `đ` → `d`) by delegating to `Unicode.Transform.LatinAscii.transform/1`. Also exposed as the `:unaccent` option on `Text.Clean.clean/2`.

* `Text.Distance` gains four set-based similarity metrics over character n-grams: `jaccard/3`, `sorensen_dice/3`, `tanimoto/3` (alias for `jaccard/3`), and `cosine/3`. All accept an `:n` option for configurable shingle size (default 2). Operate at the grapheme level for Unicode correctness.

* `Text.Inflect.En.singularize/2` and `Text.Inflect.En.singularize_noun/2` — invert the existing pluralizer. Combines reverse lookup of Conway's irregular tables, explicit suffix rules for unambiguous English plural forms (`-ies`, `-shes`/`-ches`/`-xes`/`-zes`/`-sses`), small whitelists for Greek-derived `-is`/`-es` plurals (`analyses → analysis`) and English `-us` plurals (`geniuses → genius`), and a `pluralize/2` round-trip search to validate other candidates.

### Fixed

* `Text.Inflect.En.Helpers.replace_suffix/3` now actually replaces only the trailing suffix instead of all repeated trailing occurrences, fixing cases like `theses` (which previously transformed to `thisis` instead of `thesis` because both `es` occurrences were rewritten). Affects rule output where the suffix repeats inside the base word.

## [0.4.0] — 2026-05-01

### Added

* `Text.Truecase` — case restoration for ALL-CAPS or lowercased text using POS-aware heuristics for proper nouns, acronyms, and sentence starts.

* `Text.Clean` — pipeline-style normalization (whitespace, control characters, smart-quotes, dashes, NFC/NFKC) with a composable `clean/2` API.

* `Text.Emoji` — emoji detection, stripping, and counting. Uses the `:unicode` package's emoji property tables; no external data required.

* `Text.Hyphenation` — Knuth–Liang TeX-pattern hyphenation. Ships en-US patterns (~5k); other languages can be loaded via `Text.Hyphenation.Parser` from any `hyph-*.tex` file.

* `Text.PII` — pattern-based detection and redaction of phone numbers, emails, credit-card-shaped digits, IBANs, IPv4/IPv6, and US SSNs.

* `Text.Spell` — Norvig-style edit-distance spelling suggestions backed by `Text.WordFreq`. Returns ranked candidates with their corpus frequency.

* `Text.Summarize` — extractive summarization via a sentence-graph TextRank with configurable similarity (`:cosine` or `:jaccard`) and target length.

* `Text.Syllable` — English syllable counting using a vowel-group heuristic with override exceptions. Used as the per-word syllable signal feeding `Text.Readability`.

* `Text.Readability` — Flesch, Flesch–Kincaid, Gunning-Fog, SMOG, Coleman–Liau, ARI, and Linsear-Write scores plus a unified `analyze/2` summary.

* `Text.WordFreq` — frequency lookup over a 30k-word English corpus shipped in `priv/wordfreq/en.tsv`. Provides `rank/2`, `frequency/2`, `is_common?/2`, and `top/2`.

* `Text.Lemma` — dictionary-based lemmatization. Ships an en-US table of ~42k inflected→base mappings; `lookup/2` falls back to the input when no entry exists.

* `Text.Inflect.En.Pluralize` and `Text.Inflect.En.Singularize` — English noun inflection covering ~1.6 KLoC of irregular-form rules and exceptions, with `Text.Inflect.En.Helpers` for shared morphology utilities.

* `Text.Sentiment.Lexicons.AFINN` now ships sentiment lexicons for **104 languages** (up from 7), an Emoji Sentiment Ranking 1.0 lexicon (`:emoji`, ~840 entries derived from the upstream corpus and rescaled onto AFINN's −5..+5 integer range), and per-language negator lists (`negators/1`). The seven hand-curated 0.3.0 lexicons (`:en`, `:da`, `:fi`, `:fr`, `:pl`, `:sv`, `:tr`) are preserved unchanged; the other ~95 are upstream machine-translated and ship as a baseline.

* `Text.Sentiment.Backends.Lexicon` automatically resolves per-language negators from `Text.Sentiment.Lexicons.AFINN.negators/1` based on the requested `:language` option, so non-English text gets negation handling out of the box. Callers can still override with an explicit `:negators` list.

* `mix text.gen_afinn_lexicons` regenerates `priv/sentiment/` from the vendored `data/affin/` source files. Hand-curated TSVs are preserved unless `--overwrite` is passed.

### Changed

* The `:unicode_string` dependency requirement is `~> 2.1`. The 2.1 release replaces its regex evaluator with a single-pass DFA engine; benchmarks show ~17× faster word-cloud builds for typical English prose, with linear (rather than O(N²)) scaling on long unbroken inputs.

* `Text.Word.word_count/2` documentation now explicitly calls out that the default `&String.split/1` splitter does not implement UAX #29 segmentation and does not work for languages without inter-word whitespace (Chinese, Japanese, Korean, Thai, Lao, Khmer, Burmese). Examples show how to pass a UAX-aware or dictionary-aware splitter for those cases.

## [0.3.0] — 2026-04-29

### Added

* `Text.WordCloud` — multilingual keyword extraction returning a weighted term list suitable for rendering as a word cloud. Six backends: YAKE! (default, unsupervised statistical), frequency, RAKE, TextRank, TF-IDF (requires `:reference_corpus`), and KeyBERT (neural, requires `:bumblebee`). The `:stem` option (requires the optional `:text_stemmer` dependency) buckets morphological variants — `demolish`, `demolished`, `demolishing` — into a single entry labelled with the most-frequent surface form.

* `Text.WordCloud.Layout` — Wordle-style Archimedean-spiral packing that produces renderer-agnostic `(x, y, width, height, font_size, rotation)` placements. Pluggable `:font_metrics` callback so callers can supply pixel-accurate metrics from their actual font stack.

* `Text.WordCloud.SVG` — renders placements as a self-contained SVG document. Pluggable `:palette` (list of hex strings, a `Color.Palette.Tonal` scale, a `Color.Palette.Theme`, or `nil` for single-colour) plus three mapping strategies (`:by_weight`, `:by_index`, `:by_hash`). Hex-string palettes work without optional deps; `Color.Palette` structs require the optional `:color` dependency.

* `Text.Stopwords` — bundled multilingual stopword lists from [stopwords-iso](https://github.com/stopwords-iso/stopwords-iso) (~60 languages, MIT license). Public API: `for/1`, `contains?/2`, `available_languages/0`, `available?/1`, `union/2`, `extend/2`. Generation tooling lives in `mix text.gen_stopwords`.

* `mix text.download_models --keybert` — pre-fetches the multilingual MiniLM sentence-transformer used by `Text.WordCloud.Backends.KeyBERT` (~470 MB). The `--bumblebee` shorthand now includes `--keybert` alongside `--sentiment --pos --ner`.

* `Text.POS` — part-of-speech tagging via the optional `:bumblebee` dependency. English by default (`vblagoje/bert-english-uncased-finetuned-pos`); override `:model` for other checkpoints. Returns coarse-grained tag atoms (`:noun`, `:verb`, `:adj`, …) with confidence scores.

* `Text.NER` — named-entity recognition via the optional `:bumblebee` dependency. Multilingual by default (`Davlan/bert-base-multilingual-cased-ner-hrl`, 10 high-resource languages, CoNLL-2003 tag set). Returns `Text.NER.Entity` structs with span byte offsets, type atom (`:per`, `:org`, `:loc`, `:misc`), and score.

* `Text.Embedding` — load pre-trained word vectors in fastText `.vec` format. Exposes `vector/2`, `similarity/3`, `nearest/3`, and `analogy/5` over an L2-normalised `Nx` matrix. Supports `:filter` and `:max_tokens` options for partial loads.

* `Text.Language.Classifier.Fasttext.ScriptDetector.han_variant/1` — disambiguates Simplified (`:Hans`) from Traditional (`:Hant`) Chinese using a curated codepoint-frequency analysis. `detect/1` now returns `:Hans` or `:Hant` directly for Han text when the input is unambiguous, falling back to `:Hani` otherwise. The script signal flows through to `Text.Language.Classifier.Fasttext.Locale.resolve/2`, producing `zh-Hans-CN` vs `zh-Hant-TW` automatically.

* `Text.Language.normalize/1` and `Text.Language.to_locale_string/1` — every public function in the package that takes a `:language` or `:locale` option now accepts an atom, a string (BCP-47 or otherwise), or a `Localize.LanguageTag` struct (when the optional `:localize` dependency is loaded). The new helpers normalise to the language subtag (atom) or to a canonical BCP-47 string respectively.

* `Text.Sentiment.Backend` behaviour with two shipped backends: `Text.Sentiment.Backends.Lexicon` (the default — lexicon-based, multilingual via AFINN, always available) and `Text.Sentiment.Backends.Bumblebee` (optional — neural via [Bumblebee](https://hex.pm/packages/bumblebee) and XLM-RoBERTa, requires `:bumblebee` and `:exla` deps). Routing via the `:backend` option to `Text.Sentiment.analyze/2` or globally via the `:sentiment_backend` application configuration.

* `Text.Sentiment` — multilingual lexicon-based sentiment analysis. Returns a label (`:positive`, `:negative`, `:neutral`), a normalised compound score, and the matched-token count. Handles negation (`"not good"` flips polarity) and intensifiers (`"very good"` boosts) via VADER-style scalars.

* `Text.Sentiment.Lexicons.AFINN` — bundled [AFINN](https://github.com/fnielsen/afinn) sentiment lexicons (Apache 2.0) for English, Danish, Finnish, French, Polish, Swedish, and Turkish, plus a language-agnostic emoticon lexicon. Routed automatically by `Text.Sentiment.analyze/2`'s `:language` option.

* `Text.Sentiment.lexicon_for/2` — composes a per-language lexicon with the emoticon lexicon and/or domain-specific overrides.

* `Text.Language.Classifier.Fasttext` — a pure-Elixir port of fastText's `lid.176` language identification model. Validated bit-for-bit against the official C++/Python reference for hashing, subword extraction, feature assembly, and tree traversal. See the README for usage.

* `Text.Language.Classifier.Fasttext.ModelLoader.load/2` parses an `lid.176.bin` file (~126 MB) into a typed `Model` struct with the input/output matrices held as `Nx` tensors.

* `Text.Language.Classifier.Fasttext.detect/3`, `classify/2`, and `to_locale/2` for the public detection API.

* `Text.Language.Classifier.Fasttext.ScriptDetector` for Unicode-script-of-text classification, used to disambiguate multi-script locales (e.g. `sr-Latn` vs `sr-Cyrl`). Backed by the [`unicode`](https://hex.pm/packages/unicode) Hex package.

* `Text.Language.Classifier.Fasttext.Locale.resolve/2` for CLDR-canonical locale assembly via likely-subtags. Uses the optional [`localize`](https://hex.pm/packages/localize) dependency when present, with a built-in fallback table for the most common languages otherwise.

* `mix text.download_lid176` task that fetches `lid.176.bin` into `priv/lid_176/`. The model file is gitignored and not part of the Hex package.

* `mix text.download_models` task (plural) that pre-fetches every external model used by `:text` — `lid.176.bin` plus the default Hugging Face checkpoints behind `Text.Sentiment.Backends.Bumblebee`, `Text.POS`, and `Text.NER` — for production environments that need every artefact present at boot. Selection flags (`--lid176`, `--sentiment`, `--pos`, `--ner`, `--bumblebee`) limit the download to a subset.

* `mix text.gen_subword_fixtures`, `mix text.gen_features_fixtures`, `mix text.gen_predict_fixtures` (via `priv/scripts/*.py`) for regenerating the differential test fixtures against the reference `fasttext` Python bindings.

* `docs/lid176_binary_format.md` — full byte-layout specification of fastText's model file, derived from the C++ source.

### Changed

* The minimum Elixir version is now `~> 1.17` (raised from `~> 1.8`). All development and testing targets Elixir 1.20 on Erlang/OTP 28.

* Added required dependencies on `:nx` and `:unicode`. Optional dependencies on `:exla` (recommended for inference performance) and `:localize` (for CLDR-canonical locale resolution).

* The fastText inference forward pass (`take + mean + dot`, plus the softmax tail for softmax-loss models) is now wrapped in `Nx.Defn` so that an EXLA-compiled execution runs the entire pass as a single fused XLA kernel. With EXLA configured as both backend and `defn` compiler, per-prediction wall time on `lid.176` drops from roughly 200 μs to ~100 μs — about 2× over the unfused EXLA path and 6-9× over `Nx.BinaryBackend`. Bit-equivalent to the pre-fusion form; the test suite passes both ways.

* The hierarchical-softmax scoring path is now also fused into the same `defn` graph: per-leaf paths through the Huffman tree are pre-computed at model load time and stored as fixed-shape tensors on `Text.Language.Classifier.Fasttext.HuffmanTree`. The recursive BEAM-side DFS (and its accompanying f32-rounding workaround) is gone. For `lid.176` specifically the latency is comparable to the previous DFS approach (~125 μs vs ~110 μs) — the win materialises for larger label spaces. The simpler architecture removes a fragile spot.

* Hex package version bumped to `0.3.0`.

### Removed

* **Breaking:** the legacy n-gram language classifiers (`Text.Language.Classifier.NaiveBayesian`, `CummulativeFrequency`, `RankOrder`) and their supporting modules (`Text.Language`, `Text.Language.Classifier`, `Text.Corpus`, `Text.Vocabulary`). These required a separately-installed corpus (`text_corpus_udhr`) and were not competitive with the fastText classifier on inputs outside the UDHR register. Use `Text.Language.Classifier.Fasttext.classify/2` and `detect/3` instead.

* The `:meeseeks` build-time HTML scraper dependency along with the English-inflection scraper module (`Text.Inflect.Data.En`) and its `mix text.create_english_plurals` task. Pluralization data continues to ship as a precompiled ETF blob in `priv/inflection/en/en.etf`; only the regeneration tooling is gone.

* `Text.Ngram.Frequency` struct, `Text.frequency_tuple` typedef, and the `Text.ensure_compiled?/1` helper. All three existed solely to support the deleted classifier behaviour and had no other callers.

## [0.2.0] — 2020-06-28

### Added

* Pluralization for English words.

* Language detection classifiers — corpora defined in separate libraries, e.g. [text_corpus_udhr](https://hex.pm/packages/text_corpus_udhr).

### Changed

* Refactored word counting.

## [0.1.0] — 2019-08-26

### Added

* Initial version implementing `ngram`s.

