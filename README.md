# Text

Text & language processing for Elixir.

### Detection and analysis

* **Language identification** (`Text.Language.Classifier.Fasttext`) — pure-Elixir port of fastText's `lid.176`, supporting 176 languages.
* **Locale resolution** (`Text.Language.Classifier.Fasttext.Locale`) — CLDR likely-subtags via the optional [`localize`](https://hex.pm/packages/localize) dep, with Simplified / Traditional Chinese (`Hans` / `Hant`) disambiguation from script analysis.
* **Sentiment analysis** (`Text.Sentiment`) — multilingual, two backends: bundled AFINN lexicons (default, 7 languages) or Bumblebee + XLM-RoBERTa (optional, ~30 languages).
* **Part-of-speech tagging** (`Text.POS`) — via Bumblebee; English by default.
* **Named-entity recognition** (`Text.NER`) — via Bumblebee; multilingual by default (10 languages).

### Strings

* **String distance** (`Text.Distance`) — Levenshtein, Damerau-Levenshtein, Hamming, Jaro, Jaro-Winkler.
* **Set similarity** (`Text.Similarity`) — Jaccard, Dice, overlap, cosine.
* **Phonetic encoding** (`Text.Phonetic.Soundex`, `Text.Phonetic.Metaphone`).
* **Slugification** (`Text.Slug`) — locale-aware Unicode folding via [`unicode_transform`](https://hex.pm/packages/unicode_transform), with cross-script transliteration.
* **Segmentation** (`Text.Segment`) — UAX #29 word and sentence boundaries via [`unicode_string`](https://hex.pm/packages/unicode_string), with CLDR abbreviation suppressions.

### Statistics and search

* **N-grams and word counts** (`Text.Ngram`, `Text.Word`).
* **TF-IDF and BM25** (`Text.IR`) — indexed corpus with scoring and top-K search.
* **Collocation extraction** (`Text.Collocation`) — bigrams ranked by frequency, PMI, or Dunning's log-likelihood.
* **Concordance** (`Text.KWIC`) — keyword-in-context lookup.
* **Word embeddings** (`Text.Embedding`) — load fastText-format `.vec` files, then cosine similarity, nearest neighbours, and analogies (`king - man + woman ≈ queen`).
* **Word clouds** (`Text.WordCloud`) — multilingual keyword extraction with five scoring algorithms (YAKE!, frequency, RAKE, TextRank, TF-IDF, KeyBERT), plus spiral layout (`Text.WordCloud.Layout`) for any rendering surface.
* **Stopwords** (`Text.Stopwords`) — bundled stopword lists for ~60 languages from [stopwords-iso](https://github.com/stopwords-iso/stopwords-iso).

### Inflection

* **English pluralization** (`Text.Inflect.En`) — modern and classical modes.

### Language input

Every public function that takes a `:language` (or `:locale`) option accepts an atom (`:fr`), a string (`"fr"`, `"fr-CA"`, `"zh-Hans-CN"`), or a `Localize.LanguageTag` struct (when `:localize` is loaded). See `Text.Language` for the normalisation helpers.

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

For production deployments that also use `Text.Sentiment.Backends.Bumblebee`, `Text.POS`, or `Text.NER`, run `mix text.download_models` (plural) instead — it pre-fetches `lid.176.bin` plus every default Hugging Face model into the Bumblebee cache so subsequent calls run with no network access. See `mix help text.download_models` for selection flags.

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

When the optional [`localize`](https://hex.pm/packages/localize) dependency is loaded, detections expand into full CLDR-canonical locale strings via likely-subtags. The script signal from `ScriptDetector` is used to disambiguate Latin vs Cyrillic Serbian and similar multi-script cases.

For Chinese, `ScriptDetector` runs a second-pass codepoint-frequency analysis to distinguish Simplified (`Hans`) from Traditional (`Hant`) using curated lists of distinguishing characters. Inputs containing only shared Han codepoints fall back to the generic `Hani` and likely-subtags then picks `Hans` (the mainland-China default).

```elixir
{:ok, det} = Text.Language.Classifier.Fasttext.detect("你好世界，这是简体中文。", model)
{:ok, "zh-Hans-CN"} = Text.Language.Classifier.Fasttext.to_locale(det)

{:ok, det} = Text.Language.Classifier.Fasttext.detect("你好世界，這是繁體中文。", model)
{:ok, "zh-Hant-TW"} = Text.Language.Classifier.Fasttext.to_locale(det)

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

This configuration matters even more for the Bumblebee-backed
modules (`Text.Sentiment.Backends.Bumblebee`, `Text.POS`, `Text.NER`)
— without EXLA, every layer of the underlying transformer runs on
the interpreted backend, slowing each prediction by an order of
magnitude.

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

### Word embeddings

`Text.Embedding` loads pre-trained word vectors in fastText `.vec` format and exposes lookup, cosine similarity, nearest-neighbour search, and analogies:

```elixir
{:ok, emb} = Text.Embedding.load("path/to/cc.en.300.vec")

Text.Embedding.similarity(emb, "king", "queen")
#=> 0.84

Text.Embedding.nearest(emb, "king", k: 3)
#=> [{"queen", 0.84}, {"prince", 0.79}, {"monarch", 0.77}]

Text.Embedding.analogy(emb, "king", "man", "woman", k: 1)
#=> [{"queen", 0.71}]
```

A typical pre-trained fastText vector file is several gigabytes; pass `:filter` to load only a domain-specific vocabulary, or `:max_tokens` for tests and quick experiments. The matrix is held as a single `Nx` tensor of shape `{n, dim}`.

### Part-of-speech tagging and named-entity recognition

`Text.POS` and `Text.NER` wrap [Bumblebee](https://hex.pm/packages/bumblebee)'s `token_classification` serving with sensible defaults — English POS, multilingual NER (10 high-resource languages):

```elixir
# Add to mix.exs:
#   {:bumblebee, "~> 0.6"}
#   {:exla, "~> 0.9"}

Text.POS.tag("The cat sat on the mat.")
#=> [{"the", :det, 0.99}, {"cat", :noun, 0.99}, ...]

Text.NER.extract("Barack Obama visited Berlin in 2013.")
#=> [
#=>   %Text.NER.Entity{text: "Barack Obama", type: :per, start: 0, end: 12, score: 0.99},
#=>   %Text.NER.Entity{text: "Berlin", type: :loc, start: 21, end: 27, score: 0.99}
#=> ]
```

Both modules are no-op (compile to a runtime-raise) without `:bumblebee`. First call downloads and compiles the model (~440 MB POS, ~700 MB NER); subsequent calls hit a cached `Nx.Serving`.

Override the default model via `:model` to use a language-specific or domain-specific checkpoint.

### N-Gram generation

The `Text.Ngram` module supports efficient generation of n-grams of length `2` to `7`. See `Text.Ngram.ngram/2`.

### Word clouds

`Text.WordCloud.terms/2` extracts a weighted list of terms from text, suitable for rendering as a word cloud. Default scoring is YAKE! (Campos et al. 2020) — unsupervised, statistical, multilingual by construction; no reference corpus required.

```elixir
text = """
Machine learning is a subset of artificial intelligence. Machine learning
algorithms build a model based on sample data, known as training data,
in order to make predictions or decisions.
"""

Text.WordCloud.terms(text, language: :en, max_terms: 5)
#=> [
#=>   %{term: "machine learning", weight: 1.0,   count: 2, kind: :phrase},
#=>   %{term: "machine",          weight: 0.52,  count: 3, kind: :word},
#=>   %{term: "learning",         weight: 0.29,  count: 3, kind: :word},
#=>   %{term: "artificial intelligence", weight: 0.23, count: 1, kind: :phrase},
#=>   %{term: "training data",    weight: 0.10,  count: 1, kind: :phrase}
#=> ]
```

Six scoring backends, selectable via the `:scoring` option:

* **`:yake`** *(default)* — unsupervised, multilingual, no reference corpus. Best out-of-the-box quality.
* **`:frequency`** — raw counts after stopword filtering. Baseline.
* **`:rake`** — phrase-bounded scoring (Rose et al. 2010).
* **`:text_rank`** — PageRank over a word co-occurrence graph (Mihalcea & Tarau 2004).
* **`:tf_idf`** — distinctive terms relative to a `:reference_corpus`.
* **`:key_bert`** — neural cosine similarity via a multilingual sentence-transformer (requires `:bumblebee`; ~470 MB model download).

Stopwords come from `Text.Stopwords` (bundled stopwords-iso, ~60 languages). The `:language` option drives stopword selection; pass `{:auto, model}` for fastText auto-detection. See `Text.WordCloud` for the full option list.

#### Layout

`Text.WordCloud.Layout.layout/2` takes the term list and produces `(x, y, width, height, font_size, rotation)` placements via Wordle-style Archimedean-spiral packing. Output is renderer-agnostic — feed it to SVG, Canvas, PDF, or any other surface.

```elixir
terms = Text.WordCloud.terms(text, language: :en)

placements = Text.WordCloud.Layout.layout(terms,
  width: 800,
  height: 600,
  font_size_range: {12, 96},
  rotations: [0, 90]
)
#=> [%{term: "machine learning", x: 400.0, y: 300.0, font_size: 96.0, rotation: 0, ...}, ...]
```

## Roadmap

Near-term improvements aimed at the fastText path:

* **Quantized model support.** Decode the 917 KB `lid.176.ftz` variant via product quantization to enable smaller deployments. Today only the 126 MB `lid.176.bin` is supported.

* **`Nx.Serving` for batched inference.** When throughput matters more than latency, batching predictions into a single EXLA call is a substantial multiplier.

Beyond the fastText classifier, the longer-running interest is locale-aware text segmentation:

* Finish the [Unicode regular expression](http://unicode.org/reports/tr18/) engine in [unicode_set](https://github.com/elixir-unicode/unicode_set), then implement basic Unicode word and sentence segmentation in [unicode_string](https://github.com/elixir-unicode/unicode_string), with CLDR tailorings on top.

* Snowball-based stemming, once the segmentation primitives exist to drive it.

These segmentation pieces live outside this package and are tracked in the linked repositories.
