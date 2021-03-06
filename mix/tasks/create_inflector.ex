defmodule Mix.Tasks.Text.CreateEnglishPlurals do
  @moduledoc """
  Mix task to create the plurals data set used
  by the English inflector
  """

  use Mix.Task

  @shortdoc "Create the English plurals data set"

  @doc false
  def run(_) do
    Text.Inflect.Data.En.save_data()
  end
end

