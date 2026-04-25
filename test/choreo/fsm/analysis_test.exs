defmodule Choreo.FSM.AnalysisTest do
  use ExUnit.Case

  alias Choreo.FSM
  alias Choreo.FSM.Analysis

  describe "reachable_states/1" do
    test "returns states reachable from initial" do
      fsm =
        FSM.new()
        |> FSM.add_initial_state(:a)
        |> FSM.add_state(:b)
        |> FSM.add_state(:c)
        |> FSM.add_transition(:a, :b, label: "go")

      assert Enum.sort(Analysis.reachable_states(fsm)) == [:a, :b]
    end

    test "returns empty list when no initial states" do
      fsm =
        FSM.new()
        |> FSM.add_state(:a)
        |> FSM.add_state(:b)
        |> FSM.add_transition(:a, :b, label: "go")

      assert Analysis.reachable_states(fsm) == []
    end

    test "follows multi-step paths" do
      fsm =
        FSM.new()
        |> FSM.add_initial_state(:a)
        |> FSM.add_state(:b)
        |> FSM.add_state(:c)
        |> FSM.add_transition(:a, :b, label: "1")
        |> FSM.add_transition(:b, :c, label: "2")

      assert Enum.sort(Analysis.reachable_states(fsm)) == [:a, :b, :c]
    end
  end

  describe "dead_states/1" do
    test "finds states with no path to final" do
      fsm =
        FSM.new()
        |> FSM.add_initial_state(:a)
        |> FSM.add_state(:b)
        |> FSM.add_final_state(:c)
        |> FSM.add_transition(:a, :c, label: "go")
        |> FSM.add_transition(:a, :b, label: "trap")

      assert :b in Analysis.dead_states(fsm)
      refute :a in Analysis.dead_states(fsm)
      refute :c in Analysis.dead_states(fsm)
    end

    test "returns all states when no finals exist" do
      fsm =
        FSM.new()
        |> FSM.add_initial_state(:a)
        |> FSM.add_state(:b)
        |> FSM.add_transition(:a, :b, label: "go")

      assert Enum.sort(Analysis.dead_states(fsm)) == [:a, :b]
    end

    test "empty when every state can reach a final" do
      fsm =
        FSM.new()
        |> FSM.add_initial_state(:a)
        |> FSM.add_state(:b)
        |> FSM.add_final_state(:c)
        |> FSM.add_transition(:a, :b, label: "1")
        |> FSM.add_transition(:b, :c, label: "2")

      assert Analysis.dead_states(fsm) == []
    end
  end

  describe "deterministic?/1" do
    test "true when no duplicate labels from any state" do
      fsm =
        FSM.new()
        |> FSM.add_state(:a)
        |> FSM.add_state(:b)
        |> FSM.add_state(:c)
        |> FSM.add_transition(:a, :b, label: "x")
        |> FSM.add_transition(:a, :c, label: "y")

      assert Analysis.deterministic?(fsm)
    end

    test "false when duplicate labels from a state" do
      fsm =
        FSM.new()
        |> FSM.add_state(:a)
        |> FSM.add_state(:b)
        |> FSM.add_state(:c)
        |> FSM.add_transition(:a, :b, label: "x")
        |> FSM.add_transition(:a, :c, label: "x")

      refute Analysis.deterministic?(fsm)
    end

    test "true for empty fsm" do
      assert Analysis.deterministic?(FSM.new())
    end
  end

  describe "accepts?/2" do
    test "accepts valid input sequence" do
      fsm =
        FSM.new()
        |> FSM.add_initial_state(:idle)
        |> FSM.add_state(:running)
        |> FSM.add_final_state(:done)
        |> FSM.add_transition(:idle, :running, label: "start")
        |> FSM.add_transition(:running, :done, label: "finish")

      assert Analysis.accepts?(fsm, ["start", "finish"])
    end

    test "rejects incomplete input sequence" do
      fsm =
        FSM.new()
        |> FSM.add_initial_state(:idle)
        |> FSM.add_state(:running)
        |> FSM.add_final_state(:done)
        |> FSM.add_transition(:idle, :running, label: "start")
        |> FSM.add_transition(:running, :done, label: "finish")

      refute Analysis.accepts?(fsm, ["start"])
    end

    test "rejects invalid transition" do
      fsm =
        FSM.new()
        |> FSM.add_initial_state(:idle)
        |> FSM.add_state(:running)
        |> FSM.add_final_state(:done)
        |> FSM.add_transition(:idle, :running, label: "start")

      refute Analysis.accepts?(fsm, ["invalid"])
    end

    test "accepts when one of multiple paths reaches final (NFA)" do
      fsm =
        FSM.new()
        |> FSM.add_initial_state(:q0)
        |> FSM.add_state(:q1)
        |> FSM.add_state(:q2)
        |> FSM.add_final_state(:q2)
        |> FSM.add_transition(:q0, :q1, label: "a")
        |> FSM.add_transition(:q0, :q2, label: "a")

      assert Analysis.accepts?(fsm, ["a"])
    end

    test "rejects when no initial states" do
      fsm =
        FSM.new()
        |> FSM.add_state(:a)
        |> FSM.add_final_state(:b)
        |> FSM.add_transition(:a, :b, label: "x")

      refute Analysis.accepts?(fsm, ["x"])
    end
  end

  describe "shortest_accepting_path/1" do
    test "finds shortest path to final" do
      fsm =
        FSM.new()
        |> FSM.add_initial_state(:a)
        |> FSM.add_state(:b)
        |> FSM.add_final_state(:c)
        |> FSM.add_transition(:a, :b, label: "x")
        |> FSM.add_transition(:b, :c, label: "y")

      assert {:ok, ["x", "y"]} = Analysis.shortest_accepting_path(fsm)
    end

    test "finds shortest path with branching" do
      fsm =
        FSM.new()
        |> FSM.add_initial_state(:a)
        |> FSM.add_final_state(:c)
        |> FSM.add_state(:b)
        |> FSM.add_transition(:a, :b, label: "x")
        |> FSM.add_transition(:a, :c, label: "y")
        |> FSM.add_transition(:b, :c, label: "z")

      assert {:ok, ["y"]} = Analysis.shortest_accepting_path(fsm)
    end

    test "returns error when no path exists" do
      fsm =
        FSM.new()
        |> FSM.add_initial_state(:a)
        |> FSM.add_final_state(:c)

      assert :error = Analysis.shortest_accepting_path(fsm)
    end
  end

  describe "accepted_strings/2" do
    test "enumerates accepted strings up to length" do
      fsm =
        FSM.new()
        |> FSM.add_initial_state(:a)
        |> FSM.add_final_state(:b)
        |> FSM.add_transition(:a, :b, label: "x")

      assert Analysis.accepted_strings(fsm, 2) == [["x"]]
    end

    test "includes longer paths with self-loops" do
      fsm =
        FSM.new()
        |> FSM.add_initial_state(:a)
        |> FSM.add_final_state(:b)
        |> FSM.add_transition(:a, :b, label: "x")
        |> FSM.add_transition(:b, :b, label: "y")

      strings = Analysis.accepted_strings(fsm, 2)
      assert ["x"] in strings
      assert ["x", "y"] in strings
    end

    test "returns empty when no initial states" do
      fsm =
        FSM.new()
        |> FSM.add_state(:a)
        |> FSM.add_final_state(:b)
        |> FSM.add_transition(:a, :b, label: "x")

      assert Analysis.accepted_strings(fsm, 2) == []
    end
  end
end
