defmodule Text.Similarity do
  @moduledoc """
  Set- and vector-based string similarity coefficients.

  Where `Text.Distance` answers "how many edits separate these strings",
  this module answers "how much do these strings have in common". The
  two views complement each other — edit distance is sensitive to local
  insertions and transpositions, while set-based similarity is robust
  against word reorderings and is what most search-and-deduplication
  pipelines reach for first.

  ### Inputs

  Every function in this module accepts either:

  * **two strings** — they are converted to a bag of grapheme n-grams
    using the `:n` option (default `2`, i.e. character bigrams), or

  * **two pre-computed token bags** — any enumerable of comparable terms
    (typically strings, atoms, or n-gram lists from `Text.Ngram.ngram/2`).

  String inputs that are shorter than `n` graphemes produce empty bags;
  see "Edge cases" below for how empty bags are handled.

  ### Edge cases

  * Two empty bags are vacuously similar (`1.0`).

  * One empty and one non-empty is `0.0`.

  * For very short strings, prefer a smaller `:n` or use
    `Text.Distance` instead — n-gram similarity loses meaning below
    the n-gram length.

  ### Algorithms

  | Function | Formula | Range | Notes |
  |---|---|---|---|
  | `jaccard/3` | `\|A ∩ B\| / \|A ∪ B\|` | `0.0..1.0` | Set-level; ignores duplicates |
  | `dice/3` | `2\|A ∩ B\| / (\|A\| + \|B\|)` | `0.0..1.0` | A.k.a. Sørensen-Dice |
  | `overlap/3` | `\|A ∩ B\| / min(\|A\|, \|B\|)` | `0.0..1.0` | Szymkiewicz-Simpson; favours containment |
  | `cosine/3` | `dot(a, b) / (‖a‖ · ‖b‖)` | `0.0..1.0` | Multi-set / TF; weighted by repetition |
  | `jaro/2` | `1.0 - Text.Distance.jaro/2` | `0.0..1.0` | Same as `String.jaro_distance/2` |
  | `jaro_winkler/3` | `1.0 - Text.Distance.jaro_winkler/3` | `0.0..1.0` | Jaro with prefix bonus |

  """

  @default_n 2

  @typedoc """
  A bag of tokens — anything `Enum` can iterate. Strings get converted
  to grapheme n-grams; lists, MapSets, etc. are used as-is.
  """
  @type bag :: String.t() | Enumerable.t()

  @doc """
  Returns the Jaccard similarity coefficient.

  Computed as `|A ∩ B| / |A ∪ B|` over the *sets* (deduplicated bags) of
  tokens. Returns `1.0` for identical sets, `0.0` for disjoint sets,
  and `1.0` for two empty sets.

  ### Arguments

  * `a` is a string or token enumerable.

  * `b` is a string or token enumerable.

  ### Options

  * `:n` — the n-gram size used when `a` or `b` is a string. Defaults
    to `#{@default_n}`. Ignored when both inputs are pre-tokenized.

  ### Returns

  * A float in `[0.0, 1.0]`.

  ### Examples

      iex> Text.Similarity.jaccard("night", "nacht")
      0.14285714285714285

      iex> Text.Similarity.jaccard("night", "nacht", n: 1)
      0.42857142857142855

      iex> Text.Similarity.jaccard("night", "night")
      1.0

      iex> Text.Similarity.jaccard("abc", "xyz")
      0.0

      iex> Text.Similarity.jaccard("", "")
      1.0

      iex> Text.Similarity.jaccard(~w[red green blue], ~w[blue yellow])
      0.25

  """
  @spec jaccard(bag(), bag(), keyword()) :: float()
  def jaccard(a, b, options \\ []) do
    {a_set, b_set} = to_sets(a, b, options)
    intersect = MapSet.intersection(a_set, b_set) |> MapSet.size()
    union = MapSet.union(a_set, b_set) |> MapSet.size()

    if union == 0 do
      1.0
    else
      intersect / union
    end
  end

  @doc """
  Returns the Sørensen-Dice coefficient.

  Computed as `2|A ∩ B| / (|A| + |B|)` over the *sets* (deduplicated
  bags) of tokens. Dice gives a higher score than Jaccard for the same
  inputs and is often preferred for short strings. Returns `1.0` for
  identical sets and `0.0` for disjoint sets.

  ### Arguments

  * `a` is a string or token enumerable.

  * `b` is a string or token enumerable.

  ### Options

  * `:n` — n-gram size when inputs are strings. Defaults to `#{@default_n}`.

  ### Returns

  * A float in `[0.0, 1.0]`.

  ### Examples

      iex> Text.Similarity.dice("night", "nacht")
      0.25

      iex> Text.Similarity.dice("night", "night")
      1.0

      iex> Text.Similarity.dice("abc", "xyz")
      0.0

      iex> Text.Similarity.dice("", "")
      1.0

  """
  @spec dice(bag(), bag(), keyword()) :: float()
  def dice(a, b, options \\ []) do
    {a_set, b_set} = to_sets(a, b, options)
    a_size = MapSet.size(a_set)
    b_size = MapSet.size(b_set)
    intersect = MapSet.intersection(a_set, b_set) |> MapSet.size()

    if a_size + b_size == 0 do
      1.0
    else
      2 * intersect / (a_size + b_size)
    end
  end

  @doc """
  Returns the overlap coefficient (Szymkiewicz-Simpson similarity).

  Computed as `|A ∩ B| / min(|A|, |B|)`. Unlike Jaccard or Dice, the
  overlap coefficient reaches `1.0` whenever one set is fully contained
  in the other — making it the right choice when the question is
  "is one of these a subset of the other?" rather than "are these the
  same size and content?".

  ### Arguments

  * `a` is a string or token enumerable.

  * `b` is a string or token enumerable.

  ### Options

  * `:n` — n-gram size when inputs are strings. Defaults to `#{@default_n}`.

  ### Returns

  * A float in `[0.0, 1.0]`.

  ### Examples

      iex> Text.Similarity.overlap("night", "nights")
      1.0

      iex> Text.Similarity.overlap("night", "nacht")
      0.25

      iex> Text.Similarity.overlap("abc", "xyz")
      0.0

      iex> Text.Similarity.overlap("", "")
      1.0

  """
  @spec overlap(bag(), bag(), keyword()) :: float()
  def overlap(a, b, options \\ []) do
    {a_set, b_set} = to_sets(a, b, options)
    a_size = MapSet.size(a_set)
    b_size = MapSet.size(b_set)
    intersect = MapSet.intersection(a_set, b_set) |> MapSet.size()
    smaller = min(a_size, b_size)

    cond do
      a_size == 0 and b_size == 0 -> 1.0
      smaller == 0 -> 0.0
      true -> intersect / smaller
    end
  end

  @doc """
  Returns the cosine similarity over term-frequency vectors.

  Unlike `jaccard/3`, `dice/3`, and `overlap/3`, cosine treats each
  input as a *multiset* and weights similarity by how often each token
  appears. For strings of n-grams this is rarely interesting — most
  short strings have unique n-grams — but for word-level inputs (where
  the same word repeats) cosine is the standard choice.

  Computed as `dot(a, b) / (‖a‖ · ‖b‖)`, where the vectors are indexed
  by the union of terms. Returns `1.0` for proportional vectors and
  `0.0` when there are no shared terms.

  ### Arguments

  * `a` is a string or token enumerable.

  * `b` is a string or token enumerable.

  ### Options

  * `:n` — n-gram size when inputs are strings. Defaults to `#{@default_n}`.

  ### Returns

  * A float in `[0.0, 1.0]`.

  ### Examples

      iex> Text.Similarity.cosine("night", "night")
      1.0

      iex> Text.Similarity.cosine("abc", "xyz")
      0.0

      iex> Text.Similarity.cosine("", "")
      1.0

      iex> Text.Similarity.cosine(~w[the cat sat on the mat], ~w[the dog sat on the log])
      0.7499999999999999

  """
  @spec cosine(bag(), bag(), keyword()) :: float()
  def cosine(a, b, options \\ []) do
    {a_freq, b_freq} = to_freqs(a, b, options)

    case {map_size(a_freq), map_size(b_freq)} do
      {0, 0} ->
        1.0

      {0, _} ->
        0.0

      {_, 0} ->
        0.0

      _ ->
        dot =
          a_freq
          |> Enum.reduce(0, fn {term, count_a}, acc ->
            acc + count_a * Map.get(b_freq, term, 0)
          end)

        norm_a = a_freq |> Map.values() |> sum_squares() |> :math.sqrt()
        norm_b = b_freq |> Map.values() |> sum_squares() |> :math.sqrt()

        dot / (norm_a * norm_b)
    end
  end

  defp sum_squares(values) do
    Enum.reduce(values, 0, fn v, acc -> acc + v * v end)
  end

  defp to_freqs(a, b, options) do
    n = Keyword.get(options, :n, @default_n)
    {to_freq(a, n), to_freq(b, n)}
  end

  defp to_freq(string, n) when is_binary(string) do
    string
    |> string_to_ngrams(n)
    |> count_terms()
  end

  defp to_freq(other, _n) do
    count_terms(other)
  end

  defp count_terms(enumerable) do
    Enum.reduce(enumerable, %{}, fn term, acc ->
      Map.update(acc, term, 1, &(&1 + 1))
    end)
  end

  @doc """
  Returns the Jaro similarity between two strings.

  This is the complement of `Text.Distance.jaro/2` and is also
  available as `String.jaro_distance/2` in the standard library — it
  is provided here so callers can keep the rest of the similarity
  surface in one module.

  ### Arguments

  * `a` is a UTF-8 string.

  * `b` is a UTF-8 string.

  ### Returns

  * A float in `[0.0, 1.0]` where `1.0` means identical and `0.0`
    means completely different.

  ### Examples

      iex> Text.Similarity.jaro("MARTHA", "MARTHA")
      1.0

      iex> Text.Similarity.jaro("MARTHA", "MARHTA") |> Float.round(4)
      0.9444

  """
  @spec jaro(String.t(), String.t()) :: float()
  def jaro(a, b) when is_binary(a) and is_binary(b) do
    String.jaro_distance(a, b)
  end

  @doc """
  Returns the Jaro-Winkler similarity between two strings.

  Complement of `Text.Distance.jaro_winkler/3`. Accepts the same
  options.

  ### Arguments

  * `a` is a UTF-8 string.

  * `b` is a UTF-8 string.

  ### Options

  * `:prefix_scale` — defaults to `0.1`.

  * `:max_prefix_length` — defaults to `4`.

  ### Returns

  * A float in `[0.0, 1.0]`.

  ### Examples

      iex> Text.Similarity.jaro_winkler("MARTHA", "MARHTA") |> Float.round(4)
      0.9611

      iex> Text.Similarity.jaro_winkler("MARTHA", "MARTHA")
      1.0

  """
  @spec jaro_winkler(String.t(), String.t(), keyword()) :: float()
  def jaro_winkler(a, b, options \\ []) when is_binary(a) and is_binary(b) do
    1.0 - Text.Distance.jaro_winkler(a, b, options)
  end

  # ---- internal helpers --------------------------------------------------

  defp to_sets(a, b, options) do
    n = Keyword.get(options, :n, @default_n)
    {MapSet.new(to_bag(a, n)), MapSet.new(to_bag(b, n))}
  end

  defp to_bag(string, n) when is_binary(string) do
    string_to_ngrams(string, n)
  end

  defp to_bag(other, _n) do
    other
  end

  defp string_to_ngrams(string, n) when n >= 1 do
    string
    |> String.graphemes()
    |> Enum.chunk_every(n, 1, :discard)
  end
end
