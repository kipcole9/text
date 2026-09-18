%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/", "mix.exs"],
        excluded: []
      },
      strict: true,
      checks: [
        {Credo.Check.Design.AliasUsage, false},
        {Credo.Check.Readability.AliasOrder, false},
        {Credo.Check.Refactor.Nesting, false}
      ]
    }
  ]
}
