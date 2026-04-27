# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.3.0] — Unreleased

### Added

* `Text.Sentiment` — multilingual lexicon-based sentiment analysis. Returns a label (`:positive`, `:negative`, `:neutral`), a normalised compound score, and the matched-token count. Handles negation (`"not good"` flips polarity) and intensifiers (`"very good"` boosts) via VADER-style scalars.

* `Text.Sentiment.Lexicons.AFINN` — bundled [AFINN](https://github.com/fnielsen/afinn) sentiment lexicons (Apache 2.0) for English, Danish, Finnish, French, Polish, Swedish, and Turkish, plus a language-agnostic emoticon lexicon. Routed automatically by `Text.Sentiment.analyze/2`'s `:language` option.

* `Text.Sentiment.lexicon_for/2` — composes a per-language lexicon with the emoticon lexicon and/or domain-specific overrides.

* `Text.Language.Classifier.Fasttext` — a pure-Elixir port of fastText's `lid.176` language identification model. Validated bit-for-bit against the official C++/Python reference for hashing, subword extraction, feature assembly, and tree traversal. See the README for usage.

* `Text.Language.Classifier.Fasttext.ModelLoader.load/2` parses an `lid.176.bin` file (~126 MB) into a typed `Model` struct with the input/output matrices held as `Nx` tensors.

* `Text.Language.Classifier.Fasttext.detect/3`, `classify/2`, and `to_locale/2` for the public detection API.

* `Text.Language.Classifier.Fasttext.ScriptDetector` for Unicode-script-of-text classification, used to disambiguate multi-script locales (e.g. `sr-Latn` vs `sr-Cyrl`). Backed by the [`unicode`](https://hex.pm/packages/unicode) Hex package.

* `Text.Language.Classifier.Fasttext.Locale.resolve/2` for CLDR-canonical locale assembly via likely-subtags. Uses the optional [`localize`](https://hex.pm/packages/localize) dependency when present, with a built-in fallback table for the most common languages otherwise.

* `mix text.download_model` task that fetches `lid.176.bin` into `priv/lid_176/`. The model file is gitignored and not part of the Hex package.

* `mix text.gen_subword_fixtures`, `mix text.gen_features_fixtures`, `mix text.gen_predict_fixtures` (via `priv/scripts/*.py`) for regenerating the differential test fixtures against the reference `fasttext` Python bindings.

* `docs/lid176_binary_format.md` — full byte-layout specification of fastText's model file, derived from the C++ source.

### Changed

* The minimum Elixir version is now `~> 1.17` (raised from `~> 1.8`). All development and testing targets Elixir 1.20 on Erlang/OTP 28.

* Added required dependencies on `:nx` and `:unicode`. Optional dependencies on `:exla` (recommended for inference performance) and `:localize` (for CLDR-canonical locale resolution).

* The fastText inference forward pass (`take + mean + dot`, plus the softmax tail for softmax-loss models) is now wrapped in `Nx.Defn` so that an EXLA-compiled execution runs the entire pass as a single fused XLA kernel. With EXLA configured as both backend and `defn` compiler, per-prediction wall time on `lid.176` drops from roughly 200 μs to ~100 μs — about 2× over the unfused EXLA path and 6-9× over `Nx.BinaryBackend`. Bit-equivalent to the pre-fusion form; the test suite passes both ways.

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

