defmodule Text.SegmentTest do
  use ExUnit.Case, async: true
  doctest Text.Segment

  alias Text.Segment

  describe "words/2" do
    test "drops punctuation by default" do
      assert Segment.words("Hello, world! How are you?") ==
               ["Hello", "world", "How", "are", "you"]
    end

    test "keeps punctuation with :keep" do
      assert Segment.words("Hello, world!", punctuation: :keep) ==
               ["Hello", ",", "world", "!"]
    end

    test "keeps contractions intact" do
      assert Segment.words("Don't you mean it's?") ==
               ["Don't", "you", "mean", "it's"]
    end

    test "preserves words with diacritics" do
      assert Segment.words("naïve café résumé") == ["naïve", "café", "résumé"]
    end

    test "drops surrounding whitespace and quotes" do
      assert Segment.words("  hello   world  ") == ["hello", "world"]
      assert Segment.words(~s("hello" world)) == ["hello", "world"]
    end

    test "handles empty input" do
      assert Segment.words("") == []
      assert Segment.words("   \t\n  ") == []
      assert Segment.words("!!!") == []
    end

    test "handles digits as words" do
      assert Segment.words("Apollo 11 launched 1969") ==
               ["Apollo", "11", "launched", "1969"]
    end

    test "splits CJK at codepoint boundaries (Unicode default)" do
      # Without locale-specific tailoring, Han ideographs split per character.
      tokens = Segment.words("你好世界")
      assert length(tokens) == 4
      assert Enum.all?(tokens, &(String.length(&1) == 1))
    end
  end

  describe "sentences/2" do
    test "splits on terminal punctuation" do
      assert Segment.sentences("Hello. World! Yes? Indeed.") ==
               ["Hello.", "World!", "Yes?", "Indeed."]
    end

    test "trims trailing whitespace by default" do
      assert Segment.sentences("First sentence.   Second one.") ==
               ["First sentence.", "Second one."]
    end

    test "preserves Unicode trailing whitespace with trim: false" do
      assert Segment.sentences("Hello. World!", trim: false) ==
               ["Hello. ", "World!"]
    end

    test "single sentence input" do
      assert Segment.sentences("just one sentence") == ["just one sentence"]
    end

    test "empty input" do
      assert Segment.sentences("") == []
    end

    test "without a locale, UAX #29 splits on every period followed by a capital" do
      # The default Unicode sentence-break algorithm has no
      # abbreviation awareness — `"Mr."` followed by `"Smith"` looks
      # identical to `"end."` followed by `"Smith"`, so it splits
      # between them.
      assert Segment.sentences("Mr. Smith arrived. He was on time.") ==
               ["Mr.", "Smith arrived.", "He was on time."]
    end

    test "with locale: en, CLDR suppressions keep common abbreviations attached" do
      # `i.e.` and `e.g.` are in CLDR's English suppression list, so
      # they don't trigger sentence breaks. The list is partial — `Mr.`
      # for example is not in it — but it covers the highest-frequency
      # cases.
      assert Segment.sentences(
               "He used i.e. and e.g. in his memo. Then he stopped.",
               locale: "en"
             ) == ["He used i.e. and e.g. in his memo.", "Then he stopped."]
    end

    test "suppressions: false disables the abbreviation list" do
      # With suppressions off, even the abbreviations CLDR knows about
      # produce sentence breaks.
      result =
        Segment.sentences(
          "He used i.e. and e.g. Then he stopped.",
          locale: "en",
          suppressions: false
        )

      assert length(result) > 1
    end
  end

  describe "stream/2" do
    test "streams word breaks" do
      result = Segment.stream("Hello world", break: :word) |> Enum.to_list()
      # Stream preserves whitespace tokens by default; check for content.
      assert "Hello" in result
      assert "world" in result
    end

    test "streams sentence breaks" do
      result =
        Segment.stream("First. Second.", break: :sentence) |> Enum.to_list()

      # First sentence and second sentence are present (with trailing space
      # on the first per Unicode rules).
      assert length(result) == 2
    end

    test "raises when :break is not given" do
      assert_raise KeyError, fn ->
        Segment.stream("hello", []) |> Enum.to_list()
      end
    end
  end

  describe ":locale option accepts atom, string, and Localize.LanguageTag" do
    test "atom locale" do
      assert Segment.words("hello", locale: :en) == ["hello"]
    end

    test "string locale" do
      assert Segment.words("hello", locale: "en") == ["hello"]
    end

    test "BCP-47 string with region" do
      assert Segment.words("hello", locale: "en-US") == ["hello"]
    end

    test "BCP-47 string with script and region" do
      assert Segment.words("hello", locale: "en-Latn-US") == ["hello"]
    end

    if Code.ensure_loaded?(Localize.LanguageTag) do
      @tag :requires_localize
      test "Localize.LanguageTag input" do
        {:ok, tag} = Localize.validate_locale("en-US")
        assert Segment.words("hello", locale: tag) == ["hello"]
      end

      @tag :requires_localize
      test "sentences/2 with LanguageTag uses CLDR suppressions" do
        {:ok, tag} = Localize.validate_locale("en")

        assert Segment.sentences(
                 "He used i.e. and e.g. in his memo. Then he stopped.",
                 locale: tag
               ) == ["He used i.e. and e.g. in his memo.", "Then he stopped."]
      end
    end
  end
end
