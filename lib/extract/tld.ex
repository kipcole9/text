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
  Returns the count of TLDs in the bundled IANA list.

  ### Examples

      iex> Text.Extract.Tld.count() > 1000
      true

  """
  @spec count() :: non_neg_integer()
  def count, do: MapSet.size(@tlds)
end
