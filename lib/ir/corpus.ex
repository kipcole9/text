defmodule Text.IR.Corpus do
  @moduledoc """
  An indexed corpus of documents for information-retrieval scoring.

  Wraps a list of documents in the precomputed statistics that TF-IDF
  and BM25 need: document frequencies, term frequencies, document
  lengths, and average document length. Build once with `new/2`, then
  query repeatedly via `Text.IR.tfidf/3`, `Text.IR.bm25/4`, or
  `Text.IR.search/3`.

  ### Tokenisation

  By default, documents are split into terms with `Text.Segment.words/1`
  and case-folded. Pass `:tokenizer` to override (any function from
  `String.t() -> [String.t()]`) and `:fold_case` to disable lowercasing.

  ### Document identifiers

  Each document is referenced by its zero-based index in the input
  list. The index is stable for the lifetime of the corpus struct.
  Original document text is retained for downstream highlighting and
  KWIC display.

  """

  alias Text.Segment

  @typedoc "A term — typically a single word."
  @type term_string :: String.t()

  @typedoc "Zero-based document index."
  @type doc_id :: non_neg_integer()

  @type t :: %__MODULE__{
          # Original (un-tokenised, un-folded) document text per id.
          documents: %{doc_id() => String.t()},
          # Per-document term frequencies: doc_id → %{term => count}.
          term_frequencies: %{doc_id() => %{term_string() => pos_integer()}},
          # Per-document length (number of terms after tokenisation).
          doc_lengths: %{doc_id() => non_neg_integer()},
          # Document frequency per term: term → number of documents
          # the term appears in at least once.
          document_frequencies: %{term_string() => pos_integer()},
          # Total number of documents.
          n_docs: non_neg_integer(),
          # Average document length across the corpus (terms per doc).
          avg_doc_length: float(),
          # Tokeniser used at index time. Held so query tokenisation
          # at search time uses the same function.
          tokenizer: (String.t() -> [String.t()]),
          # Whether terms were case-folded.
          fold_case: boolean()
        }

  defstruct documents: %{},
            term_frequencies: %{},
            doc_lengths: %{},
            document_frequencies: %{},
            n_docs: 0,
            avg_doc_length: 0.0,
            tokenizer: nil,
            fold_case: true

  @doc """
  Builds an indexed corpus from a list of documents.

  ### Arguments

  * `documents` is a list of `t:String.t/0` documents.

  ### Options

  * `:tokenizer` — a one-arg function from `t:String.t/0` to `[t:String.t/0]`.
    Defaults to `&Text.Segment.words/1`.

  * `:fold_case` — when `true` (default), terms are lowercased so the
    index is case-insensitive. Set `false` to preserve case.

  ### Returns

  * A `t:t/0` struct.

  ### Examples

      iex> docs = ["the cat sat", "the dog sat", "the dog ran"]
      iex> corpus = Text.IR.Corpus.new(docs)
      iex> corpus.n_docs
      3
      iex> corpus.avg_doc_length
      3.0
      iex> Map.get(corpus.document_frequencies, "the")
      3
      iex> Map.get(corpus.document_frequencies, "ran")
      1

  """
  @spec new([String.t()], keyword()) :: t()
  def new(documents, options \\ []) when is_list(documents) do
    tokenizer = Keyword.get(options, :tokenizer, &Segment.words/1)
    fold_case? = Keyword.get(options, :fold_case, true)

    indexed = Enum.with_index(documents)

    {tfs, lengths, total_terms} =
      Enum.reduce(indexed, {%{}, %{}, 0}, fn {doc, id}, {tfs, lens, total} ->
        terms =
          doc
          |> tokenizer.()
          |> maybe_fold_case(fold_case?)

        tf = count_terms(terms)
        n = length(terms)
        {Map.put(tfs, id, tf), Map.put(lens, id, n), total + n}
      end)

    dfs = compute_dfs(tfs)
    n_docs = length(documents)
    avg_len = if n_docs == 0, do: 0.0, else: total_terms / n_docs

    %__MODULE__{
      documents: Map.new(indexed, fn {doc, id} -> {id, doc} end),
      term_frequencies: tfs,
      doc_lengths: lengths,
      document_frequencies: dfs,
      n_docs: n_docs,
      avg_doc_length: avg_len,
      tokenizer: tokenizer,
      fold_case: fold_case?
    }
  end

  @doc """
  Returns the corpus's view of a query — tokens after the same
  pre-processing applied at index time.

  Useful when assembling a query vector for `Text.IR.bm25/4` or any
  scoring function that needs the same tokenisation as the corpus.

  ### Examples

      iex> corpus = Text.IR.Corpus.new(["one two three"])
      iex> Text.IR.Corpus.tokenize_query(corpus, "TWO three!")
      ["two", "three"]

  """
  @spec tokenize_query(t(), String.t()) :: [term_string()]
  def tokenize_query(%__MODULE__{tokenizer: tokenizer, fold_case: fold?}, query) do
    query
    |> tokenizer.()
    |> maybe_fold_case(fold?)
  end

  # ---- internal ---------------------------------------------------------

  defp maybe_fold_case(terms, false), do: terms
  defp maybe_fold_case(terms, true), do: Enum.map(terms, &String.downcase/1)

  defp count_terms(terms) do
    Enum.reduce(terms, %{}, fn term, acc ->
      Map.update(acc, term, 1, &(&1 + 1))
    end)
  end

  defp compute_dfs(term_frequencies) do
    term_frequencies
    |> Enum.reduce(%{}, fn {_id, tf}, dfs ->
      Enum.reduce(Map.keys(tf), dfs, fn term, acc ->
        Map.update(acc, term, 1, &(&1 + 1))
      end)
    end)
  end
end
