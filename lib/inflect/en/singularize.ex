defmodule Text.Inflect.En.Singularize do
  @moduledoc false

  import Text.Inflect.En.Helpers
  alias Text.Inflect.En

  @saved_data_path "priv/inflection/en/en.etf"
  @external_resource @saved_data_path

  @inflections File.read!(@saved_data_path)
               |> :erlang.binary_to_term()

  @doc false
  def inflections do
    Text.Inflect.En.Singularize.inflections()
  end

  # Singularize is the INVERSE of this
  # Handle words that do not inflect in the plural (such as fish, travois, chassis, nationalities
  # ending in -ese etc. - see Tables A.2 and A.3)...
  #         if suffix(-fish) or suffix(-ois) or suffix(-sheep)
  #         or suffix(-deer) or suffix(-pox) or suffix(-[A-Z].*ese)
  #         or suffix(-itis) or category(-,-),
  #                 return the original noun

  def is_non_inflecting(word, mode) when is_binary(word) do
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

  def is_pronoun(word, _mode) do
    pronoun_singular(word)
  end

  # Handle standard irregular plurals (mongooses, oxen, etc. - see table A.1)...
  #         if the word has an irregular plural,
  #                 return the specified singular

  def is_irregular_noun(word, mode) do
    irregular_singular(word, mode)
  end

  # Singularize is the INVERSE of this
  # Handle irregular inflections for common suffixes (synopses, mice and men, etc.)...
  #         if suffix(-man),      return inflection(-man,-men)
  #         if suffix(-[lm]ouse), return inflection(-ouse,-ice)
  #         if suffix(-tooth),    return inflection(-tooth,-teeth)
  #         if suffix(-goose),    return inflection(-goose,-geese)
  #         if suffix(-foot),     return inflection(-foot,-feet)
  #         if suffix(-zoon),     return inflection(-zoon,-zoa)
  #         if suffix(-[csx]is),  return inflection(-is,-es)

  def is_irregular_suffix(word, _mode) do
    cond do
      suffix?(word, "men") ->
        replace_suffix(word, "men", "man")

      suffix?(word, "lice") ->
        replace_suffix(word, "lice", "louse")

      suffix?(word, "mice") ->
        replace_suffix(word, "mice", "mouse")

      suffix?(word, "teeth") ->
        replace_suffix(word, "teeth", "tooth")

      suffix?(word, "geese") ->
        replace_suffix(word, "geese", "goose")

      suffix?(word, "feet") ->
        replace_suffix(word, "feet", "foot")

      suffix?(word, "zoa") ->
        replace_suffix(word, "zoa", "zoon")

      true ->
        nil
    end
  end

  # Greek/Latin -es/-ces/-xes plurals (analyses → analysis, axes → axis,
  # appendices → appendix). Conservative: only fires when stripping the
  # plural suffix yields a known classical singular.
  @classical_is_es_plurals (
                             for w <- Text.Inflect.En.Helpers.is_ides(),
                                 String.ends_with?(w, "is"),
                                 do:
                                   String.replace_suffix(w, "is", "es")
                           )
                           |> MapSet.new()

  def is_classical_is_plural(word, _mode) do
    if word in @classical_is_es_plurals do
      String.replace_suffix(word, "es", "is")
    end
  end

  # Singularize is the INVERSE of this
  # Handle fully assimilated classical inflections (vertebrae, codices, etc. - see tables A.10,
  # A.14, A.19 and A.20, and tables A.11, A.15 and A.21 if in "classical mode)...
  #         if category(-ex,-ices), return inflection(-ex,-ices)
  #         if category(-um,-a),    return inflection(-um,-a)
  #         if category(-on,-a),    return inflection(-on,-a)
  #         if category(-a,-ae),    return inflection(-a,-ae)

  def is_assimilated_classical(word, mode) do
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

  # TODO: Ambiguous reversal
  # Singularize is the INVERSE of this
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

  def is_classical(word, :classical = mode) do
    cond do
      suffix?(word, "trices") ->
        replace_suffix(word, "trices", "trix")

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

  def is_classical(word, :modern = mode) do
    cond do
      category?(word, "-us", "-i", mode) ->
       replace_suffix(word, "us", "uses")

      true ->
        nil
    end
  end

  # Singularize is the INVERSE of this
  # The suffixes -ch, -sh, and -ss all take -es in the plural (churches, classes, etc)...
  #         if suffix(-[cs]h), return inflection(-h,-hes)
  #         if suffix(-ss),    return inflection(-ss,-sses)

  def is_compound_plural(word, _mode) do
    cond do
     suffix?(word, "ches") ->
       replace_suffix(word, "hes", "h")

     suffix?(word, "shes") ->
       replace_suffix(word, "shes", "sh")

     suffix?(word, "sses") ->
       replace_suffix(word, "sses", "ss")

      true ->
        nil
    end
  end

  # Singularize is the INVERSE of this
  # Certain words ending in -f or -fe take -ves in the plural (lives, wolves, etc)...
  #         if suffix(-[aeo]lf) or suffix(-[^d]eaf) or suffix(-arf),
  #                 return inflection(-f,-ves)
  #
  #         if suffix(-[nlw]ife),
  #                 return inflection(-fe,-ves)

  def is_ves_plural(word, _mode) do
    cond do
     suffix?(word, "alves") ->
       replace_suffix(word, "ves", "f")

     suffix?(word, "elves") ->
       replace_suffix(word, "ves", "f")

     suffix?(word, "olves") ->
       replace_suffix(word, "ves", "f")

     suffix?(word, "arves") ->
       replace_suffix(word, "ves", "f")

     suffix?(word, "nives") ->
       replace_suffix(word, "ves", "fe")

     suffix?(word, "lives") ->
       replace_suffix(word, "ves", "fe")

     suffix?(word, "wives") ->
       replace_suffix(word, "ves", "fe")

     suffix?(word, "deaves") ->
       replace_suffix(word, "ves", "f")

      true ->
        nil
    end
  end

  # Singularize is the INVERSE of this
  # Words ending in -y take -ys if preceded by a vowel (storeys, stays, etc.) or when a proper noun
  # (Marys, Tonys, etc.), but -ies if preceded by a consonant (stories, skies, etc.)...
  #         if suffix(-[aeiou]y), return inflection(-y,-ys)
  #         if suffix(-[A-Z].*y), return inflection(-y,-ys)
  #         if suffix(-y),        return inflection(-y,-ies)

  def is_word_ending_in_y(word, _mode) do
    cond do
     suffix?(word, "ys") && vowel?(word, -3) ->
        replace_suffix(word, "ys", "y")

     suffix?(word, "ys") && starts_with_upper?(word) ->
        replace_suffix(word, "ys", "y")

     suffix?(word, "ies") ->
       replace_suffix(word, "ies", "y")

      true ->
        nil
    end
  end

  # TODO
  # Some words ending in -o take -os (lassos, solos, etc. - see tables A.17 and A.18); the rest
  # take -oes (potatoes, dominoes, etc.) However, words in which the -o is preceded by a vowel
  # always take -os (folios, bamboos)...
  #         if category(-o,-os) or suffix(-[aeiou]o),
  #                 return inflection(-o,-os)
  #
  #         if suffix(-o), return inflection(-o,-oes)

  def is_o_suffix(word, :modern = mode) do
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

  def is_o_suffix(word, :classical = mode) do
    cond do
      category?(word, "-o", "-os", mode) ->
       replace_suffix(word, "o", "i")

     suffix?(word, "o") ->
        word <> "es"

      true ->
        nil
    end
  end

  # Singularize is the INVERSE of this
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
    def is_general(unquote(general) <> suffix, _mode) do
      cond do
        suffix?(suffix, "ls") -> unquote(general) <> replace_suffix(suffix, "ls", "l")
        true -> nil
      end
    end
  end

  def is_general(_word, _mode) do
    nil
  end

  # Non inflecting words don't change in either direction
  def is_non_inflecting_verb(word) do
    cond do
      category?(word, "non_inflecting_verb") ->
        word

      true ->
        nil
    end
  end

  # Singularize is the INVERSE of this
  # Otherwise, assume that the plural just adds -s (cats, programmes, trees, etc.)...
  #         otherwise, return inflection(-,-s)
  #
  # We pattern-match the common English plural suffixes in order of
  # specificity:
  #
  #   * `-ies`  → `-y`     (cities → city)
  #   * `-ves`  → `-fe`    (knives → knife)
  #   * `-shes`/`-ches`/`-sses`/`-zes`/`-xes`/`-oes` → trim `-es`
  #     (boxes → box, kisses → kiss, churches → church, potatoes → potato)
  #   * `-s`    → trim `-s` (cats → cat, houses → house)
  def is_regular(word, _mode) do
    cond do
      String.length(word) <= 2 ->
        word

      suffix?(word, "ies") ->
        replace_suffix(word, "ies", "y")

      suffix?(word, "ves") ->
        replace_suffix(word, "ves", "fe")

      suffix?(word, "sses") ->
        replace_suffix(word, "sses", "ss")

      suffix?(word, "shes") or suffix?(word, "ches") ->
        replace_suffix(word, "es", "")

      suffix?(word, "xes") or suffix?(word, "zes") ->
        replace_suffix(word, "es", "")

      # -oes after a consonant (potato, hero) → trim -es. After a
      # vowel (shoes, toes) we want to trim only the -s, which the
      # final -s rule below handles.
      suffix?(word, "oes") and not vowel?(word, String.length(word) - 4) ->
        replace_suffix(word, "es", "")

      suffix?(word, "s") ->
        replace_suffix(word, "s", "")

      true ->
        word
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

  def is_irregular_verb(word) do
    cond do
      category?(word, "irregular_verb") ->
        irregular_verb(word)

      true ->
        nil
    end
  end

  # Singularize is the INVERSE of this
  # Verbs in the regular 3rd person singular lose their -es, -ies, or -oes suffix (she catches -
  # they catch, he tries -> they try, it does -> they do, etc.)...
  #         if suffix(-[cs]hes), return inflection(-hes,-h)
  #         if suffix(-[sx]es),  return inflection(-es,-)
  #         if suffix(-zzes),    return inflection(-es,-)
  #         if suffix(-ies),     return inflection(-ies,-y)
  #         if suffix(-oes),     return inflection(-oes,-o)

  def is_third_person_singular(word) do
    cond do
     suffix?(word, "ch") ->
       replace_suffix(word, "ch", "ches")

     suffix?(word, "sh") ->
       replace_suffix(word, "sh", "shes")

     suffix?(word, "ss") ->
       word

     suffix?(word, "s") ->
       word <> "ses"

     suffix?(word, "x") ->
       word <> "xes"

     suffix?(word, "zz") ->
       replace_suffix(word, "zz", "zzes")

     suffix?(word, "y") ->
       replace_suffix(word, "y", "ies")

     suffix?(word, "o") ->
       replace_suffix(word, "o", "oes")

      true ->
        nil
    end
  end

  # Singularize is the INVERSE of this
  # NOTE that this is implemented in is_third_person_singular/1 above
  # Other 3rd person singular verbs ending in -s (but not -ss) also lose their suffix...
  #         if suffix(-[^s]s), return inflection(-s,-)

  def is_third_person_singular_s(_word) do
    nil
  end

  # Handle ambiguous simple verbs that might also be nouns (thought, sink, fly, etc. - see Table
  # A.4)...
  #         if the word is in the ambiguous category,
  #                 return the specified plural form

  def is_ambiguous(word) do
    cond do
      category?(word, "ambiguous") ->
        En.pluralize_noun(word)

      true ->
        nil
    end
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
      |> En.pluralize_noun()

    if suffix?(plural_noun, "s") do
      plural_noun <> "'"
    else
      plural_noun <> "'s"
    end
  end

  @doc false
  def category?(word, "irregular_verb") do
    Map.has_key?(pluralize_auxillary_irregular(), word)
  end

  def category?(word, "ambiguous") do
    word in ambiguous()
  end

  def category?(word, "non_inflecting_verb") do
    word in non_inflecting_verbs()
  end

  def category?(word, "personal_possessive") do
    Map.has_key?(personal_possessive(), word)
  end

  @doc false
  def category?(word, "irregular_noun", _mode) do
    Map.has_key?(irregular(), word)
  end

  def category?(word, "pronoun", _mode) do
    Map.has_key?(pronouns(), word)
  end

  def category?(word, "herd", _mode) do
    Enum.any?(non_inflecting_suffix(), &suffix?(word, &1))
  end

  def category?(word, "nationalities", _mode) do
   suffix?(word, "ese") && starts_with_upper?(word)
  end

  @doc false
  def category?(word, "-", "-", _) do
    word in non_inflecting_nouns()
  end

  def category?(word, "-o", "-os", :classical) do
    word in o_words_classical()
  end

  def category?(word, "-o", "-os", :modern) do
    word in o_words_modern()
  end

  def category?(word, "-ex", "-ices", :modern) do
    word in ex_ices_modern()
  end

  def category?(word, "-ex", "-ices", :classical) do
    word in ex_ices_classical()
  end

  def category?(word, "-um", "-a", :modern) do
    word in um_a_modern()
  end

  def category?(word, "-um", "-a", :classical) do
    word in um_a_classical()
  end

  def category?(word, "-on", "-a", _mode) do
    word in on_a()
  end

  def category?(word, "-a", "-ae", :modern) do
    word in a_ae_modern()
  end

  def category?(word, "-a", "-ae", :classical) do
    word in a_ae_classical()
  end

  def category?(word, "-en", "-ina", :classical) do
    word in en_ina()
  end

  def category?(word, "-a", "-ata", _mode) do
    word in a_ata()
  end

  def category?(word, "-is", "-ides", _mode) do
    word in is_ides()
  end

  def category?(word, "-us", "-i", _mode) do
    word in us_i()
  end

  def category?(word, "-us", "-us", _mode) do
    word in us_us()
  end

  def category?(word, "-o", "-i", _mode) do
    word in o_i()
  end

  def category?(word, "-", "-i", _mode) do
    word in any_i()
  end

  def category?(word, "-", "-im", _mode) do
    word in any_im()
  end

end