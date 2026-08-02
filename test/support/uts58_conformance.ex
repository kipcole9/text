defmodule Text.UTS58.Conformance do
  @moduledoc """
  Loads the vendored [UTS #58](https://www.unicode.org/reports/tr58/) conformance test files.

  The fixtures under `test/fixtures/uts58/` are refreshed with `mix text.download_uts58`. They are
  vendored rather than fetched at test time so the suite runs offline and a conformance change
  arrives as a reviewable diff.
  """

  @fixtures Path.join([__DIR__, "..", "fixtures", "uts58"]) |> Path.expand()

  @open_marker "⸠"
  @close_marker "⸡"

  @doc """
  Returns the marker characters that delimit an expected link in `LinkDetectionTest.txt`.
  """
  def markers, do: {@open_marker, @close_marker}

  @doc """
  Returns the detection cases as `{plain_text, expected_links}` tuples.

  `plain_text` is the line with the `⸠`/`⸡` markers removed — what a detector is given — and
  `expected_links` is the list of substrings that should be detected, in order. A line with no
  markers yields an empty list, which is a meaningful case: nothing should be detected.
  """
  def detection_cases do
    "LinkDetectionTest.txt"
    |> read()
    |> Enum.map(fn line -> {strip_markers(line), expected_links(line)} end)
  end

  @doc """
  Returns the formatting cases as `{fully_escaped, minimally_escaped}` tuples.

  The file is paired lines rather than delimited fields: the first line of each pair is the source
  with everything percent-escaped, the second is the readable form UTS #58 defines.
  """
  def formatting_cases do
    "LinkFormattingTest.txt"
    |> read()
    |> Enum.chunk_every(2)
    |> Enum.flat_map(fn
      [escaped, minimal] -> [{escaped, minimal}]
      [_odd] -> []
    end)
  end

  # The structure notation used in the `LinkFormattingTest.txt` comments. Each marker introduces one
  # component of the intended URL, and a component's text runs to the next marker or the closing
  # brace — it may itself contain `=`, so splitting on that would be wrong.
  @structure_markers %{
    "\u{1D47A}" => :scheme,
    "\u{1D46F}" => :host,
    "\u{1D477}" => :path,
    "\u{1D478}" => :query,
    "\u{1D47D}" => :value,
    "\u{1D46D}" => :fragment
  }

  @doc """
  Returns the formatting cases with their intended structure, as `{parts, minimally_escaped}`.

  `parts` is the keyword list `Text.Extract.Escape.minimal/1` accepts, taken from the structure
  comment that accompanies each pair. That comment is the real input: the file's "fully escaped"
  column leaves syntax characters literal even where they are data, so `{𝑷=α#β}` is written
  `…/%CE%B1#%CE%B2` and cannot be told apart from a path followed by a fragment.
  """
  def formatting_structures do
    markers = Map.keys(@structure_markers) |> Enum.join()
    pattern = ~r/([#{markers}])=(.*?)(?=\s*[#{markers}]=|\}\s*$)/u

    "LinkFormattingTest.txt"
    |> Path.expand(@fixtures)
    |> File.read!()
    |> String.split("\n")
    |> Enum.chunk_while([], &chunk_case/2, &{:cont, Enum.reverse(&1), []})
    |> Enum.flat_map(fn
      [structure, _escaped, minimal] -> [{parse_structure(structure, pattern), minimal}]
      _incomplete -> []
    end)
  end

  defp chunk_case(line, acc) do
    cond do
      String.starts_with?(line, "# {") -> {:cont, [line]}
      String.trim(line) == "" or String.starts_with?(line, "#") -> {:cont, acc}
      acc == [] -> {:cont, acc}
      length(acc) == 2 -> {:cont, Enum.reverse([line | acc]), []}
      true -> {:cont, [line | acc]}
    end
  end

  defp parse_structure(comment, pattern) do
    pattern
    |> Regex.scan(comment, capture: :all_but_first)
    |> Enum.map(fn [marker, value] -> {Map.fetch!(@structure_markers, marker), value} end)
  end

  @doc """
  Returns the raw significant lines of a fixture, with comments and blank lines removed.
  """
  def read(file) do
    @fixtures
    |> Path.join(file)
    |> File.read!()
    |> String.split("\n")
    |> Enum.reject(&(String.trim(&1) == "" or String.starts_with?(&1, "#")))
  end

  @doc """
  Removes the link markers from a line, giving the text a detector is presented with.
  """
  def strip_markers(line) do
    line
    |> String.replace(@open_marker, "")
    |> String.replace(@close_marker, "")
  end

  @doc """
  Returns the substrings marked as links in a line, in order.
  """
  def expected_links(line) do
    ~r/#{@open_marker}(.*?)#{@close_marker}/u
    |> Regex.scan(line, capture: :all_but_first)
    |> Enum.map(&hd/1)
  end

  @doc """
  Reinserts the markers around each detected link, for comparison against the original line.

  ### Arguments

  * `text` is the unmarked line.

  * `links` is a list of `{byte_offset, byte_length}` spans, in order.

  ### Returns

  * The text with `⸠` and `⸡` inserted around each span.

  """
  def insert_markers(text, links) do
    {result, last} =
      Enum.reduce(links, {[], 0}, fn {offset, length}, {acc, position} ->
        before = binary_part(text, position, offset - position)
        link = binary_part(text, offset, length)

        {[acc, before, @open_marker, link, @close_marker], offset + length}
      end)

    IO.iodata_to_binary([result, binary_part(text, last, byte_size(text) - last)])
  end
end
