defmodule Choreo.PlannerTest do
  use ExUnit.Case

  doctest Choreo.Planner
  doctest Choreo.Planner.Render.Mermaid

  alias Choreo.Planner

  describe "construction" do
    test "new/1 creates an empty planner" do
      planner = Planner.new("Test Project")
      assert planner.name == "Test Project"
      assert %Yog.Multi.Graph{} = planner.graph
      assert Planner.tasks(planner) == []
    end

    test "add_task/3 with defaults" do
      planner = Planner.new() |> Planner.add_task(:t1)
      assert [{:t1, data}] = Planner.tasks(planner)
      assert data.node_type == :task
      assert data.status == :backlog
      assert data.priority == :medium
    end

    test "add_task/3 with options" do
      planner =
        Planner.new() |> Planner.add_task(:t1, title: "Design", status: :done, priority: :high)

      assert [{:t1, data}] = Planner.tasks(planner)
      assert data.title == "Design"
      assert data.status == :done
      assert data.priority == :high
    end

    test "add_milestone/3" do
      planner = Planner.new() |> Planner.add_milestone(:v1, title: "V1")
      assert [{:v1, data}] = Planner.milestones(planner)
      assert data.node_type == :milestone
      assert data.title == "V1"
    end

    test "add_user/3" do
      planner = Planner.new() |> Planner.add_user(:alice, name: "Alice")
      assert [{:alice, data}] = Planner.users(planner)
      assert data.node_type == :user
      assert data.name == "Alice"
    end

    test "add_label/3" do
      planner = Planner.new() |> Planner.add_label(:frontend, title: "Frontend")
      assert [{:frontend, data}] = Planner.labels(planner)
      assert data.node_type == :label
      assert data.title == "Frontend"
    end
  end

  describe "builder — edges" do
    test "contains/3 links milestone to task" do
      planner =
        Planner.new()
        |> Planner.add_milestone(:v1)
        |> Planner.add_task(:t1)
        |> Planner.contains(:v1, :t1)

      assert Planner.children(planner, :v1) == [:t1]
      assert Planner.parent(planner, :t1) == :v1
    end

    test "depends_on/3 creates dependency edge" do
      planner =
        Planner.new()
        |> Planner.add_task(:a)
        |> Planner.add_task(:b)
        |> Planner.depends_on(:b, :a)

      assert Planner.dependencies(planner, :b) == [:a]
      assert Planner.dependents(planner, :a) == [:b]
    end

    test "blocks/3 creates blocker edge" do
      planner =
        Planner.new()
        |> Planner.add_task(:a)
        |> Planner.add_task(:b)
        |> Planner.blocks(:a, :b)

      assert Planner.dependencies(planner, :b) == [:a]
    end

    test "assign/3 links task to user" do
      planner =
        Planner.new()
        |> Planner.add_task(:t1)
        |> Planner.add_user(:alice)
        |> Planner.assign(:t1, :alice)

      assert Planner.assignee(planner, :t1) == :alice
      assert Planner.assigned_tasks(planner, :alice) == [:t1]
    end

    test "tag/3 links task to label" do
      planner =
        Planner.new()
        |> Planner.add_task(:t1)
        |> Planner.add_label(:frontend)
        |> Planner.tag(:t1, :frontend)

      assert [{t1_id, frontend_id, 1, %{type: :tagged_with}}] =
               Planner.edges_with_meta(planner)
               |> Enum.filter(fn {_, _, _, m} -> m[:type] == :tagged_with end)

      assert t1_id == :t1
      assert frontend_id == :frontend
    end

    test "relates/3 creates bidirectional edge" do
      planner =
        Planner.new()
        |> Planner.add_task(:a)
        |> Planner.add_task(:b)
        |> Planner.relates(:a, :b)

      assert length(Planner.edges_with_meta(planner)) == 2
    end

    test "update_task/3 merges properties" do
      planner =
        Planner.new()
        |> Planner.add_task(:t1, title: "Old")
        |> Planner.update_task(:t1, title: "New", status: :in_progress)

      assert [{:t1, data}] = Planner.tasks(planner)
      assert data.title == "New"
      assert data.status == :in_progress
    end

    test "remove_task/2 removes node and edges" do
      planner =
        Planner.new()
        |> Planner.add_task(:a)
        |> Planner.add_task(:b)
        |> Planner.depends_on(:b, :a)
        |> Planner.remove_task(:a)

      assert length(Planner.tasks(planner)) == 1
      assert Planner.dependencies(planner, :b) == []
    end

    test "contains/3 validates node types" do
      assert_raise ArgumentError, fn ->
        Planner.new()
        |> Planner.add_task(:a)
        |> Planner.add_task(:b)
        |> Planner.contains(:a, :b)
      end
    end
  end

  describe "queries" do
    test "tasks_by_status/2" do
      planner =
        Planner.new()
        |> Planner.add_task(:a, status: :done)
        |> Planner.add_task(:b, status: :backlog)

      assert [{:a, _}] = Planner.tasks_by_status(planner, :done)
      assert [{:b, _}] = Planner.tasks_by_status(planner, :backlog)
    end

    test "edges_with_meta/1" do
      planner =
        Planner.new()
        |> Planner.add_task(:a)
        |> Planner.add_task(:b)
        |> Planner.depends_on(:b, :a)

      assert [{_, _, _, meta}] = Planner.edges_with_meta(planner)
      assert meta[:type] == :depends_on
    end
  end

  describe "mermaid rendering" do
    test "to_mermaid with kanban syntax" do
      planner =
        Planner.new("Test")
        |> Planner.add_task(:a, title: "Task A", status: :done)
        |> Planner.add_task(:b, title: "Task B", status: :backlog)

      mermaid = Planner.to_mermaid(planner, syntax: :kanban)
      assert mermaid =~ "kanban"
      assert mermaid =~ "Task A"
      assert mermaid =~ "Task B"
      assert mermaid =~ "Done"
      assert mermaid =~ "Backlog"
    end

    test "to_mermaid with gantt syntax" do
      planner =
        Planner.new("Test")
        |> Planner.add_task(:a, title: "Task A", status: :done, estimate_hours: 16)

      mermaid = Planner.to_mermaid(planner, syntax: :gantt)
      assert mermaid =~ "gantt"
      assert mermaid =~ "Test"
      assert mermaid =~ "Task A"
    end

    test "to_mermaid with flowchart syntax" do
      planner =
        Planner.new()
        |> Planner.add_task(:a, title: "Task A")
        |> Planner.add_task(:b, title: "Task B")
        |> Planner.depends_on(:b, :a)

      mermaid = Planner.to_mermaid(planner, syntax: :flowchart)
      assert mermaid =~ "graph TD"
      assert mermaid =~ "Task A"
      assert mermaid =~ "Task B"
    end

    test "kanban filters by milestone" do
      planner =
        Planner.new()
        |> Planner.add_milestone(:v1)
        |> Planner.add_task(:a, title: "A", status: :done)
        |> Planner.add_task(:b, title: "B", status: :backlog)
        |> Planner.contains(:v1, :a)

      mermaid = Planner.to_mermaid(planner, syntax: :kanban, milestone: :v1)
      assert mermaid =~ "A"
      refute mermaid =~ "B"
    end

    test "to_mermaid with kanban_compat syntax" do
      planner =
        Planner.new("Test")
        |> Planner.add_task(:a, title: "Task A", status: :done)
        |> Planner.add_task(:b, title: "Task B", status: :backlog)

      mermaid = Planner.to_mermaid(planner, syntax: :kanban_compat)
      assert mermaid =~ "flowchart LR"
      assert mermaid =~ "Task A"
      assert mermaid =~ "Task B"
      assert mermaid =~ "Done"
      assert mermaid =~ "Backlog"
      assert mermaid =~ "subgraph"
    end

    test "kanban_compat applies status colours" do
      planner =
        Planner.new()
        |> Planner.add_task(:a, title: "A", status: :done)
        |> Planner.add_task(:b, title: "B", status: :in_progress)

      mermaid = Planner.to_mermaid(planner, syntax: :kanban_compat)
      assert mermaid =~ "fill:#4ade80"
      assert mermaid =~ "fill:#60a5fa"
    end

    test "kanban_compat filters by milestone" do
      planner =
        Planner.new()
        |> Planner.add_milestone(:v1)
        |> Planner.add_task(:a, title: "A", status: :done)
        |> Planner.add_task(:b, title: "B", status: :backlog)
        |> Planner.contains(:v1, :a)

      mermaid = Planner.to_mermaid(planner, syntax: :kanban_compat, milestone: :v1)
      assert mermaid =~ "A"
      refute mermaid =~ "b[\"B\"]"
    end

    test "kanban_compat filters by assignee" do
      planner =
        Planner.new()
        |> Planner.add_task(:a, title: "A", status: :done)
        |> Planner.add_task(:b, title: "B", status: :backlog)
        |> Planner.add_user(:alice)
        |> Planner.assign(:a, :alice)

      mermaid = Planner.to_mermaid(planner, syntax: :kanban_compat, assignee: :alice)
      assert mermaid =~ "A"
      refute mermaid =~ "b[\"B\"]"
    end
  end

  describe "dot rendering" do
    test "to_dot renders a graph" do
      planner =
        Planner.new()
        |> Planner.add_task(:a, title: "Task A")
        |> Planner.add_task(:b, title: "Task B")
        |> Planner.depends_on(:b, :a)

      dot = Planner.to_dot(planner)
      assert dot =~ "digraph G"
      assert dot =~ "Task A"
      assert dot =~ "Task B"
    end
  end

  describe "planner themes and options" do
    test "to_dot/2 supports themes and highlights" do
      planner =
        Planner.new()
        |> Planner.add_task(:a, title: "Task A", fillcolor: "#ffaaaa", penwidth: 2.5)
        |> Planner.add_task(:b, title: "Task B", status: :in_progress)
        |> Planner.add_milestone(:m1, title: "v1.0 Milestone")
        |> Planner.add_user(:alice, name: "Alice")
        |> Planner.add_task(:c, title: "Task C")
        |> Planner.add_task("task with spaces", title: "Spaced Task")
        |> Planner.depends_on(:b, :a)
        |> Planner.blocks(:a, :c)
        |> Planner.assign(:a, :alice)
        |> Planner.tag(:a, :frontend)
        |> Planner.relates(:b, "task with spaces")

      for theme <- [:dark, :warm, :forest, :ocean, :default, :custom, :invalid] do
        theme_opt =
          if theme == :custom,
            do: %Choreo.Theme{name: :custom, colors: %{task: "#ff0000"}},
            else: theme

        dot =
          Planner.to_dot(planner,
            theme: theme_opt,
            direction: :td,
            highlighted_nodes: [:a],
            highlighted_edges: [{:a, :b}]
          )

        assert dot =~ "digraph"
        assert dot =~ "Task A"
        assert dot =~ "v1.0 Milestone"
        assert dot =~ "\"task with spaces\""
      end

      assert %Choreo.Theme{name: :planner_warm} = Choreo.Planner.Render.DOT.theme(:warm)
    end

    test "to_mermaid/2 supports themes, directions, and highlights" do
      planner =
        Planner.new()
        |> Planner.add_task(:a, title: "Task A")
        |> Planner.add_task(:b, title: "Task B")
        |> Planner.depends_on(:b, :a)

      for theme <- [:dark, :warm, :forest, :ocean, :default, :custom, :invalid] do
        theme_opt =
          if theme == :custom,
            do: %Choreo.Theme{name: :custom, colors: %{task: "#ff0000"}},
            else: theme

        mermaid =
          Planner.to_mermaid(planner,
            theme: theme_opt,
            direction: :td,
            highlighted_nodes: [:a],
            highlighted_edges: [{:a, :b}],
            syntax: :flowchart
          )

        assert mermaid =~ "graph TD"
      end

      assert %Choreo.Theme{name: :planner_warm} = Choreo.Planner.Render.Mermaid.theme(:warm)
    end
  end

  describe "to_mermaid/2 swimlane syntax" do
    test "renders swimlane-beta header" do
      planner =
        Planner.new()
        |> Planner.add_task(:a, title: "Task A")
        |> Planner.add_task(:b, title: "Task B")
        |> Planner.depends_on(:b, :a)

      mermaid = Planner.to_mermaid(planner, syntax: :swimlane)
      assert String.starts_with?(mermaid, "swimlane-beta LR")
    end

    test "respects swimlane direction option" do
      planner =
        Planner.new()
        |> Planner.add_task(:a, title: "Task A")
        |> Planner.add_task(:b, title: "Task B")
        |> Planner.depends_on(:b, :a)

      mermaid = Planner.to_mermaid(planner, syntax: :swimlane, direction: :tb)
      assert String.starts_with?(mermaid, "swimlane-beta TB")
    end

    test "renders swimlanes grouped by assignee (default)" do
      planner =
        Planner.new()
        |> Planner.add_user(:alice, name: "Alice")
        |> Planner.add_task(:a, title: "Task A")
        |> Planner.assign(:a, :alice)

      mermaid = Planner.to_mermaid(planner, syntax: :swimlane)
      assert String.contains?(mermaid, "subgraph alice[\"Alice\"]")
      assert String.contains?(mermaid, "a")
    end

    test "renders swimlanes grouped by milestone" do
      planner =
        Planner.new()
        |> Planner.add_milestone(:m1, title: "Release 1")
        |> Planner.add_task(:a, title: "Task A")
        |> Planner.contains(:m1, :a)

      mermaid = Planner.to_mermaid(planner, syntax: :swimlane, swimlane_by: :milestone)
      assert String.contains?(mermaid, "subgraph m1[\"Release 1\"]")
      assert String.contains?(mermaid, "a")
    end

    test "renders swimlanes grouped by status" do
      planner =
        Planner.new()
        |> Planner.add_task(:a, title: "Task A", status: :in_progress)

      mermaid = Planner.to_mermaid(planner, syntax: :swimlane, swimlane_by: :status)
      assert String.contains?(mermaid, "subgraph in_progress[\"In Progress\"]")
      assert String.contains?(mermaid, "a")
    end
  end

  describe "protocols" do
    test "Choreo.Mermaid protocol" do
      planner = Planner.new() |> Planner.add_task(:a, title: "A")
      assert Choreo.to_mermaid(planner) =~ "kanban"
    end

    test "Choreo.DOT protocol" do
      planner = Planner.new() |> Planner.add_task(:a, title: "A")
      assert Choreo.to_dot(planner) =~ "digraph G"
    end
  end

  describe "hardened edge cases" do
    test "relationship builders implicitly register missing nodes" do
      planner =
        Planner.new()
        |> Planner.contains(:v1, :t1)
        |> Planner.depends_on(:t2, :t1)
        |> Planner.blocks(:t2, :t3)
        |> Planner.assign(:t1, :alice)
        |> Planner.tag(:t1, :frontend)

      # Check contains implicitly created v1 (milestone) and t1 (task)
      assert Map.get(planner.graph.nodes, :v1).node_type == :milestone
      assert Map.get(planner.graph.nodes, :t1).node_type == :task

      # Check depends_on implicitly created t2 (task)
      assert Map.get(planner.graph.nodes, :t2).node_type == :task

      # Check blocks implicitly created t3 (task)
      assert Map.get(planner.graph.nodes, :t3).node_type == :task

      # Check assign implicitly created alice (user)
      assert Map.get(planner.graph.nodes, :alice).node_type == :user

      # Check tag implicitly created frontend (label)
      assert Map.get(planner.graph.nodes, :frontend).node_type == :label
    end

    test "relates/3 raises when either node does not exist" do
      planner =
        Planner.new()
        |> Planner.add_task(:t1)

      assert_raise ArgumentError, ~r/relates\/3 requires both nodes to exist/, fn ->
        Planner.relates(planner, :t1, :t4)
      end
    end

    test "to_dot/2 handles node names with spaces and special characters" do
      planner =
        Planner.new()
        |> Planner.add_milestone("my milestone", title: "my milestone")
        |> Planner.add_task("another-task!", title: "another-task!")
        |> Planner.contains("my milestone", "another-task!")

      dot = Planner.to_dot(planner)
      assert String.contains?(dot, "\"my milestone\"")
      assert String.contains?(dot, "\"another-task!\"")
    end

    test "to_mermaid/2 handles node names with spaces and special characters" do
      planner =
        Planner.new()
        |> Planner.add_milestone("my milestone", title: "my milestone")
        |> Planner.add_task("another-task!", title: "another-task!")
        |> Planner.contains("my milestone", "another-task!")

      mermaid = Planner.to_mermaid(planner, syntax: :flowchart)
      assert String.contains?(mermaid, "my milestone")
      assert String.contains?(mermaid, "another-task!")
    end

    test "to_mermaid/2 kanban with ticket_base_url, priorities, and assignee filtering" do
      planner =
        Planner.new("Launch")
        |> Planner.add_user(:alice, name: "Alice Developer")
        |> Planner.add_task(:t1, title: "Critical Task", priority: :critical, ticket: "PROJ-1")
        |> Planner.add_task(:t2, title: "Low Task", priority: :low, status: :todo)
        |> Planner.add_task(:t3, title: "Review Task", priority: :high, status: :in_review)
        |> Planner.assign(:t1, :alice)

      kanban =
        Planner.to_mermaid(planner, syntax: :kanban, ticket_base_url: "https://jira.example.com")

      assert kanban =~ "ticketBaseUrl: 'https://jira.example.com'"
      assert kanban =~ "priority: Very High"
      assert kanban =~ "assigned: Alice Developer"
      assert kanban =~ "ticket: PROJ-1"

      filtered = Planner.to_mermaid(planner, syntax: :kanban, assignee: :alice)
      assert filtered =~ "t1"
      refute filtered =~ "t2"
    end

    test "to_mermaid/2 kanban_compat renders flowchart-based kanban board" do
      planner =
        Planner.new("Kanban Compat")
        |> Planner.add_task(:t1, title: "Backlog Item", status: :backlog)
        |> Planner.add_task(:t2, title: "In Progress Item", status: :in_progress)
        |> Planner.add_task(:t3, title: "Done Item", status: :done)

      compat = Planner.to_mermaid(planner, syntax: :kanban_compat)
      assert compat =~ "flowchart LR"
      assert compat =~ "subgraph col_backlog"
      assert compat =~ "subgraph col_in_progress"
      assert compat =~ "subgraph col_done"
      assert compat =~ "Backlog Item"
    end

    test "to_mermaid/2 gantt supports section_by :assignee and empty task list" do
      empty_planner = Planner.new("Empty Project")
      assert Planner.to_mermaid(empty_planner, syntax: :gantt) =~ "gantt"

      planner =
        Planner.new("Gantt Sections")
        |> Planner.add_milestone(:m1, title: "Milestone 1")
        |> Planner.add_user(:alice, name: "Alice")
        |> Planner.add_task(:t1, title: "Alice's Task", duration: 3)
        |> Planner.contains(:m1, :t1)
        |> Planner.assign(:t1, :alice)

      gantt_assignee = Planner.to_mermaid(planner, syntax: :gantt, section_by: :assignee)
      assert gantt_assignee =~ "section Alice"
      assert gantt_assignee =~ "Alice's Task"

      gantt_milestone = Planner.to_mermaid(planner, syntax: :gantt, milestone: :m1)
      assert gantt_milestone =~ "Milestone 1"
    end
  end
end
