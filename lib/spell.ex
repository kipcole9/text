defmodule Text.Spell do
  @moduledoc """
  Spell correction.

  Uses Peter Norvig's classic edit-distance approach: enumerate
  every word within edit distance 1 (or 2) of the query, intersect
  with a known-words dictionary, and rank by corpus frequency. The
  dictionary and frequencies come from `Text.WordFreq`, so adding
  a language for spell correction is the same as adding it to
  `Text.WordFreq`.

  This is appropriate for one-shot correction of user input. For
  high-throughput use cases, a SymSpell-style precomputed deletion
  index would be faster; that may arrive in a future release.

  ### Edit operations

  Distance-1 edits cover the four single-character mistakes that
  dominate real typing errors:

  * Deletion (`hellp` → `help`).
  * Transposition (`recieve` → `receive`).
  * Replacement (`speel` → `spell`).
  * Insertion (`spel` → `spell`).

  Distance-2 edits are the same operations applied twice. They
  produce many more candidates and are slower but catch
  double-typo cases.

  """

  alias Text.WordFreq

  @lowercase ~c"abcdefghijklmnopqrstuvwxyz"

  @doc """
  Returns the most likely correction for a word.

  ### Arguments

  * `word` is a single word as a string. Lookup is case-insensitive
    on the dictionary side; the original casing is preserved when
    no correction is needed.

  ### Options

  * `:language` is the language atom passed through to
    `Text.WordFreq`. Default `:en`.

  * `:max_edit_distance` is `1` or `2`. Default `2`.

  ### Returns

  * The best candidate string. If the input is already a known word,
    it is returned unchanged. If no candidate at any considered
    distance is in the dictionary, the original word is returned.

  ### Examples

      iex> Text.Spell.correct("speling")
      "spelling"

      iex> Text.Spell.correct("the")
      "the"

  """
  @spec correct(String.t(), keyword()) :: String.t()
  def correct(word, options \\ []) when is_binary(word) do
    case candidates(word, options) do
      [] -> word
      cands -> Enum.max_by(cands, &WordFreq.count(&1, options))
    end
  end

  @doc """
  Returns the ranked list of correction candidates for a word.

  Candidates are returned in descending order of corpus frequency.

  ### Arguments

  * `word` is a single word as a string.

  ### Options

  * `:language` is the language atom passed through to
    `Text.WordFreq`. Default `:en`.

  * `:max_edit_distance` is `1` or `2`. Default `2`.

  * `:limit` caps the number of results. Default is no limit.

  ### Returns

  * A list of candidate strings, ordered most-likely first. Empty
    when the input has no known-word candidates at any considered
    distance.

  ### Examples

      iex> "speling" |> Text.Spell.candidates(limit: 3) |> Enum.take(1)
      ["spelling"]

      iex> Text.Spell.candidates("xqzwt")
      []

  """
  @spec candidates(String.t(), keyword()) :: [String.t()]
  def candidates(word, options \\ []) when is_binary(word) do
    word_lower = String.downcase(word)
    max_edit = Keyword.get(options, :max_edit_distance, 2)
    limit = Keyword.get(options, :limit, :infinity)

    found = find_candidates(word_lower, max_edit, options)

    found
    |> Enum.sort_by(&WordFreq.count(&1, options), :desc)
    |> maybe_take(limit)
  end

  @doc """
  Returns true if the word is in the bundled dictionary.

  ### Arguments

  * `word` is a single word as a string.

  ### Options

  * `:language` is the language atom passed through to
    `Text.WordFreq`. Default `:en`.

  ### Returns

  * `true` if the word is known, `false` otherwise.

  ### Examples

      iex> Text.Spell.known?("hello")
      true

      iex> Text.Spell.known?("xqzwt")
      false

  """
  @spec known?(String.t(), keyword()) :: boolean()
  def known?(word, options \\ []) when is_binary(word) do
    WordFreq.count(word, options) > 0
  end

  @doc """
  Returns the set of all distance-1 edits of a word.

  Useful for inspection or building custom correction logic.

  ### Arguments

  * `word` is a string.

  ### Returns

  * A list of unique strings, each one edit operation away from
    the input.

  ### Examples

      iex> "spel" |> Text.Spell.edits1() |> Enum.member?("spell")
      true

  """
  @spec edits1(String.t()) :: [String.t()]
  def edits1(word) when is_binary(word) do
    splits =
      for i <- 0..String.length(word) do
        {String.slice(word, 0, i), String.slice(word, i..-1//1)}
      end

    deletes =
      for {l, r} <- splits, r != "" do
        l <> String.slice(r, 1..-1//1)
      end

    transposes =
      for {l, r} <- splits, String.length(r) > 1 do
        <<a::utf8, b::utf8, rest::binary>> = r
        l <> <<b::utf8, a::utf8>> <> rest
      end

    replaces =
      for {l, r} <- splits, r != "", c <- @lowercase do
        l <> <<c::utf8>> <> String.slice(r, 1..-1//1)
      end

    inserts =
      for {l, r} <- splits, c <- @lowercase do
        l <> <<c::utf8>> <> r
      end

    (deletes ++ transposes ++ replaces ++ inserts) |> Enum.uniq()
  end

  defp find_candidates(word, max_edit, options) do
    cond do
      known?(word, options) ->
        [word]

      max_edit >= 1 ->
        case known_set(edits1(word), options) do
          [] when max_edit >= 2 -> known_set(edits2(word), options)
          [] -> []
          found -> found
        end

      true ->
        []
    end
  end

  defp edits2(word) do
    word
    |> edits1()
    |> Enum.flat_map(&edits1/1)
    |> Enum.uniq()
  end

  defp known_set(words, options) do
    words
    |> Enum.filter(&known?(&1, options))
    |> Enum.uniq()
  end

  defp maybe_take(list, :infinity), do: list
  defp maybe_take(list, n), do: Enum.take(list, n)
end
