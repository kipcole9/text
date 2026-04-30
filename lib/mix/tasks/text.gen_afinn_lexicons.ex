defmodule Mix.Tasks.Text.GenAfinnLexicons do
  @shortdoc "Regenerates priv/sentiment from the vendored AFINN data set"

  @moduledoc """
  Converts the [AFINN](https://github.com/fnielsen/afinn) data vendored
  under `data/affin/` into per-language TSV files under
  `priv/sentiment/`, ready for compile-time loading by
  `Text.Sentiment.Lexicons.AFINN`.

  Three sources are processed:

  * `data/affin/languages/AFINN-<tag>.json` — per-language word→score
    maps. Each becomes `priv/sentiment/afinn-<tag>.tsv`.

    Hand-curated TSVs already present in `priv/sentiment/` are
    **preserved**; only languages that don't yet have a curated TSV
    are written from the vendored JSON. (For example the existing
    Polish TSV has more entries than the upstream JSON, so we keep it.)

  * `data/affin/emojis/Emoji_Sentiment_Data_v1.0.csv` — Emoji Sentiment
    Ranking 1.0 frequency data. Mapped onto AFINN's −5..+5 scale via
    `round((Positive − Negative) / Occurrences × 5)` and written to
    `priv/sentiment/afinn-emoji.tsv`.

  * `data/affin/languages/negators/all.json` — per-language lists of
    negation phrases. Written to `priv/sentiment/negators.tsv` as
    `<lang>\\t<phrase>` rows for compile-time loading.

  ## Usage

      mix text.gen_afinn_lexicons               # additive: keep curated TSVs
      mix text.gen_afinn_lexicons --overwrite   # regenerate every TSV from JSON

  """

  use Mix.Task

  @data_root Path.join(["data", "affin"])
  @priv_root Path.join(["priv", "sentiment"])

  @impl true
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: [overwrite: :boolean])
    overwrite? = Keyword.get(opts, :overwrite, false)

    File.mkdir_p!(@priv_root)

    written_langs = generate_language_tsvs(overwrite?)
    generate_emoji_tsv(overwrite?)
    generate_negators_tsv(overwrite?)

    Mix.shell().info(
      "Wrote #{length(written_langs)} language TSV(s); see #{@priv_root}/."
    )
  end

  ## ── Languages ─────────────────────────────────────────────────────

  defp generate_language_tsvs(overwrite?) do
    Path.wildcard(Path.join([@data_root, "languages", "AFINN-*.json"]))
    |> Enum.reduce([], fn json_path, acc ->
      tag = json_path |> Path.basename(".json") |> String.replace_prefix("AFINN-", "")
      tsv_path = Path.join(@priv_root, "afinn-#{tag}.tsv")

      cond do
        not overwrite? and File.exists?(tsv_path) ->
          Mix.shell().info("  keeping curated #{tsv_path}")
          acc

        true ->
          case json_to_tsv(json_path) do
            :empty ->
              Mix.shell().info("  skipping #{json_path} (upstream JSON is empty)")
              acc

            tsv ->
              File.write!(tsv_path, tsv)
              Mix.shell().info("  wrote #{tsv_path}")
              [tag | acc]
          end
      end
    end)
  end

  defp json_to_tsv(json_path) do
    json_path
    |> File.read!()
    |> Jason.decode!()
    |> Enum.sort()
    |> Enum.map_join("\n", fn {word, score} -> "#{word}\t#{score}" end)
    |> case do
      "" -> :empty
      body -> body <> "\n"
    end
  end

  ## ── Emoji ─────────────────────────────────────────────────────────

  @emoji_csv Path.join(["data", "affin", "emojis", "Emoji_Sentiment_Data_v1.0.csv"])

  # Minimum (positive − negative) / occurrences ratio for an emoji to
  # be considered meaningfully polar. Emoji below this threshold are
  # dropped from the lexicon (treated as neutral).
  @neutral_margin 0.05

  defp generate_emoji_tsv(overwrite?) do
    out = Path.join(@priv_root, "afinn-emoji.tsv")

    if not overwrite? and File.exists?(out) do
      Mix.shell().info("  keeping curated #{out}")
      :ok
    else
      rows =
        @emoji_csv
        |> File.stream!()
        |> Stream.drop(1)
        |> Stream.map(&parse_emoji_row/1)
        |> Stream.reject(&is_nil/1)
        |> Stream.map(fn {emoji, score} -> "#{emoji}\t#{score}" end)
        |> Enum.join("\n")
        |> Kernel.<>("\n")

      File.write!(out, rows)
      Mix.shell().info("  wrote #{out}")
    end
  end

  # Parses one CSV row from Emoji_Sentiment_Data_v1.0.csv. Columns are:
  # Emoji, Unicode codepoint, Occurrences, Position, Negative, Neutral,
  # Positive, Unicode name, Unicode block.
  defp parse_emoji_row(line) do
    case line |> String.trim_trailing() |> String.split(",") do
      [emoji, _cp, occurrences, _position, negative, _neutral, positive | _] ->
        with {occ, ""} <- Integer.parse(occurrences),
             {neg, ""} <- Integer.parse(negative),
             {pos, ""} <- Integer.parse(positive),
             true <- occ > 0 do
          # Map (pos − neg) / occ ∈ [−1, +1] onto AFINN's [-5, +5]
          # integer scale. Drop emoji whose polarity ratio is below
          # `@neutral_margin` — a few-token lean inside thousands of
          # occurrences isn't statistically meaningful (e.g. 😢 has
          # +5/749 ≈ 0.7%, which rounds to neutral). Above the margin
          # we use ceiling-away-from-zero so a meaningful lean of, say,
          # 9% still registers as ±1.
          ratio = (pos - neg) / occ

          cond do
            abs(ratio) < @neutral_margin -> nil
            ratio > 0 -> {emoji, min(5, max(1, ceil_pos(ratio * 5.0)))}
            ratio < 0 -> {emoji, max(-5, min(-1, -ceil_pos(-ratio * 5.0)))}
          end
        else
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp ceil_pos(x) when x > 0, do: trunc(Float.ceil(x))

  ## ── Negators ──────────────────────────────────────────────────────

  @negators_json Path.join(["data", "affin", "languages", "negators", "all.json"])

  defp generate_negators_tsv(overwrite?) do
    out = Path.join(@priv_root, "negators.tsv")

    if not overwrite? and File.exists?(out) do
      Mix.shell().info("  keeping curated #{out}")
      :ok
    else
      rows =
        @negators_json
        |> File.read!()
        |> Jason.decode!()
        |> Enum.sort()
        |> Enum.flat_map(fn {lang, phrases} ->
          phrases
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))
          |> Enum.uniq()
          |> Enum.sort()
          |> Enum.map(&"#{lang}\t#{&1}")
        end)
        |> Enum.join("\n")
        |> Kernel.<>("\n")

      File.write!(out, rows)
      Mix.shell().info("  wrote #{out}")
    end
  end
end
