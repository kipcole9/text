defmodule Text.Phonetic.NYSIIS do
  @moduledoc """
  New York State Identification and Intelligence System (NYSIIS)
  phonetic encoding (Robert L. Taft, 1970).

  NYSIIS was designed as a Soundex successor for English personal-name
  matching. Compared to Soundex it:

  * keeps **letters** rather than digits, so the codes are pronounceable;
  * is more discriminating in practice (`Roberts` and `Doberts` get
    different codes);
  * handles common English-name patterns natively (`MAC` → `MCC`,
    `KN` → `NN`, `PH`/`PF` → `FF`, `SCH` → `SSS`, etc.).

  This module implements Taft's original algorithm, optionally with the
  6-character truncation that the 1970 specification mandated. Pass
  `max_length: nil` (the default) to skip truncation; pass `6` for the
  classical fixed-length code.

  ## When to use

  NYSIIS is a strong default for fuzzy English name matching when you
  want the matching key to remain readable. For maximum discrimination
  on multi-cultural names, prefer `Text.Phonetic.DoubleMetaphone`.

  ## References

  Taft, R. L. (1970). *Name Search Techniques*. New York State
  Identification and Intelligence System.

  https://www.archives.gov/research/census/soundex/ describes the
  Soundex / NYSIIS lineage.
  """

  alias Text.Clean

  @vowels MapSet.new(~c"AEIOU")

  @doc """
  Returns the NYSIIS code for `name`.

  ### Arguments

  * `name` is a string. Non-Latin letters and diacritics are folded
    to ASCII via `Text.Clean.unaccent/1` before encoding.

  ### Options

  * `:max_length` — truncate the resulting code to this length.
    Pass `6` for the classical Taft NYSIIS. Defaults to `nil`
    (no truncation).

  ### Returns

  * The NYSIIS code as an uppercase ASCII string. Returns `""` for
    empty input or input with no Latin letters.

  ### Examples

      iex> Text.Phonetic.NYSIIS.encode("Watkins")
      "WATCAN"

      iex> Text.Phonetic.NYSIIS.encode("MacDonald")
      "MCDANALD"

      iex> Text.Phonetic.NYSIIS.encode("MacDonald", max_length: 6)
      "MCDANA"

  """
  @spec encode(String.t(), keyword()) :: String.t()
  def encode(name, options \\ []) when is_binary(name) do
    max_length = Keyword.get(options, :max_length)

    case prepare(name) do
      [] ->
        ""

      letters ->
        letters
        |> rewrite_first()
        |> rewrite_last()
        |> walk_body()
        |> postprocess()
        |> maybe_truncate(max_length)
    end
  end

  @doc """
  Returns `true` if `name_a` and `name_b` produce the same NYSIIS code.

  ### Arguments

  * `name_a` is a string.

  * `name_b` is a string.

  ### Options

  Same as `encode/2`. The same options are applied to both inputs.

  ### Returns

  * `true` when both inputs produce a non-empty NYSIIS code and the
    codes are equal.

  * `false` otherwise (including when either input is empty or
    contains no Latin letters).

  ### Examples

      iex> Text.Phonetic.NYSIIS.match?("MacDonald", "McDonald")
      true

      iex> Text.Phonetic.NYSIIS.match?("Smith", "Schmidt")
      false

  """
  @spec match?(String.t(), String.t(), keyword()) :: boolean()
  def match?(name_a, name_b, options \\ []) when is_binary(name_a) and is_binary(name_b) do
    code_a = encode(name_a, options)
    code_a != "" and code_a == encode(name_b, options)
  end

  ## ── preprocessing ─────────────────────────────────────────────────

  defp prepare(name) do
    name
    |> Clean.unaccent()
    |> String.upcase()
    |> :unicode.characters_to_list()
    |> Enum.filter(fn c -> c >= ?A and c <= ?Z end)
  end

  # Step 1: first-letter rewrites.
  defp rewrite_first([?M, ?A, ?C | rest]), do: [?M, ?C, ?C | rest]
  defp rewrite_first([?K, ?N | rest]), do: [?N, ?N | rest]
  defp rewrite_first([?K | rest]), do: [?C | rest]
  defp rewrite_first([?P, ?H | rest]), do: [?F, ?F | rest]
  defp rewrite_first([?P, ?F | rest]), do: [?F, ?F | rest]
  defp rewrite_first([?S, ?C, ?H | rest]), do: [?S, ?S, ?S | rest]
  defp rewrite_first(other), do: other

  # Step 2: last-letter rewrites.
  defp rewrite_last(letters) do
    case Enum.reverse(letters) do
      [?E, ?E | rest] ->
        Enum.reverse([?Y | rest])

      [?E, ?I | rest] ->
        Enum.reverse([?Y | rest])

      [a, b | rest] when {b, a} in [{?D, ?T}, {?R, ?T}, {?R, ?D}, {?N, ?T}, {?N, ?D}] ->
        Enum.reverse([?D | rest])

      _ ->
        letters
    end
  end

  ## ── body walk ─────────────────────────────────────────────────────

  # The first letter is preserved verbatim; subsequent letters are
  # rewritten with limited 1- and 2-char lookahead/lookback. We track
  # `prev_input` (the *input* letter that came before, for H/W rules)
  # and `prev_emit` (the most recent letter pushed to `acc`, for the
  # consecutive-duplicate suppression rule).
  defp walk_body([]), do: ""

  defp walk_body([first | rest]) do
    walk(rest, [first], first, first)
  end

  defp walk([], acc, _prev_input, _prev_emit) do
    acc |> Enum.reverse() |> List.to_string()
  end

  # EV → AF
  defp walk([?E, ?V | rest], acc, _prev_input, prev_emit) do
    {acc, prev_emit} = push_chars(~c"AF", acc, prev_emit)
    walk(rest, acc, ?V, prev_emit)
  end

  # Vowel → A
  defp walk([c | rest], acc, _prev_input, prev_emit) when c in [?A, ?E, ?I, ?O, ?U] do
    {acc, prev_emit} = push_chars(~c"A", acc, prev_emit)
    walk(rest, acc, c, prev_emit)
  end

  defp walk([?Q | rest], acc, _prev_input, prev_emit) do
    {acc, prev_emit} = push_chars(~c"G", acc, prev_emit)
    walk(rest, acc, ?Q, prev_emit)
  end

  defp walk([?Z | rest], acc, _prev_input, prev_emit) do
    {acc, prev_emit} = push_chars(~c"S", acc, prev_emit)
    walk(rest, acc, ?Z, prev_emit)
  end

  defp walk([?M | rest], acc, _prev_input, prev_emit) do
    {acc, prev_emit} = push_chars(~c"N", acc, prev_emit)
    walk(rest, acc, ?M, prev_emit)
  end

  # KN → N (consume K, then N becomes N; covered by next step)
  defp walk([?K, ?N | rest], acc, _prev_input, prev_emit) do
    {acc, prev_emit} = push_chars(~c"N", acc, prev_emit)
    walk(rest, acc, ?N, prev_emit)
  end

  defp walk([?K | rest], acc, _prev_input, prev_emit) do
    {acc, prev_emit} = push_chars(~c"C", acc, prev_emit)
    walk(rest, acc, ?K, prev_emit)
  end

  # SCH → SSS, PH → FF (multi-char body rewrites)
  defp walk([?S, ?C, ?H | rest], acc, _prev_input, prev_emit) do
    {acc, prev_emit} = push_chars(~c"SSS", acc, prev_emit)
    walk(rest, acc, ?H, prev_emit)
  end

  defp walk([?P, ?H | rest], acc, _prev_input, prev_emit) do
    {acc, prev_emit} = push_chars(~c"FF", acc, prev_emit)
    walk(rest, acc, ?H, prev_emit)
  end

  # H rule: if the previous *input* letter is not a vowel, or the next
  # input letter is not a vowel, replace H with the previous letter.
  defp walk([?H | rest], acc, prev_input, prev_emit) do
    next_input = List.first(rest)

    replacement =
      if prev_input in @vowels and next_input in @vowels do
        ?H
      else
        prev_input
      end

    {acc, prev_emit} = push_chars([replacement], acc, prev_emit)
    walk(rest, acc, ?H, prev_emit)
  end

  # W rule: if the previous *input* letter is a vowel, replace W with
  # the previous letter (typically already encoded as A).
  defp walk([?W | rest], acc, prev_input, prev_emit) do
    replacement = if prev_input in @vowels, do: prev_input, else: ?W
    {acc, prev_emit} = push_chars([replacement], acc, prev_emit)
    walk(rest, acc, ?W, prev_emit)
  end

  # Default
  defp walk([c | rest], acc, _prev_input, prev_emit) do
    {acc, prev_emit} = push_chars([c], acc, prev_emit)
    walk(rest, acc, c, prev_emit)
  end

  # Push a list of chars to the (reversed) accumulator, suppressing
  # any char equal to the most recently emitted one.
  defp push_chars([], acc, prev_emit), do: {acc, prev_emit}

  defp push_chars([c | rest], acc, prev_emit) do
    if c == prev_emit do
      push_chars(rest, acc, prev_emit)
    else
      push_chars(rest, [c | acc], c)
    end
  end

  ## ── postprocessing ────────────────────────────────────────────────

  defp postprocess(""), do: ""

  defp postprocess(key) do
    key
    |> drop_trailing(?S)
    |> rewrite_trailing_ay()
    |> drop_trailing(?A)
  end

  defp drop_trailing(key, char) do
    case String.last(key) do
      <<^char::utf8>> when byte_size(key) > 1 ->
        binary_part(key, 0, byte_size(key) - 1)

      _ ->
        key
    end
  end

  defp rewrite_trailing_ay(key) do
    if String.ends_with?(key, "AY") do
      binary_part(key, 0, byte_size(key) - 2) <> "Y"
    else
      key
    end
  end

  defp maybe_truncate(key, nil), do: key

  defp maybe_truncate(key, n) when is_integer(n) and n > 0 do
    if String.length(key) > n do
      String.slice(key, 0, n)
    else
      key
    end
  end
end
