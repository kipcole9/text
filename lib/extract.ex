defmodule Text.Extract do
  @moduledoc """
  Extract URLs and email addresses from arbitrary text at
  social-media quality.

  The extractor follows the rules that twitter-text uses (and which
  Slack, Mastodon, and most "auto-link" implementations imitate),
  layered with full UTS #46 IDNA processing for internationalised
  domain names via the `:unicode_idna` package.

  ## Pipeline

  1. **Scan** — `Text.Extract.Scanner` performs one linear pass over
     the text and emits candidate spans. Boundary rules (twitter-text
     §3) reject candidates immediately preceded by `$`, `_`, `@`, `#`,
     `-`, `.`, or alphanumerics.

  2. **Validate** — each candidate goes through `Text.Extract.Url` (or
     `Text.Extract.Email` once that ships) for:

     * RFC 3986 / RFC 5322 structural parsing.

     * UTS #46 ToASCII for every host label (rejects DISALLOWED
       codepoints, invalid hyphen positions, oversized labels, …).

     * Twitter-style host-label rules — no leading/trailing
       `-`/`_`, underscores forbidden in the registrable domain and
       TLD labels.

     * TLD lookup against `Text.Extract.Tld`'s bundled IANA list.

  3. **Boundary cleanup** — `Text.Extract.Boundary` shrinks the span
     to drop trailing punctuation and unbalanced brackets without
     losing legitimate inner punctuation (Wikipedia-style URLs with
     parentheses are preserved).

  Each result is a map with the original Unicode form, the all-ASCII
  Punycode form, byte offsets into the source, and the parsed RFC 3986
  components.

  ## Examples

      iex> Text.Extract.urls("see http://example.com today") |> Enum.map(& &1.url)
      ["http://example.com"]

      iex> Text.Extract.urls("foo.com bar.net baz.org") |> Enum.map(& &1.url)
      ["foo.com", "bar.net", "baz.org"]

      iex> Text.Extract.urls("see http://en.wikipedia.org/wiki/URI_(disambiguation).") |> Enum.map(& &1.url)
      ["http://en.wikipedia.org/wiki/URI_(disambiguation)"]

  """

  alias Text.Extract.{Scanner, Url}

  @doc """
  Extracts URLs from `text`.

  ### Arguments

  * `text` is a UTF-8 string.

  ### Options

  * `:require_scheme` — when `true`, only `scheme://…` URLs validate;
    schemeless candidates like `example.com` are rejected. Default
    `false` (matches Twitter / auto-linking behaviour).

  * `:schemes` — allowlist of accepted schemes. Default
    `["http", "https", "ftp", "ftps"]`.

  * `:tld_mode` — `:iana` (default) or `:any`. See `Text.Extract.Tld`.

  * `:strict_idn` — when `true`, IDNA uses STD3 ASCII rules (rejects
    `_` in labels). Default `false`.

  ### Returns

  * A list of URL records in document order. Each record has
    `:url`, `:ascii`, `:span`, `:scheme`, `:userinfo`, `:host`,
    `:ascii_host`, `:port`, `:path`, `:query`, `:fragment`.

  ### Examples

      iex> [r] = Text.Extract.urls("see http://example.com today")
      iex> {r.url, r.host, r.span}
      {"http://example.com", "example.com", {4, 18}}

      iex> Text.Extract.urls("nothing here") |> length()
      0

  """
  @spec urls(String.t(), keyword()) :: [Url.url_record()]
  def urls(text, options \\ []) when is_binary(text) do
    text
    |> Scanner.scan()
    |> Enum.filter(fn {kind, _span} -> kind == :url end)
    |> Enum.flat_map(fn {_kind, span} ->
      case Url.validate(text, span, options) do
        {:ok, record} -> [record]
        {:error, _reason} -> []
      end
    end)
  end
end
