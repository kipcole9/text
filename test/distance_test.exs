defmodule Text.DistanceTest do
  use ExUnit.Case, async: true
  doctest Text.Distance

  alias Text.Distance

  describe "levenshtein/2" do
    test "canonical reference cases" do
      assert Distance.levenshtein("kitten", "sitting") == 3
      assert Distance.levenshtein("Saturday", "Sunday") == 3
      assert Distance.levenshtein("flaw", "lawn") == 2
      assert Distance.levenshtein("intention", "execution") == 5
    end

    test "identical strings return 0" do
      assert Distance.levenshtein("", "") == 0
      assert Distance.levenshtein("abc", "abc") == 0
      assert Distance.levenshtein("hello world", "hello world") == 0
    end

    test "empty string against non-empty equals other length" do
      assert Distance.levenshtein("", "abc") == 3
      assert Distance.levenshtein("abc", "") == 3
      assert Distance.levenshtein("", "the quick fox") == 13
    end

    test "single substitution" do
      assert Distance.levenshtein("cat", "bat") == 1
      assert Distance.levenshtein("abc", "abd") == 1
    end

    test "single insertion or deletion" do
      assert Distance.levenshtein("abc", "abcd") == 1
      assert Distance.levenshtein("abcd", "abc") == 1
    end

    test "is symmetric" do
      pairs = [{"hello", "world"}, {"the", "quick"}, {"abc", "xyz"}, {"a", "abcdef"}]

      for {a, b} <- pairs do
        assert Distance.levenshtein(a, b) == Distance.levenshtein(b, a)
      end
    end

    test "operates on graphemes, not bytes" do
      # "naïve" is 5 graphemes whether ï is precomposed (U+00EF) or
      # decomposed (U+0069 + U+0308). With grapheme-level analysis the
      # distance to "naive" is 1 in both cases.
      assert Distance.levenshtein("naïve", "naive") == 1
      assert Distance.levenshtein("café", "cafe") == 1
    end

    test "handles CJK and other multibyte scripts at grapheme level" do
      # Each Han character is a single grapheme. "你好" → "你们" is one
      # substitution.
      assert Distance.levenshtein("你好", "你们") == 1
      assert Distance.levenshtein("こんにちは", "こんばんは") == 2
    end
  end

  describe "damerau_levenshtein/2" do
    test "transposition counts as a single edit" do
      assert Distance.damerau_levenshtein("ca", "ac") == 1
      assert Distance.damerau_levenshtein("teh", "the") == 1
      assert Distance.damerau_levenshtein("recieve", "receive") == 1
    end

    test "matches Levenshtein when no transpositions help" do
      assert Distance.damerau_levenshtein("kitten", "sitting") == 3
      assert Distance.damerau_levenshtein("flaw", "lawn") == 2
    end

    test "two non-overlapping transpositions" do
      # "abcdef" → "bacdfe": transpose ab and ef.
      assert Distance.damerau_levenshtein("abcdef", "bacdfe") == 2
    end

    test "identical and empty inputs" do
      assert Distance.damerau_levenshtein("", "") == 0
      assert Distance.damerau_levenshtein("abc", "abc") == 0
      assert Distance.damerau_levenshtein("", "abcd") == 4
      assert Distance.damerau_levenshtein("abcd", "") == 4
    end

    test "is bounded above by Levenshtein" do
      pairs = [
        {"kitten", "sitting"},
        {"abcdef", "bacdfe"},
        {"hello", "ehlol"},
        {"a", "ab"},
        {"the quick fox", "teh quikc fxo"}
      ]

      for {a, b} <- pairs do
        assert Distance.damerau_levenshtein(a, b) <= Distance.levenshtein(a, b)
      end
    end

    test "is symmetric" do
      pairs = [{"abc", "bac"}, {"hello", "ehllo"}, {"the", "hte"}]

      for {a, b} <- pairs do
        assert Distance.damerau_levenshtein(a, b) == Distance.damerau_levenshtein(b, a)
      end
    end
  end

  describe "hamming/2" do
    test "canonical reference cases" do
      assert Distance.hamming("karolin", "kathrin") == 3
      assert Distance.hamming("karolin", "kerstin") == 3
      assert Distance.hamming("1011101", "1001001") == 2
      assert Distance.hamming("2173896", "2233796") == 3
    end

    test "identical strings return 0" do
      assert Distance.hamming("", "") == 0
      assert Distance.hamming("abc", "abc") == 0
    end

    test "raises on length mismatch" do
      assert_raise ArgumentError, ~r/different grapheme length/, fn ->
        Distance.hamming("abc", "abcd")
      end

      assert_raise ArgumentError, ~r/different grapheme length/, fn ->
        Distance.hamming("", "a")
      end
    end

    test "operates on graphemes" do
      # café and cafe are both 4 graphemes; they differ in the last.
      assert Distance.hamming("café", "cafe") == 1
      assert Distance.hamming("你好", "你们") == 1
    end
  end

  describe "jaro/2" do
    test "is 0.0 for identical strings" do
      assert Distance.jaro("", "") == 0.0
      assert Distance.jaro("MARTHA", "MARTHA") == 0.0
      assert Distance.jaro("hello world", "hello world") == 0.0
    end

    test "matches canonical reference values" do
      # Reference similarities from Winkler's original 1990 paper.
      assert_in_delta Distance.jaro("MARTHA", "MARHTA"), 1.0 - 0.9444, 1.0e-3
      assert_in_delta Distance.jaro("DIXON", "DICKSONX"), 1.0 - 0.7666, 1.0e-3
      assert_in_delta Distance.jaro("DWAYNE", "DUANE"), 1.0 - 0.8222, 1.0e-3
    end

    test "is the complement of String.jaro_distance" do
      pairs = [{"abc", "xyz"}, {"hello", "world"}, {"naïve", "naive"}, {"", "abc"}]

      for {a, b} <- pairs do
        assert_in_delta Distance.jaro(a, b), 1.0 - String.jaro_distance(a, b), 1.0e-9
      end
    end

    test "is symmetric" do
      pairs = [{"MARTHA", "MARHTA"}, {"DIXON", "DICKSONX"}]

      for {a, b} <- pairs do
        assert_in_delta Distance.jaro(a, b), Distance.jaro(b, a), 1.0e-9
      end
    end
  end

  describe "jaro_winkler/3" do
    test "is 0.0 for identical strings" do
      assert Distance.jaro_winkler("", "") == 0.0
      assert Distance.jaro_winkler("MARTHA", "MARTHA") == 0.0
    end

    test "matches canonical reference values" do
      # Reference similarities from Winkler 1990, default scale 0.1.
      assert_in_delta Distance.jaro_winkler("MARTHA", "MARHTA"), 1.0 - 0.9611, 1.0e-3
      assert_in_delta Distance.jaro_winkler("DIXON", "DICKSONX"), 1.0 - 0.8133, 1.0e-3
      assert_in_delta Distance.jaro_winkler("DWAYNE", "DUANE"), 1.0 - 0.8400, 1.0e-3
    end

    test "is never larger than the underlying Jaro distance" do
      # Prefix bonus only ever decreases distance.
      pairs = [
        {"MARTHA", "MARHTA"},
        {"DIXON", "DICKSONX"},
        {"DWAYNE", "DUANE"},
        {"abcd", "abce"},
        {"hello", "world"}
      ]

      for {a, b} <- pairs do
        assert Distance.jaro_winkler(a, b) <= Distance.jaro(a, b) + 1.0e-9
      end
    end

    test "with prefix_scale: 0.0 equals plain Jaro distance" do
      pairs = [{"MARTHA", "MARHTA"}, {"DIXON", "DICKSONX"}, {"abc", "abd"}]

      for {a, b} <- pairs do
        assert_in_delta Distance.jaro_winkler(a, b, prefix_scale: 0.0),
                        Distance.jaro(a, b),
                        1.0e-9
      end
    end

    test "honours :max_prefix_length" do
      # Two strings with a 6-grapheme common prefix. Default max is 4,
      # so capping the prefix at 4 vs at 6 produces different results.
      a = "abcdef0"
      b = "abcdef1"

      default = Distance.jaro_winkler(a, b)
      with_six = Distance.jaro_winkler(a, b, max_prefix_length: 6)

      assert with_six < default
    end

    test "is symmetric" do
      pairs = [{"MARTHA", "MARHTA"}, {"DIXON", "DICKSONX"}]

      for {a, b} <- pairs do
        assert_in_delta Distance.jaro_winkler(a, b), Distance.jaro_winkler(b, a), 1.0e-9
      end
    end
  end

  describe "set-based metrics over n-grams" do
    test "identical strings → 0.0 for all set metrics" do
      for fun <- [&Distance.jaccard/2, &Distance.sorensen_dice/2,
                  &Distance.tanimoto/2, &Distance.cosine/2] do
        assert fun.("kitten", "kitten") == 0.0
      end
    end

    test "completely disjoint n-gram sets → 1.0" do
      for fun <- [&Distance.jaccard/2, &Distance.sorensen_dice/2,
                  &Distance.tanimoto/2, &Distance.cosine/2] do
        assert fun.("abcdef", "uvwxyz") == 1.0
      end
    end

    test "tanimoto/2 is an alias for jaccard/2 on binary features" do
      assert Distance.tanimoto("night", "nacht") == Distance.jaccard("night", "nacht")
      assert Distance.tanimoto("knuth", "nuth") == Distance.jaccard("knuth", "nuth")
    end

    test "dice ≤ jaccard for matching strings" do
      # Sørensen–Dice weights matches more heavily than Jaccard, so its
      # distance is always ≤ Jaccard's for the same input pair.
      pairs = [{"night", "nacht"}, {"smith", "smyth"}, {"phonetic", "phonemic"}]

      for {a, b} <- pairs do
        assert Distance.sorensen_dice(a, b) <= Distance.jaccard(a, b),
               "expected dice ≤ jaccard for #{inspect({a, b})}"
      end
    end

    test "n-gram size is configurable" do
      # Trigrams give different (and usually higher) distance than bigrams
      # for short inputs.
      bi = Distance.jaccard("kitten", "sitten")
      tri = Distance.jaccard("kitten", "sitten", n: 3)
      assert bi != tri
    end

    test "is symmetric" do
      pairs = [{"night", "nacht"}, {"abc", "xyz"}, {"hello", "world"}]

      for {a, b} <- pairs, fun <- [&Distance.jaccard/2, &Distance.sorensen_dice/2,
                                    &Distance.cosine/2] do
        assert fun.(a, b) == fun.(b, a),
               "expected symmetry for #{inspect({a, b})}"
      end
    end

    test "shorter than n-gram size still produces a valid result" do
      # When a string is shorter than `n`, we treat the whole string as
      # a single shingle.
      assert Distance.jaccard("ab", "ab", n: 3) == 0.0
      assert Distance.jaccard("ab", "cd", n: 3) == 1.0
    end
  end
end
