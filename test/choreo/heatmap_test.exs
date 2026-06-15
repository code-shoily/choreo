defmodule Choreo.HeatmapTest do
  use ExUnit.Case

  alias Choreo.Analysis
  alias Choreo.Theme
  alias Choreo.Workflow

  test "heatmap coloring for infrastructure" do
    system =
      Choreo.new()
      |> Choreo.add_service(:a)
      |> Choreo.add_service(:b)
      |> Choreo.add_service(:c)
      |> Choreo.connect(:a, :b)
      |> Choreo.connect(:a, :c)
      |> Choreo.connect(:b, :c)

    # a has degree 2, b has 2, c has 2 in a triangle
    # Let's add d connected only to a
    system = system |> Choreo.add_service(:d) |> Choreo.connect(:a, :d)

    # Now a has degree 3, b has 2, c has 2, d has 1
    heat = Analysis.heatmap(system, palette: :heat)

    nodes = heat.graph.nodes
    # a should have the hottest color (last in scale)
    assert nodes[:a].fillcolor == Theme.color_from_scale(1.0, :heat)
    # d should have the coolest color (first in scale)
    assert nodes[:d].fillcolor == Theme.color_from_scale(0.0, :heat)
  end

  test "heatmap for workflow" do
    wf =
      Workflow.new()
      |> Workflow.add_start(:s)
      |> Workflow.add_task(:t1)
      |> Workflow.add_task(:t2)
      |> Workflow.add_end(:e)
      |> Workflow.connect(:s, :t1)
      |> Workflow.connect(:t1, :t2)
      |> Workflow.connect(:t2, :e)

    heat = Analysis.heatmap(wf, palette: :cool)
    nodes = heat.graph.nodes
    # Should work on Workflow without error
    assert nodes[:s].fillcolor
    assert nodes[:e].fillcolor
  end

  test "heatmap for fsm" do
    fsm =
      Choreo.FSM.new()
      |> Choreo.FSM.add_initial_state(:a)
      |> Choreo.FSM.add_state(:b)
      |> Choreo.FSM.add_final_state(:c)
      |> Choreo.FSM.add_transition(:a, :b, label: "x")
      |> Choreo.FSM.add_transition(:b, :c, label: "y")

    heat = Analysis.heatmap(fsm, palette: :heat)
    nodes = heat.graph.nodes
    assert nodes[:a].fillcolor
    assert nodes[:c].fillcolor
  end

  test "different palettes produce different colors" do
    system =
      Choreo.new() |> Choreo.add_service(:a) |> Choreo.add_service(:b) |> Choreo.connect(:a, :b)

    heat = Analysis.heatmap(system, palette: :heat)
    cool = Analysis.heatmap(system, palette: :cool)

    assert heat.graph.nodes[:a].fillcolor != cool.graph.nodes[:a].fillcolor
  end

  test "legend generation" do
    leg = Analysis.legend(:heat)
    dot = Choreo.to_dot(leg)
    assert dot =~ "cluster_importance_legend"
    assert dot =~ "label=\"Importance Legend\""
    assert dot =~ "style=dashed"
  end
end
