defmodule Text.Phonetic.Soundex do
  @moduledoc """
  Soundex phonetic encoding (Russell-Odell, 1918).

  Encodes a word as a four-character code that groups names sharing
  rough English pronunciation under the same key. Designed for the
  English-language US census of 1880; the original use case was finding
  surnames despite spelling variations on hand-filled forms ("Smith" vs
  "Smyth", "Robert" vs "Roberts").

  The encoding is **deliberately lossy**:

  * Only the first letter is preserved verbatim.

  * `H`, `W`, and the vowels `A E I O U Y` are dropped after the first
    position.

  * The remaining consonants are mapped to one of six numeric classes
    based on phonetic similarity (`B F P V` → `1`, `C G J K Q S X Z` →
    `2`, etc.).

  * Adjacent duplicates of the same class are collapsed to one digit.

  * The result is padded or truncated to four characters: one letter
    followed by three digits.

  ### When to use

  Soundex is primarily useful for **English surname matching** — the
  domain it was designed for. It is well-known and widely implemented,
  which makes it a useful interchange format with legacy systems
  (Oracle, MySQL, and many genealogy tools all expose it).

  For modern fuzzy-name matching, consider Metaphone or Double
  Metaphone instead — both produce more discriminating codes and
  handle non-Anglo-Saxon names better. This module ships Soundex
  primarily for compatibility with those legacy systems and as a
  baseline reference.

  ### Algorithm reference

  Implementation follows the variant codified by the U.S. National
  Archives at https://www.archives.gov/research/census/soundex.html,
  which is the de-facto standard.

  """

  @digit_classes %{
    "B" => "1",
    "F" => "1",
    "P" => "1",
    "V" => "1",
    "C" => "2",
    "G" => "2",
    "J" => "2",
    "K" => "2",
    "Q" => "2",
    "S" => "2",
    "X" => "2",
    "Z" => "2",
    "D" => "3",
    "T" => "3",
    "L" => "4",
    "M" => "5",
    "N" => "5",
    "R" => "6"
  }

  @vowels MapSet.new(~w[A E I O U Y])
  @hw MapSet.new(~w[H W])

  @doc """
  Returns the Soundex code for an English word.

  ### Arguments

  * `word` is a string. Non-letter characters are ignored. The first
    letter of the result preserves the case-folded first letter of the
    input.

  ### Returns

  * A four-character string of the form `<letter><digit><digit><digit>`,
    e.g. `"R163"`. Returns `""` for an empty or letter-free input.

  ### Examples

      iex> Text.Phonetic.Soundex.encode("Robert")
      "R163"

      iex> Text.Phonetic.Soundex.encode("Rupert")
      "R163"

      iex> Text.Phonetic.Soundex.encode("Rubin")
      "R150"

      iex> Text.Phonetic.Soundex.encode("Ashcraft")
      "A261"

      iex> Text.Phonetic.Soundex.encode("Tymczak")
      "T522"

      iex> Text.Phonetic.Soundex.encode("Pfister")
      "P236"

      iex> Text.Phonetic.Soundex.encode("Smith")
      "S530"

      iex> Text.Phonetic.Soundex.encode("Smyth")
      "S530"

      iex> Text.Phonetic.Soundex.encode("")
      ""

  """
  @spec encode(String.t()) :: String.t()
  def encode(word) when is_binary(word) do
    letters = String.upcase(word) |> String.replace(~r/[^A-Z]/, "")

    case letters do
      "" -> ""
      <<first::utf8, rest::binary>> -> build_code(<<first::utf8>>, rest)
    end
  end

  defp build_code(first_letter, rest) do
    seed_class = Map.get(@digit_classes, first_letter)

    digits =
      rest
      |> String.graphemes()
      |> classify_letters()
      |> collapse_runs(seed_class)
      |> Enum.take(3)

    pad =
      case length(digits) do
        n when n < 3 -> List.duplicate("0", 3 - n)
        _ -> []
      end

    IO.iodata_to_binary([first_letter | digits ++ pad])
  end

  defp classify_letters(letters) do
    Enum.map(letters, fn letter ->
      cond do
        Map.has_key?(@digit_classes, letter) -> {:digit, Map.fetch!(@digit_classes, letter)}
        MapSet.member?(@hw, letter) -> :hw
        MapSet.member?(@vowels, letter) -> :vowel
        true -> :vowel
      end
    end)
  end

  # Walk the classified letters maintaining the most recent digit. Per
  # the 1968 NARA Soundex revision:
  #
  #   * `{:digit, d}` is emitted only if it differs from the previous
  #     digit (after the rules below).
  #   * `:hw` is invisible to adjacency: a digit before H/W and the
  #     same digit after H/W are considered adjacent and collapse.
  #   * `:vowel` separates: a digit, vowel, same digit produces only
  #     the first occurrence's digit. Wait — no. `:vowel` resets the
  #     "previous digit" to nil so subsequent same-class digits emit
  #     fresh. (See `Tymczak` → T-5-2-2 collapses to T522 because
  #     the two `2`s are separated only by `c` in pre-classify; under
  #     vowel separation they would both emit.)
  #
  # The seed class handles the "first letter shares a class with the
  # next mapped consonant" case (e.g. `Pfister` → P and f are both
  # class 1, so the f is dropped to give P236).
  defp collapse_runs(classified, seed_class) do
    seed = if seed_class, do: seed_class, else: nil

    {digits, _} =
      Enum.reduce(classified, {[], seed}, fn
        {:digit, d}, {acc, last} ->
          if d == last do
            {acc, d}
          else
            {[d | acc], d}
          end

        :hw, {acc, last} ->
          {acc, last}

        :vowel, {acc, _last} ->
          {acc, nil}
      end)

    Enum.reverse(digits)
  end
end
