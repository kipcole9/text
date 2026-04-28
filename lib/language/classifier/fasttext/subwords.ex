defmodule Text.Language.Classifier.Fasttext.Subwords do
  @moduledoc """
  Character n-gram extraction and input-matrix indexing for fastText models.

  Mirrors the C++ `Dictionary::computeSubwords` and `Dictionary::pushHash`
  routines in `src/dictionary.cc`. Used at inference time to convert a word
  into the subset of input matrix rows whose embeddings should be averaged
  into the word's feature vector.

  ### Algorithm

  fastText prefixes the word with `<` (BOW) and suffixes it with `>` (EOW),
  then generates every byte-aligned UTF-8 substring whose length in
  characters is between `minn` and `maxn`. Single-character n-grams that
  start with `<` or end with `>` are dropped — those are the boundary
  markers themselves, which would carry no information beyond the word
  identity.

  Each n-gram's hash (see `Text.Language.Classifier.Fasttext.Hash`) is
  reduced modulo `args.bucket` and offset by `dictionary.nwords` to land in
  the second half of the input matrix where the subword embeddings live.

  ### UTF-8 handling

  fastText operates on UTF-8 byte sequences but counts *characters*, not
  bytes, when sizing n-grams. A continuation byte (`0x80..0xBF`) is never a
  valid n-gram start, and once a leading byte is consumed any continuation
  bytes that follow are pulled into the same character. The implementation
  inspects bytes directly via `(byte &&& 0xC0) == 0x80` to identify
  continuation bytes — exactly what the C++ does.

  This must match the reference bit-for-bit, otherwise non-Latin scripts
  (Chinese, Cyrillic, Devanagari, Arabic) hash to different buckets and
  inference quality collapses for those languages. The test suite includes
  golden subword-index fixtures generated from the official fastText
  Python bindings on `lid.176` for differential validation.

  ### `pushHash` semantics

  fastText's `pushHash` has three regimes keyed off `pruneidx_size`:

  * `< 0` — model was never pruned. Push `nwords + (hash % bucket)`. This
    is the regime `lid.176` runs in.

  * `== 0` — model went through pruning but produced no entries. Drop the
    n-gram entirely. Rare in practice.

  * `> 0` — model has a populated prune index. Look the hash up in
    `pruneidx`; if absent, drop the n-gram; if present, push
    `nwords + remapped_id`.

  See `Dictionary::pushHash` in `src/dictionary.cc`.

  """

  import Bitwise

  alias Text.Language.Classifier.Fasttext.{Args, Dictionary, Hash}

  @bow "<"
  @eow ">"

  @doc """
  Generates the character n-grams of a word with the BOW/EOW boundary
  markers.

  ### Arguments

  * `word` is a UTF-8 binary. The caller passes the raw word; this function
    adds the `<` and `>` markers internally.

  * `minn` is the minimum n-gram length in characters.

  * `maxn` is the maximum n-gram length in characters.

  ### Returns

  * A list of UTF-8 binaries in the order the reference implementation
    emits them. Order matters for `pushHash` to produce the same index
    sequence as the C++ implementation.

  ### Examples

      iex> Text.Language.Classifier.Fasttext.Subwords.compute_ngrams("the", 2, 4)
      ["<t", "<th", "<the", "th", "the", "the>", "he", "he>", "e>"]

      iex> Text.Language.Classifier.Fasttext.Subwords.compute_ngrams("a", 2, 3)
      ["<a", "<a>", "a>"]

  """
  @spec compute_ngrams(binary(), pos_integer(), pos_integer()) :: [binary()]
  def compute_ngrams(word, minn, maxn) when minn >= 1 and maxn >= minn do
    framed = @bow <> word <> @eow
    size = byte_size(framed)

    do_outer(framed, size, 0, minn, maxn, [])
    |> Enum.reverse()
  end

  @doc """
  Returns the input-matrix row indices contributed by a word's n-grams.

  Equivalent to repeatedly calling fastText's `pushHash` for each generated
  n-gram, given the model's `args` and `dictionary`. Indices are returned
  in the same order the reference implementation appends them to its
  feature vector.

  ### Arguments

  * `word` is the raw UTF-8 binary (without BOW/EOW markers).

  * `args` is a `Text.Language.Classifier.Fasttext.Args` struct providing
    `minn`, `maxn`, and `bucket`.

  * `dictionary` is a `Text.Language.Classifier.Fasttext.Dictionary`
    providing `nwords` and `pruneidx`.

  ### Returns

  * A list of non-negative integers, each a valid row index in the
    model's input matrix (in the n-gram region, i.e.
    `nwords <= idx < nwords + bucket`).

  ### Examples

      iex> args = %Text.Language.Classifier.Fasttext.Args{
      ...>   minn: 2, maxn: 4, bucket: 100, dim: 16, ws: 0, epoch: 0,
      ...>   min_count: 0, neg: 0, word_ngrams: 1, loss: :softmax,
      ...>   model: :sup, lr_update_rate: 0, t: 0.0
      ...> }
      iex> dict = %Text.Language.Classifier.Fasttext.Dictionary{
      ...>   nwords: 1000, nlabels: 0, size: 1000, ntokens: 0,
      ...>   pruneidx_size: -1, entries: [], word_to_index: %{}, pruneidx: %{}
      ...> }
      iex> indices = Text.Language.Classifier.Fasttext.Subwords.compute_indices("a", args, dict)
      iex> Enum.all?(indices, fn i -> i >= 1000 and i < 1100 end)
      true

  """
  @spec compute_indices(binary(), Args.t(), Dictionary.t()) :: [non_neg_integer()]
  def compute_indices(word, %Args{minn: minn, maxn: maxn, bucket: bucket}, %Dictionary{
        nwords: nwords,
        pruneidx_size: pruneidx_size,
        pruneidx: pruneidx
      }) do
    word
    |> compute_ngrams(minn, maxn)
    |> Enum.flat_map(fn ngram ->
      hash_mod_bucket = rem(Hash.hash(ngram), bucket)
      push_hash(hash_mod_bucket, nwords, pruneidx_size, pruneidx)
    end)
  end

  @doc """
  Direct port of fastText's `pushHash`. Returns either an empty list (drop)
  or a single-element list containing the input-matrix row index.

  Exposed for differential testing; production code should call
  `compute_indices/3`.

  """
  @spec push_hash(integer(), non_neg_integer(), integer(), %{integer() => integer()}) ::
          [non_neg_integer()]
  def push_hash(_id, _nwords, 0, _pruneidx), do: []
  def push_hash(id, _nwords, _pruneidx_size, _pruneidx) when id < 0, do: []

  def push_hash(id, nwords, pruneidx_size, _pruneidx) when pruneidx_size < 0 do
    [nwords + id]
  end

  def push_hash(id, nwords, _pruneidx_size_positive, pruneidx) do
    case Map.fetch(pruneidx, id) do
      {:ok, remapped} -> [nwords + remapped]
      :error -> []
    end
  end

  # ---- internal: byte-level walk mirroring the C++ double loop ------------

  defp do_outer(_word, size, i, _minn, _maxn, acc) when i >= size, do: acc

  defp do_outer(word, size, i, minn, maxn, acc) do
    if continuation?(:binary.at(word, i)) do
      do_outer(word, size, i + 1, minn, maxn, acc)
    else
      acc = do_inner(word, size, i, i, 1, minn, maxn, acc)
      do_outer(word, size, i + 1, minn, maxn, acc)
    end
  end

  # The inner loop builds n-grams of n=1..maxn characters starting at i.
  # `j` is the byte position one past the most recently consumed character.
  defp do_inner(_word, _size, _i, _j, n, _minn, maxn, acc) when n > maxn, do: acc

  defp do_inner(_word, size, _i, j, _n, _minn, _maxn, acc) when j >= size, do: acc

  defp do_inner(word, size, i, j, n, minn, maxn, acc) do
    j_after_lead = j + 1
    j_after_char = advance_continuations(word, size, j_after_lead)

    acc =
      if n >= minn and not (n == 1 and (i == 0 or j_after_char == size)) do
        ngram = :binary.part(word, i, j_after_char - i)
        [ngram | acc]
      else
        acc
      end

    do_inner(word, size, i, j_after_char, n + 1, minn, maxn, acc)
  end

  defp advance_continuations(word, size, j) do
    if j < size and continuation?(:binary.at(word, j)) do
      advance_continuations(word, size, j + 1)
    else
      j
    end
  end

  @compile {:inline, continuation?: 1}
  defp continuation?(byte), do: band(byte, 0xC0) == 0x80
end
