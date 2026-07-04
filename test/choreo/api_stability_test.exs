defmodule Choreo.APIStabilityTest do
  use ExUnit.Case, async: true

  @main_modules [
    Choreo,
    Choreo.C4,
    Choreo.Infrastructure,
    Choreo.FSM,
    Choreo.Dataflow,
    Choreo.Dependency,
    Choreo.DecisionTree,
    Choreo.ThreatModel,
    Choreo.Workflow,
    Choreo.Planner,
    Choreo.MindMap,
    Choreo.ERD,
    Choreo.UML,
    Choreo.Domain,
    Choreo.Sequence
  ]

  @analysis_modules [
    Choreo.Analysis,
    Choreo.C4.Analysis,
    Choreo.Infrastructure.Analysis,
    Choreo.FSM.Analysis,
    Choreo.Dataflow.Analysis,
    Choreo.Dependency.Analysis,
    Choreo.DecisionTree.Analysis,
    Choreo.ThreatModel.Analysis,
    Choreo.Workflow.Analysis,
    Choreo.Planner.Analysis,
    Choreo.MindMap.Analysis,
    Choreo.ERD.Analysis,
    Choreo.UML.Analysis,
    Choreo.Domain.Analysis,
    Choreo.Sequence.Analysis
  ]

  @renderer_modules [
    Choreo.Render.DOT,
    Choreo.Render.Mermaid,
    Choreo.C4.Render.DOT,
    Choreo.C4.Render.Mermaid,
    Choreo.FSM.Render.DOT,
    Choreo.FSM.Render.Mermaid,
    Choreo.Dataflow.Render.DOT,
    Choreo.Dataflow.Render.Mermaid,
    Choreo.Dependency.Render.DOT,
    Choreo.Dependency.Render.Mermaid,
    Choreo.DecisionTree.Render.DOT,
    Choreo.DecisionTree.Render.Mermaid,
    Choreo.ThreatModel.Render.DOT,
    Choreo.ThreatModel.Render.Mermaid,
    Choreo.Workflow.Render.DOT,
    Choreo.Workflow.Render.Mermaid,
    Choreo.Planner.Render.DOT,
    Choreo.Planner.Render.Mermaid,
    Choreo.MindMap.Render.DOT,
    Choreo.MindMap.Render.Mermaid,
    Choreo.ERD.Render.DOT,
    Choreo.ERD.Render.Mermaid,
    Choreo.UML.Render.DOT,
    Choreo.UML.Render.Mermaid,
    Choreo.Sequence.Render.DOT,
    Choreo.Sequence.Render.Mermaid
  ]

  @stable_main_api [
    new: 0,
    new: 1,
    to_dot: 1,
    to_dot: 2,
    to_mermaid: 1,
    to_mermaid: 2,
    theme: 0,
    theme: 1,
    theme: 2
  ]

  @stable_renderer_api [
    theme: 0,
    theme: 1,
    theme: 2
  ]

  @themes [:default, :dark, :minimal, :warm, :forest, :ocean]

  test "all main modules expose the stable constructor, render, and theme API" do
    for module <- @main_modules do
      functions = module.__info__(:functions)

      for function <- @stable_main_api do
        assert function in functions,
               "#{inspect(module)} is missing #{format_function(function)}"
      end
    end
  end

  test "all main modules implement DOT and Mermaid protocols" do
    for module <- @main_modules do
      value = struct(module)

      assert Choreo.DOT.impl_for(value),
             "#{inspect(module)} does not implement Choreo.DOT"

      assert Choreo.Mermaid.impl_for(value),
             "#{inspect(module)} does not implement Choreo.Mermaid"
    end
  end

  test "all analysis modules expose validate/1" do
    for module <- @analysis_modules do
      assert {:validate, 1} in module.__info__(:functions),
             "#{inspect(module)} is missing validate/1"
    end
  end

  test "all public renderer modules expose theme helpers" do
    for module <- @renderer_modules do
      functions = module.__info__(:functions)

      for function <- @stable_renderer_api do
        assert function in functions,
               "#{inspect(module)} is missing #{format_function(function)}"
      end
    end
  end

  test "all main modules support the stable named themes" do
    for module <- @main_modules, theme <- @themes do
      resolved = module.theme(theme)

      assert %Choreo.Theme{} = resolved

      if theme == :minimal do
        assert resolved.name |> to_string() |> String.contains?("minimal"),
               "#{inspect(module)} does not resolve :minimal to a minimal theme"
      end
    end
  end

  defp format_function({name, arity}), do: "#{name}/#{arity}"
end
