defmodule Text.Inflect.Data.En do
  # Imported from http://users.monash.edu/~damian/papers/HTML/Plurals_AppendixA.html
  @tables Enum.to_list(1..26) |> Enum.map(&("a" <> to_string(&1)))

  @data_dir "corpus/inflector/en"

  def data_dir do
    @data_dir
  end

  def data_path do
    Path.join(data_dir(), "en.html")
  end

  def saved_path do
    Path.join("priv/inflection/en", "en.etf")
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

  @additions_file_mapping %{
    "a1" => "irregular_noun.txt",
    "a2" => "uninflected_noun.txt",
    "a3" => "singular_s.txt",
    "a11" => "category_a_as_ae.txt",
    "a12" => "category_a_as_ata.txt",
    "a13" => "category_en_ens_ina.txt",
    "a14" => "category_ex_ices.txt",
    "a15" => "category_ex_exes_ices.txt",
    "a16" => "category_is_ises_ides.txt",
    "a17" => "category_o_os.txt",
    "a18" => "category_o_os_i.txt",
    "a19" => "category_on_a.txt",
    "a20" => "category_um_a.txt",
    "a21" => "category_um_ums_a.txt",
    "a22" => "category_us_uses_i.txt",
    "a23" => "category_us_uses_us.txt",
    "a24" => "category_any_i.txt",
    "a25" => "category_any_im.txt",
    "a26" => "category_general_generals.txt"
  }

  def save_data do
    a1 =
      tables("a1")

    all =
      tables()
      |> Map.put("a1", a1)

    final =
      all
      |> Enum.map(fn
        {"a1" = table, values} ->
          add_values =
            table
            |> get_additions()
            |> Enum.flat_map(fn
              [single, plural] -> [single, plural, plural]
              [single, modern, classical] -> [single, modern, classical]
            end)
          {"a1", values ++ add_values}

        {table, values} ->
          {table, Enum.uniq(values ++ get_additions(table))}
      end)
      |> Map.new

    File.write!(saved_path(), :erlang.term_to_binary(final))
  end

  def additions_file(table) do
    Map.fetch(@additions_file_mapping, table)
  end

  def get_additions(table) do
    case additions_file(table) do
      {:ok, file} ->
        path = Path.join(data_dir(), ["additions/", file])
        parse_file(path)
      _other ->
        []
    end
  end

  def touch_additions_files do
    @additions_file_mapping
    |> Map.values
    |> Enum.map(&Path.join(data_dir(), ["additions/", &1]))
    |> Enum.each(&File.touch/1)
  end

  def parse_file(file) do
    file
    |> File.read!
    |> String.replace(~r/#.*\n/, "")
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&split_and_trim/1)
  end

  defp split_and_trim(string) do
    list =
      string
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)

    case list do
      [word] -> word
      other -> other
    end
  end
end