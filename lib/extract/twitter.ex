defmodule Text.Extract.Twitter do
  @moduledoc """
  Twitter-text-specific URL handling quirks, gated behind the
  `:twitter_quirks` option.

  Twitter's [`twitter-text`](https://github.com/twitter/twitter-text)
  library applies a few extraction rules that aren't part of any RFC
  and don't generalise to other contexts (Mastodon, Slack, prose).
  These are useful when you specifically want behavioural parity with
  Twitter's auto-linking — e.g. for a Twitter-clone client — but
  surprising for general URL extraction:

  * **`t.co` slug rules.** Twitter's URL shortener (`t.co`) accepts
    only alphanumeric slugs and caps slugs at 40 characters. Anything
    after the alphanumeric run (`'s`, `+c`, `.x`, `#a`, `-`, …) gets
    stripped. Slugs longer than 40 chars cause the entire URL to be
    rejected.

  * **English-possessive `'s` stripping.** A trailing `'s` after any
    URL (not just t.co) is treated as English prose, not part of the
    URL.

  Both behaviours match twitter-text's published conformance fixtures.
  """

  @doc """
  Applies Twitter quirks to a parsed URL record.

  ### Arguments

  * `wrapped` is `{:ok, record}` where `record` is a URL record (from
    `Text.Extract.Url`). Wrapped form is used so this can be a step in
    a `with`-style pipeline.

  * `text` is the original source string.

  ### Returns

  * `{:ok, record}` — record possibly mutated by quirks (e.g. shorter
    `:url`, `:span`, `:path`).

  * `{:error, :twitter_quirk_rejected}` — the URL is rejected entirely
    (e.g. t.co slug exceeds 40 chars).

  ### Examples

      iex> [r] = Text.Extract.urls("see http://t.co/abcde123 today", twitter_quirks: true)
      iex> r.url
      "http://t.co/abcde123"

      iex> Text.Extract.urls("http://t.co/abcdefghijklmnopqrstuvwxyz012345678901234",
      ...>                   twitter_quirks: true)
      []

  """
  @spec apply({:ok, map()}, String.t()) ::
          {:ok, map()} | {:error, :twitter_quirk_rejected}
  def apply({:ok, _record} = wrapped, text) do
    wrapped
    |> tco_slug_rules()
    |> apostrophe_s_rule(text)
  end

  # ---- t.co slug rules -------------------------------------------------

  defp tco_slug_rules({:ok, %{ascii_host: "t.co", path: path} = record})
       when is_binary(path) do
    case extract_tco_slug(path) do
      {:ok, slug} ->
        # t.co URLs are exactly `t.co/<slug>` — query and fragment are
        # never part of a real shortener URL, so we drop them too.
        rebuild_tco(record, slug)

      :too_long ->
        {:error, :twitter_quirk_rejected}
    end
  end

  defp tco_slug_rules(other), do: other

  defp rebuild_tco(record, slug) do
    new_path = "/" <> slug
    scheme_prefix = if record.scheme, do: "#{record.scheme}://", else: ""
    new_url = scheme_prefix <> record.host <> new_path
    new_ascii = scheme_prefix <> record.ascii_host <> new_path
    {start, _len} = record.span

    {:ok,
     %{
       record
       | url: new_url,
         ascii: new_ascii,
         path: new_path,
         query: nil,
         fragment: nil,
         span: {start, byte_size(new_url)}
     }}
  end

  # t.co slugs are `[A-Za-z0-9]+`, capped at 40 chars. Anything past
  # the alphanumeric run is stripped; if the alphanumeric run itself
  # exceeds 40 chars, the whole URL is rejected.
  defp extract_tco_slug("/" <> rest) do
    {alnum, _trailing} = take_alnum(rest, "")

    cond do
      alnum == "" -> {:ok, ""}
      String.length(alnum) > 40 -> :too_long
      true -> {:ok, alnum}
    end
  end

  defp extract_tco_slug(_), do: {:ok, ""}

  defp take_alnum(<<c, rest::binary>>, acc) when c in ?A..?Z or c in ?a..?z or c in ?0..?9 do
    take_alnum(rest, acc <> <<c>>)
  end

  defp take_alnum(rest, acc), do: {acc, rest}

  # ---- apostrophe-s rule ----------------------------------------------

  defp apostrophe_s_rule({:ok, record}, _text) do
    if String.ends_with?(record.url, "'s") do
      {start, _len} = record.span
      new_url = String.replace_suffix(record.url, "'s", "")
      new_ascii = String.replace_suffix(record.ascii, "'s", "")
      new_len = byte_size(new_url)

      new_path =
        case record.path do
          nil -> nil
          path -> String.replace_suffix(path, "'s", "")
        end

      {:ok,
       %{
         record
         | url: new_url,
           ascii: new_ascii,
           path: new_path,
           span: {start, new_len}
       }}
    else
      {:ok, record}
    end
  end

  defp apostrophe_s_rule(other, _text), do: other
end
