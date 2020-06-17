defmodule Text.Inflect.Noun.Test do
  use ExUnit.Case

  # Tests defined from the data at
  # https://www.thoughtco.com/irregular-plural-nouns-in-english-1692634
  for [single, plurals] <- Text.Plurals.Helper.irregular_plurals() do
    test "irregular plural for #{single}" do
      case unquote(plurals) do
        [plural] ->
          assert Text.Inflect.En.pluralize_noun(unquote(single), :classical) == plural

        [plural, alternate] ->
          assert Text.Inflect.En.pluralize_noun(unquote(single), :classical) == plural ||
                   Text.Inflect.En.pluralize_noun(unquote(single), :classical) == alternate

        [plural, alternate, other] ->
          assert Text.Inflect.En.pluralize_noun(unquote(single), :classical) == plural ||
                   Text.Inflect.En.pluralize_noun(unquote(single), :classical) == alternate ||
                   Text.Inflect.En.pluralize_noun(unquote(single), :classical) == other
      end
    end
  end

  # Tests defined from the data at
  # http://www.focus.olsztyn.pl/list-of-plural-nouns.html
  for [single, plurals] <- Text.Plurals.Helper.plurals() do
    test "plural noun for #{single}" do
      case unquote(plurals) do
        [plural] ->
          assert Text.Inflect.En.pluralize_noun(unquote(single), :classical) == plural

        [plural, alternate] ->
          assert Text.Inflect.En.pluralize_noun(unquote(single), :classical) == plural ||
                   Text.Inflect.En.pluralize_noun(unquote(single), :classical) == alternate

        [plural, alternate, other] ->
          assert Text.Inflect.En.pluralize_noun(unquote(single), :classical) == plural ||
                   Text.Inflect.En.pluralize_noun(unquote(single), :classical) == alternate ||
                   Text.Inflect.En.pluralize_noun(unquote(single), :classical) == other
      end
    end
  end
end
