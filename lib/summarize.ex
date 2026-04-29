defmodule Text.Summarize do
  @moduledoc """
  Extractive text summarization.

  Picks the most representative sentences from a document and
  returns them in their original order. Two algorithms are
  implemented:

  * `:textrank` (default) — builds a sentence similarity graph and
    runs PageRank over it. Sentences that are similar to many other
    sentences score higher. From Mihalcea & Tarau (2004).

  * `:lexrank` — the same idea but with a hard similarity threshold:
    edges below the threshold are dropped before scoring. From
    Erkan & Radev (2004).

  Both algorithms use Jaccard similarity over content words (with
  stopwords removed) as the inter-sentence weight. The graph
  construction and ranking are pure Elixir — no embeddings, no
  external models — so summarization works on any text the
  segmenter can handle.

  This is suitable for documents from a few sentences to a few
  hundred. For very long documents, consider chunking first.
  Abstractive summarization (rewriting rather than selecting) is a
  Bumblebee-backed feature on the deferred list.

  """

  alias Text.Segment
  alias Text.Stopwords

  @default_damping 0.85
  @default_iterations 30
  @default_lexrank_threshold 0.1

  @doc """
  Returns the most representative sentences from the input text.

  ### Arguments

  * `text` is the document as a string.

  ### Options

  * `:sentences` is the number of sentences to return. Default `3`.
    If the document has fewer sentences than this, every sentence
    is returned.

  * `:algorithm` is `:textrank` (default) or `:lexrank`.

  * `:language` is the language atom used for sentence segmentation
    and stopword removal. Default `:en`.

  * `:damping` is the PageRank damping factor. Default `0.85`.

  * `:iterations` is the number of PageRank iterations. Default `30`.

  * `:threshold` is the LexRank similarity cutoff. Edges with
    similarity below this value are dropped. Only used by `:lexrank`.
    Default `0.1`.

  ### Returns

  * A string of selected sentences joined with single spaces, in
    original document order.

  ### Examples

      iex> text = "Cats are lovely pets. Dogs are loyal animals. Goldfish swim quietly. Birds sing in the morning."
      iex> Text.Summarize.summarize(text, sentences: 2) |> String.contains?(".")
      true

  """
  @spec summarize(String.t(), keyword()) :: String.t()
  def summarize(text, options \\ []) when is_binary(text) do
    sentences =
      summarize_sentences(text, options)

    Enum.join(sentences, " ")
  end

  @doc """
  Returns the selected sentences as a list (rather than joined).

  Same options as `summarize/2`. Useful when the caller wants to
  format the output (bullets, numbered lists) rather than receive
  pre-joined prose.

  ### Examples

      iex> text = "First sentence. Second sentence. Third sentence. Fourth sentence."
      iex> result = Text.Summarize.summarize_sentences(text, sentences: 2)
      iex> length(result)
      2

  """
  @spec summarize_sentences(String.t(), keyword()) :: [String.t()]
  def summarize_sentences(text, options \\ []) when is_binary(text) do
    n = Keyword.get(options, :sentences, 3)
    algorithm = Keyword.get(options, :algorithm, :textrank)
    language = Keyword.get(options, :language, :en)

    sentences = Segment.sentences(text, locale: to_string(language))
    total = length(sentences)

    cond do
      total <= n ->
        sentences

      total == 0 ->
        []

      true ->
        ranked = rank(sentences, algorithm, language, options)

        ranked
        |> Enum.with_index()
        |> Enum.sort_by(fn {score, _} -> -score end)
        |> Enum.take(n)
        |> Enum.map(fn {_, idx} -> idx end)
        |> Enum.sort()
        |> Enum.map(&Enum.at(sentences, &1))
    end
  end

  @doc """
  Returns the per-sentence importance scores from the chosen
  algorithm.

  Useful for callers that want to render a heatmap of sentence
  importance, or implement their own selection policy on top of
  the raw scores.

  ### Returns

  * A list of floats, one per sentence in the input, in document order.

  """
  @spec scores(String.t(), keyword()) :: [float()]
  def scores(text, options \\ []) when is_binary(text) do
    algorithm = Keyword.get(options, :algorithm, :textrank)
    language = Keyword.get(options, :language, :en)
    sentences = Segment.sentences(text, locale: to_string(language))
    rank(sentences, algorithm, language, options)
  end

  defp rank(sentences, algorithm, language, options) do
    similarity_matrix = build_similarity(sentences, language)

    matrix =
      case algorithm do
        :lexrank ->
          threshold = Keyword.get(options, :threshold, @default_lexrank_threshold)

          for row <- similarity_matrix do
            for v <- row, do: if(v >= threshold, do: v, else: 0.0)
          end

        :textrank ->
          similarity_matrix

        other ->
          raise ArgumentError, "Unknown algorithm: #{inspect(other)}"
      end

    pagerank(matrix,
      damping: Keyword.get(options, :damping, @default_damping),
      iterations: Keyword.get(options, :iterations, @default_iterations)
    )
  end

  defp build_similarity(sentences, language) do
    stopwords = stopword_set(language)

    tokens =
      Enum.map(sentences, fn sentence ->
        sentence
        |> String.downcase()
        |> String.split(~r/\W+/u, trim: true)
        |> Enum.reject(&MapSet.member?(stopwords, &1))
        |> MapSet.new()
      end)

    n = length(tokens)
    indexed = Enum.with_index(tokens)

    for {a, i} <- indexed do
      for {b, j} <- indexed do
        cond do
          i == j -> 0.0
          MapSet.size(a) == 0 or MapSet.size(b) == 0 -> 0.0
          true -> jaccard(a, b)
        end
      end
    end
    |> normalize_rows(n)
  end

  defp jaccard(a, b) do
    intersection = MapSet.size(MapSet.intersection(a, b))
    union = MapSet.size(MapSet.union(a, b))
    if union == 0, do: 0.0, else: intersection / union
  end

  defp normalize_rows(matrix, _n) do
    Enum.map(matrix, fn row ->
      total = Enum.sum(row)
      if total == 0.0, do: row, else: Enum.map(row, &(&1 / total))
    end)
  end

  defp pagerank(matrix, options) do
    damping = Keyword.fetch!(options, :damping)
    iterations = Keyword.fetch!(options, :iterations)
    n = length(matrix)
    initial = List.duplicate(1.0 / n, n)
    base = (1.0 - damping) / n

    Enum.reduce(1..iterations, initial, fn _, scores ->
      for i <- 0..(n - 1) do
        contribution =
          for j <- 0..(n - 1), reduce: 0.0 do
            acc ->
              weight = matrix |> Enum.at(j) |> Enum.at(i)
              acc + Enum.at(scores, j) * weight
          end

        base + damping * contribution
      end
    end)
  end

  defp stopword_set(language) do
    if Stopwords.available?(language) do
      # Reconstruct via Enum.into so dialyzer sees a properly typed MapSet
      # rather than a literal struct from another module.
      Enum.into(Stopwords.for(language), MapSet.new())
    else
      MapSet.new()
    end
  end
end
