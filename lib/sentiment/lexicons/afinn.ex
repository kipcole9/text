defmodule Text.Sentiment.Lexicons.AFINN do
  @moduledoc """
  Bundled [AFINN](https://github.com/fnielsen/afinn) sentiment lexicons.

  AFINN is a list of words rated for sentiment polarity on an integer
  scale from `-5` (extremely negative) to `+5` (extremely positive),
  with `0` reserved for neutral terms. The English list (`AFINN-165`)
  has roughly 3,400 entries; community translations cover ~100
  additional languages at varying quality.

  All AFINN data is distributed under the Apache 2.0 license, the same
  as this package, and is bundled in `priv/sentiment/`.

  This module exposes:

  * `lexicon/1` — returns the AFINN word→score map for a language tag,
    plus two synthetic lexicons:
      * `:emoticon` — text emoticons (`:-)`, `:(`, `<3`, …).
      * `:emoji`    — Unicode emoji, derived from the
        [Emoji Sentiment Ranking 1.0](http://kt.ijs.si/data/Emoji_sentiment_ranking/)
        corpus and rescaled to AFINN's −5..+5 range.

  * `negators/1` — returns the per-language list of negation phrases
    used by `Text.Sentiment.Backends.Lexicon` to flip polarity for the
    word that follows. The English fallback is used when a language
    has no negator list.

  * `available/0` — every loaded language tag, including `:emoji` and
    `:emoticon`.

  ## Quality note

  The English (`:en`), Danish (`:da`), Finnish (`:fi`), French
  (`:fr`), Polish (`:pl`), Swedish (`:sv`), and Turkish (`:tr`)
  lexicons are hand-curated by the upstream AFINN project. The other
  ~95 language lexicons are machine-translated derivatives from the
  same upstream source — useful as a baseline, but expect noisier
  scores for low-resource languages.

  ## Tag list

  Language tags are the upstream filenames lower-cased: typically
  ISO 639-1 two-letter codes (`:en`, `:de`, `:ja`), occasionally
  three-letter codes (`:ceb`, `:haw`, `:hmn`), and one BCP-47-style
  tag (`:"zh-tw"`). Note that the upstream uses the legacy ISO
  codes `:iw` for Hebrew and `:jw` for Javanese; modern code values
  are `:he` and `:jv` respectively.

  Use `available/0` to enumerate the tags loaded into the running
  build.
  """

  @priv_dir Path.join([__DIR__, "..", "..", "..", "priv", "sentiment"])

  # Discover every TSV at compile time. Each `afinn-<tag>.tsv` becomes
  # a `lexicon/1` clause; `negators.tsv` populates `negators/1`.
  @afinn_paths Path.wildcard(Path.join(@priv_dir, "afinn-*.tsv"))
  @negators_path Path.join(@priv_dir, "negators.tsv")

  for path <- @afinn_paths, do: @external_resource(path)
  @external_resource @negators_path

  # ── TSV parser ───────────────────────────────────────────────────
  parse_tsv = fn path ->
    path
    |> File.read!()
    |> String.split(~r/\r?\n/, trim: true)
    |> Enum.reduce(%{}, fn line, acc ->
      case String.split(line, "\t", parts: 2) do
        [token, score_string] ->
          case Integer.parse(score_string) do
            {n, _} -> Map.put(acc, token, n)
            :error -> acc
          end

        _ ->
          acc
      end
    end)
  end

  # ── Lexicons ─────────────────────────────────────────────────────
  @lexicons Enum.into(@afinn_paths, %{}, fn path ->
              tag =
                path
                |> Path.basename(".tsv")
                |> String.replace_prefix("afinn-", "")
                |> String.to_atom()

              {tag, parse_tsv.(path)}
            end)

  @available @lexicons |> Map.keys() |> Enum.sort()

  # ── Negators ─────────────────────────────────────────────────────
  @negators (
              if File.exists?(@negators_path) do
                @negators_path
                |> File.read!()
                |> String.split(~r/\r?\n/, trim: true)
                |> Enum.reduce(%{}, fn line, acc ->
                  case String.split(line, "\t", parts: 2) do
                    [lang, phrase] ->
                      tag = String.to_atom(lang)
                      Map.update(acc, tag, [phrase], &[phrase | &1])

                    _ ->
                      acc
                  end
                end)
                |> Map.new(fn {lang, phrases} ->
                  {lang, phrases |> Enum.uniq() |> Enum.sort()}
                end)
              else
                %{}
              end
            )

  @en_default_negators ~w(not no never none nobody nowhere neither nor cannot can't won't shouldn't wouldn't isn't aren't wasn't weren't doesn't don't didn't haven't hasn't hadn't ain't)

  @typedoc "An AFINN language tag, plus the synthetic `:emoticon` / `:emoji`."
  @type tag :: atom()

  @doc """
  Returns the bundled AFINN lexicon for `tag` as a `%{token =>
  integer}` map.

  Raises `ArgumentError` if `tag` is not in `available/0`.

  ## Examples

      iex> Text.Sentiment.Lexicons.AFINN.lexicon(:en) |> Map.get("good")
      3

      iex> Text.Sentiment.Lexicons.AFINN.lexicon(:fr) |> Map.get("excellent")
      4

      iex> Text.Sentiment.Lexicons.AFINN.lexicon(:emoticon) |> Map.get(":-)")
      2

      iex> Text.Sentiment.Lexicons.AFINN.lexicon(:emoji) |> Map.get("\u{1F602}")
      2

  """
  @spec lexicon(tag()) :: %{String.t() => integer()}
  def lexicon(tag) when is_atom(tag) do
    case Map.fetch(@lexicons, tag) do
      {:ok, lexicon} ->
        lexicon

      :error ->
        raise ArgumentError,
              "no bundled AFINN lexicon for #{inspect(tag)}. " <>
                "Available: #{inspect(@available)}."
    end
  end

  @doc """
  Returns the list of every loaded AFINN language tag, sorted.

  The list always includes the synthetic `:emoticon` and `:emoji`
  lexicons.

  ## Examples

      iex> :en in Text.Sentiment.Lexicons.AFINN.available()
      true

      iex> :emoji in Text.Sentiment.Lexicons.AFINN.available()
      true

  """
  @spec available() :: [tag()]
  def available, do: @available

  @doc """
  Returns the list of negation phrases for the given language tag,
  used by `Text.Sentiment.Backends.Lexicon` to flip the polarity of
  the word immediately following a negator.

  Falls back to a built-in English negator list when the tag has no
  curated entry.

  ## Examples

      iex> "not" in Text.Sentiment.Lexicons.AFINN.negators(:en)
      true

      iex> Text.Sentiment.Lexicons.AFINN.negators(:fr) |> Enum.take(1) |> length()
      1

  """
  @spec negators(atom()) :: [String.t()]
  def negators(tag) when is_atom(tag) do
    Map.get(@negators, tag, @en_default_negators)
  end

  @doc """
  Returns `true` if `tag` has a curated negator list.

  ## Examples

      iex> Text.Sentiment.Lexicons.AFINN.has_negators?(:en)
      true

      iex> Text.Sentiment.Lexicons.AFINN.has_negators?(:nonexistent)
      false

  """
  @spec has_negators?(atom()) :: boolean()
  def has_negators?(tag) when is_atom(tag), do: Map.has_key?(@negators, tag)
end
