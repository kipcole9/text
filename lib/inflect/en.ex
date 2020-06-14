defmodule Text.Inflect.En do
  @moduledoc """
  Implementation of the paper
  [An Algorithmic Approach to English Pluralization](http://users.monash.edu/~damian/papers/HTML/Plurals.html)
  to inflect english words from and to plural forms.

  """
  @saved_data_path "priv/inflection/en.etf"
  @inflections File.read!(@saved_data_path)
  |> :erlang.binary_to_term

  @doc """
  Pluralize an english word.

  ## Arguments

  * `word` is any english word

  * `mode` is `:modern` or `:classical`

  `mode` when `:classical` applies pluralization
  on latin words used in english but with latin
  suffixes.

  ## Returns

  * a `String` representing the pluralized word

  ## Examples

      iex> Text.Inflect.En.pluralize "Major general"
      "Major generals"

      iex> Text.Inflect.En.pluralize "person"
      "persons"

      iex> Text.Inflect.En.pluralize "fish"
      "fish"

      iex> Text.Inflect.En.pluralize "soliloquy"
      "soliloquies"

  """
  def pluralize(word, mode \\ :modern) do
    is_non_inflecting(word, mode) ||
    is_pronoun(word, mode) ||
    is_irregular(word, mode) ||
    is_irregular_suffix(word, mode) ||
    is_assimilated_classical(word, mode) ||
    is_classical(word, mode) ||
    is_compound_plural(word, mode) ||
    is_ves_plural(word, mode) ||
    is_word_ending_in_y(word, mode) ||
    is_o_suffix(word, mode) ||
    is_general(word, mode) ||
    is_regular(word, mode)
  end

  # Handle words that do not inflect in the plural (such as fish, travois, chassis, nationalities
  # ending in -ese etc. - see Tables A.2 and A.3)...
  #         if suffix(-fish) or suffix(-ois) or suffix(-sheep)
  #         or suffix(-deer) or suffix(-pox) or suffix(-[A-Z].*ese)
  #         or suffix(-itis) or category(-,-),
  #                 return the original noun

  @non_inflecting_suffix ["fish", "ois", "sheep", "deer", "pox", "itis"]

  @non_inflecting_words @inflections
  |> Map.take(["a2", "a3"])
  |> Map.values
  |> List.flatten

  defp is_non_inflecting(word, _mode) when is_binary(word) do
    non_inflecting? =
      Enum.any?(@non_inflecting_suffix, &String.ends_with?(word, &1)) ||
      (String.ends_with?(word, "ese") && starts_with_upper?(word)) ||
      word in @non_inflecting_words

    if non_inflecting?, do: word, else: nil
  end

  defp starts_with_upper?(<< char :: utf8, _rest :: binary >>) when char in ?A..?Z, do: true
  defp starts_with_upper?(_word), do: false

  # Handle pronouns in the nominative, accusative, and dative (see Tables A.5), as well as
  # prepositional phrases...
  #         if the word is a pronoun,
  #                 return the specified plural of the pronoun
  #
  #         if the word is of the form: "<preposition> <pronoun>",
  #                 return "<preposition> <specified plural of pronoun>"

  @pronouns @inflections
  |> Map.get("a5")
  |> Enum.drop(3)
  |> Enum.reject(&(&1 == "->"))
  |> Enum.map(&String.replace_trailing(&1, " ->", ""))
  |> Enum.map(fn x -> if String.contains?(x, "|"), do: String.split(x, "|"), else: x end)
  |> Enum.chunk_every(2)
  |> Map.new(&List.to_tuple/1)

  defp is_pronoun(word, :modern) do
    case Map.get(@pronouns, word) do
      nil -> nil
      [modern, _classical] -> modern
      other -> other
    end
  end

  defp is_pronoun(word, :classical) do
    case Map.get(@pronouns, word) do
      nil -> nil
      [_modern, classical] -> classical
      other -> other
    end
  end

  # Handle standard irregular plurals (mongooses, oxen, etc. - see table A.1)...
  #         if the word has an irregular plural,
  #                 return the specified plural

  @irregular @inflections
  |> Map.get("a1")
  |> Enum.drop(3)
  |> Enum.map(fn x -> if x == "(none)", do: nil, else: x end)
  |> Enum.chunk_every(3)
  |> Enum.map(fn
    [word, nil, plural] -> [word, plural, plural]
    [word, plural, nil] -> [word, plural, plural]
    other -> other
  end)
  |> Map.new(fn [word, english, classical] -> {word, [english, classical]} end)

  defp is_irregular(word, :modern) do
    if plural = Map.get(@irregular, word), do: hd(plural), else: plural
  end

  defp is_irregular(word, :classical) do
    if plural = Map.get(@irregular, word), do: tl(plural), else: plural
  end

  # Handle irregular inflections for common suffixes (synopses, mice and men, etc.)...
  #         if suffix(-man),      return inflection(-man,-men)
  #         if suffix(-[lm]ouse), return inflection(-ouse,-ice)
  #         if suffix(-tooth),    return inflection(-tooth,-teeth)
  #         if suffix(-goose),    return inflection(-goose,-geese)
  #         if suffix(-foot),     return inflection(-foot,-feet)
  #         if suffix(-zoon),     return inflection(-zoon,-zoa)
  #         if suffix(-[csx]is),  return inflection(-is,-es)

  defp is_irregular_suffix(word, _mode) do
    cond do
      String.ends_with?(word, "man") -> String.replace_trailing(word, "man", "men")
      String.ends_with?(word, "louse") -> String.replace_trailing(word, "louse", "lice")
      String.ends_with?(word, "mouse") -> String.replace_trailing(word, "mouse", "mice")
      String.ends_with?(word, "tooth") -> String.replace_trailing(word, "tooth", "teeth")
      String.ends_with?(word, "goose") -> String.replace_trailing(word, "goose", "geese")
      String.ends_with?(word, "foot") -> String.replace_trailing(word, "foot", "feet")
      String.ends_with?(word, "zoon") -> String.replace_trailing(word, "zoon", "zoa")
      String.ends_with?(word, "cis") -> String.replace_trailing(word, "cis", "ces")
      String.ends_with?(word, "sis") -> String.replace_trailing(word, "sis", "ses")
      String.ends_with?(word, "xis") -> String.replace_trailing(word, "xis", "xes")
      true -> nil
    end
  end

  # Handle fully assimilated classical inflections (vertebrae, codices, etc. - see tables A.10,
  # A.14, A.19 and A.20, and tables A.11, A.15 and A.21 if in "classical mode)...
  #         if category(-ex,-ices), return inflection(-ex,-ices)
  #         if category(-um,-a),    return inflection(-um,-a)
  #         if category(-on,-a),    return inflection(-on,-a)
  #         if category(-a,-ae),    return inflection(-a,-ae)

  @assimilated_modern_mode @inflections
  |> Map.take(["a10", "a14", "a19", "a20"])
  |> Map.values
  |> List.flatten

  defp is_assimilated_classical(word, :modern) when word in @assimilated_modern_mode do
    do_assimilated_classical(word)
  end

  @assimilated_classical_mode @inflections
  |> Map.take(["a10", "a14", "a19", "a20", "a11", "a15", "a21"])
  |> Map.values
  |> List.flatten

  defp is_assimilated_classical(word, :classical) when word in @assimilated_classical_mode do
    do_assimilated_classical(word)
  end

  defp is_assimilated_classical(_word, _mode) do
    nil
  end

  defp do_assimilated_classical(word) do
    cond do
      String.ends_with?(word, "ex") -> String.replace_trailing(word, "ex", "ices")
      String.ends_with?(word, "um") -> String.replace_trailing(word, "um", "a")
      String.ends_with?(word, "on") -> String.replace_trailing(word, "on", "a")
      String.ends_with?(word, "a") -> String.replace_trailing(word, "a", "ae")
      true -> nil
    end
  end

  # Handle classical variants of modern inflections (stigmata, soprani, etc. - see tables A.11 to
  # A.13, A.15, A.16, A.18, A.21 to A.25)...
  #         if in classical mode,
  #                 if suffix(-trix),       return inflection(-trix,-trices)
  #                 if suffix(-eau),        return inflection(-eau,-eaux)
  #                 if suffix(-ieu),        return inflection(-ieu,-ieux)
  #                 if suffix(-..[iay]nx),  return inflection(-nx,-nges)
  #                 if category(-en,-ina),  return inflection(-en,-ina)
  #                 if category(-a,-ata),   return inflection(-a,-ata)
  #                 if category(-is,-ides), return inflection(-is,-ides)
  #                 if category(-us,-i),    return inflection(-us,-i)
  #                 if category(-us,-us),   return the original noun
  #                 if category(-o,-i),     return inflection(-o,-i)
  #                 if category(-,-i),      return inflection(-,-i)
  #                 if category(-,-im),     return inflection(-,-im)

  @classical @inflections
  |> Map.take(["a11", "a13", "a15", "a16", "a18", "a21", "a22"])
  |> Map.values
  |> List.flatten

  defp is_classical(word, _mode) when word in @classical do
    cond do
      String.ends_with?(word, "trix") -> String.replace_trailing(word, "trix", "trices")
      String.ends_with?(word, "eau") -> word <> "x"
      String.ends_with?(word, "ieu") -> word <> "x"

      String.ends_with?(word, "inx") -> String.replace_trailing(word, "nx", "nges")
      String.ends_with?(word, "anx") -> String.replace_trailing(word, "nx", "nges")
      String.ends_with?(word, "ynx") -> String.replace_trailing(word, "nx", "nges")

      String.ends_with?(word, "en") -> String.replace_trailing(word, "en", "ina")
      String.ends_with?(word, "a") -> word <> "ta"
      String.ends_with?(word, "is") -> String.replace_trailing(word, "is", "ides")
      String.ends_with?(word, "us") -> word
      String.ends_with?(word, "o") -> String.replace_trailing(word, "o", "i")

      String.ends_with?(word, "im") -> word
      String.ends_with?(word, "i") -> word

      true -> nil
    end
  end

  defp is_classical(_word, _mode) do
    nil
  end

  # The suffixes -ch, -sh, and -ss all take -es in the plural (churches, classes, etc)...
  #         if suffix(-[cs]h), return inflection(-h,-hes)
  #         if suffix(-ss),    return inflection(-ss,-sses)

  defp is_compound_plural(word, _mode) do
    cond do
      String.ends_with?(word, "ch") -> String.replace_trailing(word, "h", "hes")
      String.ends_with?(word, "sh") -> String.replace_trailing(word, "h", "hes")
      String.ends_with?(word, "ss") -> String.replace_trailing(word, "h", "sses")
      true -> nil
    end
  end

  # Certain words ending in -f or -fe take -ves in the plural (lives, wolves, etc)...
  #         if suffix(-[aeo]lf) or suffix(-[^d]eaf) or suffix(-arf),
  #                 return inflection(-f,-ves)
  #
  #         if suffix(-[nlw]ife),
  #                 return inflection(-fe,-ves)
  defp is_ves_plural(word, _mode) do
    cond do
      String.ends_with?(word, "alf") -> String.replace_trailing(word, "f", "ves")
      String.ends_with?(word, "elf") -> String.replace_trailing(word, "f", "ves")
      String.ends_with?(word, "olf") -> String.replace_trailing(word, "f", "ves")
      String.ends_with?(word, "arf") -> String.replace_trailing(word, "f", "ves")

      String.ends_with?(word, "nife") -> String.replace_trailing(word, "fe", "ves")
      String.ends_with?(word, "life") -> String.replace_trailing(word, "fe", "ves")
      String.ends_with?(word, "wife") -> String.replace_trailing(word, "fe", "ves")

      String.ends_with?(word, "eaf") ->
        if String.at(word, -4) == "d", do: nil, else: String.replace_trailing(word, "f", "ves")

      true -> nil
    end
  end

  # Words ending in -y take -ys if preceded by a vowel (storeys, stays, etc.) or when a proper noun
  # (Marys, Tonys, etc.), but -ies if preceded by a consonant (stories, skies, etc.)...
  #         if suffix(-[aeiou]y), return inflection(-y,-ys)
  #         if suffix(-[A-Z].*y), return inflection(-y,-ys)
  #         if suffix(-y),        return inflection(-y,-ies)

  @vowels ["a", "e", "i", "o", "u"]
  defp is_word_ending_in_y(word, _mode) do
    cond do
      String.ends_with?(word, "y") && :erlang.binary_part(word, -2, 1) in @vowels ->
        word <> "s"

      String.ends_with?(word, "y") && starts_with_upper?(word)->
        word <> "s"

      String.ends_with?(word, "y") ->
        String.replace_trailing(word, "y", "ies")

      true -> nil
    end
  end

  # Some words ending in -o take -os (lassos, solos, etc. - see tables A.17 and A.18); the rest
  # take -oes (potatoes, dominoes, etc.) However, words in which the -o is preceded by a vowel
  # always take -os (folios, bamboos)...
  #         if category(-o,-os) or suffix(-[aeiou]o),
  #                 return inflection(-o,-os)
  #
  #         if suffix(-o), return inflection(-o,-oes)

  @o_words @inflections
  |> Map.take(["a17", "a18"])
  |> Map.values
  |> List.flatten

  defp is_o_suffix(word, _mode) do
    is_vowel_and_o? =
      String.ends_with?(word, "o") && :erlang.binary_part(word, -2, 1) in @vowels

    cond do
      (word in @o_words) || is_vowel_and_o? -> word <> "s"
      String.ends_with?(word, "o") -> word <> "es"
      true -> nil
    end
  end

  # Handle plurals of compound words (Postmasters General, Major Generals, mothers-in-law, etc) by
  # recursively applying the entire algorithm to the underlying noun. See Table A.26 for the
  # military suffix -general, which inflects to -generals...
  #         if category(-general,-generals), return inflection(-l,-ls)
  #
  #         if the word is of the form: "<word> general",
  #                 return "<plural of word> general"
  #
  #         if the word is of the form: "<word> <preposition> <words>",
  #                 return "<plural of word> <preposition> <words>"

  @generals @inflections
  |> Map.get("a26")

  for general <- @generals do
    defp is_general(unquote(general) <> suffix, _mode) do
      cond do
        String.ends_with?(suffix, "l") -> unquote(general) <> suffix <> "s"
        true -> nil
      end
    end
  end

  defp is_general(_word, _mode) do
    nil
  end

  # Otherwise, assume that the plural just adds -s (cats, programmes, trees, etc.)...
  #         otherwise, return inflection(-,-s)
  defp is_regular(word, _mode) do
    word <> "s"
  end

end