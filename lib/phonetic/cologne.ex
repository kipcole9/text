defmodule Text.Phonetic.Cologne do
  @moduledoc """
  Cologne phonetics (Kölner Phonetik), the German-language counterpart
  to Soundex.

  Designed by Hans Joachim Postel in 1969 specifically for German names
  and German-language text. Encodes a word as a digit string in which
  similarly-pronounced German names share a key. Particularly good with
  German spelling variants — `Müller` / `Mueller` / `Muller`,
  `Meyer` / `Maier` / `Mayer` / `Meier` all collapse to the same code.

  ## Encoding

  Each letter maps to a digit `0`–`8`:

  | Letter         | Code |
  |----------------|------|
  | A, E, I, J, O, U, Y | 0 |
  | H              | (skipped) |
  | B              | 1 |
  | P (not before H) | 1 |
  | P before H     | 3 |
  | D, T (not before C, S, Z) | 2 |
  | D, T before C, S, Z | 8 |
  | F, V, W        | 3 |
  | G, K, Q        | 4 |
  | C — see context rules below | 4 or 8 |
  | X — see context rules below | 48 or 8 |
  | L              | 5 |
  | M, N           | 6 |
  | R              | 7 |
  | S, Z           | 8 |

  Context rules for C and X are slightly elaborate (initial vs medial
  position; preceding and following letter); see the implementation
  for the full table.

  Post-processing:

  1. Collapse runs of identical adjacent codes to a single code.
  2. Drop every `0` except the one in the first position.

  Result: a digit string of variable length.

  ## Examples

      iex> Text.Phonetic.Cologne.encode("Müller")
      "657"

      iex> Text.Phonetic.Cologne.encode("Mueller")
      "657"

      iex> Text.Phonetic.Cologne.encode("Meyer")
      "67"

      iex> Text.Phonetic.Cologne.encode("Mayer")
      "67"

      iex> Text.Phonetic.Cologne.encode("Maier")
      "67"

      iex> Text.Phonetic.Cologne.encode("Schmidt")
      "862"

      iex> Text.Phonetic.Cologne.encode("Wikipedia")
      "3412"

  ## Reference

  Postel, H. J. (1969). *Die Kölner Phonetik: Ein Verfahren zur
  Identifizierung von Personennamen auf der Grundlage der
  Gestaltanalyse*. IBM-Nachrichten 19, 925–931.
  """

  alias Text.Clean

  @vowels ~c"AEIJOUY"
  @csz ~c"CSZ"
  @initial_c_to_4 ~c"AHKLOQRUX"
  @medial_c_to_4 ~c"AHKOQUX"
  @after_for_c4 ~c"SZ"
  @ckq ~c"CKQ"

  @doc """
  Returns the Kölner-Phonetik code for `name`.

  ### Arguments

  * `name` is a string. German umlauts (`Ä Ö Ü ß`) are normalised
    before encoding, and other diacritics are folded via
    `Text.Clean.unaccent/1`.

  ### Returns

  * A digit string. The first character is always `0`–`8`. Returns
    `""` for empty input or input containing no Latin letters.

  ### Examples

      iex> Text.Phonetic.Cologne.encode("Schmitt")
      "862"

      iex> Text.Phonetic.Cologne.encode("Wikipedia")
      "3412"

  """
  @spec encode(String.t()) :: String.t()
  def encode(name) when is_binary(name) do
    case prepare(name) do
      [] -> ""
      letters -> letters |> walk() |> finalise()
    end
  end

  @doc """
  Returns `true` if `name_a` and `name_b` produce the same Kölner
  code (and both produce a non-empty code).

  ### Arguments

  * `name_a` is a string.

  * `name_b` is a string.

  ### Returns

  * `true` when both inputs produce a non-empty Kölner code and the
    codes are equal.

  * `false` otherwise.

  ### Examples

      iex> Text.Phonetic.Cologne.match?("Müller", "Mueller")
      true

      iex> Text.Phonetic.Cologne.match?("Meyer", "Maier")
      true

      iex> Text.Phonetic.Cologne.match?("Schmidt", "Schneider")
      false

  """
  @spec match?(String.t(), String.t()) :: boolean()
  def match?(name_a, name_b) when is_binary(name_a) and is_binary(name_b) do
    code_a = encode(name_a)
    code_a != "" and code_a == encode(name_b)
  end

  ## ── normalization ───────────────────────────────────────────────

  # German uppercase normalisation:
  #   * `ß` → `SS`
  #   * `Ä Ö Ü` → `A O U`
  # then strip non-letters.
  defp prepare(name) do
    name
    |> String.replace("ß", "ss")
    |> String.replace("ẞ", "SS")
    |> Clean.unaccent()
    |> String.upcase()
    |> :unicode.characters_to_list()
    |> Enum.filter(fn c -> c >= ?A and c <= ?Z end)
  end

  ## ── walk: produce the raw digit-or-skip stream ──────────────────

  defp walk(letters), do: walk(letters, nil, true, [])

  defp walk([], _prev, _initial?, acc), do: Enum.reverse(acc)

  defp walk([c | rest], prev, initial?, acc) do
    code = code_for(c, prev, List.first(rest), initial?)

    case code do
      :skip -> walk(rest, c, false, acc)
      digits -> walk(rest, c, false, prepend_digits(digits, acc))
    end
  end

  defp prepend_digits([], acc), do: acc
  defp prepend_digits([d | rest], acc), do: prepend_digits(rest, [d | acc])

  ## ── per-letter code lookup ──────────────────────────────────────

  # H is dropped entirely.
  defp code_for(?H, _prev, _next, _initial?), do: :skip

  # Vowels (incl. J, Y) → 0
  defp code_for(c, _prev, _next, _initial?) when c in @vowels, do: ~c"0"

  defp code_for(?B, _prev, _next, _initial?), do: ~c"1"

  defp code_for(?P, _prev, ?H, _initial?), do: ~c"3"
  defp code_for(?P, _prev, _next, _initial?), do: ~c"1"

  defp code_for(c, _prev, next, _initial?) when c in [?D, ?T] and next in @csz, do: ~c"8"
  defp code_for(c, _prev, _next, _initial?) when c in [?D, ?T], do: ~c"2"

  defp code_for(c, _prev, _next, _initial?) when c in [?F, ?V, ?W], do: ~c"3"
  defp code_for(c, _prev, _next, _initial?) when c in [?G, ?K, ?Q], do: ~c"4"

  # C in initial position
  defp code_for(?C, _prev, next, true) when next in @initial_c_to_4, do: ~c"4"
  defp code_for(?C, _prev, _next, true), do: ~c"8"

  # C in medial position
  defp code_for(?C, prev, _next, false) when prev in @after_for_c4, do: ~c"8"
  defp code_for(?C, prev, next, false) when next in @medial_c_to_4 and prev not in @ckq, do: ~c"4"
  defp code_for(?C, _prev, _next, false), do: ~c"8"

  # X — emits two digits when not after C, K or Q (encodes as if 'KS')
  defp code_for(?X, prev, _next, _initial?) when prev in @ckq, do: ~c"8"
  defp code_for(?X, _prev, _next, _initial?), do: ~c"48"

  defp code_for(?L, _prev, _next, _initial?), do: ~c"5"
  defp code_for(c, _prev, _next, _initial?) when c in [?M, ?N], do: ~c"6"
  defp code_for(?R, _prev, _next, _initial?), do: ~c"7"
  defp code_for(c, _prev, _next, _initial?) when c in [?S, ?Z], do: ~c"8"

  defp code_for(_other, _prev, _next, _initial?), do: :skip

  ## ── post-processing ────────────────────────────────────────────

  defp finalise([]), do: ""

  defp finalise([first | _] = codes) do
    codes
    |> collapse_runs()
    |> drop_zeros_except_leading(first)
    |> List.to_string()
  end

  # Collapse runs of identical adjacent codes.
  defp collapse_runs(codes), do: collapse_runs(codes, [])

  defp collapse_runs([], acc), do: Enum.reverse(acc)
  defp collapse_runs([c, c | rest], acc), do: collapse_runs([c | rest], acc)
  defp collapse_runs([c | rest], acc), do: collapse_runs(rest, [c | acc])

  # Drop every `?0` except the very first code (only if that first code
  # is itself a `0`).
  defp drop_zeros_except_leading([?0 | rest], ?0) do
    [?0 | Enum.reject(rest, &(&1 == ?0))]
  end

  defp drop_zeros_except_leading(codes, _first) do
    Enum.reject(codes, &(&1 == ?0))
  end
end
