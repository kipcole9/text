# Text

Text & language processing for Elixir. Capabilities:

* n-gram generation from text
* pluralization of English words
* word counting (word frequencies)
* language detection — pluggable classifier, vocabulary, and corpus backends, plus a pure-Elixir port of fastText's `lid.176` model (new in v0.3)
* CLDR-canonical locale resolution from a detection (with the optional [`localize`](https://hex.pm/packages/localize) dependency)

## Installation

```elixir
def deps do
  [
    {:text, "~> 0.3.0"}
  ]
end
```

## fastText `lid.176` Language Identification

`Text.Language.Classifier.Fasttext` is a pure-Elixir reimplementation of fastText's [`lid.176`](https://fasttext.cc/docs/en/language-identification.html) model, validated bit-for-bit against the official C++ / Python reference for hashing, n-gram generation, feature extraction, and tree traversal.

It supports 176 languages, runs in pure BEAM (no NIFs, no Python sidecar), and produces predictions that match the reference within rounding for inputs whose probability is above the noise floor.

### One-time setup

The `lid.176.bin` model is approximately 126 MB and is **not** shipped with this package. Fetch it once after installing:

```sh
mix text.download_model
```

The file is written to `priv/lid_176/lid.176.bin` inside this project. It is added to `.gitignore` and is **not** part of the Hex package payload — every install fetches its own copy.

### Detecting a language

```elixir
{:ok, model} = Text.Language.Classifier.Fasttext.ModelLoader.load(
  Path.join(:code.priv_dir(:text), "lid_176/lid.176.bin")
)

{:ok, det} = Text.Language.Classifier.Fasttext.detect("Bonjour le monde", model)
det.language    #=> "fr"
det.script      #=> :Latn
det.confidence  #=> 0.984...
det.alternatives
#=> [{"en", 0.0035}, {"it", 0.0024}, {"oc", 0.0009}, {"ca", 0.0006}]
```

### Just the language code

```elixir
{:ok, "es"} = Text.Language.Classifier.Fasttext.classify("Hola mundo", model)
```

### Resolving to a CLDR locale

When the optional [`localize`](https://hex.pm/packages/localize) dependency is loaded, detections expand into full CLDR-canonical locale strings via likely-subtags. The script signal from `ScriptDetector` is used to disambiguate Latin vs Cyrillic Serbian and similar multi-script cases; for `zh` / `ja` / `ko` the language alone determines the script, so likely-subtags fills it in automatically.

```elixir
{:ok, det} = Text.Language.Classifier.Fasttext.detect("你好世界", model)
{:ok, "zh-Hans-CN"} = Text.Language.Classifier.Fasttext.to_locale(det)

{:ok, det} = Text.Language.Classifier.Fasttext.detect("Bonjour le monde", model)
{:ok, "fr-Latn-CA"} = Text.Language.Classifier.Fasttext.to_locale(det, region: :CA)
```

Without `localize` a built-in fallback table covers ~60 of the most common languages.

### Tensor backend

The model's input matrix is approximately 128 MB of `float32` data held in an `Nx` tensor. `Nx.BinaryBackend` works out of the box. The inference forward pass (`take + mean + dot`, plus `softmax` for softmax-loss models) is wrapped in `defn` so an EXLA-compiled execution runs the whole pass as a single fused kernel — three BEAM ↔ NIF transitions per prediction instead of seven. For production throughput add `:exla` to your deps and configure it as both the default backend and the default `defn` compiler:

```elixir
# config/config.exs
config :nx, default_backend: EXLA.Backend
config :nx, :default_defn_options, compiler: EXLA
```

`exla` is declared as an optional dependency of `:text`. Without it the package still works correctly — `Nx.Defn.Evaluator` runs the same `defn` graph against `Nx.BinaryBackend` — but per-prediction wall time is roughly an order of magnitude higher. See [docs/comparative_performance_report.md](docs/comparative_performance_report.md) for measured numbers.

### Quantized model

The 917 KB quantized variant `lid.176.ftz` is **not yet supported** — product-quantization decoding is on the v2 follow-up list. The 126 MB `lid.176.bin` works today and produces identical results to fastText's own predictions on it.

### Reference fixtures and differential tests

The package's test suite includes golden fixtures generated from the official `fasttext` Python bindings against `lid.176`, covering hashing, subword extraction, feature assembly, and predictions across 24 languages. The tests are skipped by default (the model is not present in CI); run them locally with:

```sh
mix text.download_model               # one-time
pip install fasttext                  # one-time, for fixture regeneration
mix test --include requires_lid_176
```

The fixture-generation scripts live under `priv/scripts/` and are wired up as `mix text.gen_*_fixtures` tasks for convenience.

## Other capabilities

### Word Counting

`text` contains an implementation of word counting that is oriented towards large streams of words rather than discrete strings. Input to `Text.Word.word_count/2` can be a `String.t`, `File.Stream.t` or `Flow.t` allowing flexible streaming of text.

### English Pluralization

`text` includes an inflector for the English language that takes an approach based upon  [An Algorithmic Approach to English Pluralization](http://users.monash.edu/~damian/papers/HTML/Plurals.html). See the module `Text.Inflect.En` and the functions:

* `Text.Inflect.En.pluralize/2`
* `Text.Inflect.En.pluralize_noun/2`
* `Text.Inflect.En.pluralize_verb/1`
* `Text.Inflect.En.pluralize_adjective/1`

### Sentiment analysis

`Text.Sentiment` runs sentiment analysis with multilingual support. Two backends are shipped:

* **`Text.Sentiment.Backends.Lexicon`** (the default) — lexicon-based scoring backed by the bundled [AFINN](https://github.com/fnielsen/afinn) lexicons (Apache 2.0) for **English, Danish, Finnish, French, Polish, Swedish, and Turkish**, plus a language-agnostic emoticon lexicon. Sub-millisecond per call, fully deterministic, no model download.

* **`Text.Sentiment.Backends.Bumblebee`** (optional) — neural sentiment via [Bumblebee](https://hex.pm/packages/bumblebee) and a pre-trained multilingual XLM-RoBERTa model (`cardiffnlp/twitter-xlm-roberta-base-sentiment` by default). Higher quality, particularly on idiom and sarcasm, at the cost of a 10–30 s cold start and a ~280 MB model download. Add `{:bumblebee, "~> 0.6"}` and `{:exla, "~> 0.9"}` to your deps to enable it.

Switch backends globally:

```elixir
# config/config.exs
config :text, :sentiment_backend, Text.Sentiment.Backends.Bumblebee
```

…or per call:

```elixir
Text.Sentiment.analyze(text, backend: Text.Sentiment.Backends.Bumblebee)
```

Custom backends are supported via the `Text.Sentiment.Backend` behaviour.

#### Default usage (lexicon backend)

```elixir
Text.Sentiment.analyze("This is a great day, I love it!").label
#=> :positive

Text.Sentiment.analyze("Ce produit est excellent et magnifique!", language: :fr).label
#=> :positive

Text.Sentiment.analyze("Detta är en mycket dålig idé.", language: :sv).label
#=> :negative
```

The scoring engine handles **negation** (`"not good"` → negative) and **intensifiers** (`"very good"` scores higher than `"good"`) using simple, well-understood scalars from VADER. The full result includes a raw sum, a normalised compound score in `[-1.0, +1.0]`, the matched-token count, and the resolved language tag.

For informal text containing emoticons, merge the bundled emoticon lexicon:

```elixir
lex = Text.Sentiment.lexicon_for(:en, with_emoticons: true)
Text.Sentiment.analyze("That movie was awful :-(", lexicon: lex).label
#=> :negative
```

When the input language is unknown, detect it first with `Text.Language.Classifier.Fasttext` and route to the matching lexicon:

```elixir
{:ok, model} = Text.Language.Classifier.Fasttext.ModelLoader.load(model_path)
{:ok, detection} = Text.Language.Classifier.Fasttext.detect(text, model)
lang = String.to_atom(detection.language)
Text.Sentiment.analyze(text, language: lang)
```

Detected languages outside the bundled set fall back to English by default. For unsupported languages, supply your own `%{token => number}` lexicon via the `:lexicon` option — anything `Map`-like works.

The lexicon-based approach trades sophistication for speed and determinism: it produces useful labels in a few microseconds with no model download, but doesn't capture sarcasm, idiom, or context. When you need that, switch to the Bumblebee backend.

#### Bumblebee backend (neural multilingual)

```elixir
# Add to mix.exs:
#   {:bumblebee, "~> 0.6"}
#   {:exla, "~> 0.9"}

result = Text.Sentiment.analyze(
  "J'adore ce produit, c'est excellent!",
  backend: Text.Sentiment.Backends.Bumblebee
)
result.label    #=> :positive
result.compound #=> 0.94...
result.scores   #=> %{positive: 0.95, neutral: 0.04, negative: 0.01}
```

The first call downloads the model (~280 MB) and traces the inference graph through EXLA. Subsequent calls in the same VM hit a cached `Nx.Serving` and return in single-digit milliseconds. For production deployments where cold-start is unacceptable, start a named serving at boot (see `Bumblebee.Text.text_classification/3` + `Nx.Serving.start_link/1`) and pass `serving: <name>` to `analyze/2`.

#### Language input

Every function that takes a `:language` (or `:locale`) accepts:

* an atom (`:fr`),
* a string (`"fr"`, `"fr-CA"`, `"zh-Hans-CN"`),
* or a `Localize.LanguageTag` struct when the optional [`localize`](https://hex.pm/packages/localize) dependency is loaded.

The full BCP-47 form is normalised to its language subtag for sentiment-lexicon lookup, so `"fr-CA"`, `"FR"`, `:fr`, and `%Localize.LanguageTag{language: :fr, ...}` all route to the French lexicon.

### N-Gram generation

The `Text.Ngram` module supports efficient generation of n-grams of length `2` to `7`. See `Text.Ngram.ngram/2`.

## Roadmap

Near-term improvements aimed at the fastText path:

* **Quantized model support.** Decode the 917 KB `lid.176.ftz` variant via product quantization to enable smaller deployments. Today only the 126 MB `lid.176.bin` is supported.

* **Hans / Hant disambiguation.** `lid.176` reports `zh` for both Simplified and Traditional Chinese; `Text.Language.Classifier.Fasttext.ScriptDetector` currently folds both to `:Hani`. A codepoint-frequency analysis against the [Unihan Variants](https://www.unicode.org/reports/tr38/) database can split them, allowing `to_locale/2` to distinguish `zh-Hans-CN` from `zh-Hant-TW` without an explicit hint.

* **Vectorise the Huffman DFS.** The hierarchical-softmax traversal currently runs in pure Elixir over a precomputed logits tensor, costing roughly half of the ~100 μs per-call budget. Encoding each leaf's path as a fixed-length matrix would let EXLA score all 176 leaves in one fused kernel.

* **`Nx.Serving` for batched inference.** When throughput matters more than latency, batching predictions into a single EXLA call is a substantial multiplier.

Beyond the fastText classifier, the longer-running interest is locale-aware text segmentation:

* Finish the [Unicode regular expression](http://unicode.org/reports/tr18/) engine in [unicode_set](https://github.com/elixir-unicode/unicode_set), then implement basic Unicode word and sentence segmentation in [unicode_string](https://github.com/elixir-unicode/unicode_string), with CLDR tailorings on top.

* Snowball-based stemming, once the segmentation primitives exist to drive it.

These segmentation pieces live outside this package and are tracked in the linked repositories.
