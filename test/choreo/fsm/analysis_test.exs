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
        |> FSM.add_initial_state(:a)
        |> FSM.add_state(:b)
        |> FSM.add_state(:c)
        |> FSM.add_transition(:a, :b, label: "x")
        |> FSM.add_transition(:a, :c, label: "y")

      assert Analysis.deterministic?(fsm)
    end

    test "false when duplicate labels from a state" do
      fsm =
        FSM.new()
        |> FSM.add_initial_state(:a)
        |> FSM.add_state(:b)
        |> FSM.add_state(:c)
        |> FSM.add_transition(:a, :b, label: "x")
        |> FSM.add_transition(:a, :c, label: "x")

      refute Analysis.deterministic?(fsm)
    end

    test "false for empty fsm" do
      refute Analysis.deterministic?(FSM.new())
    end

    test "false when multiple initial states" do
      fsm =
        FSM.new()
        |> FSM.add_initial_state(:a)
        |> FSM.add_initial_state(:b)

      refute Analysis.deterministic?(fsm)
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

  describe "alphabet/1" do
    test "collects distinct transition labels" do
      fsm =
        FSM.new()
        |> FSM.add_state(:a)
        |> FSM.add_state(:b)
        |> FSM.add_state(:c)
        |> FSM.add_transition(:a, :b, label: "x")
        |> FSM.add_transition(:b, :c, label: "y")
        |> FSM.add_transition(:c, :a, label: "x")

      sigma = Analysis.alphabet(fsm)
      assert MapSet.equal?(sigma, MapSet.new(["x", "y"]))
    end

    test "excludes empty labels" do
      fsm =
        FSM.new()
        |> FSM.add_state(:a)
        |> FSM.add_state(:b)
        |> FSM.add_transition(:a, :b)
        |> FSM.add_transition(:a, :b, label: "x")

      sigma = Analysis.alphabet(fsm)
      assert sigma == MapSet.new(["x"])
    end

    test "returns empty for FSM with no transitions" do
      fsm = FSM.new() |> FSM.add_state(:a)
      assert Analysis.alphabet(fsm) == MapSet.new()
    end
  end

  describe "complete?/1" do
    test "true when every state handles every symbol" do
      fsm =
        FSM.new()
        |> FSM.add_state(:a)
        |> FSM.add_state(:b)
        |> FSM.add_transition(:a, :b, label: "x")
        |> FSM.add_transition(:a, :a, label: "y")
        |> FSM.add_transition(:b, :a, label: "x")
        |> FSM.add_transition(:b, :b, label: "y")

      assert Analysis.complete?(fsm)
    end

    test "false when a state misses a symbol" do
      fsm =
        FSM.new()
        |> FSM.add_state(:a)
        |> FSM.add_state(:b)
        |> FSM.add_transition(:a, :b, label: "x")
        |> FSM.add_transition(:a, :a, label: "y")
        # :b only handles "x", missing "y"
        |> FSM.add_transition(:b, :a, label: "x")

      refute Analysis.complete?(fsm)
    end

    test "true for FSM with no transitions" do
      fsm = FSM.new() |> FSM.add_state(:a)
      assert Analysis.complete?(fsm)
    end
  end

  describe "nondeterministic_states/1" do
    test "returns states with duplicate labels" do
      fsm =
        FSM.new()
        |> FSM.add_state(:a)
        |> FSM.add_state(:b)
        |> FSM.add_state(:c)
        |> FSM.add_transition(:a, :b, label: "x")
        |> FSM.add_transition(:a, :c, label: "x")

      result = Analysis.nondeterministic_states(fsm)
      assert {:a, "x"} in result
    end

    test "returns empty for deterministic FSM" do
      fsm =
        FSM.new()
        |> FSM.add_state(:a)
        |> FSM.add_state(:b)
        |> FSM.add_transition(:a, :b, label: "x")

      assert Analysis.nondeterministic_states(fsm) == []
    end

    test "identifies multiple offending states" do
      fsm =
        FSM.new()
        |> FSM.add_state(:a)
        |> FSM.add_state(:b)
        |> FSM.add_state(:c)
        |> FSM.add_state(:d)
        |> FSM.add_transition(:a, :b, label: "x")
        |> FSM.add_transition(:a, :c, label: "x")
        |> FSM.add_transition(:b, :c, label: "y")
        |> FSM.add_transition(:b, :d, label: "y")

      result = Analysis.nondeterministic_states(fsm)
      assert {:a, "x"} in result
      assert {:b, "y"} in result
    end
  end

  describe "validate/1" do
    test "returns empty for well-formed FSM" do
      fsm =
        FSM.new()
        |> FSM.add_initial_state(:idle)
        |> FSM.add_final_state(:done)
        |> FSM.add_transition(:idle, :done, label: "go")
        |> FSM.add_transition(:done, :idle, label: "go")

      assert Analysis.validate(fsm) == []
    end

    test "errors on missing initial states" do
      fsm =
        FSM.new()
        |> FSM.add_state(:a)
        |> FSM.add_final_state(:b)
        |> FSM.add_transition(:a, :b, label: "go")

      issues = Analysis.validate(fsm)

      assert Enum.any?(issues, fn {sev, msg} ->
               sev == :error and String.contains?(msg, "initial")
             end)
    end

    test "warns on missing final states" do
      fsm =
        FSM.new()
        |> FSM.add_initial_state(:a)
        |> FSM.add_state(:b)
        |> FSM.add_transition(:a, :b, label: "go")

      issues = Analysis.validate(fsm)

      assert Enum.any?(issues, fn {_sev, msg} ->
               String.contains?(msg, "final")
             end)
    end

    test "warns on unreachable states" do
      fsm =
        FSM.new()
        |> FSM.add_initial_state(:a)
        |> FSM.add_state(:orphan)
        |> FSM.add_final_state(:b)
        |> FSM.add_transition(:a, :b, label: "go")

      issues = Analysis.validate(fsm)

      assert Enum.any?(issues, fn {_sev, msg} ->
               String.contains?(msg, "Unreachable")
             end)
    end

    test "warns on dead states" do
      fsm =
        FSM.new()
        |> FSM.add_initial_state(:a)
        |> FSM.add_state(:trap)
        |> FSM.add_final_state(:c)
        |> FSM.add_transition(:a, :trap, label: "bad")
        |> FSM.add_transition(:a, :c, label: "good")

      issues = Analysis.validate(fsm)

      assert Enum.any?(issues, fn {_sev, msg} ->
               String.contains?(msg, "Dead")
             end)
    end

    test "warns on nondeterministic transitions" do
      fsm =
        FSM.new()
        |> FSM.add_initial_state(:a)
        |> FSM.add_final_state(:b)
        |> FSM.add_final_state(:c)
        |> FSM.add_transition(:a, :b, label: "x")
        |> FSM.add_transition(:a, :c, label: "x")

      issues = Analysis.validate(fsm)

      assert Enum.any?(issues, fn {_sev, msg} ->
               String.contains?(msg, "Nondeterministic")
             end)
    end

    test "warns on incomplete FSM" do
      fsm =
        FSM.new()
        |> FSM.add_initial_state(:a)
        |> FSM.add_final_state(:b)
        |> FSM.add_transition(:a, :b, label: "x")

      issues = Analysis.validate(fsm)

      assert Enum.any?(issues, fn {_sev, msg} ->
               String.contains?(msg, "incomplete")
             end)
    end

    test "empty FSM passes validation" do
      assert Analysis.validate(FSM.new()) == []
    end
  end

  describe "accepts?/2 with multiple initial states" do
    test "accepts when any initial state leads to final" do
      fsm =
        FSM.new()
        |> FSM.add_initial_state(:a)
        |> FSM.add_initial_state(:b)
        |> FSM.add_final_state(:c)
        |> FSM.add_transition(:a, :c, label: "x")

      assert Analysis.accepts?(fsm, ["x"])
    end

    test "rejects when no initial state reaches final" do
      fsm =
        FSM.new()
        |> FSM.add_initial_state(:a)
        |> FSM.add_initial_state(:b)
        |> FSM.add_final_state(:c)
        |> FSM.add_transition(:a, :d, label: "x")
        |> FSM.add_transition(:b, :d, label: "x")

      refute Analysis.accepts?(fsm, ["x"])
    end
  end

  describe "to_dfa/1" do
    test "converts simple NFA to equivalent DFA" do
      nfa =
        FSM.new()
        |> FSM.add_initial_state(:q0)
        |> FSM.add_state(:q1)
        |> FSM.add_state(:q2)
        |> FSM.add_final_state(:q2)
        |> FSM.add_transition(:q0, :q1, label: "a")
        |> FSM.add_transition(:q0, :q2, label: "a")
        |> FSM.add_transition(:q1, :q2, label: "b")

      dfa = Analysis.to_dfa(nfa)

      assert Analysis.deterministic?(dfa)
      assert Analysis.accepts?(dfa, ["a"])
      assert Analysis.accepts?(dfa, ["a", "b"])
      refute Analysis.accepts?(dfa, ["b"])
    end

    test "handles incomplete alphabet with trap state" do
      nfa =
        FSM.new()
        |> FSM.add_initial_state(:q0)
        |> FSM.add_final_state(:q1)
        |> FSM.add_transition(:q0, :q1, label: "a")

      dfa = Analysis.to_dfa(nfa)

      assert Analysis.deterministic?(dfa)
      assert :__trap__ in FSM.states(dfa)
      assert Analysis.complete?(dfa)
    end

    test "returns empty FSM when no initial states" do
      nfa =
        FSM.new()
        |> FSM.add_state(:q0)
        |> FSM.add_final_state(:q1)
        |> FSM.add_transition(:q0, :q1, label: "a")

      dfa = Analysis.to_dfa(nfa)
      assert FSM.states(dfa) == []
    end
  end
end
