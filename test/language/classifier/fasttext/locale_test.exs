defmodule Text.Language.Classifier.Fasttext.LocaleTest do
  use ExUnit.Case, async: true

  alias Text.Language.Classifier.Fasttext.{Detection, Locale}

  defp detection(language, script, text \\ "irrelevant") do
    %Detection{
      language: language,
      confidence: 0.95,
      script: script,
      alternatives: [],
      text: text
    }
  end

  if Code.ensure_loaded?(Localize.LanguageTag) do
    describe "resolve/2 — Localize-backed path (when :localize is loaded)" do
      @describetag :requires_localize

      test "expands en to en-Latn-US via likely-subtags" do
        assert {:ok, "en-Latn-US"} = Locale.resolve(detection("en", :Latn))
      end

      test "expands zh to zh-Hans-CN" do
        assert {:ok, "zh-Hans-CN"} = Locale.resolve(detection("zh", :Hani))
      end

      test "expands ja to ja-Jpan-JP, ignoring the Hira/Kana script signal" do
        assert {:ok, "ja-Jpan-JP"} = Locale.resolve(detection("ja", :Hira))
        assert {:ok, "ja-Jpan-JP"} = Locale.resolve(detection("ja", :Kana))
        assert {:ok, "ja-Jpan-JP"} = Locale.resolve(detection("ja", :Hani))
      end

      test "expands ko to ko-Kore-KR, ignoring the Hang script signal" do
        assert {:ok, "ko-Kore-KR"} = Locale.resolve(detection("ko", :Hang))
      end

      test "honours an explicit :region override" do
        assert {:ok, locale} = Locale.resolve(detection("fr", :Latn), region: :CA)
        assert locale == "fr-Latn-CA"
      end

      test "honours an explicit :script override (sr-Latn vs sr-Cyrl)" do
        assert {:ok, "sr-Latn-RS"} =
                 Locale.resolve(detection("sr", :Cyrl), script: :Latn)

        assert {:ok, "sr-Cyrl-RS"} =
                 Locale.resolve(detection("sr", :Cyrl))
      end

      test "Latin-script Serbian text resolves to sr-Latn" do
        # The script signal (Latn) genuinely disambiguates Serbian.
        assert {:ok, "sr-Latn-RS"} = Locale.resolve(detection("sr", :Latn))
      end
    end
  end

  describe "resolve/2 — fallback path (without :localize)" do
    test "static map produces a sensible locale for common languages" do
      # The fallback table is exercised regardless of whether :localize
      # is loaded — it's exposed for testing via `likely_fallback/0`.
      table = Locale.likely_fallback()
      assert table["en"] == {:Latn, :US}
      assert table["zh"] == {:Hans, :CN}
      assert table["ja"] == {:Jpan, :JP}
      assert table["ko"] == {:Kore, :KR}
      assert table["pt"] == {:Latn, :BR}
    end
  end
end
