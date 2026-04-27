defmodule Text.LanguageTest do
  use ExUnit.Case, async: true
  doctest Text.Language

  alias Text.Language

  describe "normalize/1" do
    test "passes atom inputs through (lowercased)" do
      assert Language.normalize(:fr) == :fr
      assert Language.normalize(:en) == :en
    end

    test "lowercases atom-cased inputs and strips region from atoms" do
      assert Language.normalize(:"fr-CA") == :fr
      assert Language.normalize(:FR) == :fr
    end

    test "extracts the language subtag from BCP-47 strings" do
      assert Language.normalize("fr") == :fr
      assert Language.normalize("fr-CA") == :fr
      assert Language.normalize("zh-Hans-CN") == :zh
      assert Language.normalize("ZH-Hant-TW") == :zh
    end

    test "tolerates the Java-style underscore separator" do
      assert Language.normalize("fr_CA") == :fr
      assert Language.normalize("zh_Hans_CN") == :zh
    end

    test "case-folds the language subtag" do
      assert Language.normalize("FR") == :fr
      assert Language.normalize("Zh") == :zh
    end
  end

  describe "to_locale_string/1" do
    test "atom inputs become a normalised string" do
      assert Language.to_locale_string(:fr) == "fr"
      assert Language.to_locale_string(:"fr-CA") == "fr-CA"
    end

    test "string inputs are normalised on subtag separators" do
      assert Language.to_locale_string("fr_CA") == "fr-CA"
      assert Language.to_locale_string("zh_Hans_CN") == "zh-Hans-CN"
    end

    test "case-folds only the language subtag" do
      assert Language.to_locale_string("FR") == "fr"
      assert Language.to_locale_string("ZH-Hans-CN") == "zh-Hans-CN"
    end
  end

  if Code.ensure_loaded?(Localize.LanguageTag) do
    describe "Localize.LanguageTag input (when :localize is loaded)" do
      @describetag :requires_localize

      test "normalize/1 extracts the language subtag" do
        {:ok, tag} = Localize.validate_locale("fr-CA")
        assert Language.normalize(tag) == :fr

        {:ok, zh} = Localize.validate_locale("zh-Hant-TW")
        assert Language.normalize(zh) == :zh
      end

      test "to_locale_string/1 returns the canonical id" do
        {:ok, tag} = Localize.validate_locale("fr-CA")
        assert Language.to_locale_string(tag) == "fr-CA"
      end
    end
  end
end
