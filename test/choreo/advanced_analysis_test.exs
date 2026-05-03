defmodule Choreo.AdvancedAnalysisTest do
  use ExUnit.Case

  alias Choreo.Analysis

  test "cut_vertices identifies SPOFs" do
    system =
      Choreo.new()
      |> Choreo.add_service(:a)
      |> Choreo.add_service(:b)
      |> Choreo.add_service(:c)
      |> Choreo.connect(:a, :b)
      |> Choreo.connect(:b, :c)

    assert Analysis.cut_vertices(system) == [:b]
  end

  test "core_numbers identifies the nucleus" do
    # Triangle (2-core) + a tail (1-core)
    system =
      Choreo.new()
      |> Choreo.add_service(:a)
      |> Choreo.add_service(:b)
      |> Choreo.add_service(:c)
      |> Choreo.add_service(:tail)
      |> Choreo.connect(:a, :b)
      |> Choreo.connect(:b, :c)
      |> Choreo.connect(:c, :a)
      |> Choreo.connect(:a, :tail)

    cores = Analysis.core_numbers(system)
    assert cores[:a] == 2
    assert cores[:b] == 2
    assert cores[:c] == 2
    assert cores[:tail] == 1
  end

  test "heatmap supports spof measure" do
    system =
      Choreo.new()
      |> Choreo.add_service(:a)
      |> Choreo.add_service(:b)
      |> Choreo.add_service(:c)
      |> Choreo.connect(:a, :b)
      |> Choreo.connect(:b, :c)

    heat = Analysis.heatmap(system, measure: :spof)
    # :b is SPOF, should be "hotter" (red)
    # :a and :c are not, should be "colder" (yellow)
    assert heat.graph.nodes[:b].fillcolor != heat.graph.nodes[:a].fillcolor
  end

  test "reduce_transitive removes redundant edges" do
    # A -> B, B -> C, A -> C (redundant)
    system =
      Choreo.new()
      |> Choreo.add_service(:a)
      |> Choreo.add_service(:b)
      |> Choreo.add_service(:c)
      |> Choreo.connect(:a, :b)
      |> Choreo.connect(:b, :c)
      |> Choreo.connect(:a, :c)

    assert Enum.count(Choreo.edges(system)) == 3
    assert {:ok, reduced} = Analysis.reduce_transitive(system)
    assert Enum.count(Choreo.edges(reduced)) == 2

    # Check that A -> C was the one removed
    edges = Choreo.edges(reduced)
    refute Enum.any?(edges, fn {src, dst, _} -> src == :a and dst == :c end)
  end

  test "path finds shortest path by default" do
    system =
      Choreo.new()
      |> Choreo.add_service(:a)
      |> Choreo.add_service(:b)
      |> Choreo.add_service(:c)
      |> Choreo.connect(:a, :b)
      |> Choreo.connect(:b, :c)
      |> Choreo.connect(:a, :c)

    {:ok, path} = Analysis.path(system, :a, :c)
    assert path.nodes == [:a, :c]
  end

  test "path finds fastest path by latency" do
    # A -> B -> C (10+10=20ms)
    # A -> C (100ms)
    system =
      Choreo.Workflow.new()
      |> Choreo.Workflow.add_task(:a, timeout_ms: 0)
      |> Choreo.Workflow.add_task(:b, timeout_ms: 10)
      |> Choreo.Workflow.add_task(:c, timeout_ms: 10)
      |> Choreo.Workflow.add_task(:slow, timeout_ms: 100)
      |> Choreo.Workflow.connect(:a, :b)
      |> Choreo.Workflow.connect(:b, :c)
      |> Choreo.Workflow.connect(:a, :slow)
      |> Choreo.Workflow.connect(:slow, :c)

    {:ok, path} = Analysis.path(system, :a, :c, measure: :latency)
    assert path.nodes == [:a, :b, :c]
  end

  test "path finds widest path by throughput" do
    # A -> B -> C (1000 events/sec)
    # A -> D -> C (100 events/sec)
    system =
      Choreo.Dataflow.new()
      |> Choreo.Dataflow.add_source(:a, rate: 1000)
      |> Choreo.Dataflow.add_transform(:b, capacity: 1000)
      |> Choreo.Dataflow.add_transform(:c, capacity: 1000)
      |> Choreo.Dataflow.add_transform(:slow, capacity: 100)
      |> Choreo.Dataflow.connect(:a, :b)
      |> Choreo.Dataflow.connect(:b, :c)
      |> Choreo.Dataflow.connect(:a, :slow)
      |> Choreo.Dataflow.connect(:slow, :c)

    {:ok, path} = Analysis.path(system, :a, :c, measure: :throughput)
    assert path.nodes == [:a, :b, :c]
  end
end
