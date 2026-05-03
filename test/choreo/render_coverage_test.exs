defmodule Choreo.RenderCoverageTest do
  use ExUnit.Case

  alias Choreo.Dataflow
  alias Choreo.Dependency
  alias Choreo.FSM
  alias Choreo.MindMap
  alias Choreo.ThreatModel
  alias Choreo.Workflow

  test "workflow renderer comprehensive" do
    wf =
      Workflow.new()
      |> Workflow.add_start(:s)
      |> Workflow.add_end(:e)
      |> Workflow.add_task(:t, timeout_ms: 100, retry: 3, description: "A task")
      |> Workflow.add_decision(:d)
      |> Workflow.add_fork(:f)
      |> Workflow.add_join(:j)
      |> Workflow.add_compensation(:c)
      |> Workflow.add_event(:ev)
      |> Workflow.connect(:s, :t)
      |> Workflow.connect(:t, :d)
      |> Workflow.connect(:d, :f)
      |> Workflow.connect(:f, :j)
      |> Workflow.connect(:j, :e)
      |> Workflow.connect(:t, :c, edge_type: :compensation)
      |> Workflow.connect(:t, :t, edge_type: :retry)
      |> Workflow.connect(:t, :e, edge_type: :failure)
      |> Workflow.connect(:t, :e, edge_type: :timeout)

    # Hit all themes
    for theme <- [:default, :dark, :warm, :forest, :ocean] do
      assert Workflow.to_dot(wf, theme: theme) =~ "digraph"
    end

    # Hit custom attributes
    wf_custom =
      wf
      |> Workflow.add_task(:custom,
        shape: :egg,
        fillcolor: "red",
        fontcolor: "blue",
        style: "bold",
        penwidth: 5.0,
        image: "icon.png"
      )

    assert Workflow.to_dot(wf_custom) =~ "shape=\"egg\""
  end

  test "dataflow renderer comprehensive" do
    df =
      Dataflow.new()
      |> Dataflow.add_source(:src)
      |> Dataflow.add_sink(:snk)
      |> Dataflow.add_buffer(:st)
      |> Dataflow.connect(:src, :st, path_type: :retry)
      |> Dataflow.connect(:st, :snk, path_type: :dead_letter)

    for theme <- [:default, :dark, :warm, :forest, :ocean] do
      assert Dataflow.to_dot(df, theme: theme) =~ "digraph"
    end
  end

  test "mind_map renderer comprehensive" do
    mm =
      MindMap.new()
      |> MindMap.set_root(:r)
      |> MindMap.add_topic(:t)
      |> MindMap.add_subtopic(:s)
      |> MindMap.add_note(:n)
      |> MindMap.branch(:r, :t)
      |> MindMap.branch(:t, :s)

    for theme <- [:default, :dark, :warm, :forest, :ocean] do
      assert MindMap.to_dot(mm, theme: theme) =~ "digraph"
    end
  end

  test "fsm renderer comprehensive" do
    fsm =
      FSM.new()
      |> FSM.add_state(:idle, type: :initial)
      |> FSM.add_state(:active)
      |> FSM.add_state(:failed, type: :final)
      |> FSM.add_transition(:idle, :active, label: "start")

    for theme <- [:default, :dark, :warm, :forest, :ocean] do
      assert FSM.to_dot(fsm, theme: theme) =~ "digraph"
    end
  end

  test "dependency renderer comprehensive" do
    dep =
      Dependency.new()
      |> Dependency.add_application(:a)
      |> Dependency.add_library(:b)
      |> Dependency.add_interface(:ext)
      |> Dependency.depends_on(:a, :b)
      |> Dependency.depends_on(:a, :ext)

    for theme <- [:default, :dark, :warm, :forest, :ocean] do
      assert Dependency.to_dot(dep, theme: theme) =~ "digraph"
    end
  end

  test "threat_model renderer comprehensive" do
    tm =
      ThreatModel.new()
      |> ThreatModel.add_external_entity(:u)
      |> ThreatModel.add_process(:p)
      |> ThreatModel.add_data_store(:d)
      |> ThreatModel.data_flow(:u, :p)

    for theme <- [:default, :dark, :warm, :forest, :ocean] do
      assert ThreatModel.to_dot(tm, theme: theme) =~ "digraph"
    end
  end
end
