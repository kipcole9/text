defmodule Text.Extract.Escape do
  @moduledoc """
  Minimal escaping of URLs, per [UTS #58 §4.1](https://www.unicode.org/reports/tr58/).

  A URL that percent-escapes every non-ASCII byte is unreadable — `https://example.com/%CE%B1%CE%B2`
  says nothing to a reader, where `https://example.com/αβ` says `αβ`. Minimal escaping produces the
  most readable serialisation that still survives link detection: a character is left as itself
  unless unescaping it would change where the link ends or what its structure is.

  A character therefore stays escaped when it:

  * terminates a link — anything with `Link_Term=Hard`, such as a space;

  * is the *last* character of the URL and has `Link_Term=Soft`, since a trailing soft character is
    trimmed by the termination algorithm. A soft character anywhere earlier is safe, which is why
    `/αβγ./δεζ.` escapes only its very last full stop;

  * would begin a later part — `?` and `#` in a path, `#` in a query — because unescaping it would
    silently restructure the URL;

  * is a bracket with no partner in the same field, which would otherwise terminate the link; or

  * is a percent sign followed by two hexadecimal digits, which would otherwise be read as an
    escape. A `%` that cannot be misread is left alone.

  Everything else is decoded, including all non-ASCII.

  This is the counterpart to `Text.Extract.Link`: that decides where a link ends when reading, this
  decides how to write one so that reading it back gives the same answer.

  """

  alias Unicode.LinkBracket
  alias Unicode.LinkTerm

  @doc """
  Rewrites a fully-escaped URL into its minimally escaped, most readable form.

  ### Arguments

  * `url` is either a URL string with every non-ASCII byte percent-escaped, or a keyword list of
    already-parsed parts: `:scheme`, `:host`, and any number of `:path`, `:query`, `:value` and
    `:fragment` entries in order. Duplicate keys are expected — one `:path` per segment, and a
    `:value` following the `:query` it belongs to.

  The structured form exists because a serialised URL is lossy about its own structure: nothing in
  `https://example.com/α#β` distinguishes a path segment containing `#` from a path followed by a
  fragment. Pass parts when the structure is already known and the distinction matters.

  ### Returns

  * The URL with escapes removed wherever doing so does not change how the link is detected or
    structured. The scheme and host are returned unchanged, since host encoding is an IDNA question
    rather than a link-detection one.

  ### Examples

      iex> Text.Extract.Escape.minimal("https://example.com/%CE%B1")
      "https://example.com/α"

      iex> Text.Extract.Escape.minimal("https://example.com/%CE%B1%20%CE%B2")
      "https://example.com/α%20β"

      iex> Text.Extract.Escape.minimal("https://example.com/%CE%B4%2E")
      "https://example.com/δ%2E"

      iex> Text.Extract.Escape.minimal("https://example.com/%CE%B1%3F%CE%BC")
      "https://example.com/α%3Fμ"

  """
  @spec minimal(String.t() | keyword()) :: String.t()
  def minimal(url) when is_binary(url) do
    {authority, rest} = split_authority(url)

    authority <> escape_parts(rest)
  end

  def minimal(parts) when is_list(parts) do
    last = last_significant_part(parts)

    parts
    |> Enum.with_index()
    |> Enum.map_reduce(false, fn {{key, value}, index}, query? ->
      serialize(key, value, query?, index == last)
    end)
    |> elem(0)
    |> IO.iodata_to_binary()
  end

  # The scheme and host are emitted verbatim; the rest are escaped according to the part they are.
  defp serialize(:scheme, value, query?, _last?), do: {value, query?}
  defp serialize(:host, value, query?, _last?), do: {value, query?}

  defp serialize(:path, value, query?, last?),
    do: {["/", escape_data(value, :path, last?)], query?}

  defp serialize(:query, value, query?, last?),
    do: {[if(query?, do: "&", else: "?"), escape_data(value, :query, last?)], true}

  defp serialize(:value, value, query?, last?),
    do: {["=", escape_data(value, :query, last?)], query?}

  defp serialize(:fragment, value, query?, last?),
    do: {["#", escape_data(value, :fragment, last?)], query?}

  defp last_significant_part(parts) do
    parts
    |> Enum.with_index()
    |> Enum.filter(fn {{key, _value}, _index} -> key not in [:scheme, :host] end)
    |> List.last()
    |> case do
      {{_key, _value}, index} -> index
      nil -> -1
    end
  end

  # Structured input is raw text rather than a serialisation, so every character is data. There is
  # no literal/escaped distinction to preserve — a `#` in a path segment is a `#` the caller means,
  # and must be escaped so that reading the result back yields the same structure.
  defp escape_data(value, part, last?) do
    codepoints = String.to_charlist(value)
    last = if last?, do: length(codepoints) - 1, else: -1
    unmatched = unmatched_brackets(Enum.map(codepoints, &{&1, :escaped}))

    codepoints
    |> Enum.with_index()
    |> Enum.map(fn {codepoint, index} ->
      if ambiguous_percent?(codepoint, index, codepoints) or restructures?(codepoint, part) or
           breaks_termination?(codepoint, index, last, unmatched) do
        percent_encode(codepoint)
      else
        <<codepoint::utf8>>
      end
    end)
    |> IO.iodata_to_binary()
  end

  # The scheme and host are left alone: their encoding is governed by IDNA, not by link detection.
  # Everything from the first `/`, `?` or `#` after the host onwards is ours.
  defp split_authority(url) do
    case Regex.run(~r{^([a-zA-Z][a-zA-Z0-9+.\-]*://[^/?#]*)(.*)$}s, url, capture: :all_but_first) do
      [authority, rest] -> {authority, rest}
      nil -> split_hostless(url)
    end
  end

  defp split_hostless(url) do
    case Regex.run(~r{^([^/?#]*)(.*)$}s, url, capture: :all_but_first) do
      [authority, rest] -> {authority, rest}
      nil -> {url, ""}
    end
  end

  # The input is fully escaped, so a literal `?` or `#` is structural and one that is data appears
  # as `%3F` or `%23`. Splitting on the literal characters is therefore unambiguous.
  defp escape_parts(rest) do
    {path, after_path} = take_until(rest, [??, ?#])
    {query, fragment} = take_until(after_path, [?#])

    # Only the final character of the whole URL is trimmed by the termination algorithm, so the
    # trailing-soft rule applies to the last non-empty part rather than to each one. A full stop
    # ending a path segment mid-URL is safe; the same character ending the URL is not.
    last = last_part(path, query, fragment)

    escape_part(path, :path, last == :path) <>
      escape_part(query, :query, last == :query) <>
      escape_part(fragment, :fragment, last == :fragment)
  end

  defp last_part(_path, _query, fragment) when fragment != "", do: :fragment
  defp last_part(_path, query, _fragment) when query != "", do: :query
  defp last_part(_path, _query, _fragment), do: :path

  defp take_until(<<>>, _stops), do: {"", ""}

  defp take_until(<<first::utf8, rest::binary>> = string, stops) do
    if first in stops and string != "" do
      case String.split(rest, [<<hd(stops)::utf8>>], parts: 2) do
        _ -> split_at_stop(string, stops)
      end
    else
      split_at_stop(string, stops)
    end
  end

  defp split_at_stop(string, stops) do
    graphemes = String.to_charlist(string)

    index =
      graphemes
      |> Enum.drop(1)
      |> Enum.find_index(&(&1 in stops))

    case index do
      nil -> {string, ""}
      index -> String.split_at(string, index + 1)
    end
  end

  # A part keeps its leading `/`, `?` or `#`; only the content after it is considered.
  defp escape_part("", _part, _last?), do: ""

  defp escape_part(<<initiator::utf8, content::binary>>, part, last?) do
    <<initiator::utf8>> <> escape_content(units(content), part, last?)
  end

  # Each unit is `{codepoint, :literal | :escaped}`. Only escaped units are candidates for
  # unescaping — a literal character is already structural and must stay exactly as it is. That
  # distinction is what separates a path separator `/` from a `%2F` inside a segment, and it is
  # recoverable from the input precisely because the input is fully escaped.
  defp escape_content(units, part, last?) do
    last = if last?, do: length(units) - 1, else: -1
    unmatched = unmatched_brackets(units)

    units
    |> Enum.with_index()
    |> Enum.map(fn {{codepoint, kind}, index} ->
      cond do
        # Safety first, and regardless of how the character arrived: a literal character that would
        # terminate the link has to be escaped, or the URL cannot be read back. This is what makes
        # a trailing unmatched `)` become `%29` even though it was already literal.
        breaks_termination?(codepoint, index, last, unmatched) ->
          percent_encode(codepoint)

        # Structure is only *preserved*, never invented. A literal `/` is a real path separator,
        # so it stays; a `%2F` is data, so it stays escaped.
        kind == :literal ->
          <<codepoint::utf8>>

        restructures?(codepoint, part) ->
          percent_encode(codepoint)

        ambiguous_percent?(codepoint, index, Enum.map(units, &elem(&1, 0))) ->
          percent_encode(codepoint)

        true ->
          <<codepoint::utf8>>
      end
    end)
    |> IO.iodata_to_binary()
  end

  defp breaks_termination?(codepoint, index, last, unmatched) do
    cond do
      LinkTerm.link_term(codepoint) == :hard -> true
      index in unmatched -> true
      index == last and LinkTerm.link_term(codepoint) == :soft -> true
      true -> false
    end
  end

  # Unescaping one of these would change the URL's structure rather than just how it reads: `/` would
  # start a new path segment, `?` a query, `#` a fragment, and `&` or `=` a new query field or the
  # boundary between a key and its value. None of them affects link *termination* — they are escaped
  # so that reading the result back recovers the same parts.
  defp restructures?(codepoint, :path) when codepoint in [?/, ??, ?#], do: true
  defp restructures?(codepoint, :query) when codepoint in [?#, ?&, ?=], do: true
  defp restructures?(_codepoint, _part), do: false

  # A percent sign only needs escaping where it could be *read* as introducing an escape. `%41` must
  # become `%2541` or it would decode to `A`, but a `%` not followed by two hex digits is
  # unambiguous and stays as it is — escaping it would be noise, which is the opposite of the point.
  defp ambiguous_percent?(?%, index, codepoints) do
    case Enum.slice(codepoints, (index + 1)..(index + 2)) do
      [high, low] -> hex?(high) and hex?(low)
      _shorter -> false
    end
  end

  defp ambiguous_percent?(_codepoint, _index, _codepoints), do: false

  defp hex?(codepoint) do
    codepoint in ?0..?9 or codepoint in ?a..?f or codepoint in ?A..?F
  end

  # Indices of brackets with no partner. An unmatched bracket terminates a link, so it has to stay
  # escaped even though its `Link_Term` is `:open` or `:close`.
  defp unmatched_brackets(units) do
    {open, unmatched} =
      units
      |> Enum.with_index()
      |> Enum.reduce({[], []}, fn {{codepoint, _kind}, index}, {open, unmatched} ->
        case LinkTerm.link_term(codepoint) do
          :open -> {[{codepoint, index} | open], unmatched}
          :close -> close_bracket(codepoint, index, open, unmatched)
          _other -> {open, unmatched}
        end
      end)

    MapSet.new(unmatched ++ Enum.map(open, &elem(&1, 1)))
  end

  defp close_bracket(codepoint, index, [{opening, opening_index} | open], unmatched) do
    if LinkBracket.pair?(codepoint, opening) do
      {open, unmatched}
    else
      {open, [index, opening_index | unmatched]}
    end
  end

  defp close_bracket(_codepoint, index, [], unmatched), do: {[], [index | unmatched]}

  # Splits content into codepoints tagged by whether they arrived percent-escaped. Consecutive
  # escapes are gathered before decoding, since one codepoint above ASCII spans several of them.
  defp units(content), do: units(content, [], [])

  defp units(<<>>, escaped, acc), do: Enum.reverse(flush(escaped, acc))

  defp units(<<?%, high, low, rest::binary>>, escaped, acc) do
    case Integer.parse(<<high, low>>, 16) do
      {byte, ""} -> units(rest, [byte | escaped], acc)
      _other -> units(<<high, low, rest::binary>>, [], [{?%, :literal} | flush(escaped, acc)])
    end
  end

  defp units(<<codepoint::utf8, rest::binary>>, escaped, acc) do
    units(rest, [], [{codepoint, :literal} | flush(escaped, acc)])
  end

  defp units(<<byte, rest::binary>>, escaped, acc) do
    units(rest, [], [{byte, :literal} | flush(escaped, acc)])
  end

  defp flush([], acc), do: acc

  defp flush(escaped, acc) do
    escaped
    |> Enum.reverse()
    |> IO.iodata_to_binary()
    |> decode_codepoints()
    |> Enum.reduce(acc, fn codepoint, acc -> [{codepoint, :escaped} | acc] end)
  end

  # A percent sequence that is not valid UTF-8 cannot be a character, so its bytes are kept as they
  # were rather than being replaced or dropped.
  defp decode_codepoints(bytes) do
    case String.valid?(bytes) do
      true -> String.to_charlist(bytes)
      false -> :binary.bin_to_list(bytes)
    end
  end

  defp percent_encode(codepoint) do
    <<codepoint::utf8>>
    |> :binary.bin_to_list()
    |> Enum.map_join(fn byte -> "%" <> (byte |> Integer.to_string(16) |> String.upcase()) end)
  end
end
