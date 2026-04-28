defmodule Text.WordCloud.Backends.TextRank do
  @moduledoc """
  TextRank backend for `Text.WordCloud`.

  Implements the keyword-extraction variant of TextRank (Mihalcea &
  Tarau, [*Bringing Order into Texts*](https://aclanthology.org/W04-3252/),
  2004). Builds an undirected, weighted graph where vertices are
  non-stopword tokens and edges connect tokens that co-occur within a
  sliding window. Weighted PageRank over that graph yields a relevance
  score per token; phrase candidates are then composed by joining
  adjacent high-scoring tokens.

  ### Strengths

  * No reference corpus required.

  * Truly multilingual — like YAKE!, TextRank's only language-specific
    dependency is the stopword list.

  * Resilient to long documents — graph density grows linearly, not
    quadratically.

  ### Caveats

  * Slower than YAKE! for short inputs (PageRank iterations dominate).

  * Phrase composition is heuristic: adjacent top-scoring tokens are
    glued, which can produce odd cuts on very dense topical text.

  ### Options

  * `:window_size` — co-occurrence window. Default `4` (Mihalcea &
    Tarau use 2–10; 4 is a common middle ground).

  * `:damping` — PageRank damping factor. Default `0.85`.

  * `:tolerance` — convergence threshold (max delta across vertices).
    Default `1.0e-5`.

  * `:max_iterations` — safety cap. Default `100`.

  Standard `Text.WordCloud` orchestrator options (`:language`,
  `:stopwords`, `:case_fold`, `:ngram_range`, `:locale`) are honoured.

  """

  @behaviour Text.WordCloud.Backend

  alias Text.WordCloud.Tokens

  @default_window 4
  @default_damping 0.85
  @default_tolerance 1.0e-5
  @default_max_iter 100

  @impl true
  def score(input, options) do
    {min_n, max_n} = Keyword.get(options, :ngram_range, {1, 3})
    window = Keyword.get(options, :window_size, @default_window)
    damping = Keyword.get(options, :damping, @default_damping)
    tolerance = Keyword.get(options, :tolerance, @default_tolerance)
    max_iter = Keyword.get(options, :max_iterations, @default_max_iter)

    %{sentences: sentences} = Tokens.prepare(input, options)

    graph = build_graph(sentences, window)
    ranks = run_page_rank(graph, damping, tolerance, max_iter)

    # Single-token scores from the rank table.
    unigrams =
      Enum.map(ranks, fn {token, rank} ->
        {[token], rank, token_count(sentences, token), :word}
      end)

    # Multi-token candidates: collapse adjacent non-stopword tokens in
    # each sentence into n-grams within `:ngram_range` and score by the
    # sum of constituent ranks (the standard TextRank phrase rule).
    phrase_candidates = collect_phrase_candidates(sentences, min_n, max_n, ranks)

    candidates =
      if min_n <= 1 and max_n >= 1, do: unigrams ++ phrase_candidates, else: phrase_candidates

    Enum.map(candidates, fn {tokens, score, count, kind} ->
      {Enum.join(tokens, " "), score, count, kind}
    end)
  end

  # ---- graph construction ---------------------------------------------

  # Builds the symmetric adjacency map. A bidirectional edge between
  # two distinct tokens within `window` of each other in any sentence
  # contributes `1` to that pair's weight (we don't double-count
  # multiple co-occurrences within the same window — standard TextRank).
  defp build_graph(sentences, window) do
    Enum.reduce(sentences, %{}, fn sentence, acc ->
      sentence
      |> Enum.with_index()
      |> Enum.reduce(acc, fn {token, position}, acc2 ->
        sentence
        |> Enum.drop(position + 1)
        |> Enum.take(window)
        |> Enum.reduce(acc2, fn other, acc3 ->
          if other == token, do: acc3, else: add_edge(acc3, token, other)
        end)
      end)
    end)
  end

  defp add_edge(graph, a, b) do
    graph
    |> Map.update(a, %{b => 1}, &Map.update(&1, b, 1, fn n -> n + 1 end))
    |> Map.update(b, %{a => 1}, &Map.update(&1, a, 1, fn n -> n + 1 end))
  end

  # ---- weighted PageRank ----------------------------------------------

  defp run_page_rank(graph, _damping, _tolerance, _max_iter) when graph == %{}, do: %{}

  defp run_page_rank(graph, damping, tolerance, max_iter) do
    vertices = Map.keys(graph)
    n = length(vertices)
    initial = Map.new(vertices, &{&1, 1.0 / n})

    iterate(graph, vertices, initial, damping, tolerance, max_iter)
  end

  defp iterate(_graph, _vertices, ranks, _damping, _tolerance, 0), do: ranks

  defp iterate(graph, vertices, ranks, damping, tolerance, iterations_left) do
    new_ranks =
      Map.new(vertices, fn v ->
        contribution =
          graph
          |> Map.fetch!(v)
          |> Enum.reduce(0.0, fn {u, weight}, sum ->
            u_total = graph |> Map.fetch!(u) |> Map.values() |> Enum.sum()

            if u_total == 0, do: sum, else: sum + weight / u_total * Map.fetch!(ranks, u)
          end)

        {v, 1.0 - damping + damping * contribution}
      end)

    delta =
      Enum.reduce(vertices, 0.0, fn v, max_d ->
        max(max_d, abs(Map.fetch!(new_ranks, v) - Map.fetch!(ranks, v)))
      end)

    if delta < tolerance,
      do: new_ranks,
      else: iterate(graph, vertices, new_ranks, damping, tolerance, iterations_left - 1)
  end

  # ---- phrase candidates -----------------------------------------------

  # Form n-grams from adjacent non-stopword tokens (the sentence-level
  # token stream is already stopword-filtered by `Tokens.prepare/2`),
  # within `min_n..max_n`. Score each as the sum of constituent ranks.
  defp collect_phrase_candidates(_sentences, min_n, _max_n, _ranks) when min_n > 1 do
    []
  end

  defp collect_phrase_candidates(_sentences, _min_n, max_n, _ranks) when max_n < 2, do: []

  defp collect_phrase_candidates(sentences, _min_n, max_n, ranks) do
    sentences
    |> Enum.flat_map(fn sentence ->
      Enum.flat_map(2..max_n//1, fn n ->
        sentence
        |> Enum.chunk_every(n, 1, :discard)
        |> Enum.map(fn chunk ->
          score = chunk |> Enum.map(&Map.get(ranks, &1, 0.0)) |> Enum.sum()
          {chunk, score}
        end)
      end)
    end)
    |> count_and_score()
    |> Enum.map(fn {tokens, score, count} -> {tokens, score, count, :phrase} end)
  end

  defp count_and_score(scored_chunks) do
    scored_chunks
    |> Enum.reduce(%{}, fn {tokens, score}, acc ->
      Map.update(acc, tokens, {score, 1}, fn {s, c} -> {s, c + 1} end)
    end)
    |> Enum.map(fn {tokens, {score, count}} -> {tokens, score, count} end)
  end

  defp token_count(sentences, token) do
    Enum.reduce(sentences, 0, fn sentence, acc ->
      acc + Enum.count(sentence, &(&1 == token))
    end)
  end
end
