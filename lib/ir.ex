defmodule Text.IR do
  @moduledoc """
  Information-retrieval scoring against an indexed corpus.

  Two scoring functions are provided:

  * **TF-IDF** (`tfidf/3`) — the classical term frequency × inverse
    document frequency. Useful as a feature for clustering and
    classification, and as a fast first-pass relevance signal.

  * **BM25** (`bm25/4`) — Okapi BM25, the de-facto standard probabilistic
    relevance ranking used by Lucene/Elasticsearch and most modern
    search engines. Strictly better than TF-IDF for ranking results to
    a query.

  Both score functions consume a `Text.IR.Corpus` built once with
  `Text.IR.Corpus.new/2`. The corpus precomputes document frequencies,
  term frequencies, and document lengths so per-query scoring is
  O(query terms × matching documents).

  ### TF-IDF formula

      tf-idf(t, d) = tf(t, d) · log(N / df(t))

  where `tf(t, d)` is the count of term `t` in document `d`, `N` is
  the total number of documents in the corpus, and `df(t)` is the
  number of documents containing `t`. This module uses raw term
  frequency (not log-normalised) and the smooth IDF variant
  `log((N + 1) / (df + 1)) + 1` so the score is non-negative even
  when a query term occurs in every document.

  ### BM25 formula

      score(d, q) = Σ over t in q: idf(t) · (tf · (k1 + 1)) /
                                    (tf + k1 · (1 - b + b · |d|/avgdl))

  with the smooth IDF `log((N - df + 0.5) / (df + 0.5) + 1)` (Lucene's
  variant — guarantees non-negative IDF) and parameters `k1 = 1.2`,
  `b = 0.75` by default.

  """

  alias Text.IR.Corpus

  @bm25_k1 1.2
  @bm25_b 0.75

  @doc """
  Returns the TF-IDF score for `term` in document `doc_id` of the
  given corpus.

  ### Arguments

  * `corpus` is a `Text.IR.Corpus`.

  * `doc_id` is the zero-based document index.

  * `term` is the term string to score. The term is folded to match
    the corpus's case-folding setting before lookup.

  ### Returns

  * A non-negative float. Returns `0.0` when the term doesn't appear
    in the document.

  ### Examples

      iex> docs = ["the cat sat", "the dog sat", "a fox ran"]
      iex> corpus = Text.IR.Corpus.new(docs)
      iex> Text.IR.tfidf(corpus, 0, "cat") > 0.0
      true

      iex> docs = ["the cat sat", "the dog sat", "a fox ran"]
      iex> corpus = Text.IR.Corpus.new(docs)
      iex> Text.IR.tfidf(corpus, 0, "missing")
      0.0

  """
  @spec tfidf(Corpus.t(), Corpus.doc_id(), Corpus.term_string()) :: float()
  def tfidf(%Corpus{} = corpus, doc_id, term) do
    folded = fold_term(corpus, term)
    tf = corpus.term_frequencies |> Map.get(doc_id, %{}) |> Map.get(folded, 0)

    if tf == 0 do
      0.0
    else
      tf * smooth_idf(corpus, folded)
    end
  end

  @doc """
  Returns the BM25 score for the entire query against document `doc_id`.

  ### Arguments

  * `corpus` is a `Text.IR.Corpus`.

  * `doc_id` is the zero-based document index.

  * `query` is either a string (which is tokenised through the
    corpus's tokenizer) or a list of pre-tokenised terms.

  ### Options

  * `:k1` — saturation parameter, defaults to `1.2`. Higher values
    make repeated occurrences of the same term in a document weigh
    more heavily.

  * `:b` — length-normalisation parameter, defaults to `0.75`.
    `0.0` disables length normalisation; `1.0` normalises fully.

  ### Returns

  * A non-negative float. `0.0` if no query term appears in the
    document.

  ### Examples

      iex> docs = ["the cat sat on the mat", "the dog sat on the log", "the cat ran"]
      iex> corpus = Text.IR.Corpus.new(docs)
      iex> Text.IR.bm25(corpus, 0, "cat sat") > Text.IR.bm25(corpus, 1, "cat sat")
      true

  """
  @spec bm25(Corpus.t(), Corpus.doc_id(), String.t() | [Corpus.term_string()], keyword()) ::
          float()
  def bm25(%Corpus{} = corpus, doc_id, query, options \\ []) do
    k1 = Keyword.get(options, :k1, @bm25_k1)
    b = Keyword.get(options, :b, @bm25_b)

    query_terms = normalise_query(corpus, query)
    doc_tf = Map.get(corpus.term_frequencies, doc_id, %{})
    doc_len = Map.get(corpus.doc_lengths, doc_id, 0)
    length_factor = 1 - b + b * doc_len / max(corpus.avg_doc_length, 1)

    Enum.reduce(query_terms, 0.0, fn term, acc ->
      tf = Map.get(doc_tf, term, 0)

      if tf == 0 do
        acc
      else
        idf = bm25_idf(corpus, term)
        numerator = tf * (k1 + 1)
        denominator = tf + k1 * length_factor
        acc + idf * numerator / denominator
      end
    end)
  end

  @doc """
  Returns the top-K documents matching `query`, ranked by score.

  ### Arguments

  * `corpus` is a `Text.IR.Corpus`.

  * `query` is a string or pre-tokenised list of terms.

  ### Options

  * `:scorer` — `:bm25` (default) or `:tfidf`.

  * `:k` — number of results to return. Defaults to `10`.

  * `:k1`, `:b` — passed through to BM25 when `scorer: :bm25`.

  ### Returns

  * A list of `{doc_id, score}` pairs in descending score order. Documents
    with score `0.0` are excluded.

  ### Examples

      iex> docs = [
      ...>   "the cat sat on the mat",
      ...>   "the dog sat on the log",
      ...>   "elephants are large"
      ...> ]
      iex> corpus = Text.IR.Corpus.new(docs)
      iex> [{best_id, _score} | _] = Text.IR.search(corpus, "cat", k: 3)
      iex> best_id
      0

  """
  @spec search(Corpus.t(), String.t() | [Corpus.term_string()], keyword()) ::
          [{Corpus.doc_id(), float()}]
  def search(%Corpus{} = corpus, query, options \\ []) do
    scorer = Keyword.get(options, :scorer, :bm25)
    k = Keyword.get(options, :k, 10)
    query_terms = normalise_query(corpus, query)

    score_fn = scorer_function(scorer, corpus, query_terms, options)

    0..(corpus.n_docs - 1)
    |> Enum.map(fn doc_id -> {doc_id, score_fn.(doc_id)} end)
    |> Enum.reject(fn {_id, score} -> score == 0.0 end)
    |> Enum.sort_by(fn {_id, score} -> -score end)
    |> Enum.take(k)
  end

  # ---- internal ---------------------------------------------------------

  defp scorer_function(:tfidf, corpus, query_terms, _options) do
    fn doc_id ->
      Enum.reduce(query_terms, 0.0, fn term, acc ->
        acc + tfidf(corpus, doc_id, term)
      end)
    end
  end

  defp scorer_function(:bm25, corpus, query_terms, options) do
    fn doc_id -> bm25(corpus, doc_id, query_terms, options) end
  end

  defp normalise_query(_corpus, terms) when is_list(terms), do: terms

  defp normalise_query(corpus, query) when is_binary(query) do
    Corpus.tokenize_query(corpus, query)
  end

  defp fold_term(%Corpus{fold_case: false}, term), do: term
  defp fold_term(%Corpus{fold_case: true}, term), do: String.downcase(term)

  # Smooth IDF, non-negative variant: log((N + 1) / (df + 1)) + 1.
  defp smooth_idf(%Corpus{} = corpus, term) do
    df = Map.get(corpus.document_frequencies, term, 0)
    :math.log((corpus.n_docs + 1) / (df + 1)) + 1
  end

  # Lucene/Elasticsearch-style BM25 IDF: log((N - df + 0.5) / (df + 0.5) + 1).
  # The "+ 1" inside the log keeps the result non-negative even when a
  # term occurs in more than half the corpus.
  defp bm25_idf(%Corpus{} = corpus, term) do
    df = Map.get(corpus.document_frequencies, term, 0)
    :math.log((corpus.n_docs - df + 0.5) / (df + 0.5) + 1)
  end
end
