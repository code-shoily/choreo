jump_tests = [
  {Jump.CredoChecks.AvoidFunctionLevelElse, []},
  {Jump.CredoChecks.AvoidLoggerConfigureInTest, []},
  {Jump.CredoChecks.DoctestIExExamples,
   [
     derive_test_path: fn filename ->
       cond do
         String.match?(filename, ~r"^lib/choreo/([^/]+)/render/") ->
           name = Regex.run(~r"^lib/choreo/([^/]+)/render/", filename) |> Enum.at(1)
           "test/choreo/#{name}_test.exs"

         String.match?(filename, ~r"^lib/choreo/([^/]+)/analysis.ex") ->
           name = Regex.run(~r"^lib/choreo/([^/]+)/analysis.ex", filename) |> Enum.at(1)
           path = "test/choreo/#{name}/analysis_test.exs"
           if File.exists?(path), do: path, else: "test/choreo/#{name}_test.exs"

         filename == "lib/choreo/render/mermaid.ex" ->
           "test/choreo/render_coverage_test.exs"

         filename == "lib/choreo/theme.ex" ->
           "test/choreo_test.exs"

         filename == "lib/choreo/analysis.ex" ->
           "test/choreo_test.exs"

         filename == "lib/choreo/internal.ex" ->
           "test/choreo_test.exs"

         true ->
           filename
           |> String.replace_leading("lib/", "test/")
           |> String.replace_trailing(".ex", "_test.exs")
       end
     end
   ]},
  {Jump.CredoChecks.TestHasNoAssertions, []},
  {Jump.CredoChecks.TooManyAssertions, [max_assertions: 20]},
  {Jump.CredoChecks.TopLevelAliasImportRequire, []},
  {Jump.CredoChecks.VacuousTest, []},
  {Jump.CredoChecks.WeakAssertion, []}
]

%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "src/", "test/"],
        excluded: [~r"/_build/", ~r"/deps/"]
      },
      plugins: [],
      requires: [],
      strict: false,
      parse_timeout: 5000,
      color: true,
      checks: jump_tests ++ [
        # Disabled for graph algorithm domains
        {Credo.Check.Refactor.CyclomaticComplexity, false},
        {Credo.Check.Refactor.ABCSize, false},
        {Credo.Check.Refactor.FunctionArity, false},

        # Consistency
        {Credo.Check.Consistency.ExceptionNames, []},
        {Credo.Check.Consistency.LineEndings, []},
        {Credo.Check.Consistency.ParameterPatternMatching, []},
        {Credo.Check.Consistency.SpaceAroundOperators, []},
        {Credo.Check.Consistency.SpaceInParentheses, []},
        {Credo.Check.Consistency.TabsOrSpaces, []},

        # Design
        {Credo.Check.Design.AliasUsage,
         [priority: :low, if_nested_deeper_than: 2, if_called_more_often_than: 2]},
        {Credo.Check.Design.DuplicatedCode, [nodes_threshold: 3]},
        {Credo.Check.Design.SkipTestWithoutComment, []},

        # Readability
        {Credo.Check.Readability.AliasOrder, []},
        {Credo.Check.Readability.FunctionNames, []},
        {Credo.Check.Readability.LargeNumbers, []},
        {Credo.Check.Readability.MaxLineLength, [priority: :low, max_length: 120]},
        {Credo.Check.Readability.ModuleAttributeNames, []},
        {Credo.Check.Readability.ModuleDoc, []},
        {Credo.Check.Readability.ModuleNames, []},
        {Credo.Check.Readability.ParenthesesInCondition, []},
        {Credo.Check.Readability.ParenthesesOnZeroArityDefs, []},
        {Credo.Check.Readability.PredicateFunctionNames, []},
        {Credo.Check.Readability.PreferImplicitTry, []},
        {Credo.Check.Readability.RedundantBlankLines, []},
        {Credo.Check.Readability.Semicolons, []},
        {Credo.Check.Readability.SpaceAfterCommas, []},
        {Credo.Check.Readability.StringSigils, []},
        {Credo.Check.Readability.TrailingBlankLine, []},
        {Credo.Check.Readability.TrailingWhiteSpace, []},
        {Credo.Check.Readability.UnnecessaryAliasExpansion, []},
        {Credo.Check.Readability.VariableNames, []},
        {Credo.Check.Readability.WithSingleClause, []},

        # Refactor
        {Credo.Check.Refactor.AppendSingleItem, []},
        {Credo.Check.Refactor.DoubleBooleanNegation, []},
        {Credo.Check.Refactor.FilterReject, []},
        {Credo.Check.Refactor.IoPuts, []},
        {Credo.Check.Refactor.MapJoin, []},
        {Credo.Check.Refactor.NegatedConditionsInUnless, []},
        {Credo.Check.Refactor.NegatedConditionsWithElse, []},
        {Credo.Check.Refactor.Nesting, [max_nesting: 5]},
        {Credo.Check.Refactor.RedundantWithClauseResult, []},

        # Warnings
        {Credo.Check.Warning.ApplicationConfigInModuleAttribute, []},
        {Credo.Check.Warning.BoolOperationOnSameValues, []},
        {Credo.Check.Warning.ExpensiveEmptyEnumCheck, []},
        {Credo.Check.Warning.IExPry, []},
        {Credo.Check.Warning.IoInspect, []},
        {Credo.Check.Warning.MixEnv, []},
        {Credo.Check.Warning.OperationOnSameValues, []},
        {Credo.Check.Warning.OperationWithConstantResult, []},
        {Credo.Check.Warning.RaiseInsideRescue, []},
        {Credo.Check.Warning.SpecWithStruct, []},
        {Credo.Check.Warning.WrongTestFileExtension, []}
      ]
    }
  ]
}
