defmodule Text.SimilarityTest do
  use ExUnit.Case, async: true
  doctest Text.Similarity

  alias Text.Similarity

  describe "jaccard/3" do
    test "identical inputs return 1.0" do
      assert Similarity.jaccard("hello", "hello") == 1.0
      assert Similarity.jaccard("", "") == 1.0
      assert Similarity.jaccard(~w[a b c], ~w[a b c]) == 1.0
    end

    test "disjoint inputs return 0.0" do
      assert Similarity.jaccard("abc", "xyz") == 0.0
      assert Similarity.jaccard(~w[red green], ~w[blue yellow]) == 0.0
    end

    test "one empty, one non-empty is 0.0" do
      assert Similarity.jaccard("", "abc") == 0.0
      assert Similarity.jaccard("abc", "") == 0.0
    end

    test "ignores duplicate tokens (set semantics)" do
      # Both bags have the same set of tokens; Jaccard treats them as
      # equal even though one has duplicates.
      assert Similarity.jaccard(~w[a b a b], ~w[a b]) == 1.0
    end

    test "is symmetric" do
      pairs = [{"hello", "world"}, {"night", "nacht"}, {"abc", "abcd"}]

      for {a, b} <- pairs do
        assert Similarity.jaccard(a, b) == Similarity.jaccard(b, a)
      end
    end

    test ":n option controls n-gram size" do
      bi = Similarity.jaccard("night", "nacht", n: 2)
      tri = Similarity.jaccard("night", "nacht", n: 3)
      uni = Similarity.jaccard("night", "nacht", n: 1)

      # All three are well-defined and produce different values.
      assert is_float(bi)
      assert is_float(tri)
      assert is_float(uni)

      # 1-grams: {n,i,g,h,t} ∩ {n,a,c,h,t} = {n,h,t}; ∪ has 7
      assert_in_delta uni, 3 / 7, 1.0e-9
    end
  end

  describe "dice/3" do
    test "identical and disjoint" do
      assert Similarity.dice("hello", "hello") == 1.0
      assert Similarity.dice("abc", "xyz") == 0.0
      assert Similarity.dice("", "") == 1.0
    end

    test "is always ≥ Jaccard for the same inputs" do
      pairs = [{"night", "nacht"}, {"hello", "hallo"}, {"abc", "abcd"}]

      for {a, b} <- pairs do
        assert Similarity.dice(a, b) >= Similarity.jaccard(a, b) - 1.0e-9
      end
    end

    test "matches the algebraic relationship `2j / (1 + j)`" do
      # For the SAME set inputs, dice = 2j/(1+j). Holds when the bag
      # sizes are equal — for unequal sizes the relationship doesn't
      # hold, so use a balanced pair.
      pairs = [{"abc", "abd"}, {"hello", "world"}, {"nacht", "night"}]

      for {a, b} <- pairs do
        j = Similarity.jaccard(a, b)
        d = Similarity.dice(a, b)
        # Sizes of bigram bags from these strings are equal, so the
        # identity holds.
        assert_in_delta d, 2 * j / (1 + j), 1.0e-9
      end
    end
  end

  describe "overlap/3" do
    test "containment yields 1.0" do
      # "night" bigrams are a subset of "nights" bigrams.
      assert Similarity.overlap("night", "nights") == 1.0
      assert Similarity.overlap("nights", "night") == 1.0
    end

    test "identical and disjoint" do
      assert Similarity.overlap("hello", "hello") == 1.0
      assert Similarity.overlap("abc", "xyz") == 0.0
      assert Similarity.overlap("", "") == 1.0
    end

    test "one empty against non-empty is 0.0" do
      assert Similarity.overlap("", "abc") == 0.0
      assert Similarity.overlap("abc", "") == 0.0
    end

    test "is symmetric" do
      pairs = [{"night", "nights"}, {"abc", "xyz"}]

      for {a, b} <- pairs do
        assert Similarity.overlap(a, b) == Similarity.overlap(b, a)
      end
    end
  end

  describe "cosine/3" do
    test "identical and disjoint" do
      assert Similarity.cosine("hello", "hello") == 1.0
      assert Similarity.cosine("abc", "xyz") == 0.0
      assert Similarity.cosine("", "") == 1.0
      assert Similarity.cosine("", "abc") == 0.0
    end

    test "weighted by term repetition (multiset semantics)" do
      # ["a","a","b"] vs ["a","b"]: same set but different bags.
      # Cosine should be < 1.0 because frequencies differ.
      score = Similarity.cosine(~w[a a b], ~w[a b])
      assert score < 1.0
      # Manual: dot=2*1+1*1=3; ||A||=sqrt(4+1)=sqrt(5); ||B||=sqrt(2)
      # cosine = 3 / (sqrt(5)*sqrt(2)) = 3/sqrt(10) ≈ 0.9487
      assert_in_delta score, 3 / :math.sqrt(10), 1.0e-9
    end

    test "scales with shared term frequency" do
      base = ~w[the cat sat on the mat]
      similar = ~w[the dog sat on the log]
      different = ~w[my fish swims very fast]

      assert Similarity.cosine(base, similar) > Similarity.cosine(base, different)
    end

    test "is symmetric" do
      pairs = [{"hello", "world"}, {~w[a b c], ~w[c d e]}]

      for {a, b} <- pairs do
        assert_in_delta Similarity.cosine(a, b), Similarity.cosine(b, a), 1.0e-9
      end
    end
  end

  describe "jaro/2 and jaro_winkler/3" do
    test "are the complement of the corresponding Distance functions" do
      pairs = [{"MARTHA", "MARHTA"}, {"DIXON", "DICKSONX"}, {"DWAYNE", "DUANE"}]

      for {a, b} <- pairs do
        assert_in_delta Similarity.jaro(a, b),
                        1.0 - Text.Distance.jaro(a, b),
                        1.0e-9

        assert_in_delta Similarity.jaro_winkler(a, b),
                        1.0 - Text.Distance.jaro_winkler(a, b),
                        1.0e-9
      end
    end

    test "Jaro-Winkler is at least as high as plain Jaro for shared prefixes" do
      pairs = [{"MARTHA", "MARHTA"}, {"DIXON", "DICKSONX"}]

      for {a, b} <- pairs do
        assert Similarity.jaro_winkler(a, b) >= Similarity.jaro(a, b) - 1.0e-9
      end
    end

    test "identical strings give 1.0 in both" do
      assert Similarity.jaro("hello", "hello") == 1.0
      assert Similarity.jaro_winkler("hello", "hello") == 1.0
    end
  end
end
