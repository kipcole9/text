defmodule Text.Vocabulary do
  @callback build_vocabulary() :: map()
  @callback get_vocabulary() :: map()


end