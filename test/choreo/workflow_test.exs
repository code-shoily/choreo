defmodule Choreo.WorkflowTest do
  use ExUnit.Case

  alias Choreo.Workflow

  describe "new/0" do
    test "creates an empty workflow" do
      workflow = Workflow.new()
      assert Workflow.nodes(workflow) == []
      assert Workflow.starts(workflow) == []
      assert Workflow.ends(workflow) == []
    end
  end

  describe "node builders" do
    test "add_start/3 creates a start node" do
      workflow = Workflow.new() |> Workflow.add_start(:begin, label: "Start")
      assert :begin in Workflow.starts(workflow)
      assert Yog.node(workflow.graph, :begin).node_type == :start
    end

    test "add_end/3 creates an end node" do
      workflow = Workflow.new() |> Workflow.add_end(:finish, label: "End")
      assert :finish in Workflow.ends(workflow)
      assert Yog.node(workflow.graph, :finish).node_type == :end
    end

    test "add_task/3 creates a task with metadata" do
      workflow =
        Workflow.new()
        |> Workflow.add_task(:process, timeout_ms: 5000, retry: 3, retry_backoff_ms: 100)

      assert :process in Workflow.tasks(workflow)
      data = Yog.node(workflow.graph, :process)
      assert data.node_type == :task
      assert data.timeout_ms == 5000
      assert data.retry == 3
      assert data.retry_backoff_ms == 100
    end

    test "add_decision/3 creates a decision node" do
      workflow = Workflow.new() |> Workflow.add_decision(:check)
      assert Yog.node(workflow.graph, :check).node_type == :decision
    end

    test "add_fork/3 creates a fork node" do
      workflow = Workflow.new() |> Workflow.add_fork(:split)
      assert Yog.node(workflow.graph, :split).node_type == :fork
    end

    test "add_join/3 creates a join node" do
      workflow = Workflow.new() |> Workflow.add_join(:merge)
      assert Yog.node(workflow.graph, :merge).node_type == :join
    end

    test "add_compensation/3 creates a compensation node" do
      workflow = Workflow.new() |> Workflow.add_compensation(:rollback, for: :process)
      assert :rollback in Workflow.compensations(workflow)
      assert Yog.node(workflow.graph, :rollback).target_task == :process
    end

    test "add_event/3 creates an event node" do
      workflow = Workflow.new() |> Workflow.add_event(:timer)
      assert Yog.node(workflow.graph, :timer).node_type == :event
    end
  end

  describe "connect/4" do
    test "connects two nodes with sequence edge by default" do
      workflow =
        Workflow.new()
        |> Workflow.add_start(:a)
        |> Workflow.add_task(:b)
        |> Workflow.connect(:a, :b)

      assert Yog.has_edge?(workflow.graph, :a, :b)
      meta = workflow.edge_meta[{:a, :b}]
      assert meta.edge_type == :sequence
    end

    test "connects with condition" do
      workflow =
        Workflow.new()
        |> Workflow.add_decision(:d)
        |> Workflow.add_task(:b)
        |> Workflow.connect(:d, :b, condition: "yes")

      meta = workflow.edge_meta[{:d, :b}]
      assert meta.condition == "yes"
      assert meta.label == "yes"
    end

    test "connects with compensation edge type" do
      workflow =
        Workflow.new()
        |> Workflow.add_task(:a)
        |> Workflow.add_compensation(:c)
        |> Workflow.connect(:a, :c, edge_type: :compensation)

      meta = workflow.edge_meta[{:a, :c}]
      assert meta.edge_type == :compensation
      assert meta.label == "compensate"
    end

    test "uses target timeout_ms as default weight" do
      workflow =
        Workflow.new()
        |> Workflow.add_task(:a)
        |> Workflow.add_task(:b, timeout_ms: 5000)
        |> Workflow.connect(:a, :b)

      {_from, _to, weight} = hd(Yog.all_edges(workflow.graph))
      assert weight == 5000
    end
  end

  describe "swimlanes" do
    test "add_swimlane/3 groups nodes" do
      workflow =
        Workflow.new()
        |> Workflow.add_swimlane("backend", label: "Backend Services")
        |> Workflow.add_task(:api, swimlane: "backend")

      assert Yog.node(workflow.graph, :api)[:cluster] == "cluster_backend"
    end
  end

  describe "to_dot/2" do
    test "renders a non-empty DOT string" do
      workflow =
        Workflow.new()
        |> Workflow.add_start(:start)
        |> Workflow.add_task(:process)
        |> Workflow.add_end(:end)
        |> Workflow.connect(:start, :process)
        |> Workflow.connect(:process, :end)

      dot = Workflow.to_dot(workflow)
      assert String.contains?(dot, "digraph")
      assert String.contains?(dot, "start")
      assert String.contains?(dot, "process")
    end

    test "renders with dark theme" do
      workflow =
        Workflow.new()
        |> Workflow.add_start(:a)
        |> Workflow.add_end(:b)
        |> Workflow.connect(:a, :b)

      dot = Workflow.to_dot(workflow, theme: :dark)
      assert String.contains?(dot, "digraph")
    end
  end

  describe "queries" do
    test "nodes/1 returns all node ids" do
      workflow =
        Workflow.new()
        |> Workflow.add_start(:a)
        |> Workflow.add_task(:b)

      assert Enum.sort(Workflow.nodes(workflow)) == [:a, :b]
    end

    test "edges/1 returns all edges" do
      workflow =
        Workflow.new()
        |> Workflow.add_start(:a)
        |> Workflow.add_task(:b)
        |> Workflow.connect(:a, :b)

      assert [{:a, :b, _}] = Workflow.edges(workflow)
    end
  end
end
