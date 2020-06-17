defmodule Text.Inflect.En do
  @moduledoc """
  Pluralisation for the English language based on the paper
  [An Algorithmic Approach to English Pluralization](http://users.monash.edu/~damian/papers/HTML/Plurals.html).

  """
  @saved_data_path "priv/inflection/en/en.etf"
  @external_resource @saved_data_path

  @inflections File.read!(@saved_data_path)
               |> :erlang.binary_to_term()

  @doc false
  def inflections do
    @inflections
  end

  @doc """
  Pluralize an english noun.

  ## Arguments

  * `word` is any English noun.

  * `mode` is `:modern` or `:classical`. The
    default is `:modern`.

  ## Returns

  * a `String` representing the pluralized noun

  ## Notes

  `mode` when `:classical` applies pluralization
  on latin words used in english but with latin
  suffixes.

  ## Examples

      iex> Text.Inflect.En.pluralize_noun "Major general"
      "Major generals"

      iex> Text.Inflect.En.pluralize_noun "fish"
      "fish"

      iex> Text.Inflect.En.pluralize_noun "soliloquy"
      "soliloquies"

      iex> Text.Inflect.En.pluralize_noun "genius", :classical
      "genii"

      iex> Text.Inflect.En.pluralize_noun "genius"
      "geniuses"

      iex> Text.Inflect.En.pluralize_noun "platypus", :classical
      "platypodes"

      iex> Text.Inflect.En.pluralize_noun "platypus"
      "platypuses"

  """
  def pluralize_noun(word, mode \\ :modern) do
    is_non_inflecting(word, mode) ||
      is_pronoun(word, mode) ||
      is_irregular_noun(word, mode) ||
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

  defp is_non_inflecting(word, mode) when is_binary(word) do
    cond do
      category?(word, "herd", mode) ->
        word

      category?(word, "nationalities", mode) ->
        word

      category?(word, "-", "-", mode) ->
        word

      true ->
        nil
    end
  end

  # Handle pronouns in the nominative, accusative, and dative (see Tables A.5), as well as
  # prepositional phrases...
  #         if the word is a pronoun,
  #                 return the specified plural of the pronoun
  #
  #         if the word is of the form: "<preposition> <pronoun>",
  #                 return "<preposition> <specified plural of pronoun>"

  defp is_pronoun(word, mode) do
    cond do
      category?(word, "pronoun", mode) ->
        pronoun(word, mode)

      true ->
        nil
    end
  end

  # Handle standard irregular plurals (mongooses, oxen, etc. - see table A.1)...
  #         if the word has an irregular plural,
  #                 return the specified plural

  defp is_irregular_noun(word, mode) do
    cond do
      category?(word, "irregular_noun", mode) ->
        irregular_noun(word, mode)

      true ->
        nil
    end
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
      suffix?(word, "man") ->
        replace_suffix(word, "man", "men")

      suffix?(word, "louse") ->
        replace_suffix(word, "louse", "lice")

      suffix?(word, "mouse") ->
        replace_suffix(word, "mouse", "mice")

      suffix?(word, "tooth") ->
        replace_suffix(word, "tooth", "teeth")

      suffix?(word, "goose") ->
        replace_suffix(word, "goose", "geese")

      suffix?(word, "foot") ->
        replace_suffix(word, "foot", "feet")

      suffix?(word, "zoon") ->
        replace_suffix(word, "zoon", "zoa")

      suffix?(word, "cis") ->
        replace_suffix(word, "cis", "ces")

      suffix?(word, "sis") ->
        replace_suffix(word, "sis", "ses")

      suffix?(word, "xis") ->
        replace_suffix(word, "xis", "xes")

      true ->
        nil
    end
  end

  # Handle fully assimilated classical inflections (vertebrae, codices, etc. - see tables A.10,
  # A.14, A.19 and A.20, and tables A.11, A.15 and A.21 if in "classical mode)...
  #         if category(-ex,-ices), return inflection(-ex,-ices)
  #         if category(-um,-a),    return inflection(-um,-a)
  #         if category(-on,-a),    return inflection(-on,-a)
  #         if category(-a,-ae),    return inflection(-a,-ae)

  defp is_assimilated_classical(word, mode) do
    cond do
      category?(word, "-ex", "-ices", mode) ->
        replace_suffix(word, "ex", "ices")

      category?(word, "-um", "-a", mode) ->
        replace_suffix(word, "um", "a")

      category?(word, "-on", "-a", mode) ->
        replace_suffix(word, "on", "a")

      category?(word, "-a", "-ae", mode) ->
        replace_suffix(word, "a", "ae")

      true ->
        nil
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

  defp is_classical(word, :classical = mode) do
    cond do
      suffix?(word, "trix") ->
        replace_suffix(word, "trix", "trices")

      suffix?(word, "eau") ->
        word <> "x"

      suffix?(word, "ieu") ->
        word <> "x"

      suffix?(word, "inx") ->
        replace_suffix(word, "nx", "nges")

      suffix?(word, "anx") ->
        replace_suffix(word, "nx", "nges")

      suffix?(word, "ynx") ->
        replace_suffix(word, "nx", "nges")

      category?(word, "-en", "-ina", mode) ->
        replace_suffix(word, "en", "ina")

      category?(word, "-a", "-ata", mode) ->
        word <> "ta"

      category?(word, "-is", "-ides", mode) ->
        replace_suffix(word, "is", "ides")

      category?(word, "-us", "-i", mode) ->
        replace_suffix(word, "us", "i")

      category?(word, "-us", "-us", mode) ->
        word

      category?(word, "-o", "-i", mode) ->
        replace_suffix(word, "o", "i")

      category?(word, "-", "-i", mode) ->
        word <> "i"

      category?(word, "-", "-im", mode) ->
        word <> "im"

      true ->
        nil
    end
  end

  defp is_classical(word, :modern = mode) do
    cond do
      category?(word, "-us", "-i", mode) ->
        replace_suffix(word, "us", "uses")

      true ->
        nil
    end
  end

  # The suffixes -ch, -sh, and -ss all take -es in the plural (churches, classes, etc)...
  #         if suffix(-[cs]h), return inflection(-h,-hes)
  #         if suffix(-ss),    return inflection(-ss,-sses)

  defp is_compound_plural(word, _mode) do
    cond do
      suffix?(word, "ch") ->
        replace_suffix(word, "h", "hes")

      suffix?(word, "sh") ->
        replace_suffix(word, "h", "hes")

      suffix?(word, "ss") ->
        replace_suffix(word, "h", "sses")

      true ->
        nil
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
      suffix?(word, "alf") ->
        replace_suffix(word, "f", "ves")

      suffix?(word, "elf") ->
        replace_suffix(word, "f", "ves")

      suffix?(word, "olf") ->
        replace_suffix(word, "f", "ves")

      suffix?(word, "arf") ->
        replace_suffix(word, "f", "ves")

      suffix?(word, "nife") ->
        replace_suffix(word, "fe", "ves")

      suffix?(word, "life") ->
        replace_suffix(word, "fe", "ves")

      suffix?(word, "wife") ->
        replace_suffix(word, "fe", "ves")

      suffix?(word, "eaf") ->
        if String.at(word, -4) == "d", do: nil, else: replace_suffix(word, "f", "ves")

      true ->
        nil
    end
  end

  # Words ending in -y take -ys if preceded by a vowel (storeys, stays, etc.) or when a proper noun
  # (Marys, Tonys, etc.), but -ies if preceded by a consonant (stories, skies, etc.)...
  #         if suffix(-[aeiou]y), return inflection(-y,-ys)
  #         if suffix(-[A-Z].*y), return inflection(-y,-ys)
  #         if suffix(-y),        return inflection(-y,-ies)

  defp is_word_ending_in_y(word, _mode) do
    cond do
      suffix?(word, "y") && vowel?(word, -2) ->
        word <> "s"

      suffix?(word, "y") && starts_with_upper?(word) ->
        word <> "s"

      suffix?(word, "y") ->
        replace_suffix(word, "y", "ies")

      true ->
        nil
    end
  end

  # Some words ending in -o take -os (lassos, solos, etc. - see tables A.17 and A.18); the rest
  # take -oes (potatoes, dominoes, etc.) However, words in which the -o is preceded by a vowel
  # always take -os (folios, bamboos)...
  #         if category(-o,-os) or suffix(-[aeiou]o),
  #                 return inflection(-o,-os)
  #
  #         if suffix(-o), return inflection(-o,-oes)

  defp is_o_suffix(word, :modern = mode) do
    cond do
      category?(word, "-o", "-os", mode) ->
        word <> "s"

      suffix?(word, "o") && vowel?(word, -2) ->
        word <> "s"

      suffix?(word, "o") ->
        word <> "es"

      true ->
        nil
    end
  end

  defp is_o_suffix(word, :classical = mode) do
    cond do
      category?(word, "-o", "-os", mode) ->
        replace_suffix(word, "o", "i")

      suffix?(word, "o") ->
        word <> "es"

      true ->
        nil
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
        suffix?(suffix, "l") -> unquote(general) <> suffix <> "s"
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

  @doc """
  Pluralize an english verb.

  ## Arguments

  * `word` is any English verb.

  ## Returns

  * a `String` representing the pluralized verb

  ## Examples

      iex> Text.Inflect.En.pluralize_verb "has"
      "have"

      iex> Text.Inflect.En.pluralize_verb "catches"
      "catch"

  """
  def pluralize_verb(word) do
    is_non_inflecting_verb(word) ||
    is_irregular_verb(word) ||
    is_third_person_singular(word) ||
    is_third_person_singular_s(word) ||
    is_ambiguous(word) ||

    # All other cases are regular 1st or 2nd person verbs, which don't inflect...
    #         otherwise, return the verb uninflected
    word
  end

  defp is_non_inflecting_verb(word) do
    cond do
      category?(word, "non_inflecting_verb") ->
        word

      true ->
        nil
    end
  end

  # Check if the verb is being used as an auxiliary and has a known irregular inflection (has seen,
  # was going, etc. See Table A.8 for irregular verbs)...
  #         if the word has the form "<auxiliary> <words>"
  #         and <auxiliary> belongs to the category of irregular verbs,
  #                 return "<specified plural of auxiliary> <words>"

  # Handle simple irregular verbs (has, is, etc. - see Table A.8)...
  #         if the word belongs to the category of irregular verbs,
  #                 return the specified plural form

  # Combine the both cases in this simpler execution

  defp is_irregular_verb(word) do
    cond do
      category?(word, "irregular_verb") ->
        irregular_verb(word)

      true ->
        nil
    end
  end

  # Verbs in the regular 3rd person singular lose their -es, -ies, or -oes suffix (she catches -
  # they catch, he tries -> they try, it does -> they do, etc.)...
  #         if suffix(-[cs]hes), return inflection(-hes,-h)
  #         if suffix(-[sx]es),  return inflection(-es,-)
  #         if suffix(-zzes),    return inflection(-es,-)
  #         if suffix(-ies),     return inflection(-ies,-y)
  #         if suffix(-oes),     return inflection(-oes,-o)

  defp is_third_person_singular(word) do
    cond do
      suffix?(word, "ches") ->
        replace_suffix(word, "hes", "h")

      suffix?(word, "shes") ->
        replace_suffix(word, "hes", "h")

      suffix?(word, "ses") ->
        replace_suffix(word, "es", "")

      suffix?(word, "xes") ->
        replace_suffix(word, "es", "")

      suffix?(word, "zzes") ->
        replace_suffix(word, "es", "")

      suffix?(word, "ies") ->
        replace_suffix(word, "ies", "y")

      suffix?(word, "oes") ->
        replace_suffix(word, "oes", "o")

      true ->
        nil
    end
  end

  # Other 3rd person singular verbs ending in -s (but not -ss) also lose their suffix...
  #         if suffix(-[^s]s), return inflection(-s,-)

  defp is_third_person_singular_s(word) do
    cond do
      suffix?(word, "ss") ->
        nil

      suffix?(word, "s") ->
        replace_suffix(word, "s", "")

      true ->
        nil
    end
  end

  # Handle ambiguous simple verbs that might also be nouns (thought, sink, fly, etc. - see Table
  # A.4)...
  #         if the word is in the ambiguous category,
  #                 return the specified plural form

  defp is_ambiguous(word) do
    cond do
      category?(word, "ambiguous") ->
        pluralize_noun(word)

      true ->
        nil
    end
  end

  @doc """
  Pluralize an english adjective.

  ## Arguments

  * `word` is any English adjective.

  ## Returns

  * a `String` representing the pluralized
    adjective

  ## Examples

      iex> Text.Inflect.En.pluralize_adjective "a"
      "some"

      iex> Text.Inflect.En.pluralize_adjective "my"
      "our"

      iex> Text.Inflect.En.pluralize_adjective "child's"
      "children's"

      iex> Text.Inflect.En.pluralize_adjective "Mary's"
      "Marys'"

  """
  def pluralize_adjective(word) do
    is_indefinite_article(word)  ||
    is_possessive_pronoun(word) ||
    is_genetive(word) ||
    # In all other cases no inflection is required...
    #         otherwise, return the adjective uninflected
    word
  end

  # Handle indefinite articles and demonstratives...
  #         if the word is "a" or "an", return "some"
  #         if the word is "this",      return "these"
  #         if the word is "that",      return "those"

  def is_indefinite_article(word) do
    cond do
      word in ["a", "an"] ->
        "some"
      word == "this" ->
        "these"
      word == "that" ->
        "those"
      true ->
        nil
    end
  end

  # Handle possessive pronouns (my -> our, its -> their, etc - see Table A.7)...
  #         if the word is a personal possessive,
  #                 return the specified plural form

  def is_possessive_pronoun(word) do
    cond do
      category?(word, "personal_possessive") ->
        personal_possessive(word)

      true ->
        nil
    end
  end

  # Handle genitives (dog's -> dogs', child's -> children's, Mary's -> Marys', etc). The general
  # rule is: remove the apostrophe and any trailing -s, form the plural of the resultant noun, and
  # then append an apostrophe (or -'s if the pluralized noun doesn't end in -s)...
  #         if suffix(-'s) or suffix(-'),
  #                 if suffix(-'), let the noun <owner> be inflection(-',-)
  #                 otherwise,     let the noun <owner> be inflection(-'s,-)
  #                 let the noun <owners> be the noun plural of <owner>
  #                 if <owners> ends in -s, return "<owners>'"
  #                 otherwise,              return "<owners>'s"
  def is_genetive(word) do
    cond do
      suffix?(word, "'s") ->
        do_genetive(word, "'s")

      suffix?(word, "'") ->
        do_genetive(word, "'")

      true ->
        nil
    end
  end

  def do_genetive(word, suffix) do
    plural_noun =
      word
      |> replace_suffix(suffix, "")
      |> pluralize_noun()

    if suffix?(plural_noun, "s") do
      plural_noun <> "'"
    else
      plural_noun <> "'s"
    end
  end

  ##########################################

  # Category definitions

  ##########################################

  @non_inflecting_nouns @inflections
                        |> Map.take(["a2", "a3"])
                        |> Map.values()
                        |> List.flatten()

  @ambiguous @inflections
    |> Map.get("a4")

  @personal_possessive @inflections
  |> Map.get("a7")
  |> Enum.drop(3)
  |> Enum.flat_map(&String.split(&1, " "))
  |> Enum.reject(&(&1 == "->" || &1 == " "))
  |> Enum.chunk_every(2)
  |> Enum.map(&List.to_tuple/1)
  |> Map.new

  @pluralize_auxillary_irregular @inflections
  |> Map.get("a8")
  |> Enum.drop(3)
  |> Enum.map(&String.split(&1, " -> "))
  |> Enum.map(&List.to_tuple/1)
  |> Map.new

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

  @pronouns @inflections
            |> Map.get("a5")
            |> Enum.drop(3)
            |> Enum.reject(&(&1 == "->"))
            |> Enum.map(&String.replace(&1, " ->", ""))
            |> Enum.map(fn x -> if String.contains?(x, "|"), do: String.split(x, "|"), else: x end)
            |> Enum.chunk_every(2)
            |> Map.new(&List.to_tuple/1)

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

  @doc false
  def category?(word, "irregular_verb") do
    Map.has_key?(@pluralize_auxillary_irregular, word)
  end

  def category?(word, "ambiguous") do
   word in @ambiguous
  end

  def category?(word, "non_inflecting_verb") do
    word in @non_inflecting_verbs
  end

  def category?(word, "personal_possessive") do
    Map.has_key?(@personal_possessive, word)
  end

  @doc false
  def category?(word, "irregular_noun", _mode) do
    Map.has_key?(@irregular, word)
  end

  def category?(word, "pronoun", _mode) do
    Map.has_key?(@pronouns, word)
  end

  @non_inflecting_suffix ["fish", "ois", "sheep", "deer", "pox", "itis"]
  def category?(word, "herd", _mode) do
    Enum.any?(@non_inflecting_suffix, &suffix?(word, &1))
  end

  def category?(word, "nationalities", _mode) do
    suffix?(word, "ese") && starts_with_upper?(word)
  end

  @doc false
  def category?(word, "-", "-", _) do
    word in @non_inflecting_nouns
  end

  def category?(word, "-o", "-os", :classical) do
    word in @o_words_classical
  end

  def category?(word, "-o", "-os", :modern) do
    word in @o_words_modern
  end

  def category?(word, "-ex", "-ices", :modern) do
    word in @ex_ices_modern
  end

  def category?(word, "-ex", "-ices", :classical) do
    word in @ex_ices_classical
  end

  def category?(word, "-um", "-a", :modern) do
    word in @um_a_modern
  end

  def category?(word, "-um", "-a", :classical) do
    word in @um_a_classical
  end

  def category?(word, "-on", "-a", :modern) do
    word in @on_a
  end

  def category?(word, "-on", "-a", :classical) do
    word in @on_a
  end

  def category?(word, "-a", "-ae", :modern) do
    word in @a_ae_modern
  end

  def category?(word, "-a", "-ae", :classical) do
    word in @a_ae_classical
  end

  def category?(word, "-en", "-ina", :classical) do
    word in @en_ina
  end

  def category?(word, "-a", "-ata", _mode) do
    word in @a_ata
  end

  def category?(word, "-is", "-ides", _mode) do
    word in @is_ides
  end

  def category?(word, "-us", "-i", _mode) do
    word in @us_i
  end

  def category?(word, "-us", "-us", _mode) do
    word in @us_us
  end

  def category?(word, "-o", "-i", _mode) do
    word in @o_i
  end

  def category?(word, "-", "-i", _mode) do
    word in @any_i
  end

  def category?(word, "-", "-im", _mode) do
    word in @any_im
  end

  ##########################################

  # Helpers

  ##########################################

  defp suffix?(word, suffix) do
    String.ends_with?(word, suffix)
  end

  defp replace_suffix(word, suffix, replacement) do
    String.replace_trailing(word, suffix, replacement)
  end

  @vowels ["a", "e", "i", "o", "u"]
  defp vowel?(word, pos)  do
    String.at(word, pos) in @vowels
  end

  defp irregular_noun(word, mode) do
    [modern, classical] = Map.fetch!(@irregular, word)
    if mode == :modern, do: modern, else: classical
  end

  defp irregular_verb(word) do
    Map.fetch!(@pluralize_auxillary_irregular, word)
  end

  defp pronoun(word, mode) do
    [modern, classical] = Map.fetch!(@pronouns, word)
    if mode == :modern, do: modern, else: classical
  end

  defp personal_possessive(word) do
    Map.fetch!(@personal_possessive, word)
  end

  defp starts_with_upper?(<<char::utf8, _rest::binary>>) when char in ?A..?Z, do: true
  defp starts_with_upper?(_word), do: false
end
