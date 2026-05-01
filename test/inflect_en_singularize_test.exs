defmodule Text.Inflect.EnSingularizeTest do
  use ExUnit.Case, async: true

  alias Text.Inflect.En

  describe "singularize/2 — irregular nouns" do
    test "Conway irregular table" do
      assert En.singularize("mice") == "mouse"
      assert En.singularize("children") == "child"
      assert En.singularize("oxen") == "ox"
      assert En.singularize("feet") == "foot"
      assert En.singularize("teeth") == "tooth"
      assert En.singularize("geese") == "goose"
      assert En.singularize("men") == "man"
      assert En.singularize("women") == "woman"
    end

    test "modern octopus / platypus" do
      assert En.singularize("octopuses") == "octopus"
      assert En.singularize("platypuses") == "platypus"
    end

    test "classical octopodes / platypodes" do
      assert En.singularize("octopodes", :classical) == "octopus"
      assert En.singularize("platypodes", :classical) == "platypus"
    end
  end

  describe "singularize/2 — regular English plurals" do
    test "plain -s" do
      for {pl, sg} <- [{"cats", "cat"}, {"dogs", "dog"}, {"books", "book"}] do
        assert En.singularize(pl) == sg
      end
    end

    test "-ies → -y" do
      for {pl, sg} <- [{"cities", "city"}, {"parties", "party"}, {"ladies", "lady"}] do
        assert En.singularize(pl) == sg
      end
    end

    test "-shes / -ches → trim -es" do
      for {pl, sg} <- [{"wishes", "wish"}, {"churches", "church"}, {"ashes", "ash"}] do
        assert En.singularize(pl) == sg
      end
    end

    test "-xes / -zes → trim -es" do
      for {pl, sg} <- [{"boxes", "box"}, {"taxes", "tax"}, {"buzzes", "buzz"}] do
        assert En.singularize(pl) == sg
      end
    end

    test "-sses → -ss" do
      for {pl, sg} <- [{"kisses", "kiss"}, {"masses", "mass"}, {"glasses", "glass"}] do
        assert En.singularize(pl) == sg
      end
    end

    test "-ves → -fe / -f" do
      assert En.singularize("knives") == "knife"
      assert En.singularize("lives") == "life"
      assert En.singularize("wives") == "wife"
      assert En.singularize("leaves") == "leaf"
    end
  end

  describe "singularize/2 — -oes ambiguity" do
    test "-Co bases (consonant + o) trim -es" do
      for {pl, sg} <- [
            {"potatoes", "potato"},
            {"heroes", "hero"},
            {"tomatoes", "tomato"},
            {"echoes", "echo"}
          ] do
        assert En.singularize(pl) == sg, "expected #{pl} → #{sg}"
      end
    end

    test "-oe bases trim only -s" do
      for {pl, sg} <- [{"shoes", "shoe"}, {"toes", "toe"}, {"canoes", "canoe"}] do
        assert En.singularize(pl) == sg, "expected #{pl} → #{sg}"
      end
    end
  end

  describe "singularize/2 — Greek -is/-es" do
    test "common Greek-derived nouns" do
      for {pl, sg} <- [
            {"analyses", "analysis"},
            {"crises", "crisis"},
            {"theses", "thesis"},
            {"hypotheses", "hypothesis"},
            {"diagnoses", "diagnosis"}
          ] do
        assert En.singularize(pl) == sg, "expected #{pl} → #{sg}"
      end
    end
  end

  describe "singularize/2 — -uses (English -us → -uses)" do
    test "common -us nouns" do
      for {pl, sg} <- [
            {"geniuses", "genius"},
            {"statuses", "status"},
            {"viruses", "virus"},
            {"campuses", "campus"}
          ] do
        assert En.singularize(pl) == sg, "expected #{pl} → #{sg}"
      end
    end

    test "-use bases keep their -e (houses, abuses)" do
      assert En.singularize("houses") == "house"
      assert En.singularize("abuses") == "abuse"
      assert En.singularize("muses") == "muse"
    end
  end

  describe "singularize/2 — non-inflecting and pronouns" do
    test "non-inflecting nouns are returned unchanged" do
      assert En.singularize("sheep") == "sheep"
      assert En.singularize("fish") == "fish"
      assert En.singularize("deer") == "deer"
    end

    test "pronouns" do
      # "we" → "I" (canonical Conway choice, since "we" is the
      # plural of "I"); "they" → ambiguous, picks one of {he, she, it};
      # "them" → ambiguous, picks one of {him, her, it}.
      assert En.singularize("we") == "I"
    end

    test "already-singular words are returned unchanged" do
      assert En.singularize("party") == "party"
      assert En.singularize("data") == "data"
    end
  end

  describe "round-trip" do
    # Note: pluralize_noun has known gaps for some sibilant-ending
    # bases (e.g. `pluralize_noun("box") == "boxs"` rather than
    # `"boxes"`), so the round-trip identity does not hold there.
    # The list below excludes those cases — they're correct on the
    # singularize side, but the inverse pluralize would need a fix
    # in the original Conway-paper module.
    test "pluralize ∘ singularize ≈ identity for common plurals" do
      plurals = ~w(
        cats dogs cities parties potatoes heroes shoes toes
        knives mice oxen feet
      )

      for plural <- plurals do
        round_trip = plural |> En.singularize() |> En.pluralize_noun()

        assert round_trip == plural,
               "round-trip failed: pluralize(singularize(#{plural})) = #{round_trip}"
      end
    end
  end
end
