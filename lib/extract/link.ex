defmodule Text.Extract.Link do
  @moduledoc """
  Phase 3 of the URL / email extraction pipeline: decide where a candidate link ends.

  This implements the termination algorithm of
  [UTS #58 §3.5.1](https://www.unicode.org/reports/tr58/), replacing the ASCII-only heuristics that
  preceded it. Real-world prose embeds links in sentences, so `See http://example.com.` must yield
  `http://example.com` with the sentence-final full stop dropped, while
  `https://en.wikipedia.org/wiki/URI_(disambiguation)` must keep its closing parenthesis because a
  matching opener appears inside the link.

  UTS #58 does not define where a link *starts* — §3.2 puts that outside its scope — so
  `Text.Extract.Scanner` still finds candidates and `Text.Extract.Url` still validates them. Only
  the end of the span is decided here.

  ### How it works

  The scan walks the candidate one codepoint at a time, keeping a `last_safe` offset that marks the
  longest prefix known to be a valid link. Each codepoint is classified by `Unicode.LinkTerm`:

  * `:include` — part of the link; `last_safe` advances past it.

  * `:hard` — ends the link immediately; the scan returns `last_safe`.

  * `:soft` — provisionally part of the link, but `last_safe` does *not* advance. A later
    `:include` pulls it back in, so `a.b` keeps its full stop while `a.` does not.

  * `:open` — a bracket, pushed onto a stack. `last_safe` does not advance, so a trailing unclosed
    bracket is dropped.

  * `:close` — pops the stack and compares through `Unicode.LinkBracket`. A match is included and
    `last_safe` advances; a mismatch, or a close with nothing on the stack, ends the link.

  The bracket stack is cleared at separators, so a bracket opened in one field cannot be closed in
  the next: at the part initiators `/`, `?` and `#` always, at `=` and `&` within a query or
  fragment, and at a comma within a fragment. Those are scoped to their part — `=` is an ordinary
  path character, and clearing on it everywhere would break URLs such as
  `.../system.net.httpwebrequest(v=VS.100).aspx`. The stack is capped at 125 entries, beyond which
  further open brackets are treated as ordinary included characters rather than being stacked.

  Because the properties cover the whole repertoire rather than a handful of ASCII characters, this
  handles the 61 non-ASCII bracket pairs and 129 ranges of soft terminators that the previous
  implementation could not.

  """

  alias Unicode.LinkBracket
  alias Unicode.LinkTerm

  # UTS #58 §3.5.1 caps the bracket stack so that pathological input cannot grow it without bound.
  @stack_limit 125

  # Brackets do not pair across a part boundary, so a part initiator clears the stack.
  @part_initiators [?/, ??, ?#]

  @doc """
  Trims a candidate link to the longest prefix that UTS #58 considers part of the link.

  ### Arguments

  * `candidate` is the candidate substring, as emitted by `Text.Extract.Scanner.scan/1`.

  ### Returns

  * The candidate with any trailing characters that terminate the link removed. Never grows; only
    the end of the string is trimmed.

  ### Examples

      iex> Text.Extract.Link.shrink("http://example.com.")
      "http://example.com"

      iex> Text.Extract.Link.shrink("http://example.com)")
      "http://example.com"

      iex> Text.Extract.Link.shrink("http://en.wikipedia.org/wiki/URI_(disambiguation)")
      "http://en.wikipedia.org/wiki/URI_(disambiguation)"

      iex> Text.Extract.Link.shrink("http://x.com/path......")
      "http://x.com/path"

  """
  @spec shrink(String.t()) :: String.t()
  def shrink(candidate) when is_binary(candidate) do
    codepoints = String.to_charlist(candidate)
    keep = scan(codepoints, 0, 0, [], :none)

    codepoints
    |> Enum.take(keep)
    |> List.to_string()
  end

  # `position` counts codepoints consumed, `last_safe` is the longest prefix known to be safe,
  # `stack` holds the opening brackets not yet closed in the current part, and `part` is the URL
  # part being scanned, which decides whether a comma separates fields.
  defp scan([], _position, last_safe, _stack, _part), do: last_safe

  defp scan([codepoint | rest], position, last_safe, stack, part) do
    next = position + 1
    part = enter_part(codepoint, part)

    if clears_stack?(codepoint, part) do
      # Separators are themselves part of the link, so `last_safe` advances with them.
      scan(rest, next, next, [], part)
    else
      classify(codepoint, rest, position, last_safe, stack, part)
    end
  end

  defp enter_part(??, _part), do: :query
  defp enter_part(?#, _part), do: :fragment
  defp enter_part(?/, :none), do: :path
  defp enter_part(_codepoint, part), do: part

  defp clears_stack?(codepoint, _part) when codepoint in @part_initiators, do: true

  # `=` and `&` separate fields in a query, and equally in a fragment — text fragments carry
  # `:~:text=` pairs — so a bracket opened in one field cannot be closed in the next. A comma does
  # the same inside a fragment.
  #
  # These are scoped to their part deliberately. In a path `=` is an ordinary character, and
  # clearing the stack on it there breaks real URLs such as
  # `.../system.net.httpwebrequest(v=VS.100).aspx`, whose parentheses do pair.
  defp clears_stack?(codepoint, part) when part in [:query, :fragment] and codepoint in [?=, ?&],
    do: true

  defp clears_stack?(?,, :fragment), do: true
  defp clears_stack?(_codepoint, _part), do: false

  defp classify(codepoint, rest, position, last_safe, stack, part) do
    next = position + 1

    case LinkTerm.link_term(codepoint) do
      :include ->
        scan(rest, next, next, stack, part)

      :hard ->
        last_safe

      # Provisionally included: `last_safe` stays put, so a trailing run of soft characters is
      # trimmed, but an `:include` later on pulls the whole run back into the link.
      :soft ->
        scan(rest, next, last_safe, stack, part)

      :open ->
        scan(rest, next, last_safe, push(stack, codepoint), part)

      :close ->
        close_bracket(codepoint, rest, next, last_safe, stack, part)
    end
  end

  # Beyond the cap the bracket is not tracked, so a later close cannot match it.
  defp push(stack, _codepoint) when length(stack) >= @stack_limit, do: stack
  defp push(stack, codepoint), do: [codepoint | stack]

  defp close_bracket(codepoint, rest, next, last_safe, [opening | stack], part) do
    if LinkBracket.pair?(codepoint, opening) do
      scan(rest, next, next, stack, part)
    else
      last_safe
    end
  end

  # A closing bracket with nothing open cannot belong to the link — it is the prose closing around
  # it, as in `(see example.com)`.
  defp close_bracket(_codepoint, _rest, _next, last_safe, [], _part), do: last_safe
end
