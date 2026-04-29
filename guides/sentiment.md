# Sentiment analysis

`Text.Sentiment` classifies text as `:positive`, `:negative`, or `:neutral` and produces a fine-grained polarity score. Two backends ship in the box: a fast, deterministic, multilingual **lexicon backend** (default) and an optional **neural backend** for higher quality on hard cases.

The right backend depends on your throughput, latency, and quality budget. The lexicon backend handles tens of thousands of items per second per core with no model download; the neural backend produces measurably better labels on figurative, sarcastic, or short-form text — at the cost of a one-time ~1 GB model download and an order-of-magnitude higher per-call latency.

> **Don't panic.** The defaults work end-to-end with no setup. The options below tune behaviour rather than enabling it.

## Quick start

```elixir
Text.Sentiment.analyze("I really love this product!")
#=> %{
#=>   label: :positive,
#=>   compound: 0.6,
#=>   sum: 3.0,
#=>   tokens: 6,
#=>   matched: 1,
#=>   language: :en
#=> }

Text.Sentiment.label("Don't talk to me about life.")
#=> :negative
```

`analyze/2` returns the full result; `label/2` is a thin wrapper that returns just the label.

### Result shape

| Field | Meaning |
|---|---|
| `:label` | `:positive`, `:negative`, or `:neutral` after threshold rules. |
| `:compound` | Normalised polarity score in `[-1.0, +1.0]`. The standard "give me one number" answer. |
| `:sum` | Raw signed sum of token scores before normalisation (lexicon backend only). |
| `:tokens` | Count of input tokens after splitting. |
| `:matched` | Count of tokens that scored against the lexicon. |
| `:language` | The language tag actually used (after fallback resolution). |
| `:backend` | The module that produced the result (set by the Bumblebee backend; absent for lexicon). |
| `:scores` | Per-class probability map (Bumblebee backend only). |

The `:compound` score is the value to map to UI elements (a polarity bar, a colour scale, a sort key); the `:label` is for human-readable display and downstream filtering.

## Choosing a backend

### Lexicon backend *(default)*

`Text.Sentiment.Backends.Lexicon` scores tokens against a bundled per-language lexicon, applies VADER-style adjustments for negation (`"not good"` flips polarity) and intensifiers/diminishers (`"very good"` boosts, `"slightly good"` dampens), and normalises the sum to the compound `[-1, 1]` range.

* **No model download.** No optional deps. Always available.
* **Multilingual via lexicon swap.** Bundled AFINN lexicons cover English, Danish, Finnish, French, Polish, Swedish, Turkish, plus a language-agnostic emoticon lexicon.
* **Deterministic.** Same input always produces the same output.
* **Fast.** ~10–100 µs per item on typical hardware.

The bundled language tags:

```elixir
Text.Sentiment.Lexicons.AFINN.available()
#=> [:en, :da, :fi, :fr, :pl, :sv, :tr, :emoticon]
```

### Bumblebee backend *(optional, neural)*

`Text.Sentiment.Backends.Bumblebee` runs the document through a multilingual XLM-RoBERTa classifier (`cardiffnlp/twitter-xlm-roberta-base-sentiment` by default). It catches sarcasm and idiomatic polarity that the lexicon misses, and works across ~30 languages without per-language tuning.

* **Requires `:bumblebee` and (recommended) `:exla`.** Add to your `mix.exs`:

  ```elixir
  {:bumblebee, "~> 0.6", optional: true},
  {:exla, "~> 0.9", optional: true}
  ```

* **First call is slow.** Cold start downloads ~1.1 GB of model weights and traces the inference graph. Subsequent calls hit a `:persistent_term`-cached `Nx.Serving` and run in single-digit milliseconds.

* **Pre-download for production:** `mix text.download_models --sentiment`.

To switch globally:

```elixir
# config/config.exs
config :text, :sentiment_backend, Text.Sentiment.Backends.Bumblebee
```

Or per call:

```elixir
Text.Sentiment.analyze("This was a bad experience.",
  backend: Text.Sentiment.Backends.Bumblebee
)
```

The result shape is the same on both backends — the `:label` and `:compound` fields are always present, so call sites don't need to know which backend ran.

## Languages

The `:language` option controls which AFINN lexicon (or which language the neural model is told the input is in) is used. It accepts:

* An atom: `:en`, `:fr`, `:pl`, …
* A BCP-47 string: `"en"`, `"en-US"`, `"fr-CA"`.
* A `Localize.LanguageTag` struct, when the optional `:localize` dependency is loaded.

```elixir
Text.Sentiment.analyze("J'adore ce livre.", language: :fr).label
#=> :positive

Text.Sentiment.analyze("Ten film jest okropny.", language: :pl).label
#=> :negative
```

If the requested language isn't bundled (for the lexicon backend), the result falls back to `:en`. Override with `:fallback_language`:

```elixir
Text.Sentiment.analyze("¡Qué increíble!",
  language: :es,
  fallback_language: :en  # Spanish isn't bundled — fall back to English
)
```

The neural backend ignores `:language` for routing (XLM-RoBERTa is intrinsically multilingual) but still records the value in the result for round-tripping.

## Composing custom lexicons

`Text.Sentiment.lexicon_for/2` builds composite lexicons. Common pattern: a base language plus the emoticon lexicon plus your own domain-specific overrides.

```elixir
lexicon = Text.Sentiment.lexicon_for(:en,
  with_emoticons: true,
  overrides: %{
    "lit" => 3,
    "mid" => -1,
    "based" => 4
  }
)

Text.Sentiment.analyze("That was lit :-)", lexicon: lexicon).label
#=> :positive
```

The `:lexicon` option overrides `:language`, so a custom lexicon is fully self-contained — you can mix words from multiple languages, slang, brand-charged terms, anything you want.

Score values are integers in `[-5, +5]` by AFINN convention but any number works; the compound score normalisation handles whatever range you pick.

## Negation, intensifiers, diminishers

The lexicon backend applies VADER-inspired adjustments based on tokens immediately preceding a scored term:

* **Negators** flip the sign: `"not good"` → `-good`. Default English negators: `not`, `no`, `never`, `n't`-style contractions.
* **Intensifiers** multiply: `"very good"` × 1.293. Default boosters: `very`, `extremely`, `absolutely`, …
* **Diminishers** dampen: `"slightly good"` × 0.293. Default dampers: `slightly`, `barely`, `hardly`, …

Override via options:

```elixir
Text.Sentiment.analyze("Marvin was incredibly miserable.",
  intensifiers: ["incredibly", "ridiculously", "unbelievably"]
)
```

All three options are forwarded through to `Text.Sentiment.Lexicon.score/3`. Use them to localise the modifiers when working with a non-English lexicon (the bundled AFINN lexicons cover content words but not modifier classes).

## Threshold tuning

By default, results map to a label using `compound >= 0.05` for positive and `compound <= -0.05` for negative, with everything else neutral. These VADER-derived defaults work well for most short-form text but can be too eager for longer documents (where small per-token signal accumulates and pushes neutral content into the polar buckets).

```elixir
Text.Sentiment.analyze("Tea, Earl Grey, hot.",
  positive_threshold: 0.2,
  negative_threshold: -0.2
)
```

For batch labelling pipelines it's often easier to skip the `:label` and bin the `:compound` score yourself with thresholds tuned to your domain.

## Production checklist

1. **Pre-download neural model weights at deploy time:** `mix text.download_models --sentiment`. Avoids cold-start latency on the first request.

2. **Start a named `Nx.Serving` at boot** if you're using the Bumblebee backend at high QPS:

   ```elixir
   {:ok, _} = Nx.Serving.start_link(
     serving: Bumblebee.Text.text_classification(model_info, tokenizer, ...),
     name: MyApp.SentimentServing
   )

   Text.Sentiment.analyze(text, serving: MyApp.SentimentServing)
   ```

   This skips the `:persistent_term` lazy cache entirely.

3. **Set the global backend in config** so call sites stay backend-agnostic. Tests can override per call with `backend: Text.Sentiment.Backends.Lexicon` for speed.

4. **Cap input length** for the Bumblebee backend (default sequence length 128 tokens). Long text gets truncated; if your domain requires whole-document scoring, chunk by sentence and aggregate.

## When to prefer which backend

| Use case | Recommended backend |
|---|---|
| High-throughput batch jobs | **Lexicon** |
| Multilingual short text (tweets, reviews) | **Bumblebee** |
| Long-form formal prose | **Lexicon** with raised thresholds |
| Sarcasm / idiomatic / figurative | **Bumblebee** |
| Languages outside the bundled AFINN set without an `:overrides` map | **Bumblebee** |
| Embedded / no-model-download environments | **Lexicon** (only option) |
| Determinism required (reproducible audits) | **Lexicon** |
