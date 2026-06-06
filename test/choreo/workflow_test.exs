defmodule Choreo.WorkflowTest do
  use ExUnit.Case

  doctest Choreo.Workflow
  doctest Choreo.Workflow.Render.DOT

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
      assert Map.get(workflow.graph.nodes, :begin).node_type == :start
    end

    test "add_end/3 creates an end node" do
      workflow = Workflow.new() |> Workflow.add_end(:finish, label: "End")
      assert :finish in Workflow.ends(workflow)
      assert Map.get(workflow.graph.nodes, :finish).node_type == :end
    end

    test "add_task/3 creates a task with metadata" do
      workflow =
        Workflow.new()
        |> Workflow.add_task(:process, timeout_ms: 5000, retry: 3, retry_backoff_ms: 100)

      assert :process in Workflow.tasks(workflow)
      data = Map.get(workflow.graph.nodes, :process)
      assert data.node_type == :task
      assert data.timeout_ms == 5000
      assert data.retry == 3
      assert data.retry_backoff_ms == 100
    end

    test "add_decision/3 creates a decision node" do
      workflow = Workflow.new() |> Workflow.add_decision(:check)
      assert Map.get(workflow.graph.nodes, :check).node_type == :decision
    end

    test "add_fork/3 creates a fork node" do
      workflow = Workflow.new() |> Workflow.add_fork(:split)
      assert Map.get(workflow.graph.nodes, :split).node_type == :fork
    end

    test "add_join/3 creates a join node" do
      workflow = Workflow.new() |> Workflow.add_join(:merge)
      assert Map.get(workflow.graph.nodes, :merge).node_type == :join
    end

    test "add_compensation/3 creates a compensation node" do
      workflow = Workflow.new() |> Workflow.add_compensation(:rollback, for: :process)
      assert :rollback in Workflow.compensations(workflow)
      assert Map.get(workflow.graph.nodes, :rollback).target_task == :process
    end

    test "add_event/3 creates an event node" do
      workflow = Workflow.new() |> Workflow.add_event(:timer)
      assert Map.get(workflow.graph.nodes, :timer).node_type == :event
    end
  end

  describe "connect/4" do
    test "connects two nodes with sequence edge by default" do
      workflow =
        Workflow.new()
        |> Workflow.add_start(:a)
        |> Workflow.add_task(:b)
        |> Workflow.connect(:a, :b)

      assert [{:a, :b, _, meta}] = Workflow.edges_with_meta(workflow)
      assert meta.edge_type == :sequence
    end

    test "connects with condition" do
      workflow =
        Workflow.new()
        |> Workflow.add_decision(:d)
        |> Workflow.add_task(:b)
        |> Workflow.connect(:d, :b, condition: "yes")

      assert [{:d, :b, _, meta}] = Workflow.edges_with_meta(workflow)
      assert meta.condition == "yes"
      assert meta.label == "yes"
    end

    test "connects with compensation edge type" do
      workflow =
        Workflow.new()
        |> Workflow.add_task(:a)
        |> Workflow.add_compensation(:c)
        |> Workflow.connect(:a, :c, edge_type: :compensation)

      assert [{:a, :c, _, meta}] = Workflow.edges_with_meta(workflow)
      assert meta.edge_type == :compensation
      assert meta.label == "compensate"
    end

    test "uses target timeout_ms as default weight" do
      workflow =
        Workflow.new()
        |> Workflow.add_task(:a)
        |> Workflow.add_task(:b, timeout_ms: 5000)
        |> Workflow.connect(:a, :b)

      assert [{_from, _to, weight}] = Workflow.edges(workflow)
      assert weight == 5000
    end

    test "allows parallel connections between same nodes" do
      workflow =
        Workflow.new()
        |> Workflow.add_task(:a)
        |> Workflow.add_task(:b)
        |> Workflow.connect(:a, :b, label: "path1")
        |> Workflow.connect(:a, :b, label: "path2")

      edges = Workflow.edges_with_meta(workflow)
      assert length(edges) == 2
      labels = Enum.map(edges, fn {_, _, _, meta} -> meta.label end)
      assert "path1" in labels
      assert "path2" in labels
    end
  end

  describe "swimlanes" do
    test "add_swimlane/3 groups nodes" do
      workflow =
        Workflow.new()
        |> Workflow.add_swimlane("backend", label: "Backend Services")
        |> Workflow.add_task(:api, swimlane: "backend")

      assert Map.get(workflow.graph.nodes, :api)[:cluster] == "cluster_backend"
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

  describe "to_mermaid/2" do
    test "renders a non-empty Mermaid string" do
      workflow =
        Workflow.new()
        |> Workflow.add_start(:start)
        |> Workflow.add_task(:process)
        |> Workflow.add_end(:end)
        |> Workflow.connect(:start, :process)
        |> Workflow.connect(:process, :end)

      mermaid = Workflow.to_mermaid(workflow)
      assert String.contains?(mermaid, "graph TD")
      assert String.contains?(mermaid, "start")
      assert String.contains?(mermaid, "process")
    end

    test "renders with dark theme" do
      workflow =
        Workflow.new()
        |> Workflow.add_start(:a)
        |> Workflow.add_end(:b)
        |> Workflow.connect(:a, :b)

      mermaid = Workflow.to_mermaid(workflow, theme: :dark)
      assert String.contains?(mermaid, "graph TD")
      assert String.contains?(mermaid, "a")
    end

    test "renders start as circle" do
      workflow =
        Workflow.new()
        |> Workflow.add_start(:begin)

      mermaid = Workflow.to_mermaid(workflow)
      assert String.contains?(mermaid, "((\"begin\"))")
    end

    test "renders end with thick stroke" do
      workflow =
        Workflow.new()
        |> Workflow.add_end(:finish)

      mermaid = Workflow.to_mermaid(workflow)
      assert String.contains?(mermaid, "finish")
      assert String.contains?(mermaid, "stroke-width:3px")
    end

    test "renders decision as rhombus" do
      workflow =
        Workflow.new()
        |> Workflow.add_decision(:check)

      mermaid = Workflow.to_mermaid(workflow)
      assert String.contains?(mermaid, "{\"check\"}")
    end

    test "renders task as subroutine" do
      workflow =
        Workflow.new()
        |> Workflow.add_task(:process)

      mermaid = Workflow.to_mermaid(workflow)
      assert String.contains?(mermaid, "[[\"process\"]]")
    end

    test "renders compensation edge as dashed red" do
      workflow =
        Workflow.new()
        |> Workflow.add_task(:a)
        |> Workflow.add_compensation(:c)
        |> Workflow.connect(:a, :c, edge_type: :compensation)

      mermaid = Workflow.to_mermaid(workflow)
      assert String.contains?(mermaid, "stroke-dasharray")
      assert String.contains?(mermaid, "#ef4444")
    end

    test "renders swimlanes as subgraphs" do
      workflow =
        Workflow.new()
        |> Workflow.add_swimlane("backend", label: "Backend")
        |> Workflow.add_task(:api, swimlane: "backend")

      mermaid = Workflow.to_mermaid(workflow)
      assert String.contains?(mermaid, "subgraph backend")
      assert String.contains?(mermaid, "[\"Backend\"]")
      assert String.contains?(mermaid, "api")
    end

    test "renders custom theme colors" do
      workflow = Workflow.new() |> Workflow.add_task(:process)

      theme = Choreo.Theme.custom(colors: %{task: "#ff0000"})
      mermaid = Workflow.to_mermaid(workflow, theme: theme)
      assert String.contains?(mermaid, "#ff0000")
    end
  end

  describe "strict options validation" do
    test "add_task/3 raises on unknown options" do
      assert_raise NimbleOptions.ValidationError, fn ->
        Workflow.new() |> Workflow.add_task(:t, unknown: true)
      end
    end

    test "connect/4 raises on invalid edge_type" do
      assert_raise NimbleOptions.ValidationError, fn ->
        Workflow.new()
        |> Workflow.add_start(:a)
        |> Workflow.add_end(:b)
        |> Workflow.connect(:a, :b, edge_type: :invalid)
      end
    end

    test "add_swimlane/3 raises on unknown options" do
      assert_raise NimbleOptions.ValidationError, fn ->
        Workflow.new() |> Workflow.add_swimlane(:s, unknown: true)
      end
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

  describe "Choreo.Viewable" do
    test "zoom level 0 keeps only start and end nodes" do
      workflow =
        Workflow.new()
        |> Workflow.add_start(:begin)
        |> Workflow.add_task(:process)
        |> Workflow.add_decision(:check)
        |> Workflow.add_end(:finish)
        |> Workflow.connect(:begin, :process)
        |> Workflow.connect(:process, :finish)

      zoomed = Choreo.View.zoom(workflow, level: 0)
      assert Enum.sort(Workflow.nodes(zoomed)) == [:begin, :finish]
    end

    test "zoom level 1 keeps start, end, and tasks" do
      workflow =
        Workflow.new()
        |> Workflow.add_start(:begin)
        |> Workflow.add_task(:process)
        |> Workflow.add_decision(:check)
        |> Workflow.add_end(:finish)
        |> Workflow.connect(:begin, :process)
        |> Workflow.connect(:process, :finish)

      zoomed = Choreo.View.zoom(workflow, level: 1)
      assert Enum.sort(Workflow.nodes(zoomed)) == [:begin, :finish, :process]
    end

    test "zoom level 2 keeps control flow nodes" do
      workflow =
        Workflow.new()
        |> Workflow.add_start(:begin)
        |> Workflow.add_task(:process)
        |> Workflow.add_decision(:check)
        |> Workflow.add_fork(:split)
        |> Workflow.add_join(:merge)
        |> Workflow.add_event(:timer)
        |> Workflow.add_end(:finish)
        |> Workflow.connect(:begin, :process)
        |> Workflow.connect(:process, :check)
        |> Workflow.connect(:check, :finish)

      zoomed = Choreo.View.zoom(workflow, level: 2)

      assert Enum.sort(Workflow.nodes(zoomed)) == [
               :begin,
               :check,
               :finish,
               :merge,
               :process,
               :split
             ]
    end

    test "focus keeps node and neighbourhood on multigraph" do
      workflow =
        Workflow.new()
        |> Workflow.add_start(:begin)
        |> Workflow.add_task(:process)
        |> Workflow.add_end(:finish)
        |> Workflow.connect(:begin, :process)
        |> Workflow.connect(:process, :finish)

      focused = Choreo.View.focus(workflow, :process, radius: 1)
      assert Enum.sort(Workflow.nodes(focused)) == [:begin, :finish, :process]
    end

    test "filter removes matching nodes on multigraph" do
      workflow =
        Workflow.new()
        |> Workflow.add_start(:begin)
        |> Workflow.add_task(:process)
        |> Workflow.add_end(:finish)
        |> Workflow.connect(:begin, :process)
        |> Workflow.connect(:process, :finish)

      filtered =
        Choreo.View.filter(workflow, fn _id, data ->
          data[:node_type] != :task
        end)

      assert Enum.sort(Workflow.nodes(filtered)) == [:begin, :finish]
    end

    test "transitive edges add virtual metadata on multigraph" do
      workflow =
        Workflow.new()
        |> Workflow.add_start(:begin)
        |> Workflow.add_task(:process)
        |> Workflow.add_end(:finish)
        |> Workflow.connect(:begin, :process)
        |> Workflow.connect(:process, :finish)

      filtered =
        Choreo.View.filter(
          workflow,
          fn _id, data ->
            data[:node_type] != :task
          end,
          transitive: true
        )

      assert Enum.sort(Workflow.nodes(filtered)) == [:begin, :finish]

      edges = Workflow.edges_with_meta(filtered)
      assert length(edges) == 1

      {_from, _to, _weight, meta} = hd(edges)
      assert meta[:edge_type] == :virtual
    end

    test "focus_between finds shortest path on multigraph" do
      workflow =
        Workflow.new()
        |> Workflow.add_start(:begin)
        |> Workflow.add_task(:process)
        |> Workflow.add_task(:validate)
        |> Workflow.add_end(:finish)
        |> Workflow.connect(:begin, :process)
        |> Workflow.connect(:process, :validate)
        |> Workflow.connect(:validate, :finish)

      path = Choreo.View.focus_between(workflow, :begin, :finish)
      assert Enum.sort(Workflow.nodes(path)) == [:begin, :finish, :process, :validate]
    end

    test "collapse aggregates nodes on multigraph" do
      workflow =
        Workflow.new()
        |> Workflow.add_start(:begin)
        |> Workflow.add_task(:process)
        |> Workflow.add_task(:validate)
        |> Workflow.connect(:begin, :process)
        |> Workflow.connect(:begin, :validate)

      collapsed =
        Choreo.View.collapse(
          workflow,
          fn _id, data ->
            data[:node_type] == :task
          end,
          :tasks
        )

      assert :tasks in Workflow.nodes(collapsed)
      assert :begin in Workflow.nodes(collapsed)
      refute :process in Workflow.nodes(collapsed)
      refute :validate in Workflow.nodes(collapsed)

      edges = Workflow.edges(collapsed)

      assert {:begin, :tasks, _} =
               Enum.find(edges, fn {f, t, _} -> f == :begin and t == :tasks end)
    end

    test "renderer styles virtual edges" do
      workflow =
        Workflow.new()
        |> Workflow.add_start(:begin)
        |> Workflow.add_task(:process)
        |> Workflow.add_end(:finish)
        |> Workflow.connect(:begin, :process)
        |> Workflow.connect(:process, :finish)

      filtered =
        Choreo.View.filter(
          workflow,
          fn _id, data ->
            data[:node_type] != :task
          end,
          transitive: true
        )

      dot = Workflow.to_dot(filtered)
      assert String.contains?(dot, "#cbd5e1")
    end
  end

  describe "hardened edge cases" do
    test "connect/4 implicitly defines missing from/to stages as task nodes" do
      workflow =
        Workflow.new()
        |> Workflow.connect(:a, :b)

      assert Enum.sort(Workflow.nodes(workflow)) == [:a, :b]
      assert Map.get(workflow.graph.nodes, :a).node_type == :task
      assert Map.get(workflow.graph.nodes, :b).node_type == :task
      assert Map.get(workflow.graph.nodes, :a).label == "a"
      assert Map.get(workflow.graph.nodes, :b).label == "b"
    end

    test "to_dot/2 handles node names with spaces and special characters" do
      workflow =
        Workflow.new()
        |> Workflow.add_start("my start")
        |> Workflow.add_end("another-end!")
        |> Workflow.connect("my start", "another-end!")

      dot = Workflow.to_dot(workflow)
      assert String.contains?(dot, "\"my start\"")
      assert String.contains?(dot, "\"another-end!\"")
    end

    test "to_mermaid/2 handles node names with spaces and special characters" do
      workflow =
        Workflow.new()
        |> Workflow.add_start("my start")
        |> Workflow.add_end("another-end!")
        |> Workflow.connect("my start", "another-end!")

      mermaid = Workflow.to_mermaid(workflow)
      assert String.contains?(mermaid, "my start")
      assert String.contains?(mermaid, "another-end!")
    end
  end
end
