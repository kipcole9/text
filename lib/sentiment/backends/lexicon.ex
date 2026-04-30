defmodule Text.Sentiment.Backends.Lexicon do
  @moduledoc """
  Default sentiment backend — lexicon-based, multilingual via the
  bundled AFINN lexicons.

  This module implements the `Text.Sentiment.Backend` behaviour by
  wrapping `Text.Sentiment.Lexicon.score/3`, picking the bundled
  `Text.Sentiment.Lexicons.AFINN` lexicon that matches the supplied
  `:language` option (with fallback to `:en`).

  Most callers don't reference this module directly — they go through
  `Text.Sentiment.analyze/2` or `label/2`, which dispatch via
  `Text.Sentiment.Backend.resolve/1`.

  """

  @behaviour Text.Sentiment.Backend

  alias Text.Language, as: LanguageTag
  alias Text.Sentiment.{Lexicon, Lexicons}

  @default_language :en

  @impl true
  def analyze(text, options \\ []) when is_binary(text) do
    {language, lexicon, scoring_opts} = resolve_lexicon(options)

    text
    |> Lexicon.score(lexicon, scoring_opts)
    |> Map.put(:language, language)
    |> Map.put(:backend, __MODULE__)
  end

  # ---- internal: option resolution ---------------------------------------

  @scoring_keys [
    :tokenizer,
    :fold_case,
    :negators,
    :intensifiers,
    :diminishers,
    :negation_window,
    :negation_scalar,
    :intensifier_boost,
    :diminisher_factor,
    :positive_threshold,
    :negative_threshold
  ]

  defp resolve_lexicon(options) do
    {scoring_opts, control_opts} = Keyword.split(options, @scoring_keys)

    cond do
      lexicon = Keyword.get(control_opts, :lexicon) ->
        language =
          control_opts
          |> Keyword.get(:language, :custom)
          |> normalize_or_default(:custom)

        {language, lexicon, with_default_negators(scoring_opts, language)}

      true ->
        language =
          control_opts
          |> Keyword.get(:language, @default_language)
          |> normalize_or_default(@default_language)

        fallback =
          control_opts
          |> Keyword.get(:fallback_language, @default_language)
          |> normalize_or_default(@default_language)

        {used, lexicon} = bundled_or_fallback(language, fallback)
        {used, lexicon, with_default_negators(scoring_opts, used)}
    end
  end

  # Inject the per-language negator list as a default for `Lexicon.score/3`
  # unless the caller has supplied their own `:negators` list.
  defp with_default_negators(scoring_opts, language) do
    if Keyword.has_key?(scoring_opts, :negators) do
      scoring_opts
    else
      Keyword.put(scoring_opts, :negators, Lexicons.AFINN.negators(language))
    end
  end

  defp normalize_or_default(input, default) when is_nil(input), do: default

  defp normalize_or_default(input, _default) do
    LanguageTag.normalize(input)
  rescue
    FunctionClauseError -> input
  end

  defp bundled_or_fallback(language, fallback) do
    if language in Lexicons.AFINN.available() do
      {language, Lexicons.AFINN.lexicon(language)}
    else
      {fallback, Lexicons.AFINN.lexicon(fallback)}
    end
  end
end
