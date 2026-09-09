defmodule Choreo.WorkflowRenderCoverageTest do
  use ExUnit.Case, async: true

  alias Choreo.Workflow
  alias Choreo.Workflow.Render.DOT
  alias Choreo.Workflow.Render.Mermaid

  setup do
    wf =
      Workflow.new()
      |> Workflow.add_swimlane("operations", label: "Operations")
      |> Workflow.add_swimlane("finance", label: "Finance")
      |> Workflow.add_start(:start)
      |> Workflow.add_task(:validate, label: "Validate Order", swimlane: "operations")
      |> Workflow.add_decision(:check_funds, label: "Sufficient Funds?")
      |> Workflow.add_fork(:split_tasks, label: "Fork")
      |> Workflow.add_task(:charge_card, label: "Charge Card", swimlane: "finance")
      |> Workflow.add_task(:send_email, label: "Send Receipt")
      |> Workflow.add_join(:join_tasks, label: "Join")
      |> Workflow.add_compensation(:rollback, label: "Refund Card")
      |> Workflow.add_event(:notify_fraud, label: "Fraud Alert")
      |> Workflow.add_end(:finish)
      |> Workflow.connect(:start, :validate, edge_type: :sequence)
      |> Workflow.connect(:validate, :check_funds, edge_type: :sequence)
      |> Workflow.connect(:check_funds, :split_tasks, label: "Yes", edge_type: :sequence)
      |> Workflow.connect(:check_funds, :finish, label: "No", edge_type: :failure)
      |> Workflow.connect(:split_tasks, :charge_card, edge_type: :sequence)
      |> Workflow.connect(:split_tasks, :send_email, edge_type: :sequence)
      |> Workflow.connect(:charge_card, :join_tasks, edge_type: :sequence)
      |> Workflow.connect(:send_email, :join_tasks, edge_type: :sequence)
      |> Workflow.connect(:charge_card, :rollback, edge_type: :compensation)
      |> Workflow.connect(:charge_card, :charge_card, label: "Retry", edge_type: :retry)
      |> Workflow.connect(:charge_card, :notify_fraud, label: "Timeout", edge_type: :timeout)
      |> Workflow.connect(:join_tasks, :finish, edge_type: :sequence)

    {:ok, wf: wf}
  end

  describe "DOT rendering" do
    test "renders all themes and overrides", %{wf: wf} do
      for theme_name <- [:default, :dark, :minimal, :warm, :forest, :ocean] do
        dot = DOT.to_dot(wf, theme: theme_name)
        assert dot =~ "digraph"
        assert dot =~ "Validate Order"
      end

      # Custom theme and overrides
      theme = DOT.theme(:warm, edge_color: "#123456")
      dot = DOT.to_dot(wf, theme: theme)
      assert dot =~ "#123456"

      # Fallback theme
      fallback_dot = DOT.to_dot(wf, theme: :non_existent)
      assert fallback_dot =~ "digraph"
    end

    test "renders highlighted nodes and edges with rankdir", %{wf: wf} do
      dot =
        DOT.to_dot(wf,
          highlighted_nodes: [:start, :validate],
          highlighted_edges: [{:start, :validate}],
          rankdir: :lr
        )

      assert dot =~ "digraph"
      assert dot =~ "rankdir=LR"
    end
  end

  describe "Mermaid rendering" do
    test "renders flowchart syntax across themes", %{wf: wf} do
      for theme_name <- [:default, :dark, :minimal, :warm, :forest, :ocean] do
        out = Mermaid.to_mermaid(wf, syntax: :flowchart, theme: theme_name)
        assert out =~ "graph TD"
      end

      # Custom theme
      theme = Mermaid.theme(:ocean, colors: %{task: "#abcdef"})
      out = Mermaid.to_mermaid(wf, theme: theme)
      assert out =~ "#abcdef"

      # Unknown theme fallback
      assert Mermaid.to_mermaid(wf, theme: :unknown) =~ "graph TD"
    end

    test "renders flowchart with highlighted nodes and edges", %{wf: wf} do
      out =
        Mermaid.to_mermaid(wf,
          highlighted_nodes: [:start, :validate],
          highlighted_edges: [{:start, :validate}]
        )

      assert out =~ "graph TD"
    end

    test "renders swimlane syntax with directions and unassigned lane", %{wf: wf} do
      out_lr = Mermaid.to_mermaid(wf, syntax: :swimlane, direction: :lr)
      assert out_lr =~ "swimlane-beta LR"
      assert out_lr =~ "Unassigned"

      out_td = Mermaid.to_mermaid(wf, syntax: :swimlane, direction: :td)
      assert out_td =~ "swimlane-beta TD"

      out_tb = Mermaid.to_mermaid(wf, syntax: :swimlane, direction: :tb)
      assert out_tb =~ "swimlane-beta TB"

      out_rl = Mermaid.to_mermaid(wf, syntax: :swimlane, direction: :rl)
      assert out_rl =~ "swimlane-beta RL"

      out_bt = Mermaid.to_mermaid(wf, syntax: :swimlane, direction: :bt)
      assert out_bt =~ "swimlane-beta BT"

      out_default_dir = Mermaid.to_mermaid(wf, syntax: :swimlane, direction: :unknown)
      assert out_default_dir =~ "swimlane-beta LR"
    end

    test "renders swimlane when all nodes are clustered" do
      wf =
        Workflow.new()
        |> Workflow.add_swimlane("lane_a")
        |> Workflow.add_task(:t1, swimlane: "lane_a")

      out = Mermaid.to_mermaid(wf, syntax: :swimlane)
      assert out =~ "swimlane-beta"
      refute out =~ "Unassigned"
    end
  end
end
