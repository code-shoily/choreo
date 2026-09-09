defmodule Choreo.PlannerRenderCoverageTest do
  use ExUnit.Case, async: true

  alias Choreo.Planner
  alias Choreo.Planner.Render.DOT
  alias Choreo.Planner.Render.Mermaid

  setup do
    planner =
      Planner.new("Project Alpha")
      |> Planner.add_user(:alice, name: "Alice")
      |> Planner.add_user(:bob, name: "Bob")
      |> Planner.add_milestone(:m1, title: "Milestone 1")
      |> Planner.add_milestone(:m2, title: "Milestone 2")
      |> Planner.add_task(:t1,
        title: "Task 1",
        status: :backlog,
        priority: :low,
        ticket: "ALPHA-1",
        start_date: ~D[2026-01-01],
        due_date: ~D[2026-01-05]
      )
      |> Planner.add_task(:t2,
        title: "Task 2",
        status: :todo,
        priority: :high,
        ticket: "ALPHA-2",
        estimate_hours: 16
      )
      |> Planner.add_task(:t3,
        title: "Task 3",
        status: :in_progress,
        priority: :critical,
        start_date: ~D[2026-01-10],
        estimate_hours: 8
      )
      |> Planner.add_task(:t4,
        title: "Task 4",
        status: :in_review,
        due_date: ~D[2026-01-20],
        estimate_hours: 24
      )
      |> Planner.add_task(:t5,
        title: "Task 5",
        status: :done,
        estimate_hours: 0
      )
      |> Planner.add_task(:t6,
        title: "Task 6",
        status: :cancelled
      )
      |> Planner.assign(:t1, :alice)
      |> Planner.assign(:t3, :bob)
      |> Planner.contains(:m1, :t1)
      |> Planner.contains(:m1, :t2)
      |> Planner.contains(:m2, :t3)
      |> Planner.depends_on(:t2, :t1)
      |> Planner.depends_on(:t5, :t3)

    {:ok, planner: planner}
  end

  describe "Mermaid Kanban rendering" do
    test "renders kanban with ticket_base_url and card metadata", %{planner: planner} do
      out =
        Mermaid.to_mermaid(planner,
          syntax: :kanban,
          ticket_base_url: "https://jira.example.com/browse/"
        )

      assert out =~ "ticketBaseUrl: 'https://jira.example.com/browse/'"
      assert out =~ "kanban"
      assert out =~ "assigned: Alice"
      assert out =~ "priority: Very High"
      assert out =~ "priority: High"
      assert out =~ "priority: Low"
      assert out =~ "ticket: ALPHA-1"
    end

    test "filters kanban by assignee and milestone", %{planner: planner} do
      alice_kanban = Mermaid.to_mermaid(planner, syntax: :kanban, assignee: :alice)
      assert alice_kanban =~ "Task 1"
      refute alice_kanban =~ "Task 3"

      m2_kanban = Mermaid.to_mermaid(planner, syntax: :kanban, milestone: :m2)
      assert m2_kanban =~ "Task 3"
      refute m2_kanban =~ "Task 1"
    end
  end

  describe "Mermaid Kanban Compat rendering" do
    test "renders flowchart-based kanban board covering all status columns", %{planner: planner} do
      out = Mermaid.to_mermaid(planner, syntax: :kanban_compat)
      assert out =~ "flowchart LR"
      assert out =~ "Backlog"
      assert out =~ "Todo"
      assert out =~ "In Progress"
      assert out =~ "In Review"
      assert out =~ "Done"
      assert out =~ "Cancelled"
    end
  end

  describe "Mermaid Gantt rendering" do
    test "renders empty gantt chart when project has no tasks" do
      empty = Planner.new("Empty Project")
      out = Mermaid.to_mermaid(empty, syntax: :gantt)
      assert out == "gantt\n    title Empty Project\n"
    end

    test "renders gantt with section_by :milestone", %{planner: planner} do
      out =
        Mermaid.to_mermaid(planner,
          syntax: :gantt,
          section_by: :milestone,
          title: "Alpha Timeline"
        )

      assert out =~ "gantt"
      assert out =~ "title Alpha Timeline"
      assert out =~ "section Milestone 1"
      assert out =~ "section Milestone 2"
      assert out =~ "crit"
      assert out =~ "active"
      assert out =~ "done"
    end

    test "renders gantt with section_by :assignee and milestone filter", %{planner: planner} do
      out = Mermaid.to_mermaid(planner, syntax: :gantt, section_by: :assignee, milestone: :m1)
      assert out =~ "section Alice"
      assert out =~ "Task 1"
      refute out =~ "Task 3"
    end
  end

  describe "Mermaid Flowchart and Swimlane rendering" do
    test "renders flowchart with various themes", %{planner: planner} do
      for theme_name <- [:default, :dark, :warm, :forest, :ocean, :minimal] do
        out = Mermaid.to_mermaid(planner, syntax: :flowchart, theme: theme_name)
        assert out =~ "graph TD"
      end

      # Custom theme struct
      custom = Mermaid.theme(:ocean, edge_color: "#123456")
      out = Mermaid.to_mermaid(planner, syntax: :flowchart, theme: custom)
      assert out =~ "graph TD"
    end

    test "renders swimlane with various directions and groupings", %{planner: planner} do
      out_lr = Mermaid.to_mermaid(planner, syntax: :swimlane, direction: :lr)
      assert out_lr =~ "swimlane-beta LR"

      out_rl = Mermaid.to_mermaid(planner, syntax: :swimlane, direction: :rl)
      assert out_rl =~ "swimlane-beta RL"

      out_bt = Mermaid.to_mermaid(planner, syntax: :swimlane, direction: :bt)
      assert out_bt =~ "swimlane-beta BT"

      out_status = Mermaid.to_mermaid(planner, syntax: :swimlane, swimlane_by: :status)
      assert out_status =~ "subgraph done[\"Done\"]"
      assert out_status =~ "subgraph backlog[\"Backlog\"]"
    end
  end

  describe "DOT rendering" do
    test "renders DOT with themes, rankdir, and highlighted elements", %{planner: planner} do
      for theme_name <- [:default, :dark, :warm, :forest, :ocean, :minimal] do
        out = DOT.to_dot(planner, theme: theme_name)
        assert out =~ "digraph G"
      end

      hl_out =
        DOT.to_dot(planner,
          highlighted_nodes: [:t1, :t2],
          highlighted_edges: [{:t1, :t2}],
          rankdir: :lr
        )

      assert hl_out =~ "digraph G"
      assert hl_out =~ "rankdir=LR"
    end
  end
end
