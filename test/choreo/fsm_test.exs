defmodule Choreo.FSMTest do
  use ExUnit.Case

  alias Choreo.FSM

  describe "creation" do
    test "new/0 creates a directed graph by default" do
      fsm = FSM.new()
      assert Yog.type(fsm.graph) == :directed
    end

    test "new/1 can create undirected graph" do
      fsm = FSM.new(directed: false)
      assert Yog.type(fsm.graph) == :undirected
    end
  end

  describe "states" do
    test "add_state/3 creates a normal state" do
      fsm = FSM.new() |> FSM.add_state(:idle, label: "Idle")
      data = Yog.node(fsm.graph, :idle)
      assert data.state_type == :normal
      assert data.label == "Idle"
    end

    test "add_initial_state/3 marks state as initial" do
      fsm = FSM.new() |> FSM.add_initial_state(:idle)
      data = Yog.node(fsm.graph, :idle)
      assert data.state_type == :initial
      assert :idle in FSM.initial_states(fsm)
    end

    test "add_final_state/3 marks state as final" do
      fsm = FSM.new() |> FSM.add_final_state(:done)
      data = Yog.node(fsm.graph, :done)
      assert data.state_type == :final
      assert :done in FSM.final_states(fsm)
    end

    test "states/1 returns all state ids" do
      fsm =
        FSM.new()
        |> FSM.add_state(:a)
        |> FSM.add_state(:b)

      assert Enum.sort(FSM.states(fsm)) == [:a, :b]
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

    test "add_transition/4 without label" do
      fsm =
        FSM.new()
        |> FSM.add_state(:a)
        |> FSM.add_state(:b)
        |> FSM.add_transition(:a, :b)

      assert [{:a, :b, ""}] = FSM.transitions(fsm)
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
  end

  describe "transforms" do
    test "complement swaps final and normal states" do
      fsm =
        FSM.new()
        |> FSM.add_state(:a)
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
  end
end
