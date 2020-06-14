defmodule Text.IrregularPlurals do
  def plurals do
    "test/support/irregular_plurals.csv"
    |> File.read!
    |> String.split("\n")
    |> Enum.map(&String.split(&1, ", "))
    |> Enum.map(fn
      [single, plural] -> [single, String.split(plural, "-")]
      other -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end
end