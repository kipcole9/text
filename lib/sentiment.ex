defmodule Text.Sentiment do
  @moduledoc """
  Sentiment analysis with multilingual support.

  Two backends are shipped with `text`:

  * **`Text.Sentiment.Backends.Lexicon`** (the default) — fast,
    deterministic, multilingual lexicon-based scoring backed by the
    bundled AFINN lexicons (English, Danish, Finnish, French, Polish,
    Swedish, Turkish, plus a language-agnostic emoticon lexicon).
    Apache 2.0. Sub-millisecond per call. No model download, no
    optional dependencies.

  * **`Text.Sentiment.Backends.Bumblebee`** (optional) — neural
    sentiment via [Bumblebee](https://hex.pm/packages/bumblebee) and a
    pre-trained multilingual transformer (XLM-RoBERTa). Higher quality,
    slower (single-digit ms per call after a 10-30 s cold start), and
    requires adding `:bumblebee` and `:exla` to your deps.

  The default backend is the lexicon. To switch globally:

      # config/config.exs
      config :text, :sentiment_backend, Text.Sentiment.Backends.Bumblebee

  To switch per call:

      Text.Sentiment.analyze(text, backend: Text.Sentiment.Backends.Bumblebee)

  Custom backends can be supplied by implementing the
  `Text.Sentiment.Backend` behaviour.

  ### Three-line summary

      iex> {:ok, _} = {:ok, :ignored}                   # one-liner
      iex> result = Text.Sentiment.analyze("This is a great day!")
      iex> result.label
      :positive

  ### Multilingual usage

  Pass `language: <tag>` to pick a bundled AFINN lexicon. The tag
  matches the [ISO 639-1](https://en.wikipedia.org/wiki/ISO_639-1) codes
  AFINN itself uses:

      iex> Text.Sentiment.analyze("Ce produit est excellent et magnifique!", language: :fr).label
      :positive

      iex> Text.Sentiment.analyze("Detta är en mycket dålig idé.", language: :sv).label
      :negative

  For languages outside the bundled set, supply your own lexicon —
  any `%{token => number}` map works:

      custom = %{"awesome" => 4, "garbage" => -4}
      Text.Sentiment.analyze("That feature is awesome", lexicon: custom)

  ### Combining lexicons (e.g. emoticons)

  The bundled `:emoticon` lexicon is language-agnostic. Merge it with
  any per-language lexicon when scoring informal text:

      lexicon = Text.Sentiment.lexicon_for(:en, with_emoticons: true)
      Text.Sentiment.analyze("That movie was awful :-(", lexicon: lexicon)

  ### End-to-end with `Text.Language.Classifier.Fasttext`

  When the language is unknown, detect it first and route to the
  matching lexicon:

      {:ok, model} = Text.Language.Classifier.Fasttext.ModelLoader.load(path)
      {:ok, detection} = Text.Language.Classifier.Fasttext.detect(text, model)
      lang = String.to_atom(detection.language)
      Text.Sentiment.analyze(text, language: lang)

  Falls back gracefully when the detected language is not bundled —
  pass `:fallback_language` to control what happens (default `:en`).

  """

  alias Text.Sentiment.{Backend, Lexicons}

  @default_language :en

  @typedoc "Convenience type for a positive/negative/neutral label."
  @type label :: :positive | :negative | :neutral

  @typedoc "Result struct returned by `analyze/2`."
  @type result :: %{
          sum: float(),
          compound: float(),
          label: label(),
          language: atom(),
          tokens: non_neg_integer(),
          matched: non_neg_integer()
        }

  @doc """
  Analyzes the sentiment of `text`.

  ### Arguments

  * `text` is a UTF-8 string.

  ### Options

  * `:language` — accepts an atom (`:fr`), a string (`"fr"`,
    `"fr-CA"`), or a `Localize.LanguageTag` struct when the optional
    `:localize` dependency is loaded. The tag is normalised to its
    language subtag before lookup. Bundled AFINN tags are
    `#{inspect(Lexicons.AFINN.available())}`. Defaults to
    `:#{@default_language}`. Ignored when `:lexicon` is given.

  * `:lexicon` — a `%{token => number}` map. Overrides `:language` if
    given. Use `lexicon_for/2` to compose a bundled language with the
    emoticon lexicon, or supply your own.

  * `:fallback_language` — the bundled tag to fall back to if
    `:language` is given but not bundled. Same shapes as `:language`.
    Defaults to `:#{@default_language}`.

  * Any of the keyword options accepted by
    `Text.Sentiment.Lexicon.score/3` (`:tokenizer`, `:fold_case`,
    `:negators`, `:intensifiers`, `:diminishers`, etc.) are forwarded
    through.

  ### Returns

  A map with:

  * `:sum`, `:compound`, `:label`, `:tokens`, `:matched` — same fields
    as `Text.Sentiment.Lexicon.score/3`.

  * `:language` — the language tag actually used (after fallback).

  ### Examples

      iex> Text.Sentiment.analyze("I really love this product!").label
      :positive

      iex> Text.Sentiment.analyze("This was a bad experience.").label
      :negative

      iex> Text.Sentiment.analyze("The package arrived today.").label
      :neutral

  """
  @spec analyze(String.t(), keyword()) :: result()
  def analyze(text, options \\ []) when is_binary(text) do
    backend = Backend.resolve(options)
    backend.analyze(text, options)
  end

  @doc """
  Returns just the sentiment label for `text`.

  ### Arguments

  * `text` is a UTF-8 string.

  ### Options

  Same as `analyze/2`.

  ### Returns

  * `:positive`, `:negative`, or `:neutral`.

  ### Examples

      iex> Text.Sentiment.label("This is amazing!")
      :positive

      iex> Text.Sentiment.label("This is awful.")
      :negative

  """
  @spec label(String.t(), keyword()) :: label()
  def label(text, options \\ []) when is_binary(text) do
    text |> analyze(options) |> Map.fetch!(:label)
  end

  @doc """
  Builds a composite lexicon for the given language.

  Useful for combining a language-specific lexicon with the
  language-agnostic emoticon lexicon (or any other extension lexicon).

  ### Arguments

  * `language` is a bundled tag.

  ### Options

  * `:with_emoticons` — when `true` (default `false`), merges the
    emoticon lexicon into the result. Emoticon entries override
    language entries on conflict, but in practice there are none.

  * `:overrides` — an extra `%{token => number}` map merged on top.
    Useful for domain-specific terms (industry jargon, product names,
    brand-charged language).

  ### Returns

  A `%{token => number}` map suitable for `analyze/2`'s `:lexicon`
  option.

  ### Examples

      iex> lexicon = Text.Sentiment.lexicon_for(:en, with_emoticons: true)
      iex> Map.get(lexicon, "good")
      3
      iex> Map.get(lexicon, ":-)")
      2

      iex> lexicon = Text.Sentiment.lexicon_for(:en, overrides: %{"foo" => 5})
      iex> Map.get(lexicon, "foo")
      5

  """
  @spec lexicon_for(Text.Language.input(), keyword()) :: %{String.t() => number()}
  def lexicon_for(language, options \\ []) do
    tag = Text.Language.normalize(language)
    base = Lexicons.AFINN.lexicon(tag)

    base =
      if Keyword.get(options, :with_emoticons, false),
        do: Map.merge(base, Lexicons.AFINN.lexicon(:emoticon)),
        else: base

    overrides = Keyword.get(options, :overrides, %{})
    Map.merge(base, overrides)
  end
end
