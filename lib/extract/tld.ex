defmodule Text.Extract.Tld do
  @moduledoc """
  Top-level domain validation for `Text.Extract`.

  At compile time, this module reads `priv/extract/tlds.txt` (the IANA
  TLD list, refreshed by `mix text.download_tlds`) and bakes the entries
  into a `MapSet` for O(1) lookup. The bundled file is committed to
  source control; the mix task exists to make refreshes reproducible.

  TLD comparison is case-insensitive and operates on the **ASCII** form
  of a label. Internationalised TLDs in the IANA list are stored in
  Punycode (`xn--…`) — pass labels through `Unicode.IDNA.to_ascii/2`
  before lookup.

  ### Modes

  * `:iana` — match against the full bundled IANA list (~1,440 entries).

  * `:any` — accept any non-empty ASCII label (used by callers that
    need to bypass TLD validation, e.g. for intranet hostnames or
    ad-hoc strings).

  Twitter-style tiered ccTLD/gTLD lists could be layered on top by a
  caller, but in practice the IANA list and a "must end in a known TLD"
  rule reproduce twitter-text's behaviour for every URL conformance
  fixture we've checked: the TLDs that twitter-text rejects (e.g.
  `.baz`, `.govedu`, `.comm`) are simply not in IANA either.
  """

  @priv_path Application.app_dir(:text, "priv/extract/tlds.txt")
  @external_resource @priv_path

  @raw File.read!(@priv_path)

  @tlds @raw
        |> String.split(~r/\r?\n/, trim: true)
        |> Enum.reject(&String.starts_with?(&1, "#"))
        |> Enum.map(&String.downcase/1)
        |> MapSet.new()

  @version_line @raw
                |> String.split(~r/\r?\n/, trim: true)
                |> Enum.find(&String.starts_with?(&1, "#"))

  # Pre-computed Unicode forms of every IDN TLD in the IANA list. Used
  # by `Text.Extract.Scanner` to extend its bare-host regex with
  # explicit alternatives for non-ASCII TLDs (e.g. `みんな`, `中国`,
  # `рф`, `ไทย`) — without them, the scanner cannot tell where a
  # CJK-followed-by-prose URL like `twitter.みんなです` should end.
  #
  # Built at compile time from the `xn--` ACE entries via
  # `Unicode.IDNA.to_unicode/2`. Failures are skipped silently — they'd
  # represent IANA list rows that fail current UTS #46 validation,
  # which is rare but possible across Unicode versions.
  @idn_tlds @tlds
            |> Enum.filter(&String.starts_with?(&1, "xn--"))
            |> Enum.flat_map(fn ace ->
              case Unicode.IDNA.to_unicode(ace) do
                {:ok, unicode} -> [unicode]
                _ -> []
              end
            end)
            |> Enum.uniq()

  # ASCII TLDs sorted longest-first. Useful for callers that build
  # regex alternations: `co.uk` vs `uk` — the regex must try `co` and
  # `uk` separately at appropriate positions, but for a single-label
  # alternation the order matters when one TLD is a prefix of another
  # (`com` vs `comm` — `comm` isn't actually a TLD here, but the same
  # principle applies to e.g. `co` vs `com`).
  @ascii_tlds_sorted @tlds
                     |> Enum.reject(&String.starts_with?(&1, "xn--"))
                     |> Enum.sort_by(&{-String.length(&1), &1})

  @doc """
  Returns the IANA TLD list as a `MapSet` of lowercased ASCII labels.

  ### Examples

      iex> "com" in Text.Extract.Tld.iana()
      true

      iex> "googleusercontent" in Text.Extract.Tld.iana()
      false

  """
  @spec iana() :: MapSet.t(String.t())
  def iana, do: @tlds

  @doc """
  Returns the version header line from the bundled `tlds.txt`.

  ### Examples

      iex> Text.Extract.Tld.version_line() =~ "Last Updated"
      true

  """
  @spec version_line() :: String.t() | nil
  def version_line, do: @version_line

  @doc """
  Returns whether `label` is a known TLD under `mode`.

  ### Arguments

  * `label` is an ASCII string. Pass IDN labels through
    `Unicode.IDNA.to_ascii/2` first.

  * `mode` is `:iana` (default) or `:any`.

  ### Returns

  * `true` if the label is a known TLD under the mode, `false`
    otherwise.

  ### Examples

      iex> Text.Extract.Tld.tld?("com")
      true

      iex> Text.Extract.Tld.tld?("COM")
      true

      iex> Text.Extract.Tld.tld?("baz")
      false

      iex> Text.Extract.Tld.tld?("baz", :any)
      true

  """
  @spec tld?(String.t(), :iana | :any) :: boolean()
  def tld?(label, mode \\ :iana)
  def tld?(<<>>, _mode), do: false
  def tld?(label, :any) when is_binary(label), do: true

  def tld?(label, :iana) when is_binary(label) do
    MapSet.member?(@tlds, String.downcase(label))
  end

  @doc """
  Returns the ASCII TLDs sorted longest-first.

  Useful for building regex alternations where longer TLDs must be
  tried first.

  ### Examples

      iex> ascii = Text.Extract.Tld.ascii_sorted()
      iex> "com" in ascii
      true

      iex> "xn--p1ai" in Text.Extract.Tld.ascii_sorted()
      false

  """
  @spec ascii_sorted() :: [String.t()]
  def ascii_sorted, do: @ascii_tlds_sorted

  @doc """
  Returns the IDN TLDs in their Unicode form.

  Built at compile time from the `xn--` ACE entries by passing each
  through `Unicode.IDNA.to_unicode/1`. Used by `Text.Extract.Scanner`
  to extend its bare-host regex with explicit alternatives for IDN
  TLDs.

  ### Examples

      iex> tlds = Text.Extract.Tld.idn_unicode()
      iex> length(tlds) > 100
      true

      iex> "みんな" in Text.Extract.Tld.idn_unicode()
      true

  """
  @spec idn_unicode() :: [String.t()]
  def idn_unicode, do: @idn_tlds

  @doc """
  Returns the count of TLDs in the bundled IANA list.

  ### Examples

      iex> Text.Extract.Tld.count() > 1000
      true

  """
  @spec count() :: non_neg_integer()
  def count, do: MapSet.size(@tlds)
end
