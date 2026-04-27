defmodule Text.KWIC do
  @moduledoc """
  Keyword-In-Context concordance.

  Given a piece of text and a search term, returns each occurrence of
  the term with a window of surrounding tokens on either side. The
  classic concordancing tool from corpus linguistics, useful for
  inspecting how a word is actually used in a corpus, building
  glossaries, and debugging tokenisation.

  Example display rendering:

      "the quick brown" | "fox" | "jumped over the"
      "the lazy red"    | "fox" | "ran past the"

  Each match is returned as a `Text.KWIC.Match` struct carrying the
  pre-context, the matched token (in its original casing), and the
  post-context. Use `format/2` to turn a match into a readable string
  with the term centred and visually delimited.

  """

  alias Text.Segment

  defmodule Match do
    @moduledoc """
    A single keyword-in-context occurrence.

    ### Fields

    * `position` — zero-based token index within the document where the
      match occurred.

    * `left` — list of tokens preceding the match, in order.

    * `term` — the matched token, in its original casing.

    * `right` — list of tokens following the match, in order.

    """
    @type t :: %__MODULE__{
            position: non_neg_integer(),
            left: [String.t()],
            term: String.t(),
            right: [String.t()]
          }

    defstruct [:position, :left, :term, :right]
  end

  @doc """
  Returns every occurrence of `term` in `text` with surrounding context.

  ### Arguments

  * `text` is a UTF-8 string.

  * `term` is the search term — a single token (e.g. `"cat"`). Multi-word
    phrases are not yet supported.

  ### Options

  * `:context` — number of tokens of context on each side. Defaults to
    `5`.

  * `:case_sensitive` — when `false` (default), the search is
    case-insensitive. The output preserves original casing regardless.

  * `:tokenizer` — a string-to-tokens function. Defaults to
    `&Text.Segment.words/1`.

  ### Returns

  * A list of `Text.KWIC.Match` structs in document order. Returns
    `[]` if the term is not found.

  ### Examples

      iex> matches = Text.KWIC.concordance("the cat sat on the mat", "cat", context: 2)
      iex> match = hd(matches)
      iex> match.term
      "cat"
      iex> match.left
      ["the"]
      iex> match.right
      ["sat", "on"]
      iex> match.position
      1

      iex> Text.KWIC.concordance("no matches here", "missing")
      []

  """
  @spec concordance(String.t(), String.t(), keyword()) :: [Match.t()]
  def concordance(text, term, options \\ []) when is_binary(text) and is_binary(term) do
    context = Keyword.get(options, :context, 5)
    case_sensitive? = Keyword.get(options, :case_sensitive, false)
    tokenizer = Keyword.get(options, :tokenizer, &Segment.words/1)

    tokens = tokenizer.(text)

    needle = if case_sensitive?, do: term, else: String.downcase(term)
    haystack_for_match = if case_sensitive?, do: tokens, else: Enum.map(tokens, &String.downcase/1)

    haystack_for_match
    |> Enum.with_index()
    |> Enum.filter(fn {token, _idx} -> token == needle end)
    |> Enum.map(fn {_token, idx} -> build_match(tokens, idx, context) end)
  end

  @doc """
  Renders a `Match` as a readable concordance line.

  ### Arguments

  * `match` is a `Text.KWIC.Match`.

  ### Options

  * `:separator` — string placed between the three sections. Defaults
    to `" | "`.

  * `:width` — when set, pads the left context to this many characters
    so multiple lines align in a fixed-width display.

  ### Returns

  * A string.

  ### Examples

      iex> match = %Text.KWIC.Match{
      ...>   position: 1, left: ["the"], term: "cat", right: ["sat", "on"]
      ...> }
      iex> Text.KWIC.format(match)
      "the | cat | sat on"

      iex> match = %Text.KWIC.Match{
      ...>   position: 1, left: ["the"], term: "cat", right: ["sat", "on"]
      ...> }
      iex> Text.KWIC.format(match, separator: " ~ ")
      "the ~ cat ~ sat on"

  """
  @spec format(Match.t(), keyword()) :: String.t()
  def format(%Match{} = match, options \\ []) do
    separator = Keyword.get(options, :separator, " | ")
    width = Keyword.get(options, :width)

    left = Enum.join(match.left, " ")
    right = Enum.join(match.right, " ")

    left = if width, do: String.pad_leading(left, width), else: left

    Enum.join([left, match.term, right], separator)
  end

  # ---- internal ---------------------------------------------------------

  defp build_match(tokens, idx, context) do
    left =
      tokens
      |> Enum.slice(max(idx - context, 0), min(idx, context))

    right = Enum.slice(tokens, (idx + 1)..(idx + context))
    term = Enum.at(tokens, idx)

    %Match{position: idx, left: left, term: term, right: right}
  end
end
