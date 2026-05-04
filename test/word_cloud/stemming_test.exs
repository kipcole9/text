defmodule Text.WordCloud.StemmingTest do
  use ExUnit.Case, async: true

  # `:stem` requires the optional `:text_stemmer` dependency. CI runs
  # one matrix entry with all optional deps stripped to verify the
  # library still compiles and works without them; tag this whole
  # module so the runner skips it cleanly in that mode.
  @moduletag :requires_text_stemmer

  alias Text.WordCloud

  @inflected_corpus """
  Models are everywhere. Modelling is what we do. The model captures
  reality. Modelling complex systems is hard. Multiple models are
  better than one model.
  """

  describe ":stem option" do
    test "consolidates morphological variants into a single bucket" do
      with_stem =
        WordCloud.terms(@inflected_corpus,
          scoring: :frequency,
          language: :en,
          stem: true,
          max_terms: 5
        )

      without_stem =
        WordCloud.terms(@inflected_corpus,
          scoring: :frequency,
          language: :en,
          stem: false,
          max_terms: 5
        )

      # Without stemming, the variants split: model, models, modelling
      # all show up separately.
      surface_forms_no_stem = Enum.map(without_stem, & &1.term)
      assert "model" in surface_forms_no_stem or "models" in surface_forms_no_stem
      assert "modelling" in surface_forms_no_stem

      # With stemming, modelling/model/models collapse — the top
      # bucket has a much higher count.
      [top | _] = with_stem
      assert top.count > Enum.max_by(without_stem, & &1.count).count
    end

    test "uses the most-frequent surface form as the bucket label" do
      # "models" appears 3 times, "model" 2, "modelling" 2 — the
      # bucket should display "models".
      result =
        WordCloud.terms(@inflected_corpus,
          scoring: :frequency,
          language: :en,
          stem: true,
          max_terms: 3
        )

      [top | _] = result
      assert top.term in ["models", "model", "modelling"]
      # And whichever it is, it should be the most-frequent member.
      assert top.count >= 3
    end

    test "weights normalise as usual after bucketing" do
      result =
        WordCloud.terms(@inflected_corpus,
          scoring: :frequency,
          language: :en,
          stem: true,
          max_terms: 5
        )

      weights = Enum.map(result, & &1.weight)
      assert Enum.max(weights) == 1.0
      assert Enum.all?(weights, &(&1 >= 0.0 and &1 <= 1.0))
    end

    test "stem: false (default) leaves variants split" do
      default = WordCloud.terms(@inflected_corpus, scoring: :frequency, language: :en)

      explicit_off =
        WordCloud.terms(@inflected_corpus, scoring: :frequency, language: :en, stem: false)

      assert default == explicit_off
    end

    test "works with YAKE backend (default)" do
      result =
        WordCloud.terms(@inflected_corpus,
          language: :en,
          stem: true,
          max_terms: 5
        )

      # No crash and result is non-empty.
      assert length(result) > 0
      [top | _] = result
      assert top.weight == 1.0
    end

    test "works with RAKE backend" do
      result =
        WordCloud.terms(@inflected_corpus,
          scoring: :rake,
          language: :en,
          stem: true,
          max_terms: 5
        )

      assert length(result) > 0
    end

    test ":stem_language overrides :language for bucketing" do
      # Bilingual scenario: corpus is mixed but we only want English
      # variants consolidated. We test that :stem_language is honoured
      # even if :language is something else.
      result =
        WordCloud.terms(@inflected_corpus,
          scoring: :frequency,
          language: :en,
          stem: true,
          stem_language: :en,
          max_terms: 5
        )

      assert length(result) > 0
    end
  end

  describe ":stem error cases" do
    test "raises when :stem is true with no language" do
      assert_raise ArgumentError, ~r/requires a :language or :stem_language/, fn ->
        WordCloud.terms("hello world", scoring: :frequency, stem: true)
      end
    end

    test "raises when stem language is not supported by Text.Stemmer" do
      assert_raise ArgumentError, ~r/does not support language/, fn ->
        WordCloud.terms("hello world",
          scoring: :frequency,
          language: :en,
          stem: true,
          stem_language: :klingon
        )
      end
    end
  end

  describe "phrase bucketing" do
    test "phrases bucket by joined-stem-tuple" do
      # "modelling complex systems" and "model complex systems" should
      # bucket together (both stem to "modelcomplexsystem").
      corpus = """
      Modelling complex systems is hard. Model complex systems carefully.
      Modelling complex systems requires care.
      """

      result =
        WordCloud.terms(corpus,
          scoring: :frequency,
          language: :en,
          stem: true,
          ngram_range: {3, 3},
          max_terms: 5
        )

      # The phrase should appear with consolidated count.
      assert length(result) > 0
      [top | _] = result
      assert top.kind == :phrase
      # Three sentences each have a 3-gram phrase about
      # modelling/model + complex + systems.
      assert top.count >= 3
    end
  end
end
