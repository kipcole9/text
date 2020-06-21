require Text.Language.Udhr

if Code.ensure_loaded?(Text.Language.Udhr) do
  defmodule Mix.Tasks.Text.CreateVocabularies do
    @moduledoc """
    Mix task to create the vocabularies for the
    [UDHR](http://research.ics.aalto.fi/cog/data/udhr/) corpus
    used by `Text.Language.detect/2`

    """

    use Mix.Task

    @shortdoc "Create the vocabularies for the UDHR corpus"

    @doc false
    def run(_) do
      Text.Vocabulary.build_vocabularies()
    end
  end
end
