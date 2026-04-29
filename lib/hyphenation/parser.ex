defmodule Text.Hyphenation.Parser do
  @moduledoc false

  # Parses a TeX-style hyphenation pattern file (hyph-utf8 / Knuth format)
  # into the lookup structures used by Text.Hyphenation.
  #
  # The output is a `{patterns, exceptions}` tuple:
  #
  #   * `patterns` is a map from the *letters-only* pattern string to a
  #     list of priorities, one entry between each adjacent letter pair
  #     plus one entry at each end. So `.ach4` parses to
  #     `{".ach", [0, 0, 0, 0, 4]}`. The leading "." marks a word-start
  #     anchor; a trailing "." marks word-end.
  #
  #   * `exceptions` is a map from a fully-lowercased exception word (no
  #     hyphens) to the list of zero-based hyphenation point indices.
  #     `as-so-ciate` parses to `{"associate", [2, 5]}`.

  @doc "Parses a TeX hyphenation pattern file into `{patterns, exceptions}`."
  def parse_tex(content) when is_binary(content) do
    cleaned = strip_comments(content)

    patterns =
      cleaned
      |> extract_block("\\patterns{")
      |> tokens()
      |> Map.new(&parse_pattern/1)

    exceptions =
      cleaned
      |> extract_block("\\hyphenation{")
      |> tokens()
      |> Map.new(&parse_exception/1)

    {patterns, exceptions}
  end

  defp strip_comments(content) do
    content
    |> String.split("\n")
    |> Enum.map(&String.replace(&1, ~r/%.*$/, ""))
    |> Enum.join("\n")
  end

  defp extract_block(content, opener) do
    case String.split(content, opener, parts: 2) do
      [_before, after_open] ->
        case String.split(after_open, "}", parts: 2) do
          [block, _rest] -> block
          [block] -> block
        end

      [_only] ->
        ""
    end
  end

  defp tokens(block) do
    block
    |> String.split(~r/\s+/, trim: true)
    |> Enum.reject(&(&1 == ""))
  end

  @doc false
  def parse_pattern(token) do
    chars = String.to_charlist(token)
    do_split(chars, [], [0])
  end

  # Walk the chars; build `letters` (reversed) and `priorities` (reversed).
  # Invariant: priorities has one more element than letters.
  defp do_split([], letters, priorities) do
    {letters |> Enum.reverse() |> List.to_string(), Enum.reverse(priorities)}
  end

  defp do_split([c | rest], letters, [_last | priors_tail]) when c >= ?0 and c <= ?9 do
    do_split(rest, letters, [c - ?0 | priors_tail])
  end

  defp do_split([c | rest], letters, priorities) do
    do_split(rest, [c | letters], [0 | priorities])
  end

  @doc false
  def parse_exception(token) do
    parts = String.split(token, "-")
    word = Enum.join(parts)

    points =
      parts
      |> Enum.drop(-1)
      |> Enum.scan(0, fn part, acc -> acc + String.length(part) end)

    {word, points}
  end
end
