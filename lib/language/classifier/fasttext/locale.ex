defmodule Text.Language.Classifier.Fasttext.Locale do
  @moduledoc """
  Resolves a language detection into a CLDR-canonical locale string.

  fastText's `lid.176` reports a bare language code (`"en"`, `"zh"`,
  `"sr"`). For the wider Elixir localisation ecosystem to consume that
  result it generally needs three pieces of information: the language,
  the script (`Hans` vs `Hant`, `Latn` vs `Cyrl`, ...), and the
  territory. This module assembles all three.

  ### Inputs

  * The detection itself, which already carries the language and the
    text-derived script.

  * Optional `:region` and `:script` overrides — typically wired to an
    `Accept-Language` header, an IP geolocation, or a user preference.

  ### Resolution algorithm

  1. Form a candidate BCP-47 tag from `{language, script_override OR
     detection.script, region_override}` — omitting any unspecified
     piece.

  2. If [`localize`](https://hex.pm/packages/localize) is available
     (the optional dep is loaded), call `Localize.validate_locale/1` to
     run CLDR's likely-subtags algorithm. This fills in the remaining
     pieces and produces a canonical locale id like `"zh-Hans-CN"`.

  3. If `localize` is not available, fall back to a hand-rolled map of
     the most common language defaults (e.g. `"en"` → `"en-US"`,
     `"zh"` → `"zh-Hans-CN"`, `"pt"` → `"pt-BR"`). The fallback set is
     deliberately conservative — it covers the languages most users
     will hit but does not pretend to span all 176 fastText labels.

  ### Hans vs Hant

  When the detected language is `"zh"` and the script signal indicates
  `:Hani` (the generic Han atom from ScriptDetector), this module uses
  the language tag's region/script preferences to pick `Hans` or `Hant`.
  With `localize` present the choice flows through CLDR likely-subtags;
  without it, the default for bare `"zh"` is `Hans-CN`.

  """

  alias Text.Language.Classifier.Fasttext.Detection
  alias Text.Language.Classifier.Fasttext.ScriptDetector

  # Conservative fallback when `:localize` is not available. Maps each
  # bare language to a `{script, territory}` likely subtag pair drawn
  # from CLDR's likely-subtags table for that language. Covers the
  # languages users most often hit; for anything else
  # `resolve/2` returns just the language code.
  @likely_fallback %{
    "en" => {:Latn, :US},
    "fr" => {:Latn, :FR},
    "es" => {:Latn, :ES},
    "de" => {:Latn, :DE},
    "it" => {:Latn, :IT},
    "pt" => {:Latn, :BR},
    "nl" => {:Latn, :NL},
    "sv" => {:Latn, :SE},
    "no" => {:Latn, :NO},
    "fi" => {:Latn, :FI},
    "da" => {:Latn, :DK},
    "is" => {:Latn, :IS},
    "pl" => {:Latn, :PL},
    "cs" => {:Latn, :CZ},
    "sk" => {:Latn, :SK},
    "hu" => {:Latn, :HU},
    "ro" => {:Latn, :RO},
    "hr" => {:Latn, :HR},
    "sl" => {:Latn, :SI},
    "et" => {:Latn, :EE},
    "lv" => {:Latn, :LV},
    "lt" => {:Latn, :LT},
    "ca" => {:Latn, :ES},
    "gl" => {:Latn, :ES},
    "eu" => {:Latn, :ES},
    "tr" => {:Latn, :TR},
    "vi" => {:Latn, :VN},
    "id" => {:Latn, :ID},
    "ms" => {:Latn, :MY},
    "tl" => {:Latn, :PH},
    "sw" => {:Latn, :TZ},
    "ru" => {:Cyrl, :RU},
    "uk" => {:Cyrl, :UA},
    "bg" => {:Cyrl, :BG},
    "be" => {:Cyrl, :BY},
    "mk" => {:Cyrl, :MK},
    "sr" => {:Cyrl, :RS},
    "el" => {:Grek, :GR},
    "ar" => {:Arab, :EG},
    "fa" => {:Arab, :IR},
    "ur" => {:Arab, :PK},
    "he" => {:Hebr, :IL},
    "hi" => {:Deva, :IN},
    "mr" => {:Deva, :IN},
    "ne" => {:Deva, :NP},
    "bn" => {:Beng, :BD},
    "ta" => {:Taml, :IN},
    "te" => {:Telu, :IN},
    "kn" => {:Knda, :IN},
    "ml" => {:Mlym, :IN},
    "th" => {:Thai, :TH},
    "lo" => {:Laoo, :LA},
    "my" => {:Mymr, :MM},
    "km" => {:Khmr, :KH},
    "ka" => {:Geor, :GE},
    "hy" => {:Armn, :AM},
    "zh" => {:Hans, :CN},
    "ja" => {:Jpan, :JP},
    "ko" => {:Kore, :KR}
  }

  @doc """
  Resolves a `Detection` into a canonical CLDR locale string.

  ### Arguments

  * `detection` is a `Text.Language.Classifier.Fasttext.Detection`.

  ### Options

  * `:region` — overrides the territory inferred by likely-subtags.
    Useful when the caller has stronger evidence (Accept-Language,
    geolocation, user preference). An ISO 3166-1 alpha-2 code as either
    a binary or atom.

  * `:script` — overrides the script inferred from the text. Useful when
    the caller knows better than codepoint-frequency analysis (e.g. a
    publisher tagging Traditional Chinese content explicitly).

  * `:fallback` — controls behaviour when `:localize` is not available
    or the language is not in the fallback map. Either `:language_only`
    (return just the language code) or `:tag_with_script` (include the
    script subtag if known). Defaults to `:language_only` to match the
    behaviour of fastText's own outputs.

  ### Returns

  * `{:ok, locale_string}` — for example `"en-Latn-US"` or `"zh-Hans-CN"`
    when `:localize` is available, `"en-US"` or `"zh-Hans-CN"` from the
    fallback table, or just `"en"` if the language is unknown to the
    fallback.

  * `{:error, reason}` — when `:localize` is loaded and rejects the
    candidate tag.

  ### Examples

      iex> alias Text.Language.Classifier.Fasttext.Detection
      iex> det = %Detection{language: "en", confidence: 0.9, script: :Latn,
      ...>                  alternatives: [], text: "hello"}
      iex> {:ok, locale} = Text.Language.Classifier.Fasttext.Locale.resolve(det)
      iex> locale =~ "en"
      true

      iex> alias Text.Language.Classifier.Fasttext.Detection
      iex> det = %Detection{language: "zh", confidence: 0.95, script: :Hani,
      ...>                  alternatives: [], text: "你好世界"}
      iex> {:ok, locale} = Text.Language.Classifier.Fasttext.Locale.resolve(det)
      iex> String.starts_with?(locale, "zh")
      true

  """
  @spec resolve(Detection.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def resolve(%Detection{} = detection, options \\ []) do
    region_override = Keyword.get(options, :region)
    script_override = Keyword.get(options, :script)
    fallback = Keyword.get(options, :fallback, :language_only)

    # The script signal is only worth passing through when it
    # disambiguates the locale. For zh / ja / ko the language already
    # implies the script (`:Hani`, `:Hira`, `:Kana`, `:Hang` from
    # `ScriptDetector` are language-derived and add no information). For
    # multi-script languages — Serbian (Latn vs Cyrl), Uzbek, Azerbaijani,
    # etc. — the script does matter and gets forwarded.
    script =
      cond do
        script_override != nil -> script_override
        true -> meaningful_script(detection.script)
      end

    if Code.ensure_loaded?(Localize) do
      resolve_with_localize(detection.language, script, region_override)
    else
      resolve_with_fallback(detection.language, script, region_override, fallback)
    end
  end

  # ---- localize-backed path ----------------------------------------------

  defp resolve_with_localize(language, script, region_override) do
    candidate = compose_tag(language, script, region_override)

    with {:ok, language_tag} <- Localize.validate_locale(candidate),
         {:ok, enriched} <- safe_add_likely_subtags(language_tag) do
      {:ok, canonical_locale_id(enriched)}
    else
      {:error, _} ->
        # The overrides may have produced a tag CLDR rejects. Strip them
        # and resolve from the bare language so callers always get
        # something usable.
        case Localize.validate_locale(language) do
          {:ok, tag} ->
            case safe_add_likely_subtags(tag) do
              {:ok, enriched} -> {:ok, canonical_locale_id(enriched)}
              {:error, _} -> {:ok, language}
            end

          {:error, _} = err ->
            err
        end
    end
  end

  defp safe_add_likely_subtags(tag) do
    {:ok, Localize.LanguageTag.add_likely_subtags!(tag)}
  rescue
    _ -> {:error, :likely_subtags_failed}
  end

  defp canonical_locale_id(%{canonical_locale_id: id}) when is_binary(id) and id != "",
    do: id

  defp canonical_locale_id(%{language: lang, script: script, territory: territory}) do
    [to_string(lang), to_string(script), to_string(territory)]
    |> Enum.reject(&(&1 in [nil, "", "nil"]))
    |> Enum.join("-")
  end

  # ---- pure fallback path ------------------------------------------------

  defp resolve_with_fallback(language, script, region_override, fallback) do
    case Map.fetch(@likely_fallback, language) do
      {:ok, {default_script, default_region}} ->
        chosen_region = region_override || default_region
        chosen_script = script || default_script

        {:ok, [language, to_string(chosen_script), to_string(chosen_region)] |> Enum.join("-")}

      :error ->
        case fallback do
          :tag_with_script when script not in [nil, :Zyyy, :Zzzz] ->
            tag = [language, to_string(script), region_override && to_string(region_override)]
            {:ok, tag |> Enum.reject(&is_nil/1) |> Enum.join("-")}

          _ ->
            if region_override do
              {:ok, "#{language}-#{region_override}"}
            else
              {:ok, language}
            end
        end
    end
  end

  defp compose_tag(language, script, region) do
    [language, script && to_string(script), region && to_string(region)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("-")
  end

  # Scripts that are uniquely determined by the language (Han for `zh`,
  # Hiragana/Katakana for `ja`, Hangul for `ko`, the IS 15924 sentinels
  # for "common" and "unknown") add no information to the locale tag.
  # Folding them to nil lets CLDR's likely-subtags pick the correct full
  # script (`Hans`, `Jpan`, `Kore`).
  defp meaningful_script(:Hani), do: nil
  defp meaningful_script(:Hira), do: nil
  defp meaningful_script(:Kana), do: nil
  defp meaningful_script(:Hang), do: nil
  defp meaningful_script(:Zyyy), do: nil
  defp meaningful_script(:Zzzz), do: nil
  defp meaningful_script(other), do: other

  @doc false
  # Test/introspection helper. Returns the static fallback table.
  def likely_fallback, do: @likely_fallback

  # Re-export ScriptDetector's typespec without forcing callers to alias.
  @type script :: ScriptDetector.script()
end
