# What is the best estimate to minimise time
# to generate vocabularies

Benchee.run(
  %{
    "Flow 1" => fn -> Text.Vocabulary.build_vocabularies(max_demand: 1) end,
    "Flow 5" => fn -> Text.Vocabulary.build_vocabularies(max_demand: 5) end,
    "Flow 10" => fn -> Text.Vocabulary.build_vocabularies(max_demand: 10) end,
    "Flow 20" => fn -> Text.Vocabulary.build_vocabularies(max_demand: 20) end,
  }
)