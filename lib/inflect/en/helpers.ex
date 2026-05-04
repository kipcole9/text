defmodule Text.Inflect.En.Helpers do
  @moduledoc false

  @saved_data_path "priv/inflection/en/en.etf"
  @external_resource @saved_data_path

  @inflections File.read!(@saved_data_path)
               |> :erlang.binary_to_term()

  @irregular @inflections
             |> Map.get("a1")
             |> Enum.chunk_every(3)
             |> Enum.drop(1)
             |> Enum.map(fn
               [word, "(none)", plural] -> {word, [plural, plural]}
               [word, plural, "(none)"] -> {word, [plural, plural]}
               [word, modern, classical] -> {word, [modern, classical]}
               [a, b] -> {a, [b, b]}
             end)
             |> Map.new()

  @pluralize_auxillary_irregular @inflections
                                 |> Map.get("a8")
                                 |> Enum.drop(3)
                                 |> Enum.map(&String.split(&1, " -> "))
                                 |> Enum.map(&List.to_tuple/1)
                                 |> Map.new()

  @pronouns @inflections
            |> Map.get("a5")
            |> Enum.drop(3)
            |> Enum.reject(&(&1 == "->"))
            |> Enum.map(&String.replace(&1, " ->", ""))
            |> Enum.map(fn x ->
              if String.contains?(x, "|"), do: String.split(x, "|"), else: x
            end)
            |> Enum.chunk_every(2)
            |> Map.new(&List.to_tuple/1)

  @personal_possessive @inflections
                       |> Map.get("a7")
                       |> Enum.drop(3)
                       |> Enum.flat_map(&String.split(&1, " "))
                       |> Enum.reject(&(&1 == "->" || &1 == " "))
                       |> Enum.chunk_every(2)
                       |> Enum.map(&List.to_tuple/1)
                       |> Map.new()

  @non_inflecting_nouns @inflections
                        |> Map.take(["a2", "a3"])
                        |> Map.values()
                        |> List.flatten()

  @ambiguous @inflections
             |> Map.get("a4")

  @non_inflecting_verbs @inflections
                        |> Map.get("a9")

  @a_ae_modern @inflections
               |> Map.get("a10")

  @a_ae_classical @inflections
                  |> Map.take(["a10", "a11"])
                  |> Map.values()
                  |> List.flatten()

  @a_ata @inflections
         |> Map.get("a12")

  @en_ina @inflections
          |> Map.get("a13")

  @ex_ices_modern @inflections
                  |> Map.get("a14")

  @ex_ices_classical @inflections
                     |> Map.take(["a14", "a15"])
                     |> Map.values()
                     |> List.flatten()

  @is_ides @inflections
           |> Map.get("a16")

  @o_i @inflections
       |> Map.get("a18")

  @o_words_modern @inflections
                  |> Map.take(["a17", "a18"])
                  |> Map.values()
                  |> List.flatten()

  @o_words_classical @inflections
                     |> Map.get("a17")

  @on_a @inflections
        |> Map.get("a19")

  @um_a_modern @inflections
               |> Map.get("a20")

  @um_a_classical @inflections
                  |> Map.take(["a20", "a21"])
                  |> Map.values()
                  |> List.flatten()

  @us_i @inflections
        |> Map.get("a22")

  @us_us @inflections
         |> Map.get("a23")

  @any_i @inflections
         |> Map.get("a24")

  @any_im @inflections
          |> Map.get("a25")

  @non_inflecting_suffix ["fish", "ois", "sheep", "deer", "pox", "itis"]

  ## ── Reverse (plural → singular) lookup tables for singularization.
  ## Built once at compile time from the same source data.

  @irregular_to_singular_modern for {singular, [modern, _classical]} <- @irregular,
                                    into: %{},
                                    do: {modern, singular}

  @irregular_to_singular_classical for {singular, [_modern, classical]} <- @irregular,
                                       into: %{},
                                       do: {classical, singular}

  # Pronoun entries are stored as `{singular, plural}` tuples (no
  # modern/classical distinction). The same map serves both modes.
  @pronoun_to_singular for {singular, plural} <- @pronouns,
                           into: %{},
                           do: {plural, singular}

  @doc false
  def irregular_singular(word, :modern), do: Map.get(@irregular_to_singular_modern, word)
  def irregular_singular(word, :classical), do: Map.get(@irregular_to_singular_classical, word)

  @doc false
  def pronoun_singular(word), do: Map.get(@pronoun_to_singular, word)

  @doc false
  def known_irregular_plural?(word, :modern),
    do: Map.has_key?(@irregular_to_singular_modern, word)

  def known_irregular_plural?(word, :classical),
    do: Map.has_key?(@irregular_to_singular_classical, word)

  @doc false
  def known_pronoun_plural?(word), do: Map.has_key?(@pronoun_to_singular, word)

  def pluralize_auxillary_irregular do
    @pluralize_auxillary_irregular
  end

  def ambiguous do
    @ambiguous
  end

  def non_inflecting_verbs do
    @non_inflecting_verbs
  end

  def personal_possessive do
    @personal_possessive
  end

  def irregular do
    @irregular
  end

  def pronouns do
    @pronouns
  end

  def non_inflecting_suffix do
    @non_inflecting_suffix
  end

  def o_words_classical do
    @o_words_classical
  end

  def o_words_modern do
    @o_words_modern
  end

  def ex_ices_modern do
    @ex_ices_modern
  end

  def ex_ices_classical do
    @ex_ices_classical
  end

  def um_a_modern do
    @um_a_modern
  end

  def um_a_classical do
    @um_a_classical
  end

  def on_a do
    @on_a
  end

  def a_ae_modern do
    @a_ae_modern
  end

  def a_ae_classical do
    @a_ae_classical
  end

  def en_ina do
    @en_ina
  end

  def a_ata do
    @a_ata
  end

  def is_ides do
    @is_ides
  end

  def us_i do
    @us_i
  end

  def us_us do
    @us_us
  end

  def o_i do
    @o_i
  end

  def any_i do
    @any_i
  end

  def any_im do
    @any_im
  end

  def suffix?(word, suffix) do
    String.ends_with?(word, suffix)
  end

  def replace_suffix(word, suffix, replacement) do
    String.replace_suffix(word, suffix, replacement)
  end

  def non_inflecting_nouns do
    @non_inflecting_nouns
  end

  @vowels ["a", "e", "i", "o", "u"]
  def vowel?(word, pos) do
    String.at(word, pos) in @vowels
  end

  def irregular_noun(word, mode) do
    [modern, classical] = Map.fetch!(@irregular, word)
    if mode == :modern, do: modern, else: classical
  end

  def irregular_verb(word) do
    Map.fetch!(@pluralize_auxillary_irregular, word)
  end

  def pronoun(word, mode) do
    [modern, classical] = Map.fetch!(@pronouns, word)
    if mode == :modern, do: modern, else: classical
  end

  def personal_possessive(word) do
    Map.fetch!(@personal_possessive, word)
  end

  def starts_with_upper?(<<char::utf8, _rest::binary>>) when char in ?A..?Z, do: true
  def starts_with_upper?(_word), do: false
end
