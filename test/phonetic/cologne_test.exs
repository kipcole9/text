defmodule Text.Phonetic.CologneTest do
  use ExUnit.Case, async: true
  doctest Text.Phonetic.Cologne

  alias Text.Phonetic.Cologne

  describe "encode/1" do
    test "the canonical Müller / Meyer families collapse" do
      for variant <- ~w(Müller Mueller Muller müller MULLER) do
        assert Cologne.encode(variant) == "657",
               "expected #{inspect(variant)} → 657"
      end

      for variant <- ~w(Meyer Mayer Maier Meier MEYER) do
        assert Cologne.encode(variant) == "67",
               "expected #{inspect(variant)} → 67"
      end
    end

    test "common German names" do
      assert Cologne.encode("Schmidt") == "862"
      assert Cologne.encode("Schmitt") == "862"
      assert Cologne.encode("Breschnew") == "17863"
      assert Cologne.encode("Wikipedia") == "3412"
    end

    test "ß normalises to ss" do
      assert Cologne.encode("Straße") == Cologne.encode("Strasse")
    end

    test "leading vowel is preserved as 0" do
      # 'A' is a vowel → 0; the rule says drop 0 except in first position.
      assert String.starts_with?(Cologne.encode("Albert"), "0")
    end

    test "non-leading vowels are dropped" do
      assert Cologne.encode("Robert") == "7172"
      refute String.contains?(Cologne.encode("Robert"), "0")
    end

    test "X expands to 48 except after C/K/Q" do
      # 'Xerxes' starts with X (not after C/K/Q) → 48
      assert String.starts_with?(Cologne.encode("Xerxes"), "48")
    end

    test "empty / non-letter input returns empty" do
      assert Cologne.encode("") == ""
      assert Cologne.encode("123") == ""
    end
  end

  describe "match?/2" do
    test "matches German spelling variants" do
      assert Cologne.match?("Müller", "Mueller")
      assert Cologne.match?("Meyer", "Maier")
      assert Cologne.match?("Schmidt", "Schmitt")
    end

    test "distinguishes genuinely different names" do
      refute Cologne.match?("Schmidt", "Schneider")
      refute Cologne.match?("Müller", "Schulz")
    end

    test "empty input never matches" do
      refute Cologne.match?("", "anything")
      refute Cologne.match?("anything", "")
    end
  end
end
