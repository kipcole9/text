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

      iex> Text.Extract.Boundary.shrink("see http://example.com.", {4, 19})
      {4, 18}

      iex> Text.Extract.Boundary.shrink("(http://example.com)", {1, 19})
      {1, 18}

      iex> Text.Extract.Boundary.shrink("see http://en.wikipedia.org/wiki/URI_(disambiguation)", {4, 49})
      {4, 49}

      iex> Text.Extract.Boundary.shrink("a http://x.com/path......", {2, 23})
      {2, 15}

  """

  @trailing_punct ~c".,;:!?'\""
  @brackets [{?), ?(}, {?], ?[}, {?}, ?{}, {?>, ?<}]
  @bracket_closers Enum.map(@brackets, &elem(&1, 0))

  @doc """
  Trims trailing punctuation and unbalanced closers from `span`.

  ### Arguments

  * `text` is the original UTF-8 string.

  * `span` is a `{start_byte, length_bytes}` tuple referencing `text`.

  ### Returns

  * A possibly-shortened `{start, length}` span. `length` is reduced;
    `start` never changes.
  """
  @spec shrink(String.t(), {non_neg_integer(), non_neg_integer()}) ::
          {non_neg_integer(), non_neg_integer()}
  def shrink(text, {start, len}) when is_binary(text) do
    do_shrink(text, start, len)
  end

  defp do_shrink(_text, start, 0), do: {start, 0}

  defp do_shrink(text, start, len) do
    last_byte = :binary.at(text, start + len - 1)

    cond do
      last_byte in @trailing_punct ->
        do_shrink(text, start, len - 1)

      last_byte in @bracket_closers ->
        opener = bracket_opener(last_byte)

        if balanced?(text, start, len - 1, opener, last_byte) do
          {start, len}
        else
          do_shrink(text, start, len - 1)
        end

      true ->
        {start, len}
    end
  end

  defp bracket_opener(byte) do
    {_, opener} = Enum.find(@brackets, fn {closer, _} -> closer == byte end)
    opener
  end

  # Counts balanced openers/closers inside the inner span (excluding the
  # final closer at index `start + len`). Returns `true` if there's at
  # least one unmatched opener — meaning the trailing closer balances
  # something and should be kept.
  defp balanced?(text, start, len, opener, closer) do
    inner = :binary.part(text, start, len)
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
