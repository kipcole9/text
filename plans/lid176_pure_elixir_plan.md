# Pure-Elixir `lid.176` Implementation Plan

## Context

Replacing the existing Bayesian classifier (UDHR-corpus based) in the `text`
library at `../text` with a pure-Elixir port of fastText's `lid.176` language
identification model. The goal is to provide significantly improved language
detection that drives downstream locale derivation for formatting, calendar
selection, and collation in the broader Elixir localisation ecosystem
(`ex_cldr`, Calendrical, localize).

A pure-Elixir implementation avoids NIFs, native toolchains, and Python
sidecars, keeping the dependency story clean for downstream users.

## Why `lid.176`

- Trained on Wikipedia, Tatoeba, and SETimes — substantially broader register
  coverage than the UDHR corpus
- 176 languages supported
- Small model footprint (~126MB unquantized, ~917KB quantized)
- Well-documented architecture: averaged subword embeddings + linear classifier
  + softmax
- Reference implementation in C++ available for differential testing

## Working Assumptions About `text`

These need to be verified against the actual package once it is accessible:

- Package named `:text` on Hex with a top-level `Text` module
- Existing public entry point likely `Text.Language.classify/1` or similar
- UDHR corpus data lives in `priv/` as compiled training data
- Minimal external library dependencies today

If any of these are wrong, integration shape changes but the underlying
approach does not.

---

## Phase 1: Understand the Model Format

Establish ground truth on `lid.176.bin` contents before writing Elixir.

### Tasks

- Obtain `lid.176.bin` (unquantized, 126MB) from fastText releases. Defer
  `lid.176.ftz` (quantized, 917KB) — product quantization decoding is
  non-trivial and not worth tackling first.
- Read fastText source files for canonical specification:
  - `src/args.cc`
  - `src/dictionary.cc`
  - `src/matrix.cc`
  - `src/fasttext.cc` (especially `loadModel` / `saveModel`)
- Generate golden test fixtures using the official `fasttext` Python package
  or C++ CLI: predictions for a corpus of test strings across many languages.
  These are required for verifying the Elixir implementation matches
  bit-for-bit, or near enough.

### Deliverable

Written specification document describing the binary format, hashing scheme,
and inference math, plus a fixture file of input/output pairs at
`test/fixtures/golden_predictions.json`.

---

## Phase 2: Binary Format Parser

The `.bin` file is a sequence of little-endian binary structures. Elixir's
binary pattern matching is well-suited to this.

### Structure to Parse

1. **Header magic and version** — sanity check
2. **Args struct** — `dim`, `ws`, `epoch`, `minCount`, `neg`, `wordNgrams`,
   `loss` type, `model` type, `bucket`, `minn`, `maxn`, `lrUpdateRate`, `t`
3. **Dictionary** — `size`, `nwords`, `nlabels`, `ntokens`, then a sequence of
   entries (word string, count, type)
4. **Input matrix** — `(nwords + bucket) × dim` floats
5. **Output matrix** — `nlabels × dim` floats (or hierarchical softmax tree,
   depending on loss)

### Implementation Sketch

```elixir
defmodule Text.Language.ModelLoader do
  def load(path) do
    {:ok, file} = :file.open(path, [:read, :binary, :raw])
    {:ok, args} = read_args(file)
    {:ok, dict} = read_dictionary(file, args)
    {:ok, input} = read_matrix(file, args.bucket + dict.nwords, args.dim)
    {:ok, output} = read_matrix(file, dict.nlabels, args.dim)
    %Text.Language.Model{args: args, dict: dict, input: input, output: output}
  end
end
```

### Considerations

- Input matrix (~126MB) should be read into an `Nx` tensor backed by
  `Nx.BinaryBackend` or, for production, `EXLA`. Avoid building it as a list
  of lists.
- Use `:file.pread/3` with explicit offsets rather than streaming — makes
  memory behaviour predictable.
- Consider `:mmap` (Elixir wrappers exist) for faster cold starts. Worth
  measuring but not essential for v1.

---

## Phase 3: Reproduce N-gram Hashing Exactly

This is where pure reimplementations most often diverge from the reference.
fastText uses a specific FNV-1a-based hash, modulo bucket count, to map
character n-grams to slots in the input matrix beyond `nwords`.

### Tasks

- Port `Dictionary::hash` from `dictionary.cc` to Elixir. Verify with
  thousands of n-gram inputs against the C++ implementation.
- Port `Dictionary::computeSubwords` which generates n-grams between `minn`
  and `maxn` characters, with the special `<` and `>` boundary markers.
- Handle UTF-8 correctly. fastText operates on UTF-8 byte sequences but
  treats character boundaries via byte inspection (continuation bytes have
  the `10xxxxxx` pattern). Must match exactly or non-Latin scripts break.

### Validation

Property-based tests using `StreamData` against the reference implementation
will pay dividends here. Generate random UTF-8 strings, hash both in Elixir
and in C++, assert equality.

---

## Phase 4: Tokenization and Feature Extraction

For language identification, input is split on whitespace, then each token
contributes:

- The token itself (looked up in the dictionary; if absent, skipped)
- All character n-grams of the token between `minn` and `maxn`

### Tasks

- Implement tokenizer matching fastText's whitespace handling
- For each token, look up its index in the dictionary (hash map keyed by
  string); for n-grams, hash into the bucket range
- Produce a flat list of feature indices into the input matrix

---

## Phase 5: Inference With Nx

Once features are extracted, inference is short:

```elixir
defmodule Text.Language.Inference do
  import Nx.Defn

  defn predict(feature_indices, input_matrix, output_matrix) do
    feature_indices
    |> then(&Nx.take(input_matrix, &1, axis: 0))
    |> Nx.mean(axes: [0])
    |> then(&Nx.dot(output_matrix, &1))
    |> Nx.softmax()
  end

  def top_k(probs, labels, k) do
    {top_probs, top_indices} = Nx.top_k(probs, k: k)

    Enum.zip(
      Nx.to_flat_list(top_indices) |> Enum.map(&Enum.at(labels, &1)),
      Nx.to_flat_list(top_probs)
    )
  end
end
```

Labels in `lid.176` are formatted as `__label__en`, `__label__zh`, etc. Strip
the prefix and you have ISO 639-1 (or 639-3 for some) codes.

Use `EXLA` as the default backend for serving — substantially faster than
`BinaryBackend` for `Nx.take` and the matmul.

---

## Phase 6: Locale Derivation Layer

Where this work intersects most directly with `localize` and `Calendrical`.
Language detection alone is insufficient for locale selection — `en` could
mean `en-US`, `en-GB`, `en-AU`, with different calendar/collation/number
implications.

### Design Considerations

- **Language to default locale mapping.** CLDR provides likely-subtags data:
  `en` → `en-Latn-US`, `pt` → `pt-Latn-BR`, `zh-Hans` → `zh-Hans-CN`. The
  `ex_cldr` library already exposes much of this. Detection layer returns a
  language code; a separate function resolves it to a locale, ideally with a
  hint mechanism (user IP, Accept-Language, prior context).

- **Script detection as an independent signal.** `lid.176` does not
  distinguish `zh-Hans` from `zh-Hant`, nor `sr-Latn` from `sr-Cyrl`. Simple
  Unicode script frequency analysis on the input gives this cheaply and
  complements the language classifier well. `Unicode.Set` or direct
  codepoint inspection works.

- **Confidence thresholds.** Short inputs are unreliable. Below some
  confidence floor, the API should return `:uncertain` rather than guessing
  — particularly important when the result drives calendar selection, where
  a wrong answer is more disruptive than no answer.

### Suggested API

```elixir
# Backward-compatible simple form
Text.Language.classify("Bonjour le monde")
# => {:ok, "fr"}

# Richer form
Text.Language.detect("Bonjour le monde")
# => {:ok, %Text.Language.Detection{
#      language: "fr",
#      confidence: 0.984,
#      script: "Latn",
#      alternatives: [{"oc", 0.008}, {"ca", 0.003}]
#    }}

# Locale resolution as a separate, composable step
Text.Language.to_locale(detection, region_hint: "CA")
# => {:ok, "fr-CA"}

Text.Language.to_locale(detection, text: "你好世界")
# => {:ok, "zh-Hans-CN"}  # script inferred from text
```

---

## Phase 7: Distribution and Packaging

The model file is too large to ship in a Hex package (current limit ~8MB;
`lid.176.bin` is 126MB).

### Options

- **Mix task to download.** `mix text.download_model` fetches and verifies
  the model on first use, caches in `:filename.basedir/3`. Pattern used by
  `tzdata`, `ex_cldr`, and others.
- **Tackle the quantized model later.** `lid.176.ftz` is 917KB and could
  ship in-package, but requires implementing product quantization decoding —
  meaningful additional effort, worthwhile for v2.

---

## Phase 8: Testing and Validation

- Unit tests on hash function, n-gram extraction, binary parsing
- Golden tests: corpus of strings across all 176 languages with expected
  predictions matching reference implementation within floating-point
  tolerance
- Property tests on tokenization round-trips
- Benchmark suite using `Benchee`: target sub-millisecond inference for
  typical inputs after warmup

---

## Integration With the Existing `text` Library

### Step 0: Audit and Preservation

Before deletion, capture what is worth preserving:

- **Public API surface.** Whatever functions `Text` exposes for language
  detection should keep working with the same signatures and return shapes
  wherever feasible. Breaking changes acceptable in major version bump but
  should be deliberate.
- **Test fixtures.** Existing tests, even if the underlying classifier
  changes, encode expectations about the API contract. Most should still
  pass after replacement.
- **Documentation conventions.** Match existing style for module docs,
  typespecs, examples.
- **The UDHR corpus itself.** Worth keeping in `priv/` even if unused by
  the classifier — reasonable evaluation set, small enough that removing
  it is not a meaningful win.

### Step 1: Module Structure Inside `text`

Internal modules rather than a standalone package:

```
lib/
  text.ex                              # existing top-level, public API preserved
  text/
    language.ex                        # public language detection API
    language/
      detector.ex                      # orchestration, replaces old Bayesian classifier
      model.ex                         # %Text.Language.Model{} struct
      model_loader.ex                  # binary parser for lid.176.bin
      hash.ex                          # FNV-1a port
      dictionary.ex                    # dictionary + n-gram generation
      tokenizer.ex                     # whitespace tokenization
      inference.ex                     # Nx forward pass
      script_detector.ex               # Unicode script frequency analysis
      locale.ex                        # language → locale resolution
priv/
  lid_176/
    .gitkeep                           # model downloaded at build time
  udhr/                                # preserved corpus, used for eval
mix/tasks/
  text.download_model.ex               # fetches lid.176.bin
test/
  text/language/
    ...                                # unit tests per module
  fixtures/
    golden_predictions.json            # generated from reference implementation
```

### Step 2: Public API Design

Two questions to settle:

1. **Does the existing API stay?** If current shape is something like
   `Text.Language.classify(string)` returning `{:ok, "en"}`, that should
   continue to work, with the new implementation providing strictly better
   answers.

2. **What new capability is exposed?** The richer information from
   `lid.176` (confidence, alternatives, script) deserves an extended API.
   See Phase 6 sketch above.

### Step 3: Dependency Additions

- `:nx` — tensor operations, mandatory
- `:exla` — optional but strongly recommended; gate behind a target or make
  the backend configurable so `:nx` `BinaryBackend` works as a fallback
- Possibly `:ex_cldr` — for locale resolution in `Text.Language.Locale`,
  though this could be optional via `Code.ensure_loaded?/1` checks if the
  dependency story should stay minimal

If existing `text` has no Nx dependency today, this is the largest change to
the package's footprint and worth flagging in the changelog.

### Step 4: Migration of the Bayesian Classifier

1. Tag a release of current code (`v0.x.y-final-bayesian` or similar) so the
   old behaviour is recoverable.
2. In a feature branch, delete the Bayesian classifier modules and any
   UDHR-loading code.
3. Implement Phases 1–5 above inside `Text.Language.*`.
4. Wire new detector into existing public API such that pre-existing call
   sites continue to work.
5. Run existing test suite. Failures fall into three categories:
   - Tests of internal Bayesian behaviour → delete
   - Tests of public API contract → should pass with new implementation,
     possibly with relaxed expectations on borderline languages
   - Tests where old classifier was wrong and new one is right → update
     expected values

### Step 5: Evaluation Against the Old Classifier

Before merging, generate a comparison report:

- Run both classifiers over UDHR (the old one's training data — new should
  win or tie) and over a held-out corpus from a different source (Tatoeba
  sentences, common crawl samples, short social-media-style text where the
  old classifier likely suffers).
- Produce confusion matrix and accuracy delta per language.
- Document in `CHANGELOG.md` so users upgrading understand the behavioural
  change.

This is also the right moment to verify the implementation against the
reference fastText output — if the Elixir version disagrees with the C++
version on the same input, that is a bug regardless of which one looks
"more correct."

### Step 6: Locale Derivation as First-Class Concern

Given the stated goal (formatting, calendar, collation), the locale
resolution layer matters as much as detection itself.

```elixir
defmodule Text.Language.Locale do
  @doc """
  Resolves a detection result to a CLDR locale string.

  Combines the detected language, optional script (from text analysis or
  explicit hint), and region hints (Accept-Language header, IP geolocation,
  user preference) using CLDR's likely-subtags algorithm.
  """
  @spec resolve(Text.Language.Detection.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def resolve(detection, opts \\ [])
end
```

The script signal is genuinely valuable here. `lid.176` reports `zh` for
both Simplified and Traditional Chinese; only by inspecting the codepoints
can you distinguish `zh-Hans` from `zh-Hant`, and that distinction matters
for collation and formatting.

### Step 7: Documentation

Substantial updates needed:

- Explain the model download step on first use — surprising users with a
  126MB download is poor form
- Document the `mix text.download_model` task
- Note `:nx` backend configuration for performance tuning
- Provide migration notes for users of the old API
- Credit fastText / Facebook Research for the model

---

## Effort Estimate

For an experienced Elixir developer comfortable with `Nx` and binary
parsing:

| Phase | Effort |
|-------|--------|
| 1–2 (model format + parser) | 2–3 days |
| 3–4 (hash + tokenization) | 3–4 days |
| 5 (Nx inference) | 1 day |
| 6 (locale derivation) | 2–3 days |
| 7 (packaging) | 1 day |
| 8 (testing) | 2–3 days initial, ongoing |

Roughly **two to three focused weeks** for a v1 with the unquantized model
and basic locale derivation.

---

## Open Questions to Resolve Early

1. What is the exact current public API of `Text.Language.*`? Plan needs
   refinement once `mix.exs` and existing module files are visible.

2. What is the minimum viable locale derivation contract? Returning just a
   language code is much simpler than committing to script-aware locale
   resolution; the latter could be a follow-up.

3. Synchronous per-call API, or `GenServer`-based serving with batched
   inference? Per-call is fine for most uses; batched matters only at high
   throughput.

4. Hard dependency on `:exla`, or fall back to `Nx.BinaryBackend` when
   absent? Affects deployment story for users on platforms where EXLA does
   not build cleanly.

5. Quantized model (`lid.176.ftz`) in v1 or v2? v2 is the safer call given
   the additional complexity of product quantization decoding.

---

## Immediate Next Steps in Claude Code

1. Read `../text/mix.exs` and `../text/lib/` to confirm current package
   structure and public API.
2. Tag and branch from current `main`.
3. Begin Phase 1: download `lid.176.bin`, generate golden fixtures from the
   reference Python implementation.
4. Begin Phase 2: write the binary format parser, validate against the
   reference by checking parsed `args` and dictionary entry counts.
5. Refine this plan with concrete file-level changes once the existing
   code is read.
