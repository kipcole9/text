defmodule Text.Extract.Boundary do
  @moduledoc """
  Phase 3 of the URL / email extraction pipeline: trim spurious
  trailing punctuation from a candidate span.

  Real-world prose embeds URLs into sentences. The text
  `"See http://example.com."` should yield the URL `http://example.com`
  with the sentence-final period dropped, while
  `"https://en.wikipedia.org/wiki/URI_(disambiguation)"` should keep
  the closing parenthesis because it has a matching opener inside the
  span.

  This module produces a (possibly shorter) `{start, length}` span by:

  1. Stripping trailing characters from a fixed punctuation set
     (`.,;:!?'"`).

  2. Stripping trailing closing brackets (`)`, `]`, `}`, `>`) that have
     no matching opener inside the span.

  Steps repeat until no further trimming is possible.

  ### Examples

      iex> Text.Extract.Boundary.shrink("http://example.com.")
      "http://example.com"

      iex> Text.Extract.Boundary.shrink("http://example.com)")
      "http://example.com"

      iex> Text.Extract.Boundary.shrink("http://en.wikipedia.org/wiki/URI_(disambiguation)")
      "http://en.wikipedia.org/wiki/URI_(disambiguation)"

      iex> Text.Extract.Boundary.shrink("http://x.com/path......")
      "http://x.com/path"

  """

  @trailing_punct ~c".,;:!?'\""
  @brackets [{?), ?(}, {?], ?[}, {?}, ?{}, {?>, ?<}]
  @bracket_closers Enum.map(@brackets, &elem(&1, 0))

  @doc """
  Trims trailing punctuation and unbalanced closers from a candidate
  string.

  ### Arguments

  * `candidate` is the candidate substring (e.g. as emitted by
    `Text.Extract.Scanner.scan/1`).

  ### Returns

  * The candidate with trailing junk removed. Never grows; only the
    end of the string is trimmed.
  """
  @spec shrink(String.t()) :: String.t()
  def shrink(candidate) when is_binary(candidate) do
    do_shrink(candidate, byte_size(candidate))
  end

  defp do_shrink(_candidate, 0), do: ""

  defp do_shrink(candidate, len) do
    last_byte = :binary.at(candidate, len - 1)

    cond do
      last_byte in @trailing_punct ->
        do_shrink(candidate, len - 1)

      last_byte in @bracket_closers ->
        opener = bracket_opener(last_byte)

        if balanced?(candidate, len - 1, opener, last_byte) do
          binary_part(candidate, 0, len)
        else
          do_shrink(candidate, len - 1)
        end

      true ->
        binary_part(candidate, 0, len)
    end
  end

  defp bracket_opener(byte) do
    {_, opener} = Enum.find(@brackets, fn {closer, _} -> closer == byte end)
    opener
  end

  # Counts balanced openers/closers inside the inner span (excluding
  # the final closer at index `len - 1`). Returns `true` if there's at
  # least one unmatched opener — meaning the trailing closer balances
  # something and should be kept.
  defp balanced?(candidate, len, opener, closer) do
    inner = binary_part(candidate, 0, len)
    do_balance(inner, opener, closer, 0)
  end

  defp do_balance(<<>>, _o, _c, depth), do: depth > 0

  defp do_balance(<<byte, rest::binary>>, opener, closer, depth) do
    cond do
      byte == opener -> do_balance(rest, opener, closer, depth + 1)
      byte == closer and depth > 0 -> do_balance(rest, opener, closer, depth - 1)
      true -> do_balance(rest, opener, closer, depth)
    end
  end
end
