defmodule Text.WordCloud.Tokens do
  @moduledoc false
  # Shared tokenization helpers for `Text.WordCloud` backends. Internal
  # API — not part of the public surface.
  #
  # Centralises the `text → sentences → words → folded → stopword-filtered`
  # pipeline so every backend works against a consistent token stream.
  # YAKE additionally needs sentence boundaries (the "different sentence"
  # feature), and TextRank needs the unfiltered token stream to build a
  # co-occurrence graph that respects stopword positions, so we expose
  # both shapes from the same call.

  alias Text.Segment

  @type sentence_tokens :: [String.t()]

  @type prepared :: %{
          sentences: [sentence_tokens()],
          tokens: [String.t()],
          stopwords: MapSet.t(String.t())
        }

  @doc """
  Tokenises `input` and applies the orchestrator's pre-processing.

  Returns a map with three keys:

  * `:sentences` — list of sentence-grouped token lists, after folding
    and stopword filtering.

  * `:tokens` — flat list of all (folded, filtered) tokens.

  * `:stopwords` — the resolved stopword set, useful to backends that
    treat stopwords as phrase boundaries rather than dropping them
    outright.

  Accepts a binary or a list of binaries. List input is treated as a
  corpus of independent documents; sentences from later documents
  follow those of earlier ones in the output.
  """
  @spec prepare(String.t() | [String.t()], keyword()) :: prepared()
  def prepare(input, options) when is_binary(input), do: prepare([input], options)

  def prepare(documents, options) when is_list(documents) do
    case_fold? = Keyword.get(options, :case_fold, true)
    locale = Keyword.get(options, :locale)
    stopwords = resolve_stopword_set(options)

    sentences =
      documents
      |> Enum.flat_map(&split_into_sentences(&1, locale))
      |> Enum.map(&split_words(&1, locale))
      |> Enum.map(&maybe_fold(&1, case_fold?))
      |> Enum.map(&Enum.reject(&1, fn token -> MapSet.member?(stopwords, token) end))
      |> Enum.reject(&(&1 == []))

    tokens = Enum.concat(sentences)

    %{sentences: sentences, tokens: tokens, stopwords: stopwords}
  end

  @doc """
  Generates n-gram candidates for each sentence within `min..max`.

  Skips n-grams that span across a stopword/punctuation boundary by
  virtue of operating on the already-filtered sentence-grouped tokens.
  Returns a flat list of `{ngram_tokens, kind}` pairs ready for
  candidate counting; `kind` is `:word` for unigrams and `:phrase`
  for n>1.
  """
  @spec candidates([sentence_tokens()], pos_integer(), pos_integer()) ::
          [{[String.t()], :word | :phrase}]
  def candidates(sentences, min_n, max_n)
      when is_integer(min_n) and is_integer(max_n) and min_n >= 1 and max_n >= min_n do
    Enum.flat_map(sentences, fn sentence ->
      Enum.flat_map(min_n..max_n//1, fn n ->
        sentence
        |> Enum.chunk_every(n, 1, :discard)
        |> Enum.map(fn chunk -> {chunk, kind_for(n)} end)
      end)
    end)
  end

  @doc """
  Counts identical n-grams, returning `[{[tokens], count, kind}]`.

  Stable ordering: n-grams are returned in the order of their first
  appearance, with `count` being the total number of occurrences.
  """
  @spec count_candidates([{[String.t()], :word | :phrase}]) ::
          [{[String.t()], pos_integer(), :word | :phrase}]
  def count_candidates(candidates) do
    candidates
    |> Enum.reduce({%{}, []}, fn {tokens, kind}, {counts, order} ->
      case Map.fetch(counts, tokens) do
        {:ok, _} ->
          {Map.update!(counts, tokens, &(&1 + 1)), order}

        :error ->
          {Map.put(counts, tokens, 1), [{tokens, kind} | order]}
      end
    end)
    |> then(fn {counts, order} ->
      order
      |> Enum.reverse()
      |> Enum.map(fn {tokens, kind} -> {tokens, Map.fetch!(counts, tokens), kind} end)
    end)
  end

  # ---- internals --------------------------------------------------------

  defp resolve_stopword_set(options) do
    case Keyword.get(options, :stopwords, :auto) do
      :none ->
        MapSet.new()

      :auto ->
        language = Keyword.get(options, :language)

        cond do
          is_nil(language) -> MapSet.new()
          Text.Stopwords.available?(language) -> Text.Stopwords.for(language)
          true -> MapSet.new()
        end

      {:extend, extras} ->
        language = Keyword.get(options, :language)

        if language && Text.Stopwords.available?(language) do
          Text.Stopwords.extend(language, extras)
        else
          MapSet.new(extras)
        end

      %MapSet{} = set ->
        set

      list when is_list(list) ->
        MapSet.new(list)
    end
  end

  # `unicode_string`'s sentence segmenter treats newlines as sentence
  # boundaries (per UAX #29), which spuriously fragments multi-line
  # input pasted from documents. Collapse all whitespace runs to a
  # single space before segmenting.
  defp normalise_whitespace(text), do: String.replace(text, ~r/\s+/u, " ")

  defp split_into_sentences(text, nil), do: text |> normalise_whitespace() |> Segment.sentences()

  defp split_into_sentences(text, locale) when is_binary(locale) do
    text
    |> normalise_whitespace()
    |> Segment.sentences(locale: locale)
  end

  defp split_words(text, nil), do: Segment.words(text)

  defp split_words(text, locale) when is_binary(locale) do
    Segment.words(text, locale: locale)
  end

  defp maybe_fold(tokens, false), do: tokens
  defp maybe_fold(tokens, true), do: Enum.map(tokens, &String.downcase/1)

  defp kind_for(1), do: :word
  defp kind_for(_), do: :phrase
end
