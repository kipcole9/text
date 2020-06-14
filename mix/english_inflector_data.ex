defmodule Text.Inflect.Data.En do
  @tables Enum.to_list(1..26) |> Enum.map(&("a" <> to_string(&1)))

  # Imported from http://users.monash.edu/~damian/papers/HTML/Plurals_AppendixA.html
  def data_path do
    "corpus/inflector/en.html"
  end

  def saved_path do
    "priv/inflection//en/en.etf"
  end

  def data do
    File.read!(data_path())
  end

  def parsed do
    Meeseeks.parse(data())
  end

  def tables() do
    import Meeseeks.XPath

    tables =
      parsed()
      |> Meeseeks.all(xpath("//table"))
      |> Enum.map(&Meeseeks.all(&1, xpath("//tt")))
      |> Enum.map(&extract_text/1)

    @tables
    |> Enum.zip(tables)
    |> Map.new
  end

  def tables("a1" = key) do
    import Meeseeks.XPath

    tables =
      parsed()
      |> Meeseeks.all(xpath("//table"))
      |> Enum.map(&Meeseeks.all(&1, xpath("//td")))
      |> Enum.map(&extract_text/1)

    @tables
    |> Enum.zip(tables)
    |> Map.new
    |> Map.get(key)
  end

  def tables(key) when is_binary(key) do
    import Meeseeks.XPath

    tables =
      parsed()
      |> Meeseeks.all(xpath("//table"))
      |> Enum.map(&Meeseeks.all(&1, xpath("//tt")))
      |> Enum.map(&extract_text/1)

    @tables
    |> Enum.zip(tables)
    |> Map.new
    |> Map.get(key)
  end

  def extract_text(tt) do
    Enum.map(tt, &Meeseeks.text(&1))
  end

  def save_data do
    a1 =
      tables("a1")

    all =
      tables()
      |> Map.put("a1", a1)

    File.write!(saved_path(), :erlang.term_to_binary(all))
  end
end