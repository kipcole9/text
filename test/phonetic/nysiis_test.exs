defmodule Text.Phonetic.NYSIISTest do
  use ExUnit.Case, async: true
  doctest Text.Phonetic.NYSIIS

  alias Text.Phonetic.NYSIIS

  describe "encode/2" do
    test "first-letter transcoding rules" do
      # MAC → MCC
      assert NYSIIS.encode("MacDonald") == "MCDANALD"
      # KN → NN (then collapsed by duplicate suppression to N)
      assert NYSIIS.encode("Knight") == "NAGT"
      # Standalone K → C
      assert NYSIIS.encode("Kim") == "CAN"
      # PH → FF (collapsed to F)
      assert NYSIIS.encode("Phillips") == "FALAP"
      # PF → FF
      assert NYSIIS.encode("Pfeffer") == "FAFAR"
      # SCH → SSS (collapsed to S)
      assert NYSIIS.encode("Schmidt") == "SNAD"
    end

    test "vowel folding" do
      assert NYSIIS.encode("Robert") == "RABAD"
      assert NYSIIS.encode("Brown") == "BRAON"
    end

    test "Q, Z, M consonant rewrites" do
      # Q is preserved as the first letter (only subsequent Qs map to G).
      assert NYSIIS.encode("Quinn") == "QAN"
      assert NYSIIS.encode("Aquinas") == "AGAN"
      # Z is preserved as the first letter (only subsequent Zs map to S).
      assert NYSIIS.encode("Zimmerman") == "ZANARNAN"
      # Trailing S is removed by post-processing.
      assert NYSIIS.encode("Hertz") == "HART"
      # SH stays as 'S' (H replaced by previous letter S, suppressed as
      # duplicate); trailing S then dropped by post-processing.
      assert NYSIIS.encode("Marsh") == "MAR"
    end

    test "EV → AF" do
      # 'Stevenson': S-T-E-V-E-N-S-O-N. After body walk:
      #   S(first), T, EV→AF, E→A, N, S, O→A, N
      assert NYSIIS.encode("Stevenson") == "STAFANSAN"
    end

    test "trailing letter rewrites" do
      assert NYSIIS.encode("Lee") == "LY"
      assert NYSIIS.encode("Marie") == "MARY"
      assert NYSIIS.encode("Marshall") == "MARSAL"
    end

    test "max_length truncates" do
      assert NYSIIS.encode("MacDonald", max_length: 6) == "MCDANA"
      assert NYSIIS.encode("Watkins", max_length: 6) == "WATCAN"
    end

    test "ASCII-only input" do
      assert NYSIIS.encode("123") == ""
      assert NYSIIS.encode("") == ""
    end

    test "diacritics fold via Text.Clean.unaccent" do
      assert NYSIIS.encode("Müller") == NYSIIS.encode("Mueller") or
               NYSIIS.encode("Müller") == NYSIIS.encode("Muller")
    end
  end

  describe "match?/3" do
    test "matches typical name variants" do
      assert NYSIIS.match?("MacDonald", "McDonald")
      assert NYSIIS.match?("Knuth", "Nuth")
    end

    test "distinguishes genuinely different names" do
      refute NYSIIS.match?("Smith", "Schmidt")
      refute NYSIIS.match?("Robert", "Albert")
    end

    test "empty input never matches" do
      refute NYSIIS.match?("", "anything")
      refute NYSIIS.match?("anything", "")
    end
  end
end
