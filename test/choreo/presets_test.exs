defmodule Choreo.PresetsTest do
  use ExUnit.Case, async: true

  alias Choreo
  alias Choreo.Dataflow
  alias Choreo.DecisionTree
  alias Choreo.Dependency
  alias Choreo.FSM
  alias Choreo.ThreatModel
  alias Choreo.Workflow

  test "basic modules render empty graphs across theme presets" do
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
  end

  test "behavioral modules render empty graphs across theme presets" do
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

  test "modules support custom per-node styling overrides" do
    # DecisionTree
    dt_dot =
      DecisionTree.new()
      |> DecisionTree.add_decision(1,
        label: "Life",
        fillcolor: "#440000",
        fontcolor: "#559900",
        shape: :diamond
      )
      |> Choreo.to_dot()

    assert dt_dot =~ "fillcolor=\"#440000\""
    assert dt_dot =~ "fontcolor=\"#559900\""
    assert dt_dot =~ "shape=\"diamond\""

    # Dataflow
    df_dot =
      Dataflow.new()
      |> Dataflow.add_source(:s, fillcolor: "#112233", penwidth: 3.5)
      |> Choreo.to_dot()

    assert df_dot =~ "fillcolor=\"#112233\""
    assert df_dot =~ "penwidth=\"3.5\""

    # FSM
    fsm_dot =
      FSM.new()
      |> FSM.add_state(:q, fontcolor: "#abcdef", style: "dotted")
      |> Choreo.to_dot()

    assert fsm_dot =~ "fontcolor=\"#abcdef\""
    assert fsm_dot =~ "style=\"dotted\""

    # Workflow
    wf_dot =
      Workflow.new()
      |> Workflow.add_task(:t, fillcolor: "#ff00ff", shape: :hexagon)
      |> Choreo.to_dot()

    assert wf_dot =~ "fillcolor=\"#ff00ff\""
    assert wf_dot =~ "shape=\"hexagon\""

    # Node images
    img_dot =
      DecisionTree.new()
      |> DecisionTree.add_decision(1, image: "/path/to/google.png")
      |> Choreo.to_dot()

    assert img_dot =~ "image=\"/path/to/google.png\""
  end
end
