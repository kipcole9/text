defmodule Text.Phonetic.MetaphoneTest do
  use ExUnit.Case, async: true
  doctest Text.Phonetic.Metaphone

  alias Text.Phonetic.Metaphone

  describe "encode/2 — preprocessing" do
    test "drops silent initial digraphs" do
      assert Metaphone.encode("Knight") == "NT"
      assert Metaphone.encode("Knot") == "NT"
      assert Metaphone.encode("Wright") == "RT"
      assert Metaphone.encode("Pneumonia") == "NMN"
      assert Metaphone.encode("Gnostic") == "NSTK"
      assert Metaphone.encode("Aerial") == "ERL"
    end

    test "remaps initial X to S" do
      assert String.first(Metaphone.encode("Xerox")) == "S"
      assert String.first(Metaphone.encode("Xenon")) == "S"
    end

    test "remaps initial WH to W" do
      assert Metaphone.encode("White") == "WT"
      assert Metaphone.encode("Where") == "WR"
    end

    test "collapses adjacent duplicates except CC" do
      assert Metaphone.encode("Tatto") == Metaphone.encode("Tato")
      assert Metaphone.encode("Hello") == Metaphone.encode("Helo")
    end
  end

  describe "encode/2 — vowel rules" do
    test "vowels are kept only at the start" do
      assert Metaphone.encode("Apple") == "APL"
      assert Metaphone.encode("Ear") == "ER"
      # Mid-word vowels disappear:
      refute String.contains?(Metaphone.encode("paper"), "A")
      refute String.contains?(Metaphone.encode("paper"), "E")
    end
  end

  describe "encode/2 — C rules" do
    test "C before I/E/Y → S" do
      assert Metaphone.encode("Ceiling") == "SLNK"
      assert Metaphone.encode("City") == "ST"
      assert Metaphone.encode("Cycle") == "SKL"
    end

    test "CH → X" do
      assert Metaphone.encode("Charm") == "XRM"
      assert Metaphone.encode("Beach") == "BX"
    end

    test "SCH → SK (Greek loanwords)" do
      assert Metaphone.encode("School") == "SKL"
      assert Metaphone.encode("Schmidt") == "SKMTT"
    end

    test "CK → K (single emission, no double silence)" do
      assert Metaphone.encode("Quick") == "KK"
      assert Metaphone.encode("Tracking") == "TRKNK"
    end

    test "default C → K" do
      assert Metaphone.encode("Cat") == "KT"
      assert Metaphone.encode("Cool") == "KL"
    end
  end

  describe "encode/2 — D, G, T rules" do
    test "DG before I/E/Y → J" do
      assert Metaphone.encode("Bridge") == "BRJ"
      assert Metaphone.encode("Edge") == "EJ"
      assert Metaphone.encode("Judge") == "JJ"
    end

    test "default D → T" do
      assert Metaphone.encode("Dog") == "TK"
      assert Metaphone.encode("Day") == "T"
    end

    test "GH at end → F" do
      assert Metaphone.encode("Cough") == "KF"
      assert Metaphone.encode("Rough") == "RF"
      assert Metaphone.encode("Laugh") == "LF"
    end

    test "GH mid-word is silent" do
      assert Metaphone.encode("Knight") == "NT"
      assert Metaphone.encode("Wright") == "RT"
    end

    test "G silent before final N or NED" do
      assert Metaphone.encode("Sign") == "SN"
      assert Metaphone.encode("Reign") == "RN"
      assert Metaphone.encode("Resigned") == "RSNT"
    end

    test "G before I/E/Y → J" do
      assert Metaphone.encode("Gem") == "JM"
      assert Metaphone.encode("Giant") == "JNT"
      assert Metaphone.encode("Gym") == "JM"
    end

    test "TH → 0 (theta)" do
      assert Metaphone.encode("Thin") == "0N"
      assert Metaphone.encode("Smith") == "SM0"
      assert Metaphone.encode("Smyth") == "SM0"
    end

    test "TIA, TIO → X" do
      assert Metaphone.encode("Nation") == "NXN"
      assert Metaphone.encode("Patio") == "PX"
    end
  end

  describe "encode/2 — letter merging behaviour" do
    test "Phillips, Filips, Phyllips collide" do
      assert Metaphone.encode("Phillips") == "FLPS"
      assert Metaphone.encode("Filips") == "FLPS"
      assert Metaphone.encode("Phyllips") == "FLPS"
    end

    test "PH → F" do
      assert Metaphone.encode("Phone") == "FN"
      assert Metaphone.encode("Photograph") == "FTKRF"
    end

    test "X mid-word → KS" do
      assert Metaphone.encode("Box") == "BKS"
      assert Metaphone.encode("Mix") == "MKS"
    end

    test "Z → S" do
      assert Metaphone.encode("Zip") == "SP"
      assert Metaphone.encode("Buzz") == "BS"
    end

    test "V → F" do
      assert Metaphone.encode("Vine") == "FN"
      assert Metaphone.encode("Have") == "HF"
    end
  end

  describe "encode/2 — edge cases" do
    test "empty input" do
      assert Metaphone.encode("") == ""
    end

    test "single letter" do
      assert Metaphone.encode("A") == "A"
      assert Metaphone.encode("B") == "B"
      assert Metaphone.encode("Z") == "S"
    end

    test "non-letter input is stripped" do
      assert Metaphone.encode("O'Brien") == Metaphone.encode("OBrien")
      assert Metaphone.encode("Smith-Jones") == Metaphone.encode("SmithJones")
    end

    test "case is normalised" do
      assert Metaphone.encode("smith") == Metaphone.encode("SMITH")
      assert Metaphone.encode("smith") == Metaphone.encode("Smith")
    end

    test "all-vowel input keeps just the surviving leading vowel" do
      # AE at start drops the A (silent initial digraph rule), leaving
      # EIOU; only the leading E survives because mid-word vowels drop.
      assert Metaphone.encode("AEIOU") == "E"
    end
  end

  describe "encode/2 — :max_length option" do
    test "truncates to the requested length" do
      assert Metaphone.encode("Photograph", max_length: 4) == "FTKR"
      assert Metaphone.encode("Tracking", max_length: 3) == "TRK"
    end

    test "max_length larger than the code is a no-op" do
      assert Metaphone.encode("Cat", max_length: 10) == "KT"
    end

    test "max_length: 4 mimics Soundex's fixed length" do
      assert String.length(Metaphone.encode("Photograph", max_length: 4)) == 4
    end
  end
end
