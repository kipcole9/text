# Part-of-speech tagging and named-entity recognition

`Text.POS` and `Text.NER` are sibling modules backed by [Bumblebee](https://hex.pm/packages/bumblebee). One assigns a coarse-grained part of speech (`:noun`, `:verb`, `:adj`, …) to every token in a sentence; the other extracts named-entity spans (`:per`, `:org`, `:loc`, `:misc`) from running text. Both run pre-trained transformers locally — no API calls, no model server.

The two modules share a setup story (one optional dep, one model download per stack), the same caching pattern (`:persistent_term` per loaded model), and the same production wiring (start an `Nx.Serving` at boot, pass it via `:serving`). This guide covers both together because the operational concerns overlap almost entirely.

> **First call is slow.** Cold start downloads the model (~440 MB for POS, ~700 MB for NER), traces the inference graph, and compiles it under EXLA. Subsequent calls run in single-digit milliseconds. Pre-download with `mix text.download_models --pos --ner` to push that one-off cost into deployment.

## Setup

Both modules require the optional `:bumblebee` dependency, plus the recommended `:exla` for compilation:

```elixir
# mix.exs
defp deps do
  [
    {:text, "~> 0.3"},
    {:bumblebee, "~> 0.6", optional: true},
    {:exla, "~> 0.9", optional: true}
  ]
end
```

Without `:bumblebee`, calling `Text.POS.tag/2` or `Text.NER.extract/2` raises with installation instructions — every other part of `:text` keeps working.

```elixir
# config/config.exs
config :nx, default_backend: EXLA.Backend
config :nx, :default_defn_options, compiler: EXLA
```

Without `:exla` the modules still work (Nx falls back to the BinaryBackend), but per-call latency goes up by an order of magnitude.

Pre-download model weights at deploy time:

```sh
mix text.download_models --pos --ner
```

The Bumblebee artefacts land in `~/.cache/bumblebee/` (override with `BUMBLEBEE_CACHE_DIR` or `XDG_CACHE_HOME`). Once cached, `Text.POS` and `Text.NER` run with no network access.

## Part-of-speech tagging

`Text.POS.tag/2` returns one `{token, tag, score}` triple per word:

```elixir
Text.POS.tag("Arthur Dent quickly grabbed his towel before the demolition began.")
#=> [
#=>   {"Arthur", :noun, 0.99},
#=>   {"Dent", :noun, 0.99},
#=>   {"quickly", :adv, 0.99},
#=>   {"grabbed", :verb, 0.99},
#=>   {"his", :pron, 0.99},
#=>   {"towel", :noun, 0.99},
#=>   {"before", :prep, 0.99},
#=>   {"the", :det, 0.99},
#=>   {"demolition", :noun, 0.99},
#=>   {"began", :verb, 0.99},
#=>   {".", :punct, 0.99}
#=> ]
```

The `score` is the model's confidence in the assigned tag. Values consistently above 0.9 for content words; lower scores cluster around homographs and rare or borrowed terms.

### Tag set

The default model (`vblagoje/bert-english-uncased-finetuned-pos`) outputs Penn Treebank / OntoNotes tags (`NN`, `NNS`, `VB`, `VBD`, …). `Text.POS` collapses these into a coarser, more ergonomic atom set:

| Atom | Penn Treebank | Description |
|---|---|---|
| `:noun` | `NN`, `NNS`, `NNP`, `NNPS` | Common and proper nouns |
| `:verb` | `VB`, `VBD`, `VBG`, `VBN`, `VBP`, `VBZ` | All verb forms |
| `:adj` | `JJ`, `JJR`, `JJS` | Adjectives and comparatives |
| `:adv` | `RB`, `RBR`, `RBS` | Adverbs |
| `:pron` | `PRP`, `PRP$` | Pronouns and possessives |
| `:det` | `DT`, `WDT`, `PDT` | Determiners |
| `:prep` | `IN`, `TO` | Prepositions |
| `:conj` | `CC` | Coordinating conjunctions |
| `:interj` | `UH` | Interjections |
| `:num` | `CD` | Cardinal numbers |
| `:modal` | `MD` | Modal verbs |
| `:punct` | `.`, `,`, `:`, parens, quotes | Punctuation |

Callers needing the fine-grained Penn tag can pass `:serving` directly and reach into the underlying classification result, but that's rare — coarse tags are what most downstream filters actually want.

### Languages

The default POS model is English-only. For other languages, supply a `:model` option pointing to a multilingual or language-specific checkpoint:

```elixir
Text.POS.tag(french_text, model: "QCRI/bert-base-multilingual-cased-pos-english")
```

The result shape is the same; only the underlying tag vocabulary changes (and the default coarse-mapping rules may not apply cleanly to non-Penn-Treebank-derived tag sets).

## Named-entity recognition

`Text.NER.extract/2` returns a list of `Text.NER.Entity` structs:

```elixir
Text.NER.extract("""
Arthur Dent traveled with Ford Prefect to Magrathea, where Slartibartfast
designed the fjords of Norway.
""")

#=> [
#=>   %Text.NER.Entity{text: "Arthur Dent",       type: :per, start: 1,   end: 12,  score: 0.998},
#=>   %Text.NER.Entity{text: "Ford Prefect",      type: :per, start: 27,  end: 39,  score: 0.997},
#=>   %Text.NER.Entity{text: "Magrathea",         type: :loc, start: 43,  end: 52,  score: 0.992},
#=>   %Text.NER.Entity{text: "Slartibartfast",    type: :per, start: 60,  end: 74,  score: 0.989},
#=>   %Text.NER.Entity{text: "Norway",            type: :loc, start: 99,  end: 105, score: 0.999}
#=> ]
```

The `Entity` fields:

| Field | Meaning |
|---|---|
| `:text` | The surface form of the entity as it appears in the input. |
| `:type` | `:per` (person), `:org` (organization), `:loc` (location), or `:misc`. |
| `:start` | Byte offset of the first character. |
| `:end` | Byte offset *one past* the last character (so `String.slice(text, start, end - start)` round-trips). |
| `:score` | Model confidence in `[0.0, 1.0]`. |

### Languages

The default NER model (`Davlan/bert-base-multilingual-cased-ner-hrl`) is **multilingual out of the box** — it covers ten high-resource languages: Arabic, German, English, Spanish, French, Italian, Latvian, Dutch, Portuguese, and Chinese. No `:language` routing is required; just pass any text in any of those languages.

```elixir
Text.NER.extract("Angela Merkel besuchte Berlin im Juni.")
#=> [
#=>   %Text.NER.Entity{text: "Angela Merkel", type: :per, ...},
#=>   %Text.NER.Entity{text: "Berlin",        type: :loc, ...}
#=> ]
```

For coverage outside those ten, pass `:model` pointing at a language-specific NER checkpoint.

### Filtering low-confidence entities

```elixir
Text.NER.extract(text, min_score: 0.9)
```

The model occasionally surfaces span guesses with confidence < 0.5 — usually unhelpful. Default is `0.0` (return everything); raise to `0.5` or `0.9` for cleaner output at the cost of missing some borderline-correct spans.

## Cold start and serving cache

The first call to `tag/2` or `extract/2` does several expensive things in sequence:

1. **Download the model.** ~440 MB (POS) or ~700 MB (NER) on first run.
2. **Trace the inference graph.** Bumblebee walks the model architecture and produces an `Nx.Defn` graph.
3. **Compile under EXLA.** XLA generates an optimised kernel for the target hardware.

This is a 10–30 second cost depending on disk speed and EXLA initialisation. Once done, the compiled `Nx.Serving` is cached in `:persistent_term` keyed by the model id; subsequent calls in the same VM hit the cache and run in single-digit milliseconds.

To reset the cache (in tests, or when switching defn options):

```elixir
Text.POS.reset()      # default model
Text.POS.reset(:all)  # every cached POS serving

Text.NER.reset(:all)
```

## Production wiring

For high-QPS workloads the lazy `:persistent_term` cache is fine but not optimal — a named `Nx.Serving` started at boot gives more control over batching and lifecycle:

```elixir
defmodule MyApp.Application do
  def start(_type, _args) do
    {:ok, model_info} = Bumblebee.load_model({:hf, "vblagoje/bert-english-uncased-finetuned-pos"})
    {:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, "google-bert/bert-base-uncased"})

    pos_serving =
      Bumblebee.Text.token_classification(model_info, tokenizer,
        compile: [batch_size: 16, sequence_length: 256],
        defn_options: [compiler: EXLA],
        aggregation: :same
      )

    children = [
      {Nx.Serving, serving: pos_serving, name: MyApp.POS, batch_size: 16}
      # ... NER analogously
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end

# At call site:
Text.POS.tag(text, serving: MyApp.POS)
```

Passing `:serving` skips the cache entirely. Batch size on the `Nx.Serving` controls how many concurrent calls are coalesced into a single GPU/CPU dispatch — typically the biggest throughput knob in production.

## Tokenizer overrides

Some Hugging Face fine-tunes ship without the Rust-compatible `tokenizer.json` Bumblebee expects (they only have the raw WordPiece/BPE files). Both `Text.POS` and `Text.NER` carry a per-model override table that maps such fine-tunes to a base-model repo with the right tokenizer:

```elixir
# Text.POS internal:
@tokenizer_overrides %{
  "vblagoje/bert-english-uncased-finetuned-pos" => "google-bert/bert-base-uncased"
}

# Text.NER internal:
@tokenizer_overrides %{
  "Davlan/bert-base-multilingual-cased-ner-hrl" => "google-bert/bert-base-multilingual-cased"
}
```

If you point `:model` at a fine-tune that itself lacks `tokenizer.json`, pass `:tokenizer_repo` to point at one that has it (typically the base model the fine-tune was trained on):

```elixir
Text.POS.tag(text,
  model: "some-fine-tune/without-tokenizer-json",
  tokenizer_repo: "the-base-model/with-tokenizer-json"
)
```

## Choosing tools for entity-driven workflows

POS and NER answer different questions and frequently complement each other:

* **NER alone** is enough when you only care about *who/where/what* — building knowledge graphs, populating CRM records, anonymising text.

* **POS alone** is enough when you need linguistic structure but not entity identity — search-time stemming masks, syntactic features for downstream classifiers, content-word filtering for word clouds (`:pos_filter` in `Text.WordCloud`).

* **Both together** matter when the question is "what is this *person* *doing*?" — pair `:per` entities from NER with `:verb` neighbours from POS for relation extraction, or filter NER `:misc` entities by POS to keep only those that are nouns.

For most consumer-facing use cases, NER alone is what people reach for first.
