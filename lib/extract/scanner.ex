defmodule Text.Extract.Scanner do
  @moduledoc """
  Phase 1 of the URL / email extraction pipeline: find candidate spans.

  The scanner is intentionally permissive. It identifies anything that
  *could* be a URL or email — full structural validation, IDNA mapping,
  TLD lookup and boundary cleanup happen later in
  `Text.Extract.Url`, `Text.Extract.Email`, and
  `Text.Extract.Boundary`.

  ### Boundary rules

  Following twitter-text §3, a candidate's first character must be
  preceded by one of:

  * Beginning of the text.

  * Whitespace (any Unicode `Zs`/`Zl`/`Zp`, `\t`, `\n`, `\r`).

  * A CJK character or other "word break" character.

  * One of the safe punctuation chars: `(`, `[`, `{`, `<`, `>`, `"`,
    `'`, `,`, `;`, `:`, `!`, `?`.

  Candidates immediately preceded by `$`, `_`, alphanumerics, `@`,
  `#`, `-`, `.` (or the same set on the *other* side of a CJK char,
  when the previous grapheme is itself part of a token) are rejected.

  ### Output

  `scan/1` returns a list of `{kind, {start_byte, length_bytes}}`
  candidates in source order. `kind` is `:url` or `:email`.
  """

  # Preceding byte allowlist: when the byte immediately before the
  # candidate falls in this set, the boundary is invalid. ASCII chars
  # only — Unicode preceders are always treated as valid breaks except
  # for combining marks (we don't see combining marks at this layer
  # because our regex anchors don't fire mid-grapheme).
  # Includes the common alphanumerics + URL-syntax characters. The
  # latter (`/`, `:`, `?`, `#`, `&`, `=`, `+`, `%`) are critical: when
  # the regex's `scheme://body` alternative fails (because of a leading
  # `$` or other forbidden preceder), the engine backs up to the
  # bare-host alternative starting *inside* the rejected scheme URL —
  # e.g. `$http://twitter.com` would match `twitter.com` because `/`
  # was not blocking. Treating URL-syntax bytes as invalid preceders
  # prevents these intra-URL re-matches.
  @invalid_preceders ~c"@$#_-./:?&=+%" ++
                       Enum.to_list(?A..?Z) ++
                       Enum.to_list(?a..?z) ++
                       Enum.to_list(?0..?9)

  # URL candidate: scheme://body, OR bare host with optional path.
  #
  # We deliberately accept a lot here — phase 2 (Url validator) decides
  # which TLDs are real and which characters belong in path / query /
  # fragment. The body class includes everything `pchar` allows in RFC
  # 3986 plus a few permissive extras (Cyrillic, CJK paths) that the
  # validator will trim.
  #
  # The `(?<!…)` negative lookbehind enforces the boundary rule above.
  # CJK / whitespace / start-of-string all pass; ASCII alnum and the
  # forbidden punctuation set fail.
  @url_regex ~r/
    (?<![A-Za-z0-9@$\#_\-.\/:?&=+%])
    (?:
      (?:[A-Za-z][A-Za-z0-9+.\-]*):\/\/[^\s]+
    |
      (?:[A-Za-z0-9_\-]+(?:\.[A-Za-z0-9_\-]+)+)
      (?::\d+)?
      (?:\/[^\s]*)?
    )
  /xu

  @email_regex ~r/
    (?<![A-Za-z0-9@$\#_\-.\/:?&=+%])
    (?:[A-Za-z0-9._%+\-]+)
    @
    (?:[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)+)
  /xu

  @doc """
  Returns candidate spans for `text`.

  ### Arguments

  * `text` is a UTF-8 string.

  ### Returns

  * A list of `{kind, {start_byte, length_bytes}}` tuples in document
    order. `kind` is `:email` or `:url`. Email candidates are emitted
    before overlapping URL candidates so downstream callers can give
    email precedence.

  ### Examples

      iex> Text.Extract.Scanner.scan("see http://example.com today")
      [{:url, {4, 18}}]

      iex> Text.Extract.Scanner.scan("alice@example.com")
      [{:email, {0, 17}}]

      iex> Text.Extract.Scanner.scan("hello world")
      []

      iex> Text.Extract.Scanner.scan("$invalid http://example.com")
      [{:url, {10, 17}}]

  """
  @spec scan(String.t()) :: [{:url | :email, {non_neg_integer(), pos_integer()}}]
  def scan(text) when is_binary(text) do
    emails = scan_with(text, @email_regex, :email)
    email_spans = MapSet.new(emails, fn {_kind, span} -> span end)

    urls =
      text
      |> scan_with(@url_regex, :url)
      |> Enum.reject(fn {_kind, {start, len}} ->
        # Drop URL candidates that are wholly contained inside an email
        # candidate — the email is the canonical interpretation.
        Enum.any?(email_spans, fn {es, el} ->
          start >= es and start + len <= es + el
        end)
      end)

    Enum.sort_by(emails ++ urls, fn {_kind, {start, _}} -> start end)
  end

  defp scan_with(text, regex, kind) do
    Regex.scan(regex, text, return: :index, capture: :first)
    |> Enum.flat_map(fn
      [{start, len}] ->
        # Defensive double-check: the negative lookbehind is the primary
        # boundary guard, but `Regex.scan` doesn't enforce string-start
        # for the *very first* match if the engine treats `^` flags
        # oddly. We additionally verify against the byte preceding the
        # match.
        if valid_preceding_byte?(text, start), do: [{kind, {start, len}}], else: []

      _ ->
        []
    end)
  end

  defp valid_preceding_byte?(_text, 0), do: true

  defp valid_preceding_byte?(text, start) do
    case :binary.at(text, start - 1) do
      byte when byte < 0x80 -> byte not in @invalid_preceders
      _ -> true
    end
  end
end
