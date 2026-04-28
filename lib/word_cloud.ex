defmodule Text.WordCloud do
  @moduledoc """
  Builds a weighted list of terms suitable for rendering as a word cloud.

  The function returns a list of `%{term, weight, count, kind}` maps
  sorted by `:weight` (descending). The top term always has weight
  `1.0`; every other weight is normalised relative to it. Visual
  layout — placing the words on a canvas — is handled separately by
  `Text.WordCloud.Layout`.

  Supports several scoring algorithms via the `:scoring` option;
  `:yake` (the default) requires no reference corpus and is
  multilingual by construction. See the `Text.WordCloud.Backends.*`
  modules for the catalogue.

  Multilingual end-to-end:

  * Tokenisation runs through `Text.Segment.words/2` (Unicode UAX #29).

  * Sentence segmentation uses `Text.Segment.sentences/2`.

  * Stopwords come from the bundled `Text.Stopwords` (~60 languages)
    via the `:stopwords` option.

  * Language is auto-detected with `Text.Language.Classifier.Fasttext`
    when `:language` is unset, falling back to no language-specific
    behaviour if the classifier is not available.

  """

  alias Text.WordCloud.Backends

  @typedoc "A scored term, ready for rendering."
  @type term_entry :: %{
          term: String.t(),
          weight: float(),
          count: pos_integer(),
          kind: :word | :phrase
        }

  @builtin_backends %{
    yake: Backends.YAKE,
    frequency: Backends.Frequency,
    rake: Backends.RAKE,
    text_rank: Backends.TextRank,
    tf_idf: Backends.TFIDF,
    key_bert: Backends.KeyBERT
  }

  @doc """
  Returns a weighted list of terms for `text` suitable for word-cloud rendering.

  ### Arguments

  * `text` is a UTF-8 string or a list of strings. A list is treated
    as a corpus of independent documents.

  ### Options

  * `:scoring` — `:yake` (default), `:frequency`, `:tf_idf`, `:rake`,
    `:text_rank`, `:key_bert`, or any module implementing
    `Text.WordCloud.Backend`.

  * `:max_terms` — cap on returned entries. Default `100`.

  * `:min_count` — drop terms occurring fewer times than this.
    Default `1`.

  * `:ngram_range` — `{min, max}` token length for candidate terms.
    Default depends on backend (`{1, 3}` for YAKE, `{1, 1}` for
    Frequency).

  * `:language` — atom, BCP-47 string, or `Localize.LanguageTag`.
    Default `nil` (no language-specific behaviour). Pass
    `{:auto, model}` to auto-detect via a pre-loaded
    `Text.Language.Classifier.Fasttext.Model` — the orchestrator
    does not load the fastText model itself, so callers wanting
    detection load it once at boot and hand it in.

  * `:stopwords` — `:auto` (use the bundled list for the resolved
    language; default), `:none`, a list, a `MapSet`, or
    `{:extend, [extra]}` to add to the bundled list.

  * `:case_fold` — boolean, default `true`.

  * `:include` — `:all` (default), `:words` only, or `:phrases` only.

  * `:reference_corpus` — used by `:tf_idf` and `:log_likelihood`.

  ### Returns

  * A list of `%{term, weight, count, kind}` maps sorted by `:weight`
    descending. The top entry has `weight: 1.0`.

  ### Examples

      iex> text = "the cat sat on the mat. the cat ran. the cat slept."
      iex> [first | _] = Text.WordCloud.terms(text, scoring: :frequency, language: :en, max_terms: 3)
      iex> first.term
      "cat"

  """
  @spec terms(String.t() | [String.t()], keyword()) :: [term_entry()]
  def terms(text, options \\ []) do
    options = resolve_options(text, options)
    backend = resolve_backend(Keyword.fetch!(options, :scoring))

    text
    |> backend.score(options)
    |> finalise(options)
  end

  # ---- options resolution ----------------------------------------------

  defp resolve_options(text, options) do
    options
    |> Keyword.put_new(:scoring, :yake)
    |> Keyword.put_new(:max_terms, 100)
    |> Keyword.put_new(:min_count, 1)
    |> Keyword.put_new(:case_fold, true)
    |> Keyword.put_new(:include, :all)
    |> Keyword.put_new(:stopwords, :auto)
    |> resolve_language(text)
    |> resolve_ngram_range()
  end

  defp resolve_language(options, text) do
    case Keyword.get(options, :language) do
      nil ->
        Keyword.put(options, :language, nil)

      {:auto, model} ->
        Keyword.put(options, :language, detect_language(text, model))

      explicit ->
        Keyword.put(options, :language, Text.Language.normalize(explicit))
    end
  end

  # Auto-detection requires a pre-loaded fastText `Model`. We use the
  # first non-empty document as the detection input — long enough to
  # be representative, short enough that the classifier runs in well
  # under a millisecond.
  defp detect_language(text, model) when is_binary(text), do: detect_language([text], model)

  defp detect_language([head | _], model) when is_binary(head) do
    case Text.Language.Classifier.Fasttext.detect(head, model) do
      {:ok, detection} -> Text.Language.normalize(detection.language)
      _ -> nil
    end
  end

  defp detect_language(_, _), do: nil

  # Per-backend default n-gram range. YAKE & RAKE & TextRank are
  # phrase-aware out of the box and benefit from the {1, 3} default;
  # Frequency is uninformative on phrases (the longest run wins for
  # spurious reasons), and TF-IDF on phrases needs reference corpora
  # large enough for phrases to recur — neither is the common case.
  defp resolve_ngram_range(options) do
    case Keyword.get(options, :ngram_range) do
      nil ->
        default =
          case Keyword.fetch!(options, :scoring) do
            :frequency -> {1, 1}
            :tf_idf -> {1, 1}
            _ -> {1, 3}
          end

        Keyword.put(options, :ngram_range, default)

      {min, max} when is_integer(min) and is_integer(max) and min >= 1 and max >= min ->
        options
    end
  end

  defp resolve_backend(scoring) when is_atom(scoring) do
    case Map.fetch(@builtin_backends, scoring) do
      {:ok, module} ->
        module

      :error ->
        if function_exported?(scoring, :score, 2) do
          scoring
        else
          raise ArgumentError,
                "unknown :scoring backend #{inspect(scoring)}. " <>
                  "Built-ins: #{inspect(Map.keys(@builtin_backends))}, or pass " <>
                  "a module implementing Text.WordCloud.Backend."
        end
    end
  end

  # ---- finalisation ----------------------------------------------------

  defp finalise(scored, options) do
    min_count = Keyword.fetch!(options, :min_count)
    include = Keyword.fetch!(options, :include)
    max_terms = Keyword.fetch!(options, :max_terms)

    scored
    |> Enum.filter(fn {_term, _score, count, _kind} -> count >= min_count end)
    |> filter_kind(include)
    |> Enum.sort_by(fn {_term, score, _count, _kind} -> -score end)
    |> normalise()
    |> Enum.take(max_terms)
  end

  defp filter_kind(entries, :all), do: entries
  defp filter_kind(entries, :words), do: Enum.filter(entries, &(elem(&1, 3) == :word))
  defp filter_kind(entries, :phrases), do: Enum.filter(entries, &(elem(&1, 3) == :phrase))

  defp normalise([]), do: []

  defp normalise(entries) do
    {_, max_score, _, _} = hd(entries)

    case max_score do
      n when n in [0, 0.0] ->
        Enum.map(entries, fn {term, _, count, kind} ->
          %{term: term, weight: 0.0, count: count, kind: kind}
        end)

      _ ->
        Enum.map(entries, fn {term, score, count, kind} ->
          %{term: term, weight: score / max_score, count: count, kind: kind}
        end)
    end
  end
end
