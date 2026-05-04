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

  ## Phoenix integration

  `Text.Extract.autolink/2` returns `Phoenix.HTML.safe()` (a
  `{:safe, iodata}` tuple), so it drops directly into a Phoenix
  template:

  ```eex
  <%= Text.Extract.autolink(@user_post) %>
  ```

  No `raw/1` needed — Phoenix knows the iodata is already escaped
  appropriately. For non-Phoenix callers, convert with
  `Phoenix.HTML.safe_to_string/1`.

  ## Examples

      iex> Text.Extract.urls("see http://example.com today") |> Enum.map(& &1.url)
      ["http://example.com"]

      iex> Text.Extract.urls("foo.com bar.net baz.org") |> Enum.map(& &1.url)
      ["foo.com", "bar.net", "baz.org"]

      iex> Text.Extract.urls("see http://en.wikipedia.org/wiki/URI_(disambiguation).")
      ...> |> Enum.map(& &1.url)
      ["http://en.wikipedia.org/wiki/URI_(disambiguation)"]

  """

  alias Text.Extract.{Email, Scanner, Url}

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
    |> Enum.flat_map(fn
      {:url, candidate, span} ->
        case Url.validate(candidate, span, options) do
          {:ok, record} -> [record]
          {:error, _} -> []
        end

      _ ->
        []
    end)
  end

  @doc """
  Extracts email addresses from `text`.

  ### Arguments

  * `text` is a UTF-8 string.

  ### Options

  * `:eai` — when `true`, allow non-ASCII codepoints in the local part
    per RFC 6531 SMTPUTF8 (e.g. `用户@example.com`). Default `true`.

  * `:tld_mode` — `:iana` (default) or `:any`.

  * `:strict_idn` — when `true`, IDNA uses STD3 ASCII rules. Default
    `false`.

  ### Returns

  * A list of email records in document order. Each record has
    `:email`, `:ascii`, `:span`, `:local`, `:host`, `:ascii_host`.

  ### Examples

      iex> [r] = Text.Extract.emails("Contact alice@example.com today.")
      iex> {r.email, r.local, r.host}
      {"alice@example.com", "alice", "example.com"}

      iex> Text.Extract.emails("no email here") |> length()
      0

  """
  @spec emails(String.t(), keyword()) :: [Email.email_record()]
  def emails(text, options \\ []) when is_binary(text) do
    text
    |> Scanner.scan()
    |> Enum.flat_map(fn
      {:email, candidate, span} ->
        case Email.validate(candidate, span, options) do
          {:ok, record} -> [record]
          {:error, _} -> []
        end

      _ ->
        []
    end)
  end

  @doc """
  Extracts both URLs and email addresses from `text`, interleaved in
  document order.

  Where a candidate matches both — e.g. `mailto:alice@example.com` —
  the email wins (it's the canonical interpretation).

  ### Returns

  * A list of records each with a `:kind` field (`:url` or `:email`)
    plus the kind-specific fields. Sorted by `:span` start position.

  ### Examples

      iex> [url, email] = Text.Extract.all("Visit https://example.com or email alice@example.com.")
      iex> {url.kind, url.url, email.kind, email.email}
      {:url, "https://example.com", :email, "alice@example.com"}

      iex> Text.Extract.all("no links or emails here")
      []

  """
  @spec all(String.t(), keyword()) :: [map()]
  def all(text, options \\ []) when is_binary(text) do
    text
    |> Scanner.scan()
    |> Enum.flat_map(fn
      {:url, candidate, span} ->
        case Url.validate(candidate, span, options) do
          {:ok, r} -> [Map.put(r, :kind, :url)]
          _ -> []
        end

      {:email, candidate, span} ->
        case Email.validate(candidate, span, options) do
          {:ok, r} -> [Map.put(r, :kind, :email)]
          _ -> []
        end

      _ ->
        []
    end)
  end

  @doc """
  Splits `text` into a list of plain-string fragments and entity maps,
  preserving document order.

  This is the primitive `Text.Extract.autolink/2` is built on, and the
  building block users typically want when rendering extracted text:
  walk the list, leave strings alone, render entity maps however you
  like (anchors, mentions, badges, link previews, …).

  Adjacent fragments and entities concatenate to the original `text`
  byte-for-byte, so round-tripping `Enum.map_join(split, &render/1)`
  with the identity renderer reproduces the input exactly.

  ### Arguments

  * `text` is a UTF-8 string.

  ### Options

  * Same options as `all/2` — `:require_scheme`, `:schemes`,
    `:tld_mode`, `:eai`, `:strict_idn`, `:twitter_quirks`.

  ### Returns

  * A list whose elements are either `String.t()` (plain text segments)
    or entity maps (`%{kind: :url, …}` / `%{kind: :email, …}`). Empty
    string segments are omitted, so two adjacent entities appear with
    no separator between them.

  ### Examples

      iex> Text.Extract.split("Visit https://example.com today.")
      ...> |> Enum.map(fn
      ...>   text when is_binary(text) -> {:text, text}
      ...>   entity -> {entity.kind, entity.url || entity.email}
      ...> end)
      [{:text, "Visit "}, {:url, "https://example.com"}, {:text, " today."}]

      iex> Text.Extract.split("plain text only")
      ["plain text only"]

      iex> Text.Extract.split("")
      []

  """
  @spec split(String.t(), keyword()) :: [String.t() | map()]
  def split(text, options \\ []) when is_binary(text) do
    text
    |> Scanner.scan()
    |> Enum.map(fn
      {:text, fragment} ->
        fragment

      {:url, candidate, span} ->
        case Url.validate(candidate, span, options) do
          {:ok, r} -> Map.put(r, :kind, :url)
          {:error, _} -> candidate
        end

      {:email, candidate, span} ->
        case Email.validate(candidate, span, options) do
          {:ok, r} -> Map.put(r, :kind, :email)
          {:error, _} -> candidate
        end
    end)
    |> coalesce_strings()
  end

  # Adjacent strings appear when a candidate fails to validate and is
  # promoted back to plain text. Coalesce them into a single fragment
  # so downstream consumers see a clean alternation.
  defp coalesce_strings(elements) do
    elements
    |> Enum.reduce([], fn
      str, [prev | rest] when is_binary(str) and is_binary(prev) ->
        [prev <> str | rest]

      el, acc ->
        [el | acc]
    end)
    |> Enum.reverse()
  end

  @doc """
  Wraps URLs and email addresses in `text` with HTML `<a>` anchors.

  Plain-text segments are HTML-escaped. Anchor display text is the
  *original* matched form (so `bücher.de` displays as `bücher.de`,
  not its Punycode); the `href` uses the ASCII Punycode form for
  URLs and `mailto:` plus the ASCII form for emails. This matches
  what every modern browser does when a user clicks an IDN link.

  For schemeless URLs (`example.com`) the `href` adds an explicit
  scheme — defaults to `https` for safety; flip via `:href_scheme`.

  ### Arguments

  * `text` is a UTF-8 string.

  ### Options

  All `all/2` options pass through, plus:

  * `:href_scheme` — `:https` (default) or `:http`. Used to construct
    the `href` for schemeless URL matches like `example.com`.

  * `:url_attrs` — extra HTML attributes (a keyword list) added to
    every URL anchor. Defaults to `[]`. Common choices:
    `[target: "_blank", rel: "noopener noreferrer nofollow"]`.

  * `:email_attrs` — extra HTML attributes added to every email anchor.

  * `:url_renderer` — `(entity -> iodata)` callback that fully overrides
    URL rendering. When supplied, `:url_attrs` and `:href_scheme` are
    ignored for URL output.

  * `:email_renderer` — `(entity -> iodata)` callback that fully
    overrides email rendering.

  ### Returns

  * `Phoenix.HTML.safe()` — i.e. `{:safe, iodata}`. Drop the result
    straight into a Phoenix template (`<%= autolink(text) %>`) and
    Phoenix renders it without re-escaping. For non-Phoenix callers,
    convert with `Phoenix.HTML.safe_to_string/1`.

  ### Examples

      iex> "Visit https://example.com today."
      ...> |> Text.Extract.autolink()
      ...> |> Phoenix.HTML.safe_to_string()
      ~s|Visit <a href="https://example.com">https://example.com</a> today.|

      iex> "Email alice@example.com please."
      ...> |> Text.Extract.autolink()
      ...> |> Phoenix.HTML.safe_to_string()
      ~s|Email <a href="mailto:alice@example.com">alice@example.com</a> please.|

      iex> "foo.com is a site."
      ...> |> Text.Extract.autolink()
      ...> |> Phoenix.HTML.safe_to_string()
      ...> |> String.contains?(~s|href="https://foo.com"|)
      true

      iex> "plain text & symbols < >"
      ...> |> Text.Extract.autolink()
      ...> |> Phoenix.HTML.safe_to_string()
      "plain text &amp; symbols &lt; &gt;"

  """
  @spec autolink(String.t(), keyword()) :: Phoenix.HTML.safe()
  def autolink(text, options \\ []) when is_binary(text) do
    href_scheme = Keyword.get(options, :href_scheme, :https)
    url_attrs = Keyword.get(options, :url_attrs, [])
    email_attrs = Keyword.get(options, :email_attrs, [])
    url_renderer = Keyword.get(options, :url_renderer)
    email_renderer = Keyword.get(options, :email_renderer)

    iodata =
      text
      |> split(options)
      |> Enum.map(fn
        str when is_binary(str) ->
          {:safe, escaped} = Phoenix.HTML.html_escape(str)
          escaped

        %{kind: :url} = entity ->
          if url_renderer do
            entity |> url_renderer.() |> ensure_safe()
          else
            render_url(entity, href_scheme, url_attrs)
          end

        %{kind: :email} = entity ->
          if email_renderer do
            entity |> email_renderer.() |> ensure_safe()
          else
            render_email(entity, email_attrs)
          end
      end)

    {:safe, iodata}
  end

  # Hand-builds an `<a>` tag as iodata. URL hosts and paths are
  # already URL-shaped (no raw markup) but we still escape via
  # `Phoenix.HTML.html_escape/1` so any oddly-shaped query strings,
  # IRI characters, or attribute values stay safe.
  defp render_url(entity, href_scheme, attrs) do
    href =
      if entity.scheme do
        entity.ascii
      else
        Atom.to_string(href_scheme) <> "://" <> entity.ascii
      end

    {:safe, href_safe} = Phoenix.HTML.html_escape(href)
    {:safe, display_safe} = Phoenix.HTML.html_escape(entity.url)

    [
      ~s|<a href="|,
      href_safe,
      ~s|"|,
      render_attrs(attrs),
      ~s|>|,
      display_safe,
      ~s|</a>|
    ]
  end

  defp render_email(entity, attrs) do
    {:safe, href_safe} = Phoenix.HTML.html_escape(entity.ascii)
    {:safe, display_safe} = Phoenix.HTML.html_escape(entity.email)

    [
      ~s|<a href="mailto:|,
      href_safe,
      ~s|"|,
      render_attrs(attrs),
      ~s|>|,
      display_safe,
      ~s|</a>|
    ]
  end

  defp render_attrs([]), do: ""

  defp render_attrs(attrs) do
    Enum.map(attrs, fn {k, v} ->
      {:safe, escaped} = Phoenix.HTML.html_escape(to_string(v))
      [" ", to_string(k), ~s|="|, escaped, ~s|"|]
    end)
  end

  # Custom renderers can return either an iodata-shaped value (raw,
  # which we trust) or a `{:safe, iodata}` tuple (already-escaped).
  # Strings get HTML-escaped — same as text segments — to prevent a
  # well-intentioned `fn e -> "[#{e.url}]" end` from injecting markup.
  defp ensure_safe({:safe, iodata}), do: iodata
  defp ensure_safe(other) when is_binary(other) do
    {:safe, escaped} = Phoenix.HTML.html_escape(other)
    escaped
  end
  defp ensure_safe(iodata) when is_list(iodata), do: iodata
end
