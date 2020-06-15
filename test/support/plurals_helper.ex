defmodule Text.Plurals.Helper do
  def irregular_plurals do
    parse("test/support/irregular_plurals.csv")
  end

  def plurals do
    parse("test/support/plural_nouns.csv")
  end

  defp parse(path) do
    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.map(&String.split(&1, ", "))
    |> Enum.map(fn
      [single, plural] -> [single, String.split(plural, "-")]
      _other -> nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(&hd/1)
  end
end
