defmodule Text.IrregularNoun.Test do
  use ExUnit.Case

  for [single, plurals] <- Text.IrregularPlurals.plurals do
    test "plural for #{single}" do
      case unquote(plurals) do
        [plural] ->
          assert Text.Inflect.En.pluralize(unquote(single), :classical) == plural
        [plural, alternate] ->
          assert (Text.Inflect.En.pluralize(unquote(single), :classical) == plural ||
                 Text.Inflect.En.pluralize(unquote(single), :classical) == alternate)
      end
    end
  end
end