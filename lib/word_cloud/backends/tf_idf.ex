defmodule Text.WordCloud.Backends.TFIDF do
  @moduledoc """
  TF-IDF backend for `Text.WordCloud`.

  Scores each candidate term as `tf(t) * idf(t)`, where `tf` is the
  raw count in the foreground text and `idf` is the inverse-document
  frequency over a user-supplied reference corpus. This is the
  classical "what is *distinctive* about this document?" scorer — it
  surfaces terms that are common in the foreground but rare across
  the background.

  ### Foreground vs background

  * The first argument to `Text.WordCloud.terms/2` is the foreground:
    a single string or a list of strings (treated as one document).

  * The reference corpus is supplied via the `:reference_corpus`
    option, either as a list of background documents (TF-IDF computes
    IDF over them) or as a precomputed `%{term => idf}` map.

  Without a reference corpus the backend falls back to `IDF = 1.0`
  for every term, reducing to a frequency cloud — which is rarely
  what you want. The orchestrator emits an `IO.warn/2` in that case.

  ### Smoothing

  Uses log-smoothed IDF with the standard `log(N / (1 + df))` form:

  * `N` = number of reference documents.
  * `df_t` = number of reference documents containing term `t`.

  Terms unseen in the reference get `IDF = log(N / 1) = log(N)`,
  giving them a sensible high score rather than zero.

  ### Defaults

  * `:ngram_range` defaults to `{1, 1}` for this backend — IDF over
    multi-token phrases is rarely meaningful unless the reference
    corpus is large enough that phrases recur. Override explicitly
    if you have such a corpus.

  Standard `Text.WordCloud` orchestrator options (`:language`,
  `:stopwords`, `:case_fold`, `:locale`) are honoured.

  """

  @behaviour Text.WordCloud.Backend

  alias Text.WordCloud.Tokens

  @impl true
  def score(input, options) do
    {min_n, max_n} = Keyword.get(options, :ngram_range, {1, 1})
    reference = Keyword.get(options, :reference_corpus)

    %{sentences: sentences} = Tokens.prepare(input, options)

    candidates =
      sentences
      |> Tokens.candidates(min_n, max_n)
      |> Tokens.count_candidates()

    idf = resolve_idf(reference, options, min_n, max_n)

    Enum.map(candidates, fn {tokens, count, kind} ->
      term = Enum.join(tokens, " ")
      idf_value = idf_for(idf, term, tokens)
      {term, count * idf_value, count, kind}
    end)
  end

  # ---- IDF resolution -------------------------------------------------

  defp resolve_idf(nil, _options, _min_n, _max_n) do
    IO.warn(
      "Text.WordCloud.Backends.TFIDF: no :reference_corpus provided. " <>
        "Falling back to IDF = 1.0; results will degrade to a frequency cloud."
    )

    :uniform
  end

  defp resolve_idf(map, _options, _min_n, _max_n) when is_map(map), do: map

  defp resolve_idf(documents, options, min_n, max_n) when is_list(documents) do
    # Each reference document is tokenized through the same pipeline
    # as the foreground so case folding, stopword removal, and locale
    # are consistent. Each doc contributes a *set* of unique terms
    # (n-grams), not a multiset, since IDF only cares about presence.
    n_docs = length(documents)
    if n_docs == 0, do: raise(ArgumentError, "Reference corpus is empty")

    df =
      Enum.reduce(documents, %{}, fn doc, acc ->
        %{sentences: doc_sentences} = Tokens.prepare(doc, options)

        terms =
          doc_sentences
          |> Tokens.candidates(min_n, max_n)
          |> Enum.map(fn {tokens, _kind} -> Enum.join(tokens, " ") end)
          |> MapSet.new()

        Enum.reduce(terms, acc, fn term, acc2 ->
          Map.update(acc2, term, 1, &(&1 + 1))
        end)
      end)

    # Smoothed IDF: log(N / (1 + df_t)) + 1.0. The `+ 1.0` shift keeps
    # terms appearing in every reference doc from collapsing to a zero
    # IDF — the standard TF-IDF "ltc" weighting variant.
    Map.new(df, fn {term, df_t} ->
      {term, :math.log(n_docs / (1 + df_t)) + 1.0}
    end)
  end

  defp idf_for(:uniform, _term, _tokens), do: 1.0

  defp idf_for(map, term, _tokens) when is_map(map) do
    case Map.fetch(map, term) do
      {:ok, value} ->
        value

      :error ->
        # Unseen term: fall back to a high IDF derived from the
        # corpus's max observed value, plus one — the term is
        # rarer than anything we've seen.
        case map_size(map) do
          0 -> 1.0
          _ -> 1.0 + (map |> Map.values() |> Enum.max())
        end
    end
  end
end
