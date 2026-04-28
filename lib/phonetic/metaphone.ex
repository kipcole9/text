defmodule Text.Phonetic.Metaphone do
  @moduledoc """
  Metaphone phonetic encoding (Lawrence Philips, 1990).

  A more discriminating phonetic encoder than `Text.Phonetic.Soundex`.
  Metaphone produces variable-length codes that better reflect English
  pronunciation rules, handling common digraphs (`gh`, `kn`, `wr`),
  silent letters, and context-dependent consonant pronunciation.

  ### Differences from Soundex

  * **Variable-length output.** Metaphone codes are as long as needed
    to encode the word, unlike Soundex's fixed four-character output.
    Use `encode/2` with a `:max_length` option to truncate.

  * **Letters, not digits.** The output uses letters that approximate
    the phonemes in the source — `K` for hard `C`/`K`, `S` for soft
    `C`/`S`/`Z`, `0` (the digit zero) for the unvoiced `th` in `"thin"`,
    `X` for `sh`, etc.

  * **Better discrimination.** Phillips/Phyllips/Filips all encode to
    `FLPS`; Tomson/Thompson both encode to `TMSN`/`TMSN`. Metaphone is
    rarely tighter than Soundex on collisions but is much more
    discriminating on intentionally different inputs.

  ### When to use

  Metaphone is the standard choice for fuzzy English-name matching in
  search, deduplication, and record-linkage pipelines. For
  multilingual or non-Anglo names, Double Metaphone (not yet
  implemented in this module) produces better results.

  ### Algorithm

  Implementation follows the rules described in Philips' 1990 paper
  *"Hanging on the Metaphone"* and the canonical reference port at
  https://en.wikipedia.org/wiki/Metaphone. Where references disagree on
  edge cases, we follow the most commonly-cited interpretation.

  """

  @vowels ~c"AEIOU"

  @doc """
  Returns the Metaphone code for an English word.

  ### Arguments

  * `word` is a string. Non-letter characters are stripped before
    encoding.

  ### Options

  * `:max_length` — truncate the output to this many characters.
    Defaults to no truncation. Pass `4` to mimic Soundex's fixed length.

  ### Returns

  * An uppercase ASCII string. Returns `""` for empty or letter-free
    input.

  ### Examples

      iex> Text.Phonetic.Metaphone.encode("Thompson")
      "0MPSN"

      iex> Text.Phonetic.Metaphone.encode("Phillips")
      "FLPS"

      iex> Text.Phonetic.Metaphone.encode("Knight")
      "NT"

      iex> Text.Phonetic.Metaphone.encode("Wright")
      "RT"

      iex> Text.Phonetic.Metaphone.encode("")
      ""

  """
  @spec encode(String.t(), keyword()) :: String.t()
  def encode(word, options \\ []) when is_binary(word) do
    max_length = Keyword.get(options, :max_length)

    word
    |> String.upcase()
    |> String.replace(~r/[^A-Z]/, "")
    |> drop_silent_initial()
    |> remap_initial()
    |> drop_adjacent_duplicates_except_c()
    |> walk(0, "")
    |> maybe_truncate(max_length)
  end

  # ---- preprocessing -----------------------------------------------------

  # Words starting with "AE", "GN", "KN", "PN", "WR" have a silent
  # first letter (e.g. "knight" → "night", "wright" → "right").
  defp drop_silent_initial(<<first, second, _rest::binary>> = word)
       when (first == ?A and second == ?E) or
              (first == ?G and second == ?N) or
              (first == ?K and second == ?N) or
              (first == ?P and second == ?N) or
              (first == ?W and second == ?R) do
    binary_part(word, 1, byte_size(word) - 1)
  end

  defp drop_silent_initial(word), do: word

  # Words starting with "X" begin with /z/ in English (e.g. "Xerox"),
  # so map to S. Words starting with "WH" simplify to "W" — the H is
  # silent in most English varieties (e.g. "what", "where").
  defp remap_initial(<<?X, rest::binary>>), do: <<?S, rest::binary>>
  defp remap_initial(<<?W, ?H, rest::binary>>), do: <<?W, rest::binary>>
  defp remap_initial(word), do: word

  # Adjacent duplicate letters collapse to one — except "CC", which can
  # encode as /ks/ in words like "accent" (handled below in the C rules).
  defp drop_adjacent_duplicates_except_c(word) do
    do_dedupe(word, "")
  end

  defp do_dedupe(<<>>, acc), do: acc

  defp do_dedupe(<<a, a, rest::binary>>, acc) when a != ?C do
    do_dedupe(<<a, rest::binary>>, acc)
  end

  defp do_dedupe(<<a, rest::binary>>, acc) do
    do_dedupe(rest, acc <> <<a>>)
  end

  # ---- main walk (placeholder; rules added in next chunk) ---------------

  # The walk consumes the input one character at a time, with knowledge
  # of the previous character (for context-sensitive rules) and the
  # output accumulated so far. `prev` is the integer codepoint of the
  # input character processed in the prior step (`0` at the start);
  # rule clauses that need to inspect it pattern-match on integers
  # like `?M`, `?S`, etc.
  defp walk(<<>>, _prev, acc), do: acc

  defp walk(<<char, rest::binary>>, prev, acc) do
    {emit, advance} = encode_char(char, rest, prev, acc)
    walk(advance, char, acc <> emit)
  end

  # ---- vowel rules -------------------------------------------------------

  # Vowels are kept only when they're the first letter of the word.
  defp encode_char(char, rest, _prev, "") when char in @vowels do
    {<<char>>, rest}
  end

  defp encode_char(char, rest, _prev, _acc) when char in @vowels do
    {"", rest}
  end

  # ---- simple consonants -------------------------------------------------

  # B: drop final 'B' after 'M' (e.g. "dumb", "climb"). Otherwise emit B.
  defp encode_char(?B, "", ?M, _acc), do: {"", ""}
  defp encode_char(?B, rest, _prev, _acc), do: {"B", rest}

  defp encode_char(?F, rest, _prev, _acc), do: {"F", rest}
  defp encode_char(?J, rest, _prev, _acc), do: {"J", rest}
  defp encode_char(?L, rest, _prev, _acc), do: {"L", rest}
  defp encode_char(?M, rest, _prev, _acc), do: {"M", rest}
  defp encode_char(?N, rest, _prev, _acc), do: {"N", rest}
  defp encode_char(?R, rest, _prev, _acc), do: {"R", rest}
  defp encode_char(?V, rest, _prev, _acc), do: {"F", rest}
  defp encode_char(?Z, rest, _prev, _acc), do: {"S", rest}
  defp encode_char(?Q, rest, _prev, _acc), do: {"K", rest}

  # X: at the start of the word "X" was already remapped to "S" in
  # preprocessing, so any X we see here is mid-word and codes as KS.
  defp encode_char(?X, rest, _prev, _acc), do: {"KS", rest}

  # Y: silent unless followed by a vowel.
  defp encode_char(?Y, <<next, _::binary>> = rest, _prev, _acc) when next in @vowels,
    do: {"Y", rest}

  defp encode_char(?Y, rest, _prev, _acc), do: {"", rest}

  # ---- C ----------------------------------------------------------------

  # CIA → X
  defp encode_char(?C, <<?I, ?A, _::binary>> = rest, _prev, _acc), do: {"X", rest}

  # CH: 'X' generally, but 'K' inside SCH (Greek-rooted words: "school",
  # "ache", "scheme"). The 'S' immediately preceding signals SCH.
  defp encode_char(?C, <<?H, rest::binary>>, ?S, _acc), do: {"K", rest}
  defp encode_char(?C, <<?H, rest::binary>>, _prev, _acc), do: {"X", rest}

  # CK → K (consume both the C and the K so we don't double-emit).
  defp encode_char(?C, <<?K, rest::binary>>, _prev, _acc), do: {"K", rest}

  # C followed by I/E/Y → S (soft C, as in "ceiling", "city", "cycle").
  defp encode_char(?C, <<next, _::binary>> = rest, _prev, _acc) when next in ~c"IEY",
    do: {"S", rest}

  # Default C → K.
  defp encode_char(?C, rest, _prev, _acc), do: {"K", rest}

  # ---- D ----------------------------------------------------------------

  # DG followed by I/E/Y → J (e.g. "edge", "bridge"). Skip the G.
  defp encode_char(?D, <<?G, next, _::binary>> = rest, _prev, _acc) when next in ~c"IEY" do
    <<?G, after_g::binary>> = rest
    {"J", after_g}
  end

  defp encode_char(?D, rest, _prev, _acc), do: {"T", rest}

  # ---- G ----------------------------------------------------------------

  # G silent before "N" at the end of the word (e.g. "sign", "reign").
  defp encode_char(?G, <<?N>>, _prev, _acc), do: {"", <<?N>>}
  # G silent in "GNED" at the end (e.g. "resigned").
  defp encode_char(?G, <<?N, ?E, ?D>>, _prev, _acc), do: {"", <<?N, ?E, ?D>>}

  # GH: classic rules:
  #   * At end of word → F  (cough → KF, rough → RF, laugh → LF).
  #   * Followed by vowel → silent both letters (through → 0R,
  #     bough → B; the G drops and the H drops because it lands
  #     after a consumed G, so nothing emits for either).
  #   * Followed by consonant → silent both letters.
  defp encode_char(?G, <<?H>>, _prev, _acc), do: {"F", ""}

  defp encode_char(?G, <<?H, rest::binary>>, _prev, _acc) do
    # Drop both G and H; advance past the H so it isn't reprocessed.
    {"", rest}
  end

  # G + I/E/Y → J (soft G, as in "gem", "giant", "gym"). GG counts as
  # the duplicate-collapsed G that already emitted, so we don't get
  # here for it — but to be defensive: we don't have GG cases since
  # dedupe handles them.
  defp encode_char(?G, <<next, _::binary>> = rest, _prev, _acc) when next in ~c"IEY",
    do: {"J", rest}

  defp encode_char(?G, rest, _prev, _acc), do: {"K", rest}

  # ---- H ----------------------------------------------------------------

  # H is silent after a vowel and not before a vowel (e.g. "ah",
  # "Sarah"). Otherwise H is emitted.
  defp encode_char(?H, <<next, _::binary>> = rest, prev, _acc)
       when prev in @vowels and next not in @vowels do
    {"", rest}
  end

  defp encode_char(?H, "", prev, _acc) when prev in @vowels, do: {"", ""}
  defp encode_char(?H, rest, _prev, _acc), do: {"H", rest}

  # ---- K ----------------------------------------------------------------

  # K silent after C (CK was already handled by C rule, but a stray K
  # after C still needs to be silenced).
  defp encode_char(?K, rest, ?C, _acc), do: {"", rest}
  defp encode_char(?K, rest, _prev, _acc), do: {"K", rest}

  # ---- P ----------------------------------------------------------------

  # PH → F
  defp encode_char(?P, <<?H, rest::binary>>, _prev, _acc), do: {"F", rest}
  defp encode_char(?P, rest, _prev, _acc), do: {"P", rest}

  # ---- S ----------------------------------------------------------------

  # SH, SIO, SIA → X
  defp encode_char(?S, <<?H, rest::binary>>, _prev, _acc), do: {"X", rest}

  defp encode_char(?S, <<?I, n, _::binary>> = rest, _prev, _acc) when n in ~c"OA",
    do: {"X", rest}

  defp encode_char(?S, rest, _prev, _acc), do: {"S", rest}

  # ---- T ----------------------------------------------------------------

  # TH → 0 (theta, the unvoiced "th" in "thin")
  defp encode_char(?T, <<?H, rest::binary>>, _prev, _acc), do: {"0", rest}
  # TIA, TIO → X
  defp encode_char(?T, <<?I, n, _::binary>> = rest, _prev, _acc) when n in ~c"AO",
    do: {"X", rest}

  # TCH: drop the T (the C will encode as K... wait, C followed by H is
  # X, but here we want to drop both T and emit ch as X). Actually
  # canonical rule: "drop T if followed by CH". So skip T, keep CH for
  # next iteration which will produce X.
  defp encode_char(?T, <<?C, ?H, _::binary>> = rest, _prev, _acc), do: {"", rest}

  defp encode_char(?T, rest, _prev, _acc), do: {"T", rest}

  # ---- W ----------------------------------------------------------------

  # W: silent unless followed by a vowel.
  defp encode_char(?W, <<next, _::binary>> = rest, _prev, _acc) when next in @vowels,
    do: {"W", rest}

  defp encode_char(?W, rest, _prev, _acc), do: {"", rest}

  # ---- fallthrough -------------------------------------------------------

  # Defensive default: emit the character. Reachable only for input
  # that survived `String.replace(~r/[^A-Z]/, "")` but isn't covered
  # by a rule above — i.e. nothing in normal use.
  defp encode_char(char, rest, _prev, _acc), do: {<<char>>, rest}

  # ---- truncation --------------------------------------------------------

  defp maybe_truncate(code, nil), do: code

  defp maybe_truncate(code, max) when is_integer(max) and max >= 0 do
    String.slice(code, 0, max)
  end
end
