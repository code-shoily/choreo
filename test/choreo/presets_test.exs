defmodule Choreo.PresetsTest do
  use ExUnit.Case, async: true

  alias Choreo
  alias Choreo.Dataflow
  alias Choreo.DecisionTree
  alias Choreo.Dependency
  alias Choreo.FSM
  alias Choreo.ThreatModel
  alias Choreo.Workflow

  test "all modules render empty graphs across theme presets" do
    assert Choreo.new() |> Choreo.to_dot(theme: :warm) =~ "digraph"
    assert Choreo.new() |> Choreo.to_dot(theme: :forest) =~ "digraph"
    assert Choreo.new() |> Choreo.to_dot(theme: :ocean) =~ "digraph"

    assert Dataflow.new() |> Dataflow.to_dot(theme: :warm) =~ "digraph"
    assert Dataflow.new() |> Dataflow.to_dot(theme: :forest) =~ "digraph"
    assert Dataflow.new() |> Dataflow.to_dot(theme: :ocean) =~ "digraph"

    assert DecisionTree.new() |> DecisionTree.to_dot(theme: :warm) =~ "digraph"
    assert DecisionTree.new() |> DecisionTree.to_dot(theme: :forest) =~ "digraph"
    assert DecisionTree.new() |> DecisionTree.to_dot(theme: :ocean) =~ "digraph"

    assert Dependency.new() |> Dependency.to_dot(theme: :warm) =~ "digraph"
    assert Dependency.new() |> Dependency.to_dot(theme: :forest) =~ "digraph"
    assert Dependency.new() |> Dependency.to_dot(theme: :ocean) =~ "digraph"

    assert FSM.new() |> FSM.to_dot(theme: :warm) =~ "digraph"
    assert FSM.new() |> FSM.to_dot(theme: :forest) =~ "digraph"
    assert FSM.new() |> FSM.to_dot(theme: :ocean) =~ "digraph"

    assert ThreatModel.new() |> ThreatModel.to_dot(theme: :warm) =~ "digraph"
    assert ThreatModel.to_dot(ThreatModel.new(), theme: :forest) =~ "digraph"
    assert ThreatModel.to_dot(ThreatModel.new(), theme: :ocean) =~ "digraph"

    assert Workflow.new() |> Workflow.to_dot(theme: :warm) =~ "digraph"
    assert Workflow.to_dot(Workflow.new(), theme: :forest) =~ "digraph"
    assert Workflow.to_dot(Workflow.new(), theme: :ocean) =~ "digraph"
  end
end
