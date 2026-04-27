defmodule Text.Distance do
  @moduledoc """
  String edit-distance algorithms.

  ### Why this module exists

  Elixir's standard library includes `String.jaro_distance/2` and
  `String.bag_distance/2`, but both functions return values in
  `[0.0, 1.0]` where `1.0` means "identical" and `0.0` means "completely
  different". That is a *similarity* measure named "distance", which is
  inconsistent with how virtually every other ecosystem (Python's
  `Levenshtein` package, Rust's `strsim`, JavaScript's `string-similarity`
  …) defines distance.

  This module provides the conventional definitions instead — `0` (or
  `0.0`) means identical, larger values mean more different — and adds
  the algorithms the standard library does not ship: Levenshtein,
  Damerau-Levenshtein, Hamming, and Jaro-Winkler. Callers wanting the
  similarity form of any of these should use `Text.Similarity` (which
  returns `1.0 - distance` for the bounded forms).

  ### Granularity

  All algorithms operate at the *grapheme* level, matching the
  convention used by `String.jaro_distance/2`. A grapheme is one
  user-perceived character — `"é"` (U+00E9) and `"é"` (U+0065 + U+0301)
  are both a single grapheme, even though their byte representations
  differ. For ASCII-only inputs the grapheme-level analysis is
  equivalent to byte-level operation.

  ### Algorithms

  | Function | Returns | Range | Definition |
  |---|---|---|---|
  | `levenshtein/2` | non-negative integer | `0..max(len(a), len(b))` | minimum number of insertions, deletions, and substitutions |
  | `damerau_levenshtein/2` | non-negative integer | `0..max(len(a), len(b))` | Levenshtein plus adjacent transposition (optimal-string-alignment variant) |
  | `hamming/2` | non-negative integer | `0..len` (raises if lengths differ) | substitutions only |
  | `jaro/2` | float | `0.0..1.0` | `1.0 - String.jaro_distance/2` |
  | `jaro_winkler/2` | float | `0.0..1.0` | Jaro with a prefix bonus, then `1.0 - similarity` |

  """

  @doc """
  Returns the Levenshtein distance between `a` and `b`.

  The Levenshtein distance is the minimum number of single-grapheme
  insertions, deletions, or substitutions needed to transform `a` into
  `b`.

  ### Arguments

  * `a` is a UTF-8 string.

  * `b` is a UTF-8 string.

  ### Returns

  * A non-negative integer.

  ### Examples

      iex> Text.Distance.levenshtein("kitten", "sitting")
      3

      iex> Text.Distance.levenshtein("Saturday", "Sunday")
      3

      iex> Text.Distance.levenshtein("", "abc")
      3

      iex> Text.Distance.levenshtein("naïve", "naive")
      1

  """
  @spec levenshtein(String.t(), String.t()) :: non_neg_integer()
  def levenshtein(a, b) when is_binary(a) and is_binary(b) do
    a_graphemes = String.graphemes(a)
    b_graphemes = String.graphemes(b)
    do_levenshtein(a_graphemes, b_graphemes)
  end

  defp do_levenshtein([], b), do: length(b)
  defp do_levenshtein(a, []), do: length(a)

  defp do_levenshtein(a, b) do
    initial_row = Enum.to_list(0..length(b))

    a
    |> Enum.with_index(1)
    |> Enum.reduce(initial_row, fn {a_char, i}, prev_row ->
      build_levenshtein_row(b, a_char, i, prev_row)
    end)
    |> List.last()
  end

  defp build_levenshtein_row(b, a_char, row_index, [first_prev | rest_prev]) do
    do_build_levenshtein_row(b, a_char, [row_index], first_prev, rest_prev)
  end

  defp do_build_levenshtein_row([], _a_char, acc, _prev_diag, _rest_prev) do
    Enum.reverse(acc)
  end

  defp do_build_levenshtein_row(
         [b_char | b_rest],
         a_char,
         [last_curr | _] = acc,
         prev_diag,
         [next_prev | next_rest]
       ) do
    cost = if a_char == b_char, do: 0, else: 1

    curr =
      next_prev + 1
      |> min(last_curr + 1)
      |> min(prev_diag + cost)

    do_build_levenshtein_row(b_rest, a_char, [curr | acc], next_prev, next_rest)
  end

  @doc """
  Returns the Damerau-Levenshtein distance between `a` and `b`.

  This is the *optimal-string-alignment* (OSA) variant, which is what
  most libraries mean by "Damerau-Levenshtein": Levenshtein with the
  added operation of transposing two adjacent graphemes, with the
  restriction that no substring is edited more than once. The full
  Damerau-Levenshtein distance (without the no-repeat-edit
  restriction) is rarely used in practice and not provided here.

  ### Arguments

  * `a` is a UTF-8 string.

  * `b` is a UTF-8 string.

  ### Returns

  * A non-negative integer.

  ### Examples

      iex> Text.Distance.damerau_levenshtein("ca", "ac")
      1

      iex> Text.Distance.damerau_levenshtein("kitten", "sitting")
      3

      iex> Text.Distance.damerau_levenshtein("abcdef", "bacdfe")
      2

      iex> Text.Distance.damerau_levenshtein("", "abc")
      3

  """
  @spec damerau_levenshtein(String.t(), String.t()) :: non_neg_integer()
  def damerau_levenshtein(a, b) when is_binary(a) and is_binary(b) do
    a_arr = a |> String.graphemes() |> List.to_tuple()
    b_arr = b |> String.graphemes() |> List.to_tuple()

    do_damerau_levenshtein(a_arr, b_arr)
  end

  defp do_damerau_levenshtein(a_arr, b_arr) do
    m = tuple_size(a_arr)
    n = tuple_size(b_arr)

    cond do
      m == 0 -> n
      n == 0 -> m
      true -> compute_damerau(a_arr, b_arr, m, n)
    end
  end

  defp compute_damerau(a_arr, b_arr, m, n) do
    initial =
      Enum.reduce(0..m, %{}, fn i, acc -> Map.put(acc, {i, 0}, i) end)
      |> then(fn acc ->
        Enum.reduce(0..n, acc, fn j, acc -> Map.put(acc, {0, j}, j) end)
      end)

    final =
      Enum.reduce(1..m, initial, fn i, d_acc ->
        Enum.reduce(1..n, d_acc, fn j, d ->
          fill_damerau_cell(d, a_arr, b_arr, i, j)
        end)
      end)

    Map.fetch!(final, {m, n})
  end

  defp fill_damerau_cell(d, a_arr, b_arr, i, j) do
    a_i = elem(a_arr, i - 1)
    b_j = elem(b_arr, j - 1)
    cost = if a_i == b_j, do: 0, else: 1

    base =
      Map.fetch!(d, {i - 1, j}) + 1
      |> min(Map.fetch!(d, {i, j - 1}) + 1)
      |> min(Map.fetch!(d, {i - 1, j - 1}) + cost)

    value =
      if i > 1 and j > 1 and elem(a_arr, i - 1) == elem(b_arr, j - 2) and
           elem(a_arr, i - 2) == elem(b_arr, j - 1) do
        min(base, Map.fetch!(d, {i - 2, j - 2}) + 1)
      else
        base
      end

    Map.put(d, {i, j}, value)
  end

  @doc """
  Returns the Hamming distance between two equal-length strings.

  The Hamming distance is the number of grapheme positions at which the
  two strings differ. It is undefined for strings of different length;
  passing such strings raises `ArgumentError`.

  ### Arguments

  * `a` is a UTF-8 string.

  * `b` is a UTF-8 string of the same grapheme length as `a`.

  ### Returns

  * A non-negative integer.

  ### Examples

      iex> Text.Distance.hamming("karolin", "kathrin")
      3

      iex> Text.Distance.hamming("karolin", "kerstin")
      3

      iex> Text.Distance.hamming("1011101", "1001001")
      2

      iex> Text.Distance.hamming("", "")
      0

  """
  @spec hamming(String.t(), String.t()) :: non_neg_integer()
  def hamming(a, b) when is_binary(a) and is_binary(b) do
    a_graphemes = String.graphemes(a)
    b_graphemes = String.graphemes(b)

    if length(a_graphemes) != length(b_graphemes) do
      raise ArgumentError,
            "Hamming distance is undefined for strings of different grapheme " <>
              "length (#{length(a_graphemes)} vs #{length(b_graphemes)})"
    end

    a_graphemes
    |> Enum.zip(b_graphemes)
    |> Enum.count(fn {x, y} -> x != y end)
  end

  @doc """
  Returns the Jaro distance between `a` and `b`.

  Jaro distance is a normalised metric in `[0.0, 1.0]` where `0.0`
  means the strings are identical and `1.0` means they have nothing in
  common. It is computed as `1.0 - String.jaro_distance(a, b)` — the
  standard library's "jaro_distance" function actually returns a
  similarity, despite the name.

  ### Arguments

  * `a` is a UTF-8 string.

  * `b` is a UTF-8 string.

  ### Returns

  * A float in `[0.0, 1.0]`.

  ### Examples

      iex> Text.Distance.jaro("MARTHA", "MARTHA")
      0.0

      iex> Text.Distance.jaro("MARTHA", "MARHTA") |> Float.round(4)
      0.0556

      iex> Text.Distance.jaro("DIXON", "DICKSONX") |> Float.round(4)
      0.2333

      iex> Text.Distance.jaro("", "")
      0.0

  """
  @spec jaro(String.t(), String.t()) :: float()
  def jaro(a, b) when is_binary(a) and is_binary(b) do
    1.0 - String.jaro_distance(a, b)
  end

  @doc """
  Returns the Jaro-Winkler distance between `a` and `b`.

  Jaro-Winkler is the Jaro similarity boosted by a per-grapheme bonus
  for shared prefixes (up to four graphemes), then expressed as a
  distance: `1.0 - similarity`. Two strings sharing a long prefix end
  up much closer than under plain Jaro.

  ### Arguments

  * `a` is a UTF-8 string.

  * `b` is a UTF-8 string.

  ### Options

  * `:prefix_scale` — the per-grapheme prefix bonus, traditionally
    `0.1` (the maximum value before Jaro-Winkler can exceed 1.0).
    Defaults to `0.1`.

  * `:max_prefix_length` — the prefix length is capped at this many
    graphemes. Defaults to `4`.

  ### Returns

  * A float in `[0.0, 1.0]`.

  ### Examples

      iex> Text.Distance.jaro_winkler("MARTHA", "MARHTA") |> Float.round(4)
      0.0389

      iex> Text.Distance.jaro_winkler("DIXON", "DICKSONX") |> Float.round(4)
      0.1867

      iex> Text.Distance.jaro_winkler("MARTHA", "MARTHA")
      0.0

  """
  @spec jaro_winkler(String.t(), String.t(), keyword()) :: float()
  def jaro_winkler(a, b, options \\ []) when is_binary(a) and is_binary(b) do
    prefix_scale = Keyword.get(options, :prefix_scale, 0.1)
    max_prefix = Keyword.get(options, :max_prefix_length, 4)

    similarity = String.jaro_distance(a, b)
    prefix = common_prefix_length(a, b, max_prefix)
    1.0 - (similarity + prefix * prefix_scale * (1.0 - similarity))
  end

  defp common_prefix_length(a, b, max) do
    a_prefix = a |> String.graphemes() |> Enum.take(max)
    b_prefix = b |> String.graphemes() |> Enum.take(max)

    a_prefix
    |> Enum.zip(b_prefix)
    |> Enum.take_while(fn {x, y} -> x == y end)
    |> length()
  end
end
