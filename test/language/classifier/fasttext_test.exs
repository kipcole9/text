defmodule Text.Language.Classifier.FasttextTest do
  use ExUnit.Case, async: true

  alias Text.Language.Classifier.Fasttext
  alias Text.Language.Classifier.Fasttext.{Detection, ModelLoader}

  @model_path Path.expand("../../../priv/lid_176/lid.176.bin", __DIR__)

  setup_all do
    if File.exists?(@model_path) do
      {:ok, model} = ModelLoader.load(@model_path)
      {:ok, model: model}
    else
      :ok
    end
  end

  describe "detect/3 (requires the real lid.176 model)" do
    @describetag :requires_lid_176

    test "returns a Detection struct with language, script, and confidence", %{
      model: model
    } do
      {:ok, %Detection{} = det} = Fasttext.detect("Hello world", model)

      assert det.language == "en"
      assert det.script == :Latn
      assert det.confidence > 0.0
      assert det.confidence <= 1.0001
      assert det.text == "Hello world"
    end

    test "alternatives carry the rest of the top-K", %{model: model} do
      {:ok, det} = Fasttext.detect("Bonjour le monde", model, k: 3)

      assert det.language == "fr"
      assert length(det.alternatives) == 2

      Enum.each(det.alternatives, fn {lang, prob} ->
        assert is_binary(lang)
        assert is_float(prob)
      end)
    end

    test "k=1 produces no alternatives", %{model: model} do
      {:ok, det} = Fasttext.detect("こんにちは", model, k: 1)
      assert det.alternatives == []
    end

    test "Cyrillic text gets script :Cyrl", %{model: model} do
      {:ok, det} = Fasttext.detect("Привет мир", model)
      assert det.language == "ru"
      assert det.script == :Cyrl
    end

    test "Han text gets script :Hani", %{model: model} do
      {:ok, det} = Fasttext.detect("你好世界", model)
      assert det.language == "zh"
      assert det.script == :Hani
    end

    test "empty input still produces a prediction (matches reference)", %{model: model} do
      # fastText's Python wrapper does not error on empty input — it
      # predicts based on the EOS token alone, with low confidence.
      assert {:ok, %Detection{confidence: c}} = Fasttext.detect("   \n\t", model)
      assert c >= 0.0
      assert c < 0.5
    end
  end

  describe "classify/2 (requires the real lid.176 model)" do
    @describetag :requires_lid_176

    test "returns just the language code", %{model: model} do
      assert {:ok, "en"} = Fasttext.classify("Hello world", model)
      assert {:ok, "fr"} = Fasttext.classify("Bonjour le monde", model)
      assert {:ok, "es"} = Fasttext.classify("Hola mundo", model)
      assert {:ok, "ja"} = Fasttext.classify("こんにちは", model)
    end

    test "empty input still produces a language code", %{model: model} do
      # Same as `detect/3` — empty input is not an error, just a
      # low-confidence prediction.
      assert {:ok, lang} = Fasttext.classify("", model)
      assert is_binary(lang)
    end
  end

  describe "to_locale/2 (requires the real lid.176 model)" do
    @describetag :requires_lid_176

    test "expands a detection into a CLDR locale (with :localize)", %{model: model} do
      if Code.ensure_loaded?(Localize) do
        {:ok, det} = Fasttext.detect("你好世界", model)
        {:ok, locale} = Fasttext.to_locale(det)
        assert String.starts_with?(locale, "zh")
      else
        :ok
      end
    end

    test "honours :region override", %{model: model} do
      {:ok, det} = Fasttext.detect("Bonjour le monde", model)
      {:ok, locale} = Fasttext.to_locale(det, region: :CA)
      assert String.contains?(locale, "CA")
    end
  end
end
