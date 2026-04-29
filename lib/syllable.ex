defmodule Text.Syllable do
  @moduledoc """
  Syllable counting for English words.

  Uses a vowel-group heuristic with a small table of known
  exceptions. This is the same family of algorithm used by Python's
  `textstat` and is accurate enough (~90%) for the readability
  metrics in `Text.Readability`. For exact hyphenation points or
  precise syllable boundaries, prefer `Text.Hyphenation`, which uses
  Liang's algorithm with TeX hyphenation patterns.

  Only English (`:en`) is supported at the moment. Other languages
  will raise `ArgumentError`. Multilingual support will arrive when
  `Text.Hyphenation` lands and this module can defer to its
  pattern-based syllable boundaries.

  """

  @vowels ~c"aeiouy"

  @exceptions %{
    "the" => 1,
    "a" => 1,
    "i" => 1,
    "you" => 1,
    "we" => 1,
    "he" => 1,
    "she" => 1,
    "are" => 1,
    "were" => 1,
    "have" => 1,
    "had" => 1,
    "has" => 1,
    "give" => 1,
    "gave" => 1,
    "love" => 1,
    "live" => 1,
    "lived" => 1,
    "lives" => 1,
    "moved" => 1,
    "moves" => 1,
    "people" => 2,
    "every" => 2,
    "everyone" => 3,
    "everything" => 3,
    "everywhere" => 3,
    "everybody" => 4,
    "business" => 2,
    "interesting" => 3,
    "different" => 3,
    "vegetable" => 3,
    "comfortable" => 3,
    "family" => 3,
    "literally" => 4,
    "actually" => 4,
    "usually" => 4,
    "queue" => 1,
    "queued" => 1,
    "queueing" => 2,
    "area" => 3,
    "real" => 1,
    "really" => 2,
    "create" => 2,
    "created" => 3,
    "creating" => 3,
    "ocean" => 2,
    "idea" => 3,
    "ideas" => 3,
    "being" => 2,
    "doing" => 2,
    "going" => 2,
    "seeing" => 2
  }

  @doc """
  Returns the number of syllables in an English word.

  ### Arguments

  * `word` is an English word as a string. Leading and trailing
    non-letter characters are stripped before counting.

  ### Options

  * `:language` is the language of the word. The default is `:en`.
    Only `:en` is supported; other values raise `ArgumentError`.

  ### Returns

  * A non-negative integer count of syllables. Returns `0` for an
    empty string or a token containing no letters.

  ### Examples

      iex> Text.Syllable.count("syllable")
      3

      iex> Text.Syllable.count("hello")
      2

      iex> Text.Syllable.count("queue")
      1

      iex> Text.Syllable.count("rhythm")
      1

      iex> Text.Syllable.count("")
      0

  """
  @spec count(String.t(), keyword()) :: non_neg_integer()
  def count(word, options \\ []) when is_binary(word) do
    case Keyword.get(options, :language, :en) do
      :en ->
        count_en(word)

      other ->
        raise ArgumentError, "Unsupported language #{inspect(other)}. Only :en is supported."
    end
  end

  @doc """
  Returns the total syllable count for a sentence or longer text.

  Splits on whitespace and sums the syllable count of each token.

  ### Arguments

  * `text` is a string containing zero or more words.

  ### Options

  * `:language` is the language of the text. The default is `:en`.

  ### Returns

  * A non-negative integer total syllable count across all tokens.

  ### Examples

      iex> Text.Syllable.count_text("the quick brown fox")
      4

      iex> Text.Syllable.count_text("")
      0

  """
  @spec count_text(String.t(), keyword()) :: non_neg_integer()
  def count_text(text, options \\ []) when is_binary(text) do
    text
    |> String.split()
    |> Enum.reduce(0, fn token, acc -> acc + count(token, options) end)
  end

  defp count_en(word) do
    cleaned = clean(word)

    cond do
      cleaned == "" ->
        0

      Map.has_key?(@exceptions, cleaned) ->
        Map.fetch!(@exceptions, cleaned)

      true ->
        max(1, vowel_groups(cleaned))
    end
  end

  defp clean(word) do
    word
    |> String.downcase()
    |> String.to_charlist()
    |> Enum.filter(&letter?/1)
    |> List.to_string()
  end

  defp letter?(c) when c >= ?a and c <= ?z, do: true
  defp letter?(_), do: false

  defp vowel_groups(word) do
    chars = String.to_charlist(word)
    base = count_groups(chars, false, 0)
    base + adjustments(chars)
  end

  defp count_groups([], _prev_vowel?, count), do: count

  defp count_groups([c | rest], prev_vowel?, count) do
    is_vowel = c in @vowels

    cond do
      is_vowel and not prev_vowel? -> count_groups(rest, true, count + 1)
      is_vowel -> count_groups(rest, true, count)
      true -> count_groups(rest, false, count)
    end
  end

  # Adjustments after the basic vowel-group count.
  defp adjustments(chars) do
    silent_e_adjustment(chars) + le_ending_adjustment(chars)
  end

  # Trailing 'e' is normally silent in English. The '-le after consonant'
  # case still subtracts here; le_ending_adjustment adds back the syllabic
  # 'l'. Net effect: -le words like "table" stay at 2 syllables.
  defp silent_e_adjustment(chars) do
    case List.last(chars) do
      ?e -> -1
      _ -> 0
    end
  end

  # Add a syllable for words ending in '-le' where the 'l' is preceded by
  # a consonant: "table" → 2, "candle" → 2, but "scale" → 1.
  defp le_ending_adjustment(chars) do
    if le_ending?(Enum.reverse(chars)), do: 1, else: 0
  end

  defp le_ending?([?e, ?l, c | _]) when c not in @vowels, do: true
  defp le_ending?(_), do: false
end
