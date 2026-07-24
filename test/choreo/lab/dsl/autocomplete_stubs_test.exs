defmodule Choreo.Lab.AutocompleteStubsTest do
  use ExUnit.Case, async: true

  @dsl_modules [
    Choreo.Lab.DSL.C4,
    Choreo.Lab.DSL.Dataflow,
    Choreo.Lab.DSL.DecisionTree,
    Choreo.Lab.DSL.Dependency,
    Choreo.Lab.DSL.Domain,
    Choreo.Lab.DSL.ERD,
    Choreo.Lab.DSL.FSM,
    Choreo.Lab.DSL.Infrastructure,
    Choreo.Lab.DSL.MindMap,
    Choreo.Lab.DSL.Planner,
    Choreo.Lab.DSL.Requirement,
    Choreo.Lab.DSL.Sequence,
    Choreo.Lab.DSL.ThreatModel,
    Choreo.Lab.DSL.UML,
    Choreo.Lab.DSL.Workflow
  ]

  test "all autocomplete stub functions raise error when called at runtime" do
    for module <- @dsl_modules do
      taxonomy = module.taxonomy()

      # Derive the main entry macro name to exclude it
      entry_macro =
        module
        |> Module.split()
        |> List.last()
        |> Macro.underscore()
        |> String.to_atom()

      verbs =
        Map.drop(taxonomy, [:options, :modifiers])
        |> Map.values()
        |> List.flatten()
        |> Enum.uniq()
        |> Enum.reject(&(&1 in [:~>, :edge, :edge_type, :and, :test, entry_macro]))

      for verb <- verbs do
        # Call with different arities to cover all default argument generated clauses
        assert_raise RuntimeError, ~r/must be called inside a DSL block/i, fn ->
          apply(module, verb, [])
        end

        assert_raise RuntimeError, ~r/must be called inside a DSL block/i, fn ->
          apply(module, verb, [nil])
        end

        assert_raise RuntimeError, ~r/must be called inside a DSL block/i, fn ->
          apply(module, verb, [nil, nil])
        end

        assert_raise RuntimeError, ~r/must be called inside a DSL block/i, fn ->
          apply(module, verb, [nil, nil, []])
        end
      end
    end
  end
end
