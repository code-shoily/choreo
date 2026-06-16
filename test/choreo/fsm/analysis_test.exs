defmodule Choreo.FSM.AnalysisTest do
  use ExUnit.Case

  alias Choreo.FSM
  alias Choreo.FSM.Analysis

  doctest Choreo.FSM.Analysis

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

  describe "livelock_states/1" do
    test "finds reachable states trapped in non-accepting loops" do
      fsm =
        FSM.new()
        |> FSM.add_initial_state(:start)
        |> FSM.add_final_state(:ok)
        |> FSM.add_state(:l1)
        |> FSM.add_state(:l2)
        |> FSM.add_transition(:start, :ok, label: "yes")
        |> FSM.add_transition(:start, :l1, label: "fail")
        |> FSM.add_transition(:l1, :l2, label: "loop")
        |> FSM.add_transition(:l2, :l1, label: "back")
        # a dead-end state with no cycles
        |> FSM.add_state(:dead_end)
        |> FSM.add_transition(:start, :dead_end, label: "trap")

      assert Enum.sort(Analysis.livelock_states(fsm)) == [:l1, :l2]
    end

    test "does not find cycles that are not dead (can reach final)" do
      fsm =
        FSM.new()
        |> FSM.add_initial_state(:start)
        |> FSM.add_final_state(:ok)
        |> FSM.add_state(:l1)
        |> FSM.add_transition(:start, :l1, label: "go")
        |> FSM.add_transition(:l1, :l1, label: "self")
        |> FSM.add_transition(:l1, :ok, label: "exit")

      assert Analysis.livelock_states(fsm) == []
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

    test "returns empty list when initial state is final" do
      fsm =
        FSM.new()
        |> FSM.add_initial_state(:a)
        |> FSM.add_final_state(:a)

      assert {:ok, []} = Analysis.shortest_accepting_path(fsm)
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

    test "warns on livelock states" do
      fsm =
        FSM.new()
        |> FSM.add_initial_state(:start)
        |> FSM.add_final_state(:ok)
        |> FSM.add_state(:l1)
        |> FSM.add_state(:l2)
        |> FSM.add_transition(:start, :ok, label: "yes")
        |> FSM.add_transition(:start, :l1, label: "fail")
        |> FSM.add_transition(:l1, :l2, label: "loop")
        |> FSM.add_transition(:l2, :l1, label: "back")

      issues = Analysis.validate(fsm)

      assert Enum.any?(issues, fn {_sev, msg} ->
               String.contains?(msg, "Livelock")
             end)
    end

    test "empty FSM passes validation" do
      assert Analysis.validate(FSM.new()) == []
    end
  end

  describe "new advanced analysis functions" do
    test "deterministic?/1" do
      fsm =
        FSM.new()
        |> FSM.add_initial_state(:a)
        |> FSM.add_state(:b)
        |> FSM.add_transition(:a, :b, label: "x")

      assert Analysis.deterministic?(fsm)
    end

    test "generate_test_cases/2" do
      fsm =
        FSM.new()
        |> FSM.add_initial_state(:a)
        |> FSM.add_state(:b)
        |> FSM.add_final_state(:c)
        |> FSM.add_transition(:a, :b, label: "x")
        |> FSM.add_transition(:b, :c, label: "y")

      # Use Enum.sort on both sides or compare set representation for robust assertion
      test_states = Analysis.generate_test_cases(fsm, :state) |> Enum.sort()
      assert test_states == [[], ["x"], ["x", "y"]]

      test_transitions = Analysis.generate_test_cases(fsm, :transition) |> Enum.sort()
      assert test_transitions == [["x"], ["x", "y"]]
    end

    test "equivalent?/2" do
      fsm1 =
        FSM.new()
        |> FSM.add_initial_state(:a)
        |> FSM.add_final_state(:b)
        |> FSM.add_transition(:a, :b, label: "x")

      fsm2 =
        FSM.new()
        |> FSM.add_initial_state(:c)
        |> FSM.add_final_state(:d)
        |> FSM.add_transition(:c, :d, label: "x")

      fsm3 =
        FSM.new()
        |> FSM.add_initial_state(:a)
        |> FSM.add_final_state(:b)
        |> FSM.add_transition(:a, :b, label: "y")

      assert Analysis.equivalent?(fsm1, fsm2)
      refute Analysis.equivalent?(fsm1, fsm3)
    end

    test "minimize/1" do
      # A DFA with equivalent states :b and :c
      fsm =
        FSM.new()
        |> FSM.add_initial_state(:a)
        |> FSM.add_state(:b)
        |> FSM.add_state(:c)
        |> FSM.add_final_state(:d)
        |> FSM.add_transition(:a, :b, label: "x")
        |> FSM.add_transition(:a, :c, label: "y")
        |> FSM.add_transition(:b, :d, label: "z")
        |> FSM.add_transition(:c, :d, label: "z")

      minimized = Analysis.minimize(fsm)
      assert minimized.meta.initial_state == :a
      # Minimize should merge the redundant paths/states
      assert length(FSM.states(minimized)) < length(FSM.states(fsm))
    end

    test "violates_invariant?/2" do
      fsm =
        FSM.new()
        |> FSM.add_initial_state(:a)
        |> FSM.add_state(:b)
        |> FSM.add_transition(:a, :b, label: "x")

      assert Analysis.violates_invariant?(fsm, forbid_path: [:a, :b])
      refute Analysis.violates_invariant?(fsm, forbid_path: [:b, :a])
    end

    test "generate_test_cases/2 returns empty when no initial state" do
      fsm =
        FSM.new()
        |> FSM.add_state(:a)
        |> FSM.add_final_state(:b)
        |> FSM.add_transition(:a, :b, label: "x")

      assert Analysis.generate_test_cases(fsm, :state) == []
      assert Analysis.generate_test_cases(fsm, :transition) == []
    end

    test "equivalent?/2 handles missing initial states" do
      with_init =
        FSM.new()
        |> FSM.add_initial_state(:a)
        |> FSM.add_final_state(:b)
        |> FSM.add_transition(:a, :b, label: "x")

      without_init =
        FSM.new()
        |> FSM.add_state(:a)
        |> FSM.add_state(:b)
        |> FSM.add_transition(:a, :b, label: "x")

      assert Analysis.equivalent?(FSM.new(), FSM.new())
      refute Analysis.equivalent?(with_init, without_init)
    end

    test "minimize/1 handles empty and already-minimal machines" do
      assert Analysis.minimize(FSM.new()) == FSM.new()

      single =
        FSM.new()
        |> FSM.add_initial_state(:a)
        |> FSM.add_final_state(:a)

      assert Analysis.minimize(single).meta.initial_state == :a
      assert :a in FSM.final_states(Analysis.minimize(single))

      minimal =
        FSM.new()
        |> FSM.add_initial_state(:a)
        |> FSM.add_final_state(:b)
        |> FSM.add_transition(:a, :b, label: "x")

      minimized = Analysis.minimize(minimal)
      assert Enum.sort(FSM.states(minimized)) == [:a, :b]
    end

    test "violates_invariant?/2 handles invalid options" do
      fsm =
        FSM.new()
        |> FSM.add_initial_state(:a)
        |> FSM.add_state(:b)
        |> FSM.add_transition(:a, :b, label: "x")

      refute Analysis.violates_invariant?(fsm, [])
      refute Analysis.violates_invariant?(fsm, forbid_path: [:a])
      refute Analysis.violates_invariant?(fsm, forbid_path: [])
    end
  end
end
