defmodule Text.CleanTest do
  use ExUnit.Case, async: true
  doctest Text.Clean

  alias Text.Clean

  describe "strip_html/1" do
    test "removes tags" do
      assert Clean.strip_html("<p>Hello</p>") == "Hello"
      assert Clean.strip_html("<a href='x'>link</a>") == "link"
    end

    test "decodes named entities" do
      assert Clean.strip_html("Tom &amp; Jerry") == "Tom & Jerry"
      assert Clean.strip_html("&copy; 2026") == "© 2026"
    end

    test "decodes numeric entities" do
      assert Clean.strip_html("&#65;&#x42;") == "AB"
    end
  end

  describe "collapse_whitespace/1" do
    test "collapses runs and trims" do
      assert Clean.collapse_whitespace("  a   b  ") == "a b"
    end

    test "handles unicode whitespace" do
      assert Clean.collapse_whitespace("a  b") == "a b"
    end
  end

  describe "strip_control/1" do
    test "removes control chars but keeps whitespace" do
      assert Clean.strip_control("a\x07b") == "ab"
      assert Clean.strip_control("a\nb\tc") == "a\nb\tc"
    end
  end

  describe "normalize/2" do
    test "NFC composes" do
      decomposed = "e" <> <<0x0301::utf8>>
      assert Clean.normalize(decomposed, :nfc) == "é"
    end

    test "NFD decomposes" do
      assert Clean.normalize("é", :nfd) == "e" <> <<0x0301::utf8>>
    end
  end

  describe "fix_mojibake/1" do
    test "common smart-quote mojibake" do
      assert Clean.fix_mojibake("itâ€™s") == "it’s"
    end

    test "common accent mojibake" do
      assert Clean.fix_mojibake("cafÃ©") == "café"
    end

    test "leaves clean text alone" do
      assert Clean.fix_mojibake("hello") == "hello"
      assert Clean.fix_mojibake("café") == "café"
    end
  end

  describe "clean/2" do
    test "applies pipeline" do
      assert Clean.clean("<p>Hello,&nbsp;<b>world</b>!</p>") == "Hello, world!"
    end

    test "options can disable steps" do
      assert Clean.clean("<p>x</p>", strip_html: false) =~ "<p>"
    end

    test "all together" do
      input = "  itâ€™s  <em>cool</em>\n\n"
      assert Clean.clean(input) == "it’s cool"
    end

    test "opt-in unaccent folds Latin diacritics" do
      assert Clean.clean("Café Résumé", unaccent: true) == "Cafe Resume"
    end

    test "default leaves accents intact" do
      assert Clean.clean("Café Résumé") == "Café Résumé"
    end
  end

  describe "unaccent/1" do
    test "strips combining-mark diacritics" do
      assert Clean.unaccent("naïve") == "naive"
      assert Clean.unaccent("résumé") == "resume"
      assert Clean.unaccent("piñata") == "pinata"
    end

    test "expands non-decomposable Latin letters" do
      assert Clean.unaccent("Æneid") == "AEneid"
      assert Clean.unaccent("ßeißen") == "sseissen"
      assert Clean.unaccent("Łódź") == "Lodz"
    end

    test "leaves ASCII unchanged" do
      assert Clean.unaccent("hello world") == "hello world"
    end

    test "passes non-Latin scripts through unchanged" do
      assert Clean.unaccent("Привет мир") == "Привет мир"
      assert Clean.unaccent("こんにちは") == "こんにちは"
    end
  end
end
