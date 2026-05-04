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
  # CJK boundary scripts — Han, Hiragana, Katakana, Hangul. Treated as
  # *boundaries* in URLs: a Hiragana char in the middle of prose marks
  # the end of a preceding URL, not a continuation of one. The single
  # exception is the IDN TLD list (handled separately, below).
  @cjk_scripts "\\p{Han}\\p{Hiragana}\\p{Katakana}\\p{Hangul}"

  # Body class for path / query / fragment characters: anything that's
  # not a non-pchar boundary. Specifically excluded:
  #
  # * `\s` — Unicode-aware whitespace (under `u` flag).
  #
  # * CJK scripts — see above; twitter-text treats them as word breaks.
  #
  # * `\p{Cf}` (Format characters) — RTL / LTR / isolate marks (U+202A,
  #   U+202C, U+2066, U+2069, …) and zero-width chars. These never
  #   belong inside a URL even though they pass `\S`.
  @url_body "[^\\s#{@cjk_scripts}\\p{Cf}]"

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

  # Tail after the host: an optional path / query / fragment. All three
  # introducers (`/`, `?`, `#`) are valid — `http://foo.com?#bar` is a
  # complete URL with an empty path, empty query, and a `bar` fragment.
  @url_tail "(?:[\\/?\\#]" <> @url_body <> "*)?"

  # Trailing-label boundary: the host's last label must not be followed
  # by another label-continuation byte, otherwise we're matching in the
  # middle of a longer label.
  @label_end "(?![A-Za-z0-9_\\-])"

  @url_regex Regex.compile!(
               @lookbehind <>
                 "(?:" <>
                 # 1. scheme://(label.)+label — relaxed host class
                 #    (any IDN). TLD validation happens in the
                 #    `Text.Extract.Url` validator, which walks labels
                 #    right-to-left and truncates the host at the
                 #    rightmost valid TLD.
                 "(?:[A-Za-z][A-Za-z0-9+.\\-]*):\\/\\/" <>
                 "(?:" <>
                 @host_label_any <>
                 "\\.)+" <>
                 @host_label_any <>
                 @label_end <>
                 "(?::\\d+)?" <>
                 @url_tail <>
                 "|" <>
                 # 2. (safe_label.)+ (safe_label | idn_unicode_tld) —
                 #    restricted host class for schemeless URLs. Last
                 #    label may be a known IDN-Unicode TLD (since the
                 #    safe label class excludes CJK and would otherwise
                 #    miss `twitter.みんな`-style hosts). Validator
                 #    handles ASCII TLD validation post-match.
                 "(?:" <>
                 @host_label_safe <>
                 "\\.)+" <>
                 "(?:" <>
                 @host_label_safe <>
                 "|" <>
                 @idn_tld_alts <>
                 ")" <>
                 @label_end <>
                 "(?::\\d+)?" <>
                 @url_tail <>
                 ")",
               "iu"
             )

  # Email local part: ASCII atext + dot, plus any non-ASCII char (RFC
  # 6531 / EAI). Whether non-ASCII actually validates is the email
  # validator's job (gated by the `:eai` option) — the scanner is
  # permissive so EAI candidates can be considered.
  @email_local "(?:[A-Za-z0-9._%+\\-]|[^\\x00-\\x7F])+"

  @email_regex Regex.compile!(
                 @lookbehind <>
                   @email_local <>
                   "@" <>
                   "(?:" <>
                   @host_label_safe <>
                   "(?:\\." <>
                   @host_label_safe <>
                   ")+)",
                 "u"
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
  def scan(text) when is_binary(text) do
    emails = candidates(text, @email_regex, :email)
    email_set = MapSet.new(emails, fn {_kind, span} -> span end)

    urls =
      text
      |> candidates(@url_regex, :url)
      |> Enum.reject(fn {_kind, {start, len}} ->
        Enum.any?(email_set, fn {es, el} ->
          start >= es and start + len <= es + el
        end)
      end)

    matches = Enum.sort_by(emails ++ urls, fn {_kind, {start, _}} -> start end)
    interleave(text, matches)
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
