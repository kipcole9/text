defmodule Text.SlugTest do
  use ExUnit.Case, async: true
  doctest Text.Slug

  alias Text.Slug

  describe "slugify/2 — Latin input" do
    test "lowercases and joins with hyphen by default" do
      assert Slug.slugify("Hello World") == "hello-world"
      assert Slug.slugify("ALL CAPS") == "all-caps"
    end

    test "drops Latin diacritics" do
      assert Slug.slugify("café résumé") == "cafe-resume"
      assert Slug.slugify("naïve façade") == "naive-facade"
      assert Slug.slugify("über lärm") == "uber-larm"
    end

    test "applies CLDR locale-specific folding" do
      # German ß → ss, dotted Turkish İ → i, Vietnamese Đ → D, etc.
      # All of these come from `unicode_transform`'s Latin-ASCII rules.
      assert Slug.slugify("Straße München") == "strasse-munchen"
      assert Slug.slugify("İstanbul Çanakkale") == "istanbul-canakkale"
      assert Slug.slugify("Đà Nẵng") == "da-nang"
    end

    test "collapses runs of whitespace and punctuation" do
      assert Slug.slugify("  multiple   spaces  ") == "multiple-spaces"
      assert Slug.slugify("dots... and... dashes---") == "dots-and-dashes"
      assert Slug.slugify("a/b\\c|d") == "a-b-c-d"
    end

    test "preserves digits" do
      assert Slug.slugify("Apollo 11") == "apollo-11"
      assert Slug.slugify("v1.2.3") == "v1-2-3"
    end
  end

  describe "slugify/2 — non-Latin input with transliteration (default)" do
    test "Cyrillic" do
      assert Slug.slugify("Привет мир") == "privet-mir"
      assert Slug.slugify("Москва") == "moskva"
    end

    test "Greek" do
      assert Slug.slugify("Καλημέρα") == "kalemera"
    end

    test "Han ideographs (Pinyin transliteration)" do
      assert Slug.slugify("北京") == "beijing"
      assert Slug.slugify("北京 上海") == "beijing-shanghai"
    end

    test "Hiragana" do
      result = Slug.slugify("こんにちは")
      assert result =~ ~r/^[a-z]+$/
      assert byte_size(result) > 0
    end

    test "mixed Latin and non-Latin" do
      assert Slug.slugify("Hello Привет 北京") == "hello-privet-beijing"
    end
  end

  describe "slugify/2 — :transliterate option" do
    test "transliterate: false drops non-Latin characters" do
      assert Slug.slugify("Hello Привет", transliterate: false) == "hello"
      assert Slug.slugify("北京 city", transliterate: false) == "city"
    end

    test "transliterate: false keeps Latin diacritic folding intact" do
      assert Slug.slugify("café 北京", transliterate: false) == "cafe"
    end
  end

  describe "slugify/2 — :separator option" do
    test "underscore separator" do
      assert Slug.slugify("Hello World", separator: "_") == "hello_world"
      assert Slug.slugify("café résumé", separator: "_") == "cafe_resume"
    end

    test "multi-character separator" do
      assert Slug.slugify("Hello World", separator: "--") == "hello--world"
    end

    test "empty separator joins with no separator" do
      assert Slug.slugify("Hello World", separator: "") == "helloworld"
      assert Slug.slugify("café résumé", separator: "") == "caferesume"
    end
  end

  describe "slugify/2 — edge cases" do
    test "empty string" do
      assert Slug.slugify("") == ""
    end

    test "all-whitespace input" do
      assert Slug.slugify("   \t\n  ") == ""
    end

    test "all-punctuation input" do
      assert Slug.slugify("!!!???...") == ""
    end

    test "emoji and symbols are dropped" do
      assert Slug.slugify("🎉 emoji 🎊") == "emoji"
      assert Slug.slugify("hello 👋 world") == "hello-world"
    end

    test "trims leading and trailing separators" do
      assert Slug.slugify("---hello---") == "hello"
      assert Slug.slugify("...word...") == "word"
    end
  end
end
