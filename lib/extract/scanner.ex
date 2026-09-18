defmodule Text.Extract.Scanner do
  @moduledoc """
  Phase 1 of the URL / email extraction pipeline: find candidate spans.

  The scanner is intentionally permissive. It identifies anything that
  *could* be a URL or email — full structural validation, IDNA mapping,
  TLD lookup and boundary cleanup happen later in
  `Text.Extract.Url`, `Text.Extract.Email`, and
  `Text.Extract.Link`.

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
  # CJK boundary scripts — Han, Hiragana, Katakana, Hangul. Treated as
  # *boundaries* in URLs: a Hiragana char in the middle of prose marks
  # the end of a preceding URL, not a continuation of one. The single
  # exception is the IDN TLD list (handled separately, below).
  @cjk_scripts "\\p{Han}\\p{Hiragana}\\p{Katakana}\\p{Hangul}"

  # Body class for path / query / fragment characters.
  #
  # Deliberately permissive: `Text.Extract.Link` applies the UTS #58 termination algorithm to the
  # captured span afterwards and `Text.Extract.Url` recomputes the span from what survives, so the
  # scanner only has to capture *at least* the true link. Over-capturing is corrected; capturing too
  # little cannot be.
  #
  # That is why CJK is not excluded here even though twitter-text treats it as a word break. UTS #58
  # gives Han, Hiragana, Katakana and Hangul `Link_Term=Include`, so they belong inside a link, and
  # `https://ja.wikipedia.org/wiki/フィンセント` is one link rather than a truncated one. Format
  # characters are likewise `Include` — the ZWNJ inside `ویکی‌پدیا` is part of the path.
  #
  # Only whitespace is excluded, which `Link_Term` classifies as `Hard` in every case.
  @url_body "\\S"

  # The twitter-text body class, kept for `twitter_quirks: true`. It stops at CJK and at format
  # characters, which is where twitter-text and UTS #58 genuinely disagree: twitter-text treats a
  # Han character following a bare host as ending the URL, UTS #58 treats it as part of the path.
  @url_body_twitter "[^\\s#{@cjk_scripts}\\p{Cf}]"

  # Host label class — any Unicode letter / mark / digit / symbol, plus
  # `_` and `-`. Used inside `://`-anchored URLs where the host is
  # unambiguously delimited by `://` on the left and `/`, `?`, `#`, or
  # whitespace on the right. `\p{S}` covers cases like `http://✪df.ws`
  # where IDN-style symbols appear in the host (twitter-text accepts
  # these even though strict UTS #46 would reject — the validator's
  # IDNA call is permissive by default; users wanting STD3 strictness
  # opt in via `:strict_idn`).
  @host_label_any "[\\p{L}\\p{M}\\p{N}\\p{S}_\\-]+"

  # Bare-host label class — same as `@host_label_any` but excludes the
  # CJK boundary scripts. Used in *schemeless* host extraction where
  # we have no `://` anchor to disambiguate "Hiragana inside a URL"
  # from "Hiragana ending a URL". The IDN-TLD alternation (below)
  # handles the case where Hiragana / Han / etc. is itself a TLD.
  @host_label_safe "(?:(?![#{@cjk_scripts}])[\\p{L}\\p{M}\\p{N}_\\-])+"

  # Under UTS #58 a bare host may be wholly non-ASCII — `다국어도메인이용환경테스트.한국` is a host,
  # not prose. Excluding CJK here would lose those entirely, and the guard against matching ordinary
  # prose is not the character class but the TLD check in `Text.Extract.Url`, which rejects anything
  # whose rightmost label is not a real TLD.
  #
  # Nor is the class limited to letters, marks and digits. Several scripts use a character of
  # another category inside a word — Tibetan writes `ཡོངས་ཁྱབ` with U+0F0B TSHEG, a `Po` — and IDNA
  # accepts them. Since `Text.Extract.Url` runs full UTS #46 processing on whatever is captured,
  # the class is ASCII letters, digits, `_` and `-`, plus any non-ASCII character that is not
  # whitespace, a label separator, or a control or format character. Restricting the ASCII half
  # matters: allowing ASCII punctuation would let `(example.com/…` start its host at the bracket.
  @host_label_unicode "(?:[A-Za-z0-9_\\-]|" <>
                        "[^\\x00-\\x7F\\s\\x{3002}\\x{FF0E}\\x{FF61}\\p{Cc}\\p{Cf}])+"

  # UTS #46 §4.5 recognises four label separators, not just `.`. `普遍适用测试。我爱你` is a
  # two-label host written with U+3002 IDEOGRAPHIC FULL STOP.
  @label_separator "[.\\x{3002}\\x{FF0E}\\x{FF61}]"

  # Bare-host TLD alternation — only the IDN Unicode TLDs (~151
  # entries, ~3 KB). We need this in the regex for the bare-host
  # pattern because the safe-label class excludes CJK / Hiragana /
  # Katakana / Hangul, so a host like `twitter.みんな` would not match
  # without an explicit IDN-TLD alternative as the last label. The
  # ASCII TLD list lives in `Text.Extract.Tld` and is checked
  # post-match by the URL validator's TLD walk.
  @idn_tld_alts Text.Extract.Tld.idn_unicode()
                |> Enum.sort_by(&(-byte_size(&1)))
                |> Enum.map_join("|", &Regex.escape/1)

  # Negative lookbehind: block continuations of an ongoing URL so a
  # rejected `$http://twitter.com` doesn't re-match its host as a fresh
  # bare URL. Includes URL-syntax bytes (`/`, `:`, `?`, `&`, `=`, `+`,
  # `%`) to defend against this case.
  @lookbehind "(?<![A-Za-z0-9@$\\#_\\-.\\/:?&=+%])"

  # Trailing-label boundary: the host's last label must not be followed
  # by another label-continuation byte, otherwise we're matching in the
  # middle of a longer label.
  @label_end "(?![A-Za-z0-9_\\-])"

  # Both regexes are built from the same shape; only the body class differs. Bound to a compile-time
  # closure rather than a private function, since a module cannot call its own functions while being
  # compiled. Both are compiled at build time so neither costs anything at scan time.
  url_pattern = fn body, safe_label, separator ->
    # Tail after the host: an optional path / query / fragment. All three introducers (`/`, `?`,
    # `#`) are valid — `http://foo.com?#bar` is a complete URL with an empty path, empty query and
    # a `bar` fragment.
    tail = "(?:[\\/?\\#]" <> body <> "*)?"

    # An explicit root label: `foo.example.com./path` is a fully qualified host followed by a
    # path, not a host followed by prose. Without this the match would stop before the dot and
    # the path would be lost.
    @lookbehind <>
      "(?:" <>
      "(?:[A-Za-z][A-Za-z0-9+.\\-]*):\\/\\/" <>
      "(?:" <>
      @host_label_any <>
      "\\.)+" <>
      @host_label_any <>
      @label_end <>
      separator <>
      "?" <>
      "(?::\\d+)?" <>
      tail <>
      "|" <>
      "(?:" <>
      safe_label <>
      separator <>
      ")+" <>
      "(?:" <>
      safe_label <>
      "|" <>
      @idn_tld_alts <>
      ")" <>
      @label_end <>
      separator <>
      "?" <>
      "(?::\\d+)?" <>
      tail <>
      ")"
  end

  @url_regex Regex.compile!(
               url_pattern.(@url_body, @host_label_unicode, @label_separator),
               "iu"
             )

  @url_regex_twitter Regex.compile!(
                       url_pattern.(@url_body_twitter, @host_label_safe, "\\."),
                       "iu"
                     )

  # Email local part: ASCII atext + dot, plus any non-ASCII char (RFC
  # 6531 / EAI). Whether non-ASCII actually validates is the email
  # validator's job (gated by the `:eai` option) — the scanner is
  # permissive so EAI candidates can be considered.
  @email_local "(?:[A-Za-z0-9._%+\\-]|[^\\x00-\\x7F])+"

  # `mailto:` is matched here rather than as a URL scheme, since what follows is an email address
  # rather than a host. UTS #58 expects `mailto:john.smith@example.com/foo/bar` to yield only the
  # address — a mailto URL has no path — which falls out of not giving this alternative a tail.
  @email_regex Regex.compile!(
                 @lookbehind <>
                   "(?:mailto:)?" <>
                   @email_local <>
                   "@" <>
                   "(?:" <>
                   @host_label_safe <>
                   "(?:\\." <>
                   @host_label_safe <>
                   ")+)",
                 "iu"
               )

  @typedoc "Element of the scanner's interleaved output."
  @type element ::
          {:text, String.t()}
          | {:url, String.t(), span()}
          | {:email, String.t(), span()}

  @typedoc "Byte offsets `{start, length}` into the source text."
  @type span :: {non_neg_integer(), non_neg_integer()}

  @doc """
  Walks `text` once and returns an interleaved list of plain-text
  fragments and URL / email candidates, preserving document order.

  Concatenating every element's content reproduces `text` byte-for-byte:

      text == scan(text) |> Enum.map_join(&content/1)

  This shape is the building block for everything else in
  `Text.Extract`. `Text.Extract.urls/2` filters for `:url` and
  validates; `Text.Extract.split/2` validates each candidate and
  promotes failures back to `:text`; `Text.Extract.autolink/2`
  renders the result.

  ### Arguments

  * `text` is a UTF-8 string.

  ### Returns

  * A list of elements:

    * `{:text, fragment}` — a span of `text` containing no candidate.

    * `{:url, candidate, {start, length}}` — a URL-shaped candidate.
      `candidate` is the substring; `start`/`length` are byte offsets
      back into `text`.

    * `{:email, candidate, {start, length}}` — an email-shaped
      candidate.

  Where a URL match is wholly contained inside an email match, the
  email wins and the URL is dropped (which is the canonical
  interpretation: `mailto:` aside, an email is never a URL).

  ### Examples

      iex> Text.Extract.Scanner.scan("see http://example.com today")
      [{:text, "see "}, {:url, "http://example.com", {4, 18}}, {:text, " today"}]

      iex> Text.Extract.Scanner.scan("alice@example.com")
      [{:email, "alice@example.com", {0, 17}}]

      iex> Text.Extract.Scanner.scan("hello world")
      [{:text, "hello world"}]

      iex> Text.Extract.Scanner.scan("$invalid http://example.com")
      [{:text, "$invalid "}, {:url, "http://example.com", {9, 18}}]

  """
  @spec scan(String.t()) :: [element()]
  def scan(text, options \\ []) when is_binary(text) and is_list(options) do
    emails = candidates(text, @email_regex, :email)
    email_set = MapSet.new(emails, fn {_kind, span} -> span end)

    urls =
      text
      |> candidates(url_regex(options), :url)
      |> Enum.reject(fn {_kind, {start, len}} ->
        Enum.any?(email_set, fn {es, el} ->
          start >= es and start + len <= es + el
        end)
      end)

    matches = Enum.sort_by(emails ++ urls, fn {_kind, {start, _}} -> start end)
    interleave(text, matches)
  end

  # `twitter_quirks: true` selects the legacy body class, where CJK and format characters end a URL.
  defp url_regex(options) do
    if Keyword.get(options, :twitter_quirks, false), do: @url_regex_twitter, else: @url_regex
  end

  # ---- candidate finding ----------------------------------------------

  defp candidates(text, regex, kind) do
    Regex.scan(regex, text, return: :index, capture: :first)
    |> Enum.flat_map(fn
      [{start, len}] ->
        if valid_preceding_byte?(text, start), do: [{kind, {start, len}}], else: []

      _ ->
        []
    end)
  end

  # ---- interleaving ----------------------------------------------------

  # Walks `matches` (sorted by start offset, non-overlapping after the
  # email-wins reduction) and emits the original text gaps between
  # them as `{:text, fragment}`. The result reconstructs `text` exactly
  # when concatenated.
  defp interleave(text, matches) do
    {acc, cursor} =
      Enum.reduce(matches, {[], 0}, fn {kind, {start, len}}, {acc, pos} ->
        gap = start - pos
        acc = if gap > 0, do: [{:text, binary_part(text, pos, gap)} | acc], else: acc
        candidate = binary_part(text, start, len)
        {[{kind, candidate, {start, len}} | acc], start + len}
      end)

    tail_size = byte_size(text) - cursor
    acc = if tail_size > 0, do: [{:text, binary_part(text, cursor, tail_size)} | acc], else: acc

    case Enum.reverse(acc) do
      [] -> if text == "", do: [], else: [{:text, text}]
      list -> list
    end
  end

  defp valid_preceding_byte?(_text, 0), do: true

  defp valid_preceding_byte?(text, start) do
    case :binary.at(text, start - 1) do
      byte when byte < 0x80 -> byte not in @invalid_preceders
      _ -> true
    end
  end
end
