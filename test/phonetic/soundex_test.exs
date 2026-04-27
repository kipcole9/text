defmodule Text.Phonetic.SoundexTest do
  use ExUnit.Case, async: true
  doctest Text.Phonetic.Soundex

  alias Text.Phonetic.Soundex

  describe "encode/1 — NARA canonical examples" do
    test "Robert / Rupert collide as R163" do
      assert Soundex.encode("Robert") == "R163"
      assert Soundex.encode("Rupert") == "R163"
    end

    test "Rubin is R150 (single consonant after vowel padding)" do
      assert Soundex.encode("Rubin") == "R150"
    end

    test "Ashcraft is A261 (H acts as a separator collapsing S/C)" do
      assert Soundex.encode("Ashcraft") == "A261"
    end

    test "Ashcroft is A261" do
      assert Soundex.encode("Ashcroft") == "A261"
    end

    test "Tymczak is T522 (4-character cap)" do
      assert Soundex.encode("Tymczak") == "T522"
    end

    test "Pfister is P236 (P/f same-class collapse)" do
      assert Soundex.encode("Pfister") == "P236"
    end

    test "Honeyman is H555" do
      assert Soundex.encode("Honeyman") == "H555"
    end

    test "Lloyd is L300" do
      assert Soundex.encode("Lloyd") == "L300"
    end
  end

  describe "encode/1 — collisions and stability" do
    test "Smith and Smyth share a code" do
      assert Soundex.encode("Smith") == Soundex.encode("Smyth")
    end

    test "case is normalised — output is always uppercase" do
      # Soundex's conventional output is always uppercase — that's the
      # form Oracle's `SOUNDEX`, MySQL's `SOUNDEX`, and the original
      # 1918 patent all produce. Lowercase input gets normalised.
      assert Soundex.encode("smith") == "S530"
      assert Soundex.encode("SMITH") == "S530"
      assert Soundex.encode("Smith") == "S530"
    end
  end

  describe "encode/1 — edge cases" do
    test "empty string" do
      assert Soundex.encode("") == ""
    end

    test "single letter pads with zeros" do
      assert Soundex.encode("A") == "A000"
      assert Soundex.encode("Z") == "Z000"
    end

    test "all-vowel string keeps just the first letter" do
      assert Soundex.encode("Aeiou") == "A000"
    end

    test "non-letter characters are ignored" do
      assert Soundex.encode("O'Brien") == Soundex.encode("OBrien")
      assert Soundex.encode("MacDonald-Smith") == Soundex.encode("MacDonaldSmith")
    end

    test "first letter is always preserved" do
      for name <- ["Xena", "Quinn", "Yousef", "Zelda"] do
        assert String.first(Soundex.encode(name)) == String.first(name)
      end
    end

    test "result is always 4 characters for non-empty input" do
      for name <- ["A", "Ab", "Abc", "Abcd", "Abcdefgh", "Smith", "Tymczak"] do
        assert String.length(Soundex.encode(name)) == 4
      end
    end
  end
end
