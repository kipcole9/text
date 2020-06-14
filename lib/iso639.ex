defmodule Text.Iso639 do
  @moduledoc false

  @iso639_file "priv/iso/language-codes-3b2.json"
  @external_resource @iso639_file

  @iso639_two_three Jason.decode!(File.read!(@iso639_file))
  |> Enum.map(fn map -> {Map.get(map, "alpha2"), Map.get(map, "alpha3-b")} end)
  |> Map.new

  def iso639_two_to_three do
    @iso639_two_three
  end

  @iso639_three_two @iso639_two_three
  |> Enum.map(fn {k, v} -> {v, k} end)
  |> Map.new

  def iso639_three_to_two do
    @iso639_three_two
  end

  def to_iso639_three(code) do
    Map.get(iso639_two_to_three(), code)
  end

  def to_iso639_two(code) do
    Map.get(iso639_three_to_two(), code)
  end

end