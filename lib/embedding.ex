defmodule Text.Embedding do
  @moduledoc """
  Word embeddings — load pre-trained vectors and compute similarity,
  nearest neighbours, and analogies.

  Designed around the fastText `.vec` text format used by the
  pre-trained vectors that Facebook publishes for ~157 languages
  (Common Crawl + Wikipedia, 300-dimensional, available from
  <https://fasttext.cc/docs/en/crawl-vectors.html>). The format is
  also produced by word2vec and GloVe with `--save-format text`,
  so any of those work too.

  ### File format

  fastText `.vec` is a UTF-8 text file:

  * Line 1: two integers separated by a space — `n dim` where `n` is
    the number of vectors and `dim` is the vector dimensionality.

  * Lines 2..n+1: a token followed by `dim` space-separated floats.
    The token is everything before the first space; values may
    contain scientific notation.

  ### Memory

  A typical fastText `.vec` for a single language is several gigabytes
  (English Common Crawl: ~7 GB). Loading it eagerly with `load/2`
  materialises the entire vector table as an `Nx` tensor of shape
  `{n, dim}`. For deployment where memory is tight, prefer the
  quantised binary format used by `lid.176.ftz` (not yet supported in
  this module) or load only a relevant subset of the vocabulary via
  `:filter`.

  ### Quick tour

      {:ok, emb} = Text.Embedding.load("path/to/cc.en.300.vec")

      Text.Embedding.vector(emb, "king")
      #=> #Nx.Tensor<f32[300] [...]>

      Text.Embedding.similarity(emb, "king", "queen")
      #=> 0.84...

      Text.Embedding.nearest(emb, "king", k: 3)
      #=> [{"queen", 0.84}, {"prince", 0.79}, {"monarch", 0.77}]

      Text.Embedding.analogy(emb, "king", "man", "woman", k: 1)
      #=> [{"queen", 0.71}]

  ### Cosine similarity

  All similarity functions in this module use cosine similarity by
  default — the dot product of two L2-normalised vectors. The
  implementation pre-normalises the embedding matrix at load time
  so per-query cost is one `Nx.dot` against a `{n, dim}` matrix.

  """

  defstruct [:vocab, :index_to_token, :vectors, :norms, :dim, :n]

  @type t :: %__MODULE__{
          # Token → row index in the matrix.
          vocab: %{String.t() => non_neg_integer()},
          # Row index → token (for nearest/analogy reverse lookups).
          index_to_token: %{non_neg_integer() => String.t()},
          # Raw embedding matrix, shape {n, dim}, type {:f, 32}.
          vectors: Nx.Tensor.t(),
          # L2-normalised matrix, shape {n, dim}, type {:f, 32}.
          # Cached so cosine queries are a single dot product.
          norms: Nx.Tensor.t(),
          dim: pos_integer(),
          n: non_neg_integer()
        }

  @doc """
  Loads embeddings from a `.vec` file.

  ### Arguments

  * `path` is the path to a fastText- or word2vec-style `.vec` text
    file.

  ### Options

  * `:filter` — a list or `MapSet` of tokens to keep. When given,
    only vectors whose token is in the filter are loaded. Useful for
    cutting memory by an order of magnitude when you only need a
    domain-specific vocabulary.

  * `:max_tokens` — load at most this many tokens (regardless of
    `:filter`). Useful for testing or a quick top-N baseline.

  ### Returns

  * `{:ok, %Text.Embedding{}}` on success.

  * `{:error, reason}` if the file is missing or malformed.

  """
  @spec load(Path.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def load(path, options \\ []) do
    filter = options |> Keyword.get(:filter, nil) |> normalise_filter()
    max_tokens = Keyword.get(options, :max_tokens, :infinity)

    with {:ok, file} <- File.open(path, [:read, :utf8]) do
      try do
        header = IO.read(file, :line)

        case parse_header(header) do
          {:ok, _declared_n, dim} ->
            {tokens, vector_lists} = read_vectors(file, dim, filter, max_tokens)
            build_struct(tokens, vector_lists, dim)

          :error ->
            {:error, :malformed_header}
        end
      after
        File.close(file)
      end
    end
  end

  @doc """
  Returns the vector for `token`, or `nil` if the token is not in the
  vocabulary.

  ### Examples

      vector = Text.Embedding.vector(embeddings, "king")
      # => #Nx.Tensor<f32[300] [...]>

      Text.Embedding.vector(embeddings, "no-such-word")
      # => nil

  """
  @spec vector(t(), String.t()) :: Nx.Tensor.t() | nil
  def vector(%__MODULE__{} = embeddings, token) when is_binary(token) do
    case Map.fetch(embeddings.vocab, token) do
      {:ok, idx} -> Nx.slice_along_axis(embeddings.vectors, idx, 1, axis: 0) |> Nx.squeeze(axes: [0])
      :error -> nil
    end
  end

  @doc """
  Returns the cosine similarity between two tokens.

  ### Returns

  * A float in `[-1.0, +1.0]`.

  * `nil` if either token is missing from the vocabulary.

  ### Examples

      Text.Embedding.similarity(emb, "king", "queen")
      # => 0.84
      Text.Embedding.similarity(emb, "king", "carrot")
      # => 0.18

  """
  @spec similarity(t(), String.t(), String.t()) :: float() | nil
  def similarity(%__MODULE__{} = embeddings, a, b) when is_binary(a) and is_binary(b) do
    with {:ok, ia} <- Map.fetch(embeddings.vocab, a),
         {:ok, ib} <- Map.fetch(embeddings.vocab, b) do
      va = Nx.slice_along_axis(embeddings.norms, ia, 1, axis: 0) |> Nx.squeeze(axes: [0])
      vb = Nx.slice_along_axis(embeddings.norms, ib, 1, axis: 0) |> Nx.squeeze(axes: [0])
      Nx.dot(va, vb) |> Nx.to_number()
    else
      :error -> nil
    end
  end

  @doc """
  Returns the `:k` nearest neighbours of `token` by cosine similarity.

  The token itself is excluded from the result.

  ### Arguments

  * `token` — a string.

  ### Options

  * `:k` — number of neighbours to return. Defaults to `10`.

  ### Returns

  * A list of `{token, similarity}` pairs sorted by similarity
    descending. Returns `[]` if the token is not in the vocabulary.

  ### Examples

      Text.Embedding.nearest(emb, "king", k: 3)
      # => [{"queen", 0.84}, {"prince", 0.79}, {"monarch", 0.77}]

  """
  @spec nearest(t(), String.t(), keyword()) :: [{String.t(), float()}]
  def nearest(%__MODULE__{} = embeddings, token, options \\ []) when is_binary(token) do
    k = Keyword.get(options, :k, 10)

    case Map.fetch(embeddings.vocab, token) do
      :error ->
        []

      {:ok, idx} ->
        query =
          embeddings.norms |> Nx.slice_along_axis(idx, 1, axis: 0) |> Nx.squeeze(axes: [0])

        top_k_against(embeddings, query, k, [idx])
    end
  end

  @doc """
  Returns the top `:k` candidates for the analogy `a : b :: c : ?`.

  Computes the query vector as `b - a + c`, normalises it, and finds
  the nearest neighbours by cosine similarity. The three input tokens
  are excluded from the result, since the most-similar vector to
  `b - a + c` is almost always one of them.

  ### Arguments

  * `a`, `b`, `c` — the three tokens framing the analogy. All three
    must be in the vocabulary; if any is missing, the function
    returns `[]`.

  ### Options

  * `:k` — number of candidates to return. Defaults to `1`.

  ### Returns

  * A list of `{token, similarity}` pairs sorted by similarity
    descending.

  ### Examples

      Text.Embedding.analogy(emb, "king", "man", "woman", k: 3)
      # => [{"queen", 0.71}, {"princess", 0.62}, ...]

  """
  @spec analogy(t(), String.t(), String.t(), String.t(), keyword()) ::
          [{String.t(), float()}]
  def analogy(%__MODULE__{} = embeddings, a, b, c, options \\ []) do
    k = Keyword.get(options, :k, 1)

    with {:ok, ia} <- Map.fetch(embeddings.vocab, a),
         {:ok, ib} <- Map.fetch(embeddings.vocab, b),
         {:ok, ic} <- Map.fetch(embeddings.vocab, c) do
      va = Nx.slice_along_axis(embeddings.vectors, ia, 1, axis: 0) |> Nx.squeeze(axes: [0])
      vb = Nx.slice_along_axis(embeddings.vectors, ib, 1, axis: 0) |> Nx.squeeze(axes: [0])
      vc = Nx.slice_along_axis(embeddings.vectors, ic, 1, axis: 0) |> Nx.squeeze(axes: [0])

      query = Nx.add(Nx.subtract(vb, va), vc) |> l2_normalize()
      top_k_against(embeddings, query, k, [ia, ib, ic])
    else
      :error -> []
    end
  end

  @doc """
  Returns the size of the loaded vocabulary.
  """
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{n: n}), do: n

  # ---- internal: file parsing -------------------------------------------

  defp parse_header(line) when is_binary(line) do
    case line |> String.trim() |> String.split() do
      [n_str, dim_str] ->
        with {n, ""} <- Integer.parse(n_str),
             {dim, ""} <- Integer.parse(dim_str) do
          {:ok, n, dim}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp parse_header(_), do: :error

  defp read_vectors(file, dim, filter, max_tokens) do
    Stream.repeatedly(fn -> IO.read(file, :line) end)
    |> Stream.take_while(fn line -> line != :eof and line != "" end)
    |> Stream.flat_map(fn line ->
      case parse_vector_line(line, dim) do
        {:ok, token, vector} -> [{token, vector}]
        :error -> []
      end
    end)
    |> Stream.filter(fn {token, _vec} -> filter == nil or token in filter end)
    |> take_or_all(max_tokens)
    |> Enum.unzip()
  end

  defp take_or_all(stream, :infinity), do: stream
  defp take_or_all(stream, n) when is_integer(n) and n >= 0, do: Stream.take(stream, n)

  defp parse_vector_line(line, dim) do
    parts = line |> String.trim_trailing("\n") |> String.split(" ", parts: dim + 1)

    case parts do
      [token | values] when length(values) == dim ->
        try do
          floats = Enum.map(values, &parse_float!/1)
          {:ok, token, floats}
        rescue
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp parse_float!(str) do
    case Float.parse(str) do
      {f, ""} -> f
      _ -> raise ArgumentError, "bad float: #{str}"
    end
  end

  # ---- internal: struct construction ------------------------------------

  defp build_struct([], _vector_lists, _dim) do
    {:error, :empty}
  end

  defp build_struct(tokens, vector_lists, dim) do
    n = length(tokens)

    vectors =
      vector_lists
      |> List.flatten()
      |> Nx.tensor(type: {:f, 32})
      |> Nx.reshape({n, dim})

    norms = l2_normalize_rows(vectors)

    vocab =
      tokens
      |> Enum.with_index()
      |> Map.new()

    index_to_token =
      tokens
      |> Enum.with_index()
      |> Map.new(fn {token, idx} -> {idx, token} end)

    {:ok,
     %__MODULE__{
       vocab: vocab,
       index_to_token: index_to_token,
       vectors: vectors,
       norms: norms,
       dim: dim,
       n: n
     }}
  end

  defp normalise_filter(nil), do: nil
  defp normalise_filter(%MapSet{} = set), do: set
  defp normalise_filter(list) when is_list(list), do: MapSet.new(list)

  # ---- internal: similarity helpers -------------------------------------

  defp l2_normalize_rows(matrix) do
    norms =
      matrix
      |> Nx.pow(2)
      |> Nx.sum(axes: [1], keep_axes: true)
      |> Nx.sqrt()
      |> Nx.add(1.0e-12)

    Nx.divide(matrix, norms)
  end

  defp l2_normalize(vector) do
    norm = vector |> Nx.pow(2) |> Nx.sum() |> Nx.sqrt() |> Nx.add(1.0e-12)
    Nx.divide(vector, norm)
  end

  defp top_k_against(%__MODULE__{} = embeddings, normalised_query, k, exclude_indices) do
    sims = Nx.dot(embeddings.norms, normalised_query) |> Nx.to_list()
    exclude = MapSet.new(exclude_indices)

    sims
    |> Enum.with_index()
    |> Enum.reject(fn {_sim, idx} -> MapSet.member?(exclude, idx) end)
    |> Enum.sort_by(fn {sim, _idx} -> -sim end)
    |> Enum.take(k)
    |> Enum.map(fn {sim, idx} -> {Map.fetch!(embeddings.index_to_token, idx), sim} end)
  end
end
