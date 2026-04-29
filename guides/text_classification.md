# Text classification — language identification

`Text.Language.Classifier.Fasttext` is a pure-Elixir port of fastText's [`lid.176`](https://fasttext.cc/docs/en/language-identification.html) model — a supervised classifier trained on Wikipedia, Tatoeba, and SETimes data that recognises **176 languages** from short input. The implementation is validated bit-for-bit against the official C++/Python reference for hashing, n-gram extraction, feature assembly, and tree traversal: same input, same prediction, same probabilities (within float-32 rounding).

It runs entirely in the BEAM — no NIFs, no Python sidecar, no model server. The trade-off is the model file (~126 MB) is fetched once at install time and lives on disk; this guide walks through the setup and the API.

## One-time setup

The `lid.176.bin` model file is **not** part of the Hex package — every install fetches its own copy. Run once after adding `:text` to your dependencies:

```sh
mix text.download_lid176
```

The file lands at `priv/lid_176/lid.176.bin` inside the project. It's gitignored and not committed.

For production environments that want every external artefact present at boot, use the broader `mix text.download_models` task — same fetch, but it can also pre-download the Bumblebee models used by `Text.Sentiment`, `Text.POS`, `Text.NER`, and `Text.WordCloud.Backends.KeyBERT`.

## Loading the model

The model is loaded once per VM and reused across every detection call:

```elixir
{:ok, model} =
  Text.Language.Classifier.Fasttext.ModelLoader.load(
    Path.join(:code.priv_dir(:text), "lid_176/lid.176.bin")
  )
```

The result is a `Text.Language.Classifier.Fasttext.Model` struct holding the input matrix, output matrix, dictionary, and Huffman tree (if applicable) as `Nx` tensors. Loading takes a few seconds; a typical pattern is to load at application boot and stash the model in `:persistent_term` or a `GenServer` for the rest of the VM's lifetime.

## Detecting a language

`detect/3` returns a full `Detection` struct:

```elixir
{:ok, det} = Text.Language.Classifier.Fasttext.detect("Bonjour le monde", model)

det.language     #=> "fr"
det.script       #=> :Latn
det.confidence   #=> 0.984
det.alternatives #=> [{"en", 0.0035}, {"it", 0.0024}, {"oc", 0.0009}, {"ca", 0.0006}]
det.text         #=> "Bonjour le monde"
```

The struct fields:

| Field | Meaning |
|---|---|
| `:language` | BCP-47 language subtag (`"fr"`, `"zh"`, `"sr"`). |
| `:confidence` | Probability of the top prediction in `[0.0, 1.0]`. |
| `:script` | Unicode script atom derived from the input text (`:Latn`, `:Cyrl`, `:Hans`, `:Hant`, `:Hani`, …). Used downstream to disambiguate multi-script locales. |
| `:alternatives` | List of `{language, probability}` for the next-best predictions. |
| `:text` | The original input, preserved for downstream use. |

Common options:

* `:k` — number of top predictions to return. Default `5`. The first becomes the main `:language`; the rest fill `:alternatives`.

* `:threshold` — drop predictions below this probability. Default `0.0`. Raise it (e.g. `0.5`) to get `{:error, :no_predictions}` for ambiguous inputs you'd rather skip than guess at.

```elixir
case Text.Language.Classifier.Fasttext.detect(unknown_text, model, threshold: 0.5) do
  {:ok, det} -> route_by_language(det.language)
  {:error, :no_predictions} -> ask_user_to_clarify()
end
```

## Just the language code

When you only need the answer:

```elixir
{:ok, "es"} = Text.Language.Classifier.Fasttext.classify("Hola, ¿cómo estás?", model)
{:ok, "ru"} = Text.Language.Classifier.Fasttext.classify("Привет, мир!", model)
{:ok, "ja"} = Text.Language.Classifier.Fasttext.classify("こんにちは世界", model)
```

`classify/2` is a thin wrapper around `detect(text, model, k: 1)` that drops everything except the top language code. Useful for routing logic where you only care which bucket to send the text into.

## Resolving to a CLDR locale

`detect/3` returns a bare language code; downstream localisation systems usually want a full locale string like `zh-Hans-CN` or `fr-FR`. `to_locale/2` runs the detection through CLDR's likely-subtags algorithm to fill in the missing pieces:

```elixir
{:ok, det} = Text.Language.Classifier.Fasttext.detect("你好世界，这是简体中文。", model)
{:ok, "zh-Hans-CN"} = Text.Language.Classifier.Fasttext.to_locale(det)

{:ok, det} = Text.Language.Classifier.Fasttext.detect("你好世界，這是繁體中文。", model)
{:ok, "zh-Hant-TW"} = Text.Language.Classifier.Fasttext.to_locale(det)
```

When the optional [`localize`](https://hex.pm/packages/localize) dependency is loaded, this calls into CLDR's actual likely-subtags table. Without it, a built-in fallback table covers ~60 of the most common languages. Add `:localize` for production-grade locale resolution:

```elixir
{:localize, "~> 0.23", optional: true}
```

Override the inferred region or script:

```elixir
{:ok, "fr-Latn-CA"} = Text.Language.Classifier.Fasttext.to_locale(det, region: :CA)
```

The region option is typically wired to an `Accept-Language` header or IP geolocation when available; otherwise the CLDR default for the language wins.

## Script detection and Hans/Hant

Many languages are written in more than one script (Serbian in Latin or Cyrillic, Punjabi in Gurmukhi or Shahmukhi, Chinese in Simplified or Traditional Han). The fastText model returns a bare language code like `"zh"` — it doesn't distinguish `Hans` from `Hant`. `Text.Language.Classifier.Fasttext.ScriptDetector` runs alongside `detect/3` and contributes the script signal.

For Chinese specifically, `ScriptDetector` runs a second-pass codepoint-frequency analysis against curated lists of distinguishing characters. If the input contains characters present only in Simplified (`国`, `电`, `时`) it returns `:Hans`; if it contains Traditional-only characters (`國`, `電`, `時`) it returns `:Hant`. Inputs containing only shared Han codepoints fall back to `:Hani`, and likely-subtags then resolves to `Hans-CN` (the mainland-China default).

```elixir
{:ok, det} = Text.Language.Classifier.Fasttext.detect("国家电网", model)
det.script  #=> :Hans

{:ok, det} = Text.Language.Classifier.Fasttext.detect("國家電網", model)
det.script  #=> :Hant

{:ok, det} = Text.Language.Classifier.Fasttext.detect("人之初", model)
det.script  #=> :Hani  (shared codepoints — could be either)
```

## Confidence calibration

fastText's confidence scores are well-calibrated for *long* inputs (a sentence or more) but inflate aggressively on very short inputs. Common patterns:

* **Short noun phrases** ("Hello world") often produce confidence > 0.95 — usually correct, but sometimes overconfident on names that look multilingual.

* **Mixed-language text** ("Click the button to login") usually classifies as the dominant language with moderate confidence; check `:alternatives` if the result looks suspicious.

* **Code-mixed or transliterated text** ("kaisi ho?" written in Latin script for Hindi) often classifies as the script's default language (`:en`) rather than the intended one. Consider a higher `:threshold` and a fallback path for ambiguous cases.

For robust routing, look at the gap between top-1 and top-2 confidences in `:alternatives`. A small gap (< 0.1) signals genuine ambiguity even when the top score is high.

## Performance

The model's input matrix is ~128 MB of `float32` data held in an `Nx` tensor. The inference forward pass (`take + mean + dot`, plus the softmax tail for softmax-loss models) is wrapped in `Nx.Defn` so an EXLA-compiled execution runs the whole pass as a single fused XLA kernel.

**Per-prediction wall time on `lid.176`:**

| Backend | Time |
|---|---|
| `Nx.BinaryBackend` (no `:exla`) | ~600 µs |
| `EXLA.Backend`, no defn fusion | ~200 µs |
| `EXLA.Backend` + fused defn graph (default) | **~100 µs** |

For production throughput add `:exla` to your deps and configure it as both the default backend and the default `defn` compiler:

```elixir
# config/config.exs
config :nx, default_backend: EXLA.Backend
config :nx, :default_defn_options, compiler: EXLA
```

Without EXLA the package still works correctly — `Nx.Defn.Evaluator` runs the same `defn` graph against `Nx.BinaryBackend` — but per-prediction wall time is roughly an order of magnitude higher.

## The 176 supported languages

The full set is documented at the [fastText project page](https://fasttext.cc/docs/en/language-identification.html). Coverage includes all 24 official EU languages, every UN official language, the major South and Southeast Asian languages, and a long tail of regional and minority languages. Languages **not** in `lid.176` include very recently-added minority languages (Quechua, some indigenous American languages) and constructed languages outside Esperanto and Ido.

Use `model.dictionary.nlabels` (which equals 176) and `model.labels` (a list of every supported label) to enumerate at runtime if you need a UI selector or to validate a user's expected language.

## Putting it together

A typical production wiring:

```elixir
# At app boot, in your Application.start/2:
def start(_type, _args) do
  {:ok, model} = Text.Language.Classifier.Fasttext.ModelLoader.load(
    Path.join(:code.priv_dir(:text), "lid_176/lid.176.bin")
  )
  :persistent_term.put(MyApp.LidModel, model)
  Supervisor.start_link(children, opts)
end

# At call site:
def detect_language(text) do
  model = :persistent_term.get(MyApp.LidModel)

  case Text.Language.Classifier.Fasttext.detect(text, model, threshold: 0.5) do
    {:ok, det} ->
      {:ok, locale} = Text.Language.Classifier.Fasttext.to_locale(det)
      {:ok, det.language, locale}

    {:error, :no_predictions} ->
      {:error, :ambiguous}
  end
end
```

This pattern loads the model once, keeps it warm in `:persistent_term`, and produces fully-resolved CLDR locales on every call.
