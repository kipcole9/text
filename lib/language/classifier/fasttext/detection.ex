defmodule Text.Language.Classifier.Fasttext.Detection do
  @moduledoc """
  The result of running fastText language identification on a piece of
  text.

  ### Fields

  * `language` is the BCP-47 language subtag fastText reports — typically
    a two-letter ISO 639-1 code (`"en"`, `"fr"`, `"zh"`), occasionally
    three-letter ISO 639-3 (`"als"`, `"yue"`).

  * `confidence` is the probability fastText assigns to the top-1 label,
    in `[0.0, 1.0]`.

  * `script` is the dominant Unicode script of the input as detected by
    `Text.Language.Classifier.Fasttext.ScriptDetector`. One of the script
    atoms documented there.

  * `alternatives` is the rest of the top-K predictions (excluding the
    top-1), each a `{language, probability}` pair. May be empty when
    `k == 1` was requested.

  * `text` is the original input. Kept on the struct so a downstream
    `Text.Language.Classifier.Fasttext.Locale.resolve/2` call can use it
    to disambiguate Hans/Hant or other script-derived locale information.

  """

  @type alternative :: {String.t(), float()}

  @type t :: %__MODULE__{
          language: String.t(),
          confidence: float(),
          script:
            Text.Language.Classifier.Fasttext.ScriptDetector.script(),
          alternatives: [alternative()],
          text: String.t()
        }

  defstruct [:language, :confidence, :script, :alternatives, :text]
end
