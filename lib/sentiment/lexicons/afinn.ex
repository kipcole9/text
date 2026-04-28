defmodule Text.Sentiment.Lexicons.AFINN do
  @moduledoc """
  Bundled [AFINN](https://github.com/fnielsen/afinn) sentiment lexicons.

  AFINN is a list of words rated for sentiment polarity on an integer
  scale from `-5` (extremely negative) to `+5` (extremely positive),
  with `0` reserved for neutral terms. The English list (`AFINN-165`)
  has roughly 3,400 entries; community translations cover Danish,
  Finnish, French, Polish, Swedish, and Turkish at similar scale.
  All AFINN data is distributed under the Apache 2.0 license, the same
  as this package, and is bundled in `priv/sentiment/`.

  This module loads each lexicon at compile time and exposes a single
  function, `lexicon/1`, that returns the corresponding `%{token =>
  score}` map. The maps are intended for use with
  `Text.Sentiment.Lexicon.score/3` (or via the `Text.Sentiment` facade,
  which selects an AFINN lexicon based on the `:language` option).

  ### Bundled language tags

  | Tag | Language | Source file |
  |---|---|---|
  | `:en` | English | `priv/sentiment/afinn-en.tsv` |
  | `:da` | Danish  | `priv/sentiment/afinn-da.tsv` |
  | `:fi` | Finnish | `priv/sentiment/afinn-fi.tsv` |
  | `:fr` | French  | `priv/sentiment/afinn-fr.tsv` |
  | `:pl` | Polish  | `priv/sentiment/afinn-pl.tsv` |
  | `:sv` | Swedish | `priv/sentiment/afinn-sv.tsv` |
  | `:tr` | Turkish | `priv/sentiment/afinn-tr.tsv` |
  | `:emoticon` | Emoticons (`:-)`, `:(`, `<3` ...) | `priv/sentiment/afinn-emoticon.tsv` |

  The emoticon lexicon is language-agnostic and can be merged into any
  language's lexicon for tweet-style or chat-style inputs — see
  `Text.Sentiment.lexicon_for/2`.

  """

  @external_resource Path.join([__DIR__, "..", "..", "..", "priv", "sentiment", "afinn-en.tsv"])
  @external_resource Path.join([__DIR__, "..", "..", "..", "priv", "sentiment", "afinn-da.tsv"])
  @external_resource Path.join([__DIR__, "..", "..", "..", "priv", "sentiment", "afinn-fi.tsv"])
  @external_resource Path.join([__DIR__, "..", "..", "..", "priv", "sentiment", "afinn-fr.tsv"])
  @external_resource Path.join([__DIR__, "..", "..", "..", "priv", "sentiment", "afinn-pl.tsv"])
  @external_resource Path.join([__DIR__, "..", "..", "..", "priv", "sentiment", "afinn-sv.tsv"])
  @external_resource Path.join([__DIR__, "..", "..", "..", "priv", "sentiment", "afinn-tr.tsv"])
  @external_resource Path.join([
                       __DIR__,
                       "..",
                       "..",
                       "..",
                       "priv",
                       "sentiment",
                       "afinn-emoticon.tsv"
                     ])

  @priv_dir Path.join([__DIR__, "..", "..", "..", "priv", "sentiment"])

  # Inline TSV parser (anonymous fun) — module attributes can't call
  # `defp` functions defined in the same module, so the parsing logic
  # is captured here as a fun and invoked once per language.
  parse = fn path ->
    path
    |> File.read!()
    |> String.split(~r/\r?\n/, trim: true)
    |> Enum.reduce(%{}, fn line, acc ->
      case String.split(line, "\t", parts: 2) do
        [token, score_string] ->
          Map.put(acc, token, String.to_integer(score_string))

        _ ->
          acc
      end
    end)
  end

  @en parse.(Path.join(@priv_dir, "afinn-en.tsv"))
  @da parse.(Path.join(@priv_dir, "afinn-da.tsv"))
  @fi parse.(Path.join(@priv_dir, "afinn-fi.tsv"))
  @fr parse.(Path.join(@priv_dir, "afinn-fr.tsv"))
  @pl parse.(Path.join(@priv_dir, "afinn-pl.tsv"))
  @sv parse.(Path.join(@priv_dir, "afinn-sv.tsv"))
  @tr parse.(Path.join(@priv_dir, "afinn-tr.tsv"))
  @emoticon parse.(Path.join(@priv_dir, "afinn-emoticon.tsv"))

  @typedoc "Bundled AFINN language tags."
  @type tag :: :en | :da | :fi | :fr | :pl | :sv | :tr | :emoticon

  @doc """
  Returns the bundled AFINN lexicon for the given language tag.

  ### Arguments

  * `tag` is one of `:en`, `:da`, `:fi`, `:fr`, `:pl`, `:sv`, `:tr`,
    or `:emoticon`.

  ### Returns

  * A `%{token => integer}` map. Missing tags raise `ArgumentError`.

  ### Examples

      iex> Text.Sentiment.Lexicons.AFINN.lexicon(:en) |> Map.get("good")
      3

      iex> Text.Sentiment.Lexicons.AFINN.lexicon(:fr) |> Map.get("excellent")
      4

      iex> Text.Sentiment.Lexicons.AFINN.lexicon(:emoticon) |> Map.get(":-)")
      2

  """
  @spec lexicon(tag()) :: %{String.t() => integer()}
  def lexicon(:en), do: @en
  def lexicon(:da), do: @da
  def lexicon(:fi), do: @fi
  def lexicon(:fr), do: @fr
  def lexicon(:pl), do: @pl
  def lexicon(:sv), do: @sv
  def lexicon(:tr), do: @tr
  def lexicon(:emoticon), do: @emoticon

  def lexicon(other) do
    raise ArgumentError,
          "no bundled AFINN lexicon for #{inspect(other)}. " <>
            "Available: :en, :da, :fi, :fr, :pl, :sv, :tr, :emoticon."
  end

  @doc """
  Returns the list of supported language tags.

  ### Examples

      iex> Text.Sentiment.Lexicons.AFINN.available()
      [:en, :da, :fi, :fr, :pl, :sv, :tr, :emoticon]

  """
  @spec available() :: [tag()]
  def available, do: [:en, :da, :fi, :fr, :pl, :sv, :tr, :emoticon]
end
