# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.3.0] — Unreleased

### Added

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

* Hex package version bumped to `0.3.0`.

### Removed

* **Breaking:** the legacy n-gram language classifiers (`Text.Language.Classifier.NaiveBayesian`, `CummulativeFrequency`, `RankOrder`) and their supporting modules (`Text.Language`, `Text.Language.Classifier`, `Text.Corpus`, `Text.Vocabulary`). These required a separately-installed corpus (`text_corpus_udhr`) and were not competitive with the fastText classifier on inputs outside the UDHR register. Use `Text.Language.Classifier.Fasttext.classify/2` and `detect/3` instead.

* The `:meeseeks` build-time HTML scraper dependency, which was unmaintained for modern Rust toolchains. The English-inflection data scraper at `mix/english_infector_data.ex` is now wrapped in a `Code.ensure_loaded?(Meeseeks)` guard and is a no-op without the optional dep — it was only used to regenerate inflection data, never at runtime.

# Changelog for Text v0.2.0

This is the changelog for Text v0.2.0 released on June 28th, 2020. For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/text/tags).

### Enhancements

* Adds pluralization for english words

* Adds language detection classifiers (corpus' are defined in separate libraries, for example [text_corpus_udhr](https://hex.pm/packages/text_corpus_udhr))

* Refactor word counting

# Changelog for Text v0.1.0

This is the changelog for Text v0.1.0 released on August 26th, 2019.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/text/tags)

### Enhancements

* Initial version implementing `ngram`s.

