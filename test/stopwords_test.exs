defmodule Text.StopwordsTest do
  use ExUnit.Case, async: true
  doctest Text.Stopwords

  alias Text.Stopwords

  describe "for/1" do
    test "returns a MapSet for a known language atom" do
      set = Stopwords.for(:en)
      assert is_struct(set, MapSet)
      assert MapSet.member?(set, "the")
    end

    test "accepts a string language tag" do
      assert Stopwords.for("en") == Stopwords.for(:en)
    end

    test "accepts a BCP-47 string with region" do
      assert Stopwords.for("en-US") == Stopwords.for(:en)
    end

    test "raises ArgumentError for an unknown language" do
      assert_raise ArgumentError, ~r/no bundled stopword list for :zz/, fn ->
        Stopwords.for(:zz)
      end
    end

    test "covers the major Western European languages" do
      for lang <- [:en, :fr, :de, :es, :it, :pt, :nl] do
        set = Stopwords.for(lang)
        assert MapSet.size(set) > 50, "expected #{lang} to have >50 stopwords"
      end
    end

    test "covers CJK + Korean" do
      for lang <- [:zh, :ja, :ko] do
        set = Stopwords.for(lang)
        assert MapSet.size(set) > 50, "expected #{lang} to have >50 stopwords"
      end
    end

    test "covers Arabic, Russian, Hindi" do
      for lang <- [:ar, :ru, :hi] do
        set = Stopwords.for(lang)
        assert MapSet.size(set) > 50, "expected #{lang} to have >50 stopwords"
      end
    end
  end

  describe "contains?/2" do
    test "returns true for a stopword" do
      assert Stopwords.contains?(:en, "the")
      assert Stopwords.contains?(:fr, "le")
      assert Stopwords.contains?(:de, "der")
    end

    test "returns false for a non-stopword" do
      refute Stopwords.contains?(:en, "rhinoceros")
      refute Stopwords.contains?(:fr, "rhinocéros")
    end

    test "is case-sensitive against the (lowercased) bundled lists" do
      assert Stopwords.contains?(:en, "the")
      refute Stopwords.contains?(:en, "The")
    end
  end

  describe "available_languages/0" do
    test "returns a sorted list of atoms" do
      langs = Stopwords.available_languages()
      assert is_list(langs)
      assert Enum.all?(langs, &is_atom/1)
      assert langs == Enum.sort(langs)
    end

    test "covers at least 50 languages" do
      assert length(Stopwords.available_languages()) >= 50
    end
  end

  describe "available?/1" do
    test "returns true for bundled languages" do
      assert Stopwords.available?(:en)
      assert Stopwords.available?("fr")
    end

    test "returns false for unbundled languages" do
      refute Stopwords.available?(:zz)
      refute Stopwords.available?("xx")
    end
  end

  describe "union/2" do
    test "merges two language sets" do
      set = Stopwords.union(:en, :fr)
      assert MapSet.member?(set, "the")
      assert MapSet.member?(set, "le")
    end

    test "is symmetric" do
      assert Stopwords.union(:en, :fr) == Stopwords.union(:fr, :en)
    end

    test "size is at least the larger of the two inputs" do
      en = Stopwords.for(:en)
      fr = Stopwords.for(:fr)
      union = Stopwords.union(:en, :fr)
      assert MapSet.size(union) >= max(MapSet.size(en), MapSet.size(fr))
    end
  end

  describe "extend/2" do
    test "adds extra tokens to the bundled set" do
      set = Stopwords.extend(:en, ["acme", "lorem"])
      assert MapSet.member?(set, "the")
      assert MapSet.member?(set, "acme")
      assert MapSet.member?(set, "lorem")
    end

    test "accepts a MapSet as extras" do
      set = Stopwords.extend(:en, MapSet.new(["acme"]))
      assert MapSet.member?(set, "acme")
    end

    test "adding empty extras is a no-op" do
      assert Stopwords.extend(:en, []) == Stopwords.for(:en)
    end

    test "does not mutate the bundled set" do
      original = Stopwords.for(:en)
      _ = Stopwords.extend(:en, ["acme"])
      assert Stopwords.for(:en) == original
      refute MapSet.member?(Stopwords.for(:en), "acme")
    end
  end
end
