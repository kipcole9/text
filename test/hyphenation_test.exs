defmodule Text.HyphenationTest do
  use ExUnit.Case, async: true
  doctest Text.Hyphenation

  alias Text.Hyphenation

  describe "points/2" do
    test "common multi-syllable English words" do
      assert Hyphenation.points("hyphenation") == [2, 6]
      assert Hyphenation.points("algorithm") == [2, 4]
      assert Hyphenation.points("photosynthesis") == [3, 5, 8, 11]
    end

    test "applies left_min and right_min" do
      # Default 2/3 for English; relaxed gives more points.
      assert Hyphenation.points("computer") == [3]
      assert Hyphenation.points("computer", right_min: 1) == [3, 6]
    end

    test "very short words yield no points" do
      assert Hyphenation.points("a") == []
      assert Hyphenation.points("cat") == []
      assert Hyphenation.points("the") == []
    end

    test "is case-insensitive" do
      assert Hyphenation.points("Hyphenation") == Hyphenation.points("hyphenation")
      assert Hyphenation.points("HYPHENATION") == Hyphenation.points("hyphenation")
    end

    test "exception list overrides patterns" do
      # "associate" is in DEK's exception list as as-so-ciate
      assert Hyphenation.points("associate") == [2, 4]
    end
  end

  describe "hyphenate/2" do
    test "default '-' hyphen" do
      assert Hyphenation.hyphenate("hyphenation") == "hy-phen-ation"
      assert Hyphenation.hyphenate("photosynthesis") == "pho-to-syn-the-sis"
    end

    test "custom hyphen" do
      assert Hyphenation.hyphenate("hyphenation", hyphen: "·") == "hy·phen·ation"
      assert Hyphenation.hyphenate("hyphenation", hyphen: "­") == "hy­phen­ation"
    end

    test "no break points returns word unchanged" do
      assert Hyphenation.hyphenate("cat") == "cat"
      assert Hyphenation.hyphenate("a") == "a"
    end
  end

  describe "count/2" do
    test "uses lax minima to count syllables" do
      assert Hyphenation.count("hyphenation") == 3
      assert Hyphenation.count("computer") == 3
      assert Hyphenation.count("photosynthesis") == 5
    end

    test "single-syllable words return 1" do
      assert Hyphenation.count("cat") == 1
      assert Hyphenation.count("the") == 1
      assert Hyphenation.count("strength") == 1
    end
  end

  describe "load_language/3" do
    test "raises for unknown language with auto-download disabled" do
      Application.delete_env(:text, :auto_download_hyphenation_data)

      assert_raise ArgumentError, ~r/auto_download_hyphenation_data/, fn ->
        Hyphenation.points("hello", language: :nonexistent_xyz)
      end
    end

    test "loaded language is registered and queryable" do
      tex = Path.join(:code.priv_dir(:text), "hyphenation/hyph-en-us.tex")
      assert :ok == Hyphenation.load_language(:test_lang, tex, left_min: 2, right_min: 3)
      assert Hyphenation.points("hyphenation", language: :test_lang) == [2, 6]
    end
  end

  describe "language input shapes" do
    test "BCP-47 string with US territory resolves to en-us" do
      assert Hyphenation.points("hyphenation", language: "en-US") ==
               Hyphenation.points("hyphenation", language: :en)
    end

    test "atom :en defaults to en-us patterns" do
      assert Hyphenation.points("computer", language: :en) ==
               Hyphenation.points("computer", language: "en-us")
    end

    test "string with underscore separator (Java-style) is normalised" do
      assert Hyphenation.points("hyphenation", language: "en_US") ==
               Hyphenation.points("hyphenation", language: :en)
    end

    test "BCP-47 region falls back to language default when not a known variant" do
      # "en-CA" is not in @hyphenation_tags; falls back to en (→ en-us).
      assert Hyphenation.points("hyphenation", language: "en-CA") ==
               Hyphenation.points("hyphenation", language: :en)
    end
  end

  describe "tag resolution defaults" do
    test "ambiguous languages map to common variants" do
      # We can verify these without auto-download by checking
      # the cached lookup happens against the right tag. The
      # easiest way: load the en-us bundle via these aliases and
      # confirm consistency with :en.
      for alias_input <- [:en, "en", "EN", "en-US", "en_US"] do
        assert Hyphenation.points("hyphenation", language: alias_input) ==
                 Hyphenation.points("hyphenation", language: :en)
      end
    end
  end

  describe "Text.Data integration" do
    setup do
      # Use an isolated cache directory for these tests so they don't
      # touch the user's real ~/.cache/text or share state across runs.
      tmp = Path.join(System.tmp_dir!(), "text-hyph-test-#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp)

      previous = Application.get_env(:text, :data_dir)
      Application.put_env(:text, :data_dir, tmp)

      on_exit(fn ->
        File.rm_rf!(tmp)

        if previous,
          do: Application.put_env(:text, :data_dir, previous),
          else: Application.delete_env(:text, :data_dir)
      end)

      %{tmp: tmp}
    end

    test "language pack is picked up from :data_dir without download", %{tmp: tmp} do
      # Simulate a previously-downloaded German pack by copying the bundled
      # English file under the German filename. We only care that the
      # discovery path works; the actual patterns don't matter here.
      hyph_dir = Path.join(tmp, "hyphenation")
      File.mkdir_p!(hyph_dir)
      bundled = Path.join(:code.priv_dir(:text), "hyphenation/hyph-en-us.tex")
      File.cp!(bundled, Path.join(hyph_dir, "hyph-de-1996.tex"))

      Application.delete_env(:text, :auto_download_hyphenation_data)

      # Should succeed without auto-download being enabled because the
      # file is already in :data_dir.
      assert Hyphenation.points("hyphenation", language: :de) |> is_list()
    end

    test "missing language with auto-download disabled raises with config hint" do
      Application.delete_env(:text, :auto_download_hyphenation_data)

      # Use a unique language atom that isn't pre-cached from another test.
      assert_raise ArgumentError, ~r/auto_download_hyphenation_data/, fn ->
        Hyphenation.points("foo", language: :"missing-#{System.unique_integer([:positive])}")
      end
    end
  end
end
