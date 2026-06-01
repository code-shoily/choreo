defmodule Choreo.RenderCoverageTest do
  use ExUnit.Case

  alias Choreo
  alias Choreo.Dataflow
  alias Choreo.DecisionTree
  alias Choreo.Dependency
  alias Choreo.FSM
  alias Choreo.MindMap
  alias Choreo.ThreatModel
  alias Choreo.Workflow

  test "infrastructure mermaid renderer comprehensive" do
    system =
      Choreo.new()
      |> Choreo.add_database(:db, kind: :postgres)
      |> Choreo.add_cache(:cache, kind: :redis)
      |> Choreo.add_service(:api)
      |> Choreo.add_network(:vpc)
      |> Choreo.add_user(:client)
      |> Choreo.add_load_balancer(:lb)
      |> Choreo.add_queue(:q, kind: :kafka)
      |> Choreo.add_storage(:s3)
      |> Choreo.connect(:api, :db, cost: 10)
      |> Choreo.connect(:api, :cache, cost: 5)
      |> Choreo.add_dataflow(:client, :api)

    for theme <- [:default, :dark, :warm, :forest, :ocean, :minimal] do
      assert Choreo.to_mermaid(system, theme: theme) =~ "graph TD"
    end

    # Custom attributes
    custom =
      system
      |> Choreo.add_database(:custom,
        shape: :circle,
        fillcolor: "red",
        fontcolor: "blue",
        style: "bold",
        penwidth: 5.0,
        image: "icon.png"
      )

    assert Choreo.to_mermaid(custom) =~ "((\"custom\"))"
  end

  test "decision_tree renderer comprehensive" do
    tree =
      DecisionTree.new()
      |> DecisionTree.set_root(:root, feature: "root")
      |> DecisionTree.add_decision(:d1, feature: "d1")
      |> DecisionTree.add_outcome(:o1, label: "O1")
      |> DecisionTree.add_outcome(:o2, label: "O2")
      |> DecisionTree.branch(:root, :d1, "yes")
      |> DecisionTree.branch(:d1, :o1, "a")
      |> DecisionTree.branch(:d1, :o2, "b")

    for theme <- [:default, :dark, :warm, :forest, :ocean] do
      assert DecisionTree.to_dot(tree, theme: theme) =~ "digraph"
      assert DecisionTree.to_mermaid(tree, theme: theme) =~ "graph TD"
    end
  end

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
      assert Workflow.to_mermaid(wf, theme: theme) =~ "graph TD"
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
      assert Dataflow.to_mermaid(df, theme: theme) =~ "graph TD"
    end
  end

  test "mind_map renderer comprehensive" do
    mm =
      MindMap.new()
      |> MindMap.set_root(:r, label: "Root")
      |> MindMap.add_topic(:t, label: "Topic")
      |> MindMap.add_subtopic(:s, label: "Subtopic")
      |> MindMap.add_note(:n, label: "Note")
      |> MindMap.branch(:r, :t)
      |> MindMap.branch(:t, :s)
      |> MindMap.branch(:t, :n)

    for theme <- [:default, :dark, :warm, :forest, :ocean] do
      assert MindMap.to_dot(mm, theme: theme) =~ "digraph"
      assert MindMap.to_mermaid(mm, theme: theme) =~ "graph TD"
    end

    native = MindMap.to_mermaid(mm, syntax: :mindmap)
    assert native =~ "mindmap"
    assert native =~ "r((Root))"
    assert native =~ "  t(Topic)"
    assert native =~ "    s[Subtopic]"
    assert native =~ "    n)Note("
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
      assert FSM.to_mermaid(fsm, theme: theme) =~ "graph LR"
    end

    native = FSM.to_mermaid(fsm, syntax: :state_diagram)
    assert native =~ "stateDiagram-v2"
    assert native =~ "  [*] --> idle"
    assert native =~ "  idle --> active : start"
    assert native =~ "  failed --> [*]"
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
      assert Dependency.to_mermaid(dep, theme: theme) =~ "graph TD"
    end

    native = Dependency.to_mermaid(dep, syntax: :class_diagram)
    assert native =~ "classDiagram"
    assert native =~ "  class a[\"a\"] {\n    <<application>>\n  }"
    assert native =~ "  class b[\"b\"] {\n    <<library>>\n  }"
    assert native =~ "  a --> b : uses"
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
      assert ThreatModel.to_mermaid(tm, theme: theme) =~ "graph LR"
    end

    assert ThreatModel.to_sequence(tm) =~ "sequenceDiagram"
    assert ThreatModel.to_sequence(tm) =~ "actor u"
    assert ThreatModel.to_sequence(tm) =~ "participant p"
  end
end
