defmodule Choreo.FSMTest do
  use ExUnit.Case

  alias Choreo.FSM

  doctest Choreo.FSM
  doctest Choreo.FSM.Render.DOT
  doctest Choreo.FSM.Render.Mermaid

  describe "creation" do
    test "new/0 creates a directed graph by default" do
      fsm = FSM.new()
      assert fsm.graph.kind == :directed
    end

    test "new/1 can create undirected graph" do
      fsm = FSM.new(directed: false)
      assert fsm.graph.kind == :undirected
    end
  end

  describe "states" do
    test "add_state/3 creates a normal state" do
      fsm = FSM.new() |> FSM.add_state(:idle, label: "Idle")
      data = fsm.graph.nodes[:idle]
      assert data.label == "Idle"
      refute :idle in FSM.initial_states(fsm)
      refute :idle in FSM.final_states(fsm)
    end

    test "add_initial_state/3 marks state as initial" do
      fsm = FSM.new() |> FSM.add_initial_state(:idle)
      assert :idle in FSM.initial_states(fsm)
    end

    test "add_final_state/3 marks state as final" do
      fsm = FSM.new() |> FSM.add_final_state(:done)
      assert :done in FSM.final_states(fsm)
    end

    test "add_state/3 with type: :initial" do
      fsm = FSM.new() |> FSM.add_state(:idle, type: :initial)
      assert :idle in FSM.initial_states(fsm)
    end

    test "add_state/3 with type: :initial raises when initial state already exists" do
      assert_raise ArgumentError, fn ->
        FSM.new()
        |> FSM.add_state(:idle, type: :initial)
        |> FSM.add_state(:running, type: :initial)
      end
    end

    test "add_initial_state/3 raises when adding second initial state" do
      assert_raise ArgumentError, fn ->
        FSM.new()
        |> FSM.add_initial_state(:idle)
        |> FSM.add_initial_state(:running)
      end
    end

    test "add_state/3 with type: :final" do
      fsm = FSM.new() |> FSM.add_state(:done, type: :final)
      assert :done in FSM.final_states(fsm)
    end

    test "add_state/3 with type: :normal clears initial and final status" do
      fsm =
        FSM.new()
        |> FSM.add_state(:a, type: :initial)
        |> FSM.add_state(:a, type: :final)
        |> FSM.add_state(:a, type: :normal)

      refute :a in FSM.initial_states(fsm)
      refute :a in FSM.final_states(fsm)
    end

    test "add_state/3 without type preserves existing initial/final status" do
      fsm =
        FSM.new()
        |> FSM.add_initial_state(:a)
        |> FSM.add_state(:a, label: "Updated")

      assert :a in FSM.initial_states(fsm)
    end

    test "remove_initial_state/2 removes initial status" do
      fsm =
        FSM.new()
        |> FSM.add_initial_state(:a)
        |> FSM.remove_initial_state(:a)

      refute :a in FSM.initial_states(fsm)
      assert :a in FSM.states(fsm)
    end

    test "remove_final_state/2 removes final status" do
      fsm =
        FSM.new()
        |> FSM.add_final_state(:a)
        |> FSM.remove_final_state(:a)

      refute :a in FSM.final_states(fsm)
      assert :a in FSM.states(fsm)
    end

    test "states/1 returns all state ids" do
      fsm =
        FSM.new()
        |> FSM.add_state(:a)
        |> FSM.add_state(:b)

      assert Enum.sort(FSM.states(fsm)) == [:a, :b]
    end
  end

  describe "remove_state" do
    test "removes state from the graph" do
      fsm =
        FSM.new()
        |> FSM.add_state(:a)
        |> FSM.add_state(:b)
        |> FSM.remove_state(:a)

      refute :a in FSM.states(fsm)
      assert :b in FSM.states(fsm)
    end

    test "removes all transitions involving the state" do
      fsm =
        FSM.new()
        |> FSM.add_state(:a)
        |> FSM.add_state(:b)
        |> FSM.add_state(:c)
        |> FSM.add_transition(:a, :b, label: "go")
        |> FSM.add_transition(:b, :c, label: "next")
        |> FSM.remove_state(:b)

      assert FSM.transitions(fsm) == []
    end

    test "clears the initial state when removed" do
      fsm =
        FSM.new()
        |> FSM.add_initial_state(:a)
        |> FSM.add_state(:b)
        |> FSM.remove_state(:a)

      assert FSM.initial_states(fsm) == MapSet.new()
      assert :a not in FSM.states(fsm)
    end

    test "removes state from the final states set when removed" do
      fsm =
        FSM.new()
        |> FSM.add_final_state(:a)
        |> FSM.add_state(:b)
        |> FSM.remove_state(:a)

      assert FSM.final_states(fsm) == []
      assert :a not in FSM.states(fsm)
    end

    test "is a no-op for a non-existent state" do
      fsm =
        FSM.new()
        |> FSM.add_state(:a)

      fsm_after = FSM.remove_state(fsm, :nonexistent)
      assert fsm_after == fsm
    end
  end

  describe "transitions" do
    test "add_transition/4 with label" do
      fsm =
        FSM.new()
        |> FSM.add_state(:a)
        |> FSM.add_state(:b)
        |> FSM.add_transition(:a, :b, label: "go")

      assert [{:a, :b, "go"}] = FSM.transitions(fsm)
    end

    test "add_transition/4 with guard" do
      fsm =
        FSM.new()
        |> FSM.add_state(:a)
        |> FSM.add_state(:b)
        |> FSM.add_transition(:a, :b, label: "go", guard: "ready")

      assert [{:a, :b, "go [ready]"}] = FSM.transitions(fsm)
    end

    test "add_transition/4 without label rejects epsilon transitions" do
      assert_raise ArgumentError,
                   "epsilon transitions (empty labels) are not supported in DFAs",
                   fn ->
                     FSM.new()
                     |> FSM.add_state(:a)
                     |> FSM.add_state(:b)
                     |> FSM.add_transition(:a, :b)
                   end
    end

    test "add_transition/4 raises on duplicate label from same state" do
      assert_raise ArgumentError, fn ->
        FSM.new()
        |> FSM.add_state(:a)
        |> FSM.add_state(:b)
        |> FSM.add_state(:c)
        |> FSM.add_transition(:a, :b, label: "x")
        |> FSM.add_transition(:a, :c, label: "x")
      end
    end

    test "add_transition/4 allows different labels between same states" do
      fsm =
        FSM.new()
        |> FSM.add_state(:a)
        |> FSM.add_state(:b)
        |> FSM.add_transition(:a, :b, label: "x")
        |> FSM.add_transition(:a, :b, label: "y")

      edges = FSM.transitions(fsm) |> Enum.sort_by(fn {_, _, l} -> l end)
      assert [{:a, :b, "x"}, {:a, :b, "y"}] = edges
    end

    test "add_transition/4 rejects epsilon transitions" do
      assert_raise ArgumentError, fn ->
        FSM.new()
        |> FSM.add_state(:a)
        |> FSM.add_state(:b)
        |> FSM.add_transition(:a, :b)
      end
    end
  end

  describe "rendering" do
    test "to_dot/1 produces a digraph" do
      fsm =
        FSM.new()
        |> FSM.add_state(:a)
        |> FSM.add_state(:b)
        |> FSM.add_transition(:a, :b, label: "go")

      dot = FSM.to_dot(fsm)
      assert String.contains?(dot, "digraph")
      assert String.contains?(dot, "a")
      assert String.contains?(dot, "b")
      assert String.contains?(dot, "->")
    end

    test "to_dot/1 renders left-to-right" do
      fsm = FSM.new() |> FSM.add_state(:a)
      dot = FSM.to_dot(fsm)
      assert String.contains?(dot, "rankdir=LR")
    end

    test "to_dot/1 marks final states as doublecircle" do
      fsm = FSM.new() |> FSM.add_final_state(:done)
      dot = FSM.to_dot(fsm)
      assert String.contains?(dot, "shape=\"doublecircle\"")
    end

    test "to_dot/1 injects entry point for initial states" do
      fsm = FSM.new() |> FSM.add_initial_state(:idle)
      dot = FSM.to_dot(fsm)
      assert String.contains?(dot, "__start_idle")
      assert String.contains?(dot, "__start_idle -> idle")
      assert String.contains?(dot, "shape=point")
    end

    test "to_dot/1 does not inject entry point when no initial state" do
      fsm = FSM.new() |> FSM.add_state(:idle)
      dot = FSM.to_dot(fsm)
      refute String.contains?(dot, "__start")
    end

    test "to_dot/2 supports dark theme" do
      fsm = FSM.new() |> FSM.add_state(:a)
      dot = FSM.to_dot(fsm, theme: :dark)
      assert String.contains?(dot, "bgcolor=")
    end

    test "to_dot/2 supports custom theme colors" do
      fsm = FSM.new() |> FSM.add_state(:a)

      theme =
        Choreo.Theme.custom(
          colors: %{normal: "#ff0000"},
          node_fontcolor: "white"
        )

      dot = FSM.to_dot(fsm, theme: theme)
      assert String.contains?(dot, "fillcolor=\"#ff0000\"")
    end

    test "to_mermaid/1 produces a Mermaid string" do
      fsm =
        FSM.new()
        |> FSM.add_state(:a)
        |> FSM.add_state(:b)
        |> FSM.add_transition(:a, :b, label: "go")

      mermaid = FSM.to_mermaid(fsm)
      assert String.contains?(mermaid, "graph LR")
      assert String.contains?(mermaid, "a")
      assert String.contains?(mermaid, "b")
      assert String.contains?(mermaid, "go")
    end

    test "to_mermaid/1 renders left-to-right" do
      fsm = FSM.new() |> FSM.add_state(:a)
      mermaid = FSM.to_mermaid(fsm)
      assert String.contains?(mermaid, "graph LR")
    end

    test "to_mermaid/1 marks final states with thick stroke" do
      fsm = FSM.new() |> FSM.add_final_state(:done)
      mermaid = FSM.to_mermaid(fsm)
      assert String.contains?(mermaid, "done")
      assert String.contains?(mermaid, "stroke-width:3px")
    end

    test "to_mermaid/1 injects entry point for initial states" do
      fsm = FSM.new() |> FSM.add_initial_state(:idle)
      mermaid = FSM.to_mermaid(fsm)
      assert String.contains?(mermaid, "((\" \"))")
      assert String.contains?(mermaid, "((\"idle\"))")
      assert String.contains?(mermaid, "fill:black,stroke:black")
      assert mermaid =~ ~r/n_\d+ --> n_\d+/
    end

    test "to_mermaid/1 does not inject entry point when no initial state" do
      fsm = FSM.new() |> FSM.add_state(:idle)
      mermaid = FSM.to_mermaid(fsm)
      refute String.contains?(mermaid, "__start")
    end

    test "to_mermaid/2 supports dark theme" do
      fsm = FSM.new() |> FSM.add_state(:a)
      mermaid = FSM.to_mermaid(fsm, theme: :dark)
      assert String.contains?(mermaid, "a")
    end

    test "to_mermaid/2 supports custom theme colors" do
      fsm = FSM.new() |> FSM.add_state(:a)

      theme =
        Choreo.Theme.custom(
          colors: %{normal: "#ff0000"},
          node_fontcolor: "white"
        )

      mermaid = FSM.to_mermaid(fsm, theme: theme)
      assert String.contains?(mermaid, "#ff0000")
    end

    test "to_mermaid/1 renders initial+final state with thick stroke" do
      fsm =
        FSM.new()
        |> FSM.add_state(:both, type: :initial)
        |> FSM.add_state(:both, type: :final)

      mermaid = FSM.to_mermaid(fsm)
      assert String.contains?(mermaid, "both")
      assert String.contains?(mermaid, "stroke-width:3px")
    end
  end

  describe "transforms" do
    test "complement swaps final and normal states" do
      fsm =
        FSM.new()
        |> FSM.add_initial_state(:a)
        |> FSM.add_final_state(:b)

      comp = FSM.complement(fsm)
      assert :a in FSM.final_states(comp)
      refute :b in FSM.final_states(comp)
    end

    test "complement preserves initial states" do
      fsm =
        FSM.new()
        |> FSM.add_initial_state(:a)
        |> FSM.add_final_state(:b)

      comp = FSM.complement(fsm)
      assert :a in FSM.initial_states(comp)
    end

    test "prune removes unreachable states" do
      fsm =
        FSM.new()
        |> FSM.add_initial_state(:a)
        |> FSM.add_state(:unreachable)
        |> FSM.add_final_state(:c)
        |> FSM.add_transition(:a, :c, label: "go")

      pruned = FSM.prune(fsm)
      refute :unreachable in FSM.states(pruned)
      assert :a in FSM.states(pruned)
      assert :c in FSM.states(pruned)
    end

    test "prune removes dead states" do
      fsm =
        FSM.new()
        |> FSM.add_initial_state(:a)
        |> FSM.add_state(:trap)
        |> FSM.add_final_state(:c)
        |> FSM.add_transition(:a, :c, label: "go")

      pruned = FSM.prune(fsm)
      refute :trap in FSM.states(pruned)
    end

    test "complement with initial and final state" do
      fsm =
        FSM.new()
        |> FSM.add_initial_state(:a)
        |> FSM.add_final_state(:a)
        |> FSM.add_state(:b)

      comp = FSM.complement(fsm)
      assert :a in FSM.initial_states(comp)
      refute :a in FSM.final_states(comp)
      assert :b in FSM.final_states(comp)
    end

    test "prune preserves initial+final state" do
      fsm =
        FSM.new()
        |> FSM.add_initial_state(:a)
        |> FSM.add_final_state(:a)
        |> FSM.add_state(:dead)
        |> FSM.add_transition(:a, :a, label: "loop")

      pruned = FSM.prune(fsm)
      assert :a in FSM.states(pruned)
      assert :a in FSM.initial_states(pruned)
      assert :a in FSM.final_states(pruned)
      refute :dead in FSM.states(pruned)
    end
  end

  describe "strict options validation" do
    test "new/1 raises on unknown options" do
      assert_raise NimbleOptions.ValidationError, fn ->
        FSM.new(unknown: true)
      end
    end

    test "add_state/3 raises on unknown options" do
      assert_raise NimbleOptions.ValidationError, fn ->
        FSM.new() |> FSM.add_state(:a, unknown: true)
      end
    end

    test "add_state/3 raises on invalid type" do
      assert_raise NimbleOptions.ValidationError, fn ->
        FSM.new() |> FSM.add_state(:a, type: :invalid)
      end
    end

    test "add_initial_state/3 raises on unknown options" do
      assert_raise NimbleOptions.ValidationError, fn ->
        FSM.new() |> FSM.add_initial_state(:a, type: :initial)
      end
    end

    test "add_final_state/3 raises on unknown options" do
      assert_raise NimbleOptions.ValidationError, fn ->
        FSM.new() |> FSM.add_final_state(:a, unknown: true)
      end
    end

    test "add_transition/4 raises on unknown options" do
      assert_raise NimbleOptions.ValidationError, fn ->
        FSM.new()
        |> FSM.add_state(:a)
        |> FSM.add_state(:b)
        |> FSM.add_transition(:a, :b, unknown: true)
      end
    end
  end

  describe "hardened edge cases" do
    test "add_transition/4 implicitly defines missing from/to states" do
      fsm =
        FSM.new()
        |> FSM.add_transition(:a, :b, label: "go")

      assert Enum.sort(FSM.states(fsm)) == [:a, :b]
      assert fsm.graph.nodes[:a].type == :state
      assert fsm.graph.nodes[:b].type == :state
    end

    test "to_dot/1 handles state names with spaces and special characters" do
      fsm =
        FSM.new()
        |> FSM.add_initial_state("my state")
        |> FSM.add_final_state("another-state!")
        |> FSM.add_transition("my state", "another-state!", label: "go")

      dot = FSM.to_dot(fsm)
      assert String.contains?(dot, "\"my state\"")
      assert String.contains?(dot, "\"another-state!\"")
      assert String.contains?(dot, "\"__start_my state\"")
      assert String.contains?(dot, "\"__start_my state\" -> \"my state\"")
    end

    test "to_mermaid/1 with syntax: :state_diagram handles state names with spaces and special characters" do
      fsm =
        FSM.new()
        |> FSM.add_initial_state("my state")
        |> FSM.add_final_state("another-state!")
        |> FSM.add_transition("my state", "another-state!", label: "go")

      mermaid = FSM.to_mermaid(fsm, syntax: :state_diagram)
      assert String.contains?(mermaid, "stateDiagram-v2")
      assert String.contains?(mermaid, "state \"my state\" as my_state")
      assert String.contains?(mermaid, "state \"another-state!\" as another_state_")
      assert String.contains?(mermaid, "[*] --> my_state")
      assert String.contains?(mermaid, "my_state --> another_state_ : go")
      assert String.contains?(mermaid, "another_state_ --> [*]")
    end
  end
end
