defmodule Text.Phonetic.DoubleMetaphoneTest do
  use ExUnit.Case, async: true
  doctest Text.Phonetic.DoubleMetaphone

  alias Text.Phonetic.DoubleMetaphone

  describe "encode/2 — common English names" do
    test "Smith family" do
      assert DoubleMetaphone.encode("Smith") == {"SM0", "XMT"}
      assert DoubleMetaphone.encode("Schmidt") == {"XMT", "SMT"}
      assert DoubleMetaphone.encode("Smyth") == {"SM0", "XMT"}
    end

    test "Catherine / Katherine variants" do
      assert DoubleMetaphone.encode("Catherine") == {"K0RN", "KTRN"}
      assert DoubleMetaphone.encode("Katherine") == {"KTRN", "KTRN"}
      # Note: Kathryn contains a K, which marks it slavo-germanic
      # under Philips' definition; consequently TH → T (not 0).
      assert DoubleMetaphone.encode("Kathryn") == {"KTRN", "KTRN"}
    end

    test "silent initial clusters" do
      assert DoubleMetaphone.encode("knight") == {"NT", "NT"}
      assert DoubleMetaphone.encode("night") == {"NT", "NT"}
      assert DoubleMetaphone.encode("wright") == {"RT", "RT"}
      assert DoubleMetaphone.encode("right") == {"RT", "RT"}
      assert DoubleMetaphone.encode("psychic") == {"SXK", "SKK"}
      assert DoubleMetaphone.encode("gnome") == {"NM", "NM"}
    end
  end

  describe "encode/2 — non-Anglo names" do
    test "German SCH-cluster names" do
      assert DoubleMetaphone.encode("Schmidt") == {"XMT", "SMT"}
      assert DoubleMetaphone.encode("Schneider") == {"XNTR", "SNTR"}
      assert DoubleMetaphone.encode("Schwartz") == {"XRTS", "SRTS"}
    end

    test "Greek-root SCH words → SK" do
      assert DoubleMetaphone.encode("school") == {"SKL", "SKL"}
      assert DoubleMetaphone.encode("scholar") == {"SKLR", "SKLR"}
      assert DoubleMetaphone.encode("schema") == {"SKM", "SKM"}
    end

    test "Italian -CIA / -CCIA → X" do
      assert DoubleMetaphone.encode("Garcia") == {"KRX", "KRX"}
      assert DoubleMetaphone.encode("Marcia") == {"MRX", "MRX"}
    end

    test "Spanish/French initial J" do
      assert DoubleMetaphone.encode("Jose") == {"H", "J"}
    end

    test "German W → A primary, F alternate" do
      assert DoubleMetaphone.encode("Wagner") == {"AKNR", "FKNR"}
      assert DoubleMetaphone.encode("Weiner") == {"ANR", "FNR"}
    end

    test "Greek-root CH → K (Christopher, chemistry)" do
      assert DoubleMetaphone.encode("Christopher") == {"KRST", "KRST"}
      assert DoubleMetaphone.encode("Chemistry") == {"KMST", "KMST"}
      assert DoubleMetaphone.encode("Chianti") == {"KNT", "KNT"}
    end
  end

  describe "encode/2 — diacritic and case folding" do
    test "diacritics fold via Text.Clean.unaccent" do
      assert DoubleMetaphone.encode("Müller") == DoubleMetaphone.encode("Muller")
      assert DoubleMetaphone.encode("Café") == DoubleMetaphone.encode("Cafe")
    end

    test "case-insensitive" do
      assert DoubleMetaphone.encode("smith") == DoubleMetaphone.encode("SMITH")
    end
  end

  describe "encode/2 — edge cases" do
    test "empty input" do
      assert DoubleMetaphone.encode("") == {"", ""}
    end

    test "letter-free input" do
      assert DoubleMetaphone.encode("123!@#") == {"", ""}
    end

    test "single letter" do
      assert DoubleMetaphone.encode("A") == {"A", "A"}
      assert DoubleMetaphone.encode("B") == {"P", "P"}
    end

    test ":max_length truncates both codes" do
      {p, a} = DoubleMetaphone.encode("Christopher", max_length: 3)
      assert String.length(p) <= 3
      assert String.length(a) <= 3
    end

    test "max_length: nil disables truncation" do
      {p, a} = DoubleMetaphone.encode("Christopher", max_length: nil)
      assert String.length(p) > 4 or String.length(a) > 4
    end
  end

  describe "match?/3" do
    test "matches across spelling variants" do
      assert DoubleMetaphone.match?("Smith", "Schmidt")
      assert DoubleMetaphone.match?("Catherine", "Katherine")
      assert DoubleMetaphone.match?("Knight", "Night")
      assert DoubleMetaphone.match?("Wright", "Right")
    end

    test "matches across cross-language variants" do
      # Where dual codes pay off — primary OR alternate sharing is enough.
      assert DoubleMetaphone.match?("Smith", "Smyth")
    end

    test "distinguishes different names" do
      refute DoubleMetaphone.match?("Smith", "Brown")
      refute DoubleMetaphone.match?("Catherine", "George")
    end

    test "empty input never matches" do
      refute DoubleMetaphone.match?("", "anything")
      refute DoubleMetaphone.match?("anything", "")
    end
  end
end
