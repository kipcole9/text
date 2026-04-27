defmodule Text.Sentiment.Lexicon do
  @moduledoc """
  Lexicon-based sentiment scoring.

  Scores a piece of text by looking up each token in a polarity lexicon
  (a map from `t:String.t/0` to a numeric score), summing the matched
  scores, and optionally adjusting for nearby negators and intensifiers.

  This module is the deterministic engine underneath `Text.Sentiment`.
  Most callers use the higher-level facade; this one is exposed for
  callers who want to plug in a custom lexicon (an industry-specific
  vocabulary, a non-AFINN translation, an emoji lexicon, etc.).

  ### Score semantics

  The default English lexicon (AFINN-165) uses integer scores in
  `-5..+5`, with `0` reserved for neutral terms. Sums of these are
  unbounded; the engine returns the raw sum plus a normalised
  compound score in `[-1.0, +1.0]` derived via the formula

      compound = sum / sqrt(sum² + α)

  with `α = 15` (matching VADER's normalisation). This tames the
  range without saturating too quickly: a sum of `5` yields about
  `+0.79`, a sum of `15` yields about `+0.97`, and a sum of `0`
  yields exactly `0.0`.

  ### Negation and intensifier handling

  Two simple, well-understood adjustments are applied during scoring:

  * **Negation**: when one of the configured negation tokens (`"not"`,
    `"never"`, `"no"`, etc.) appears in the `:negation_window` tokens
    immediately preceding a polarity-bearing token, that token's score
    is multiplied by `-0.74` (the VADER scalar). This is a deliberate
    over-correction that captures the intuition that negation usually
    flips polarity but rarely with full magnitude.

  * **Intensifiers**: when one of the configured intensifier tokens
    (`"very"`, `"extremely"`, etc.) immediately precedes a
    polarity-bearing token, that token's score is multiplied by `1.293`.
    Diminishers (`"slightly"`, `"barely"`) similarly multiply by
    `0.707`. Both scalars come from VADER and are tunable via
    `:intensifier_boost` and `:diminisher_factor`.

  These rules are deliberately limited — they don't handle multi-word
  negation, sarcasm, or domain-specific reversals. For higher-quality
  multilingual sentiment, see the planned Bumblebee-backed adapter.

  """

  alias Text.Segment

  @default_negation_window 3
  @default_negation_scalar -0.74
  @default_intensifier_boost 1.293
  @default_diminisher_factor 0.707
  @compound_alpha 15

  @typedoc "A polarity lexicon: token → numeric score."
  @type lexicon :: %{String.t() => number()}

  @typedoc "The structured result returned by `score/3`."
  @type result :: %{
          sum: float(),
          compound: float(),
          label: :positive | :negative | :neutral,
          tokens: non_neg_integer(),
          matched: non_neg_integer()
        }

  @doc """
  Scores `text` against `lexicon`.

  ### Arguments

  * `text` is a UTF-8 string.

  * `lexicon` is a map from token to numeric score. Tokens are matched
    after the same case-folding the engine applies to `text` (lowercase
    by default; see `:fold_case`).

  ### Options

  * `:tokenizer` — a one-arg function from string to token list.
    Defaults to `&Text.Segment.words/1`.

  * `:fold_case` — `true` (default) lowercases tokens before lookup.
    Set `false` if your lexicon is case-sensitive.

  * `:negators` — a list of tokens that, when seen in the
    `:negation_window` tokens preceding a polarity-bearing token, flip
    its score. Defaults to a small set of English negators
    (`"not"`, `"never"`, `"no"`, `"none"`, `"nobody"`, `"nor"`,
    `"neither"`, `"cannot"`, `"can't"`, `"don't"`, `"isn't"`, `"won't"`,
    `"wasn't"`).

  * `:intensifiers` — a list of tokens that, when immediately
    preceding a polarity-bearing token, boost its score. Defaults to a
    small set of English intensifiers.

  * `:diminishers` — a list of tokens that, when immediately preceding
    a polarity-bearing token, dampen its score. Defaults to a small
    set of English diminishers.

  * `:negation_window` — how many preceding tokens to scan for a
    negator. Defaults to `3`.

  * `:negation_scalar` — multiplier applied when a negator is found.
    Defaults to `-0.74`.

  * `:intensifier_boost` — multiplier applied when an intensifier is
    found. Defaults to `1.293`.

  * `:diminisher_factor` — multiplier applied when a diminisher is
    found. Defaults to `0.707`.

  * `:positive_threshold`, `:negative_threshold` — compound-score
    cutoffs for the `:label` field. Defaults to `0.05` and `-0.05`.

  ### Returns

  A `t:result/0` struct with:

  * `:sum` — the raw sum of matched (and adjusted) lexicon scores.

  * `:compound` — the normalised score in `[-1.0, +1.0]`.

  * `:label` — `:positive`, `:negative`, or `:neutral` based on the
    threshold cutoffs.

  * `:tokens` — total token count after tokenisation.

  * `:matched` — number of tokens that hit the lexicon.

  ### Examples

      iex> lexicon = %{"good" => 3, "bad" => -3, "great" => 4}
      iex> result = Text.Sentiment.Lexicon.score("This is a good day", lexicon)
      iex> result.label
      :positive

      iex> lexicon = %{"good" => 3, "bad" => -3}
      iex> result = Text.Sentiment.Lexicon.score("not a bad outcome", lexicon)
      iex> result.label
      :positive

  """
  @spec score(String.t(), lexicon(), keyword()) :: result()
  def score(text, lexicon, options \\ []) when is_binary(text) and is_map(lexicon) do
    tokenizer = Keyword.get(options, :tokenizer, &Segment.words/1)
    fold_case? = Keyword.get(options, :fold_case, true)

    negators = options |> Keyword.get(:negators, default_negators()) |> MapSet.new()
    intensifiers = options |> Keyword.get(:intensifiers, default_intensifiers()) |> MapSet.new()
    diminishers = options |> Keyword.get(:diminishers, default_diminishers()) |> MapSet.new()

    window = Keyword.get(options, :negation_window, @default_negation_window)
    neg_scalar = Keyword.get(options, :negation_scalar, @default_negation_scalar)
    boost = Keyword.get(options, :intensifier_boost, @default_intensifier_boost)
    diminish = Keyword.get(options, :diminisher_factor, @default_diminisher_factor)

    pos_threshold = Keyword.get(options, :positive_threshold, 0.05)
    neg_threshold = Keyword.get(options, :negative_threshold, -0.05)

    tokens =
      text
      |> tokenizer.()
      |> maybe_fold(fold_case?)

    {sum, matched} =
      tokens
      |> Enum.with_index()
      |> Enum.reduce({0.0, 0}, fn {token, idx}, {sum, matched} ->
        case Map.get(lexicon, token) do
          nil ->
            {sum, matched}

          base when is_number(base) ->
            adjusted =
              base
              |> apply_intensifier(tokens, idx, intensifiers, diminishers, boost, diminish)
              |> apply_negation(tokens, idx, window, negators, neg_scalar)

            {sum + adjusted, matched + 1}
        end
      end)

    compound = sum / :math.sqrt(sum * sum + @compound_alpha)

    label =
      cond do
        compound >= pos_threshold -> :positive
        compound <= neg_threshold -> :negative
        true -> :neutral
      end

    %{
      sum: sum * 1.0,
      compound: compound,
      label: label,
      tokens: length(tokens),
      matched: matched
    }
  end

  # ---- internal: scoring adjustments -------------------------------------

  defp apply_intensifier(base, tokens, idx, intensifiers, diminishers, boost, diminish) do
    case prev_token(tokens, idx) do
      nil ->
        base

      prev ->
        cond do
          MapSet.member?(intensifiers, prev) -> base * boost
          MapSet.member?(diminishers, prev) -> base * diminish
          true -> base
        end
    end
  end

  defp apply_negation(value, tokens, idx, window, negators, scalar) do
    if has_negator_in_window?(tokens, idx, window, negators) do
      value * scalar
    else
      value
    end
  end

  defp has_negator_in_window?(tokens, idx, window, negators) do
    start = max(idx - window, 0)

    tokens
    |> Enum.slice(start, idx - start)
    |> Enum.any?(&MapSet.member?(negators, &1))
  end

  defp prev_token(_tokens, 0), do: nil
  defp prev_token(tokens, idx), do: Enum.at(tokens, idx - 1)

  defp maybe_fold(tokens, false), do: tokens
  defp maybe_fold(tokens, true), do: Enum.map(tokens, &String.downcase/1)

  # ---- defaults ----------------------------------------------------------

  defp default_negators do
    ~w[
      not never no none nobody nor neither
      cannot can't dont don't isn't wasn't aren't weren't
      won't wouldn't shouldn't couldn't doesn't didn't hasn't haven't hadn't
    ]
  end

  defp default_intensifiers do
    ~w[
      absolutely amazingly completely especially extraordinarily
      extremely highly hugely incredibly intensely particularly
      really remarkably so terribly totally tremendously truly
      uber utterly very
    ]
  end

  defp default_diminishers do
    ~w[
      almost barely hardly less merely partly partially
      rather scarcely slightly somewhat sort kind kinda sorta
    ]
  end
end
