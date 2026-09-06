defmodule Choreo.Lab.FSMDSLTest do
  use ExUnit.Case, async: true

  import Choreo.Lab.DSL.FSM

  doctest Choreo.Lab.DSL.FSM

  test "taxonomy returns the Livebook discovery vocabulary" do
    taxonomy = Choreo.Lab.DSL.FSM.taxonomy()

    assert :state in taxonomy.states
    assert :initial in taxonomy.states
    assert :final in taxonomy.states
    assert :~> in taxonomy.edges
    assert :edge in taxonomy.edges
    assert :on in taxonomy.modifiers
    assert :guard in taxonomy.modifiers
    assert :with in taxonomy.options
    assert Choreo.Lab.DSL.FSM.verbs() == taxonomy
  end

  test "builds an FSM with variable-bound states" do
    machine =
      fsm do
        idle = initial("Idle")
        authorized = state("Authorized")
        denied = final("Denied")
        expired = final("Expired")

        idle ~> authorized |> on("token valid")
        edge idle ~> denied, "token invalid"
        authorized ~> expired |> label("token expired")
        authorized ~> denied |> guard("revoked?(token)")
      end

    assert Choreo.FSM.initial_state(machine) == :idle
    assert Enum.sort(Choreo.FSM.final_states(machine)) == [:denied, :expired]
    assert machine.graph.nodes[:authorized].label == "Authorized"

    assert {:idle, :authorized, "token valid"} in Choreo.FSM.transitions(machine)
    assert {:idle, :denied, "token invalid"} in Choreo.FSM.transitions(machine)
    assert {:authorized, :expired, "token expired"} in Choreo.FSM.transitions(machine)
    assert {:authorized, :denied, "[revoked?(token)]"} in Choreo.FSM.transitions(machine)
  end

  test "supports inline state constructors for one-off sketches" do
    machine =
      fsm do
        initial("Idle") ~> final("Done") |> on("finish")
      end

    assert Choreo.FSM.initial_state(machine) == :idle
    assert Choreo.FSM.final_states(machine) == [:done]
    assert Choreo.FSM.transitions(machine) == [{:idle, :done, "finish"}]
  end

  test "supports id option while keeping display label" do
    machine =
      fsm do
        a = initial("Idle", id: :idle_state)
        b = final("Done")

        edge a ~> b, "finish"
      end

    assert machine.graph.nodes[:idle_state].label == "Idle"
    assert Choreo.FSM.initial_state(machine) == :idle_state
    assert Choreo.FSM.transitions(machine) == [{:idle_state, :b, "finish"}]
  end

  test "supports edge/3 with label and options" do
    machine =
      fsm do
        idle = initial("Idle")
        running = state("Running")

        edge(idle ~> running, "start", guard: "ready?")
      end

    assert [{:idle, :running, "start [ready?]"}] = Choreo.FSM.transitions(machine)
    assert [{_eid, meta}] = Map.to_list(machine.edge_meta)
    assert meta.label == "start [ready?]"
    assert meta.guard == "ready?"
  end

  test "supports standalone state declarations updating env" do
    machine =
      fsm do
        initial("Idle")
        final("Done")

        idle ~> done |> on("finish")
      end

    assert Choreo.FSM.initial_state(machine) == :idle
    assert Choreo.FSM.final_states(machine) == [:done]
    assert Choreo.FSM.transitions(machine) == [{:idle, :done, "finish"}]
  end

  test "supports rich pipe modifiers with label and guard options" do
    machine =
      fsm do
        a = initial("A")
        b = state("B")
        c = final("C")

        a ~> b |> on("step", guard: "x > 0")
        b ~> c |> guard("x == 0", label: "done")
      end

    assert {:a, :b, "step [x > 0]"} in Choreo.FSM.transitions(machine)
    assert {:b, :c, "done [x == 0]"} in Choreo.FSM.transitions(machine)
  end

  test "helper stubs raise outside DSL block" do
    assert_raise RuntimeError, ~r/must be called inside a DSL block/, fn ->
      state("Idle")
    end

    assert_raise RuntimeError, ~r/must be called inside a DSL block/, fn ->
      initial("Start")
    end

    assert_raise RuntimeError, ~r/must be called inside a DSL block/, fn ->
      final("End")
    end

    assert_raise RuntimeError, ~r/must be called inside a DSL block/, fn ->
      guard("ready?")
    end
  end

  test "raises on unknown state variables" do
    assert_raise ArgumentError, ~r/unknown FSM state variable `done`/, fn ->
      Code.eval_quoted(
        quote do
          import Choreo.Lab.DSL.FSM

          fsm do
            idle = initial("Idle")
            idle ~> done |> on("finish")
          end
        end
      )
    end
  end

  test "raises when transition label or guard is missing" do
    assert_raise ArgumentError, ~r/FSM transitions require/, fn ->
      Code.eval_quoted(
        quote do
          import Choreo.Lab.DSL.FSM

          fsm do
            idle = initial("Idle")
            done = final("Done")
            idle ~> done
          end
        end
      )
    end
  end

  test "supports guard with options" do
    machine =
      fsm do
        idle = initial("Idle")
        running = state("Running")

        idle ~> running |> guard("valid?", label: "check")
      end

    assert [{:idle, :running, "check [valid?]"}] = Choreo.FSM.transitions(machine)
  end

  test "raises on unsupported FSM statement" do
    assert_raise ArgumentError, ~r/unsupported statement in FSM DSL/, fn ->
      Code.eval_quoted(
        quote do
          import Choreo.Lab.DSL.FSM

          fsm do
            123 + 456
          end
        end
      )
    end
  end

  test "raises on unsupported transition endpoint" do
    assert_raise ArgumentError, ~r/unsupported FSM transition endpoint 123/, fn ->
      Code.eval_quoted(
        quote do
          import Choreo.Lab.DSL.FSM

          fsm do
            edge 123 ~> 456, "go"
          end
        end
      )
    end
  end

  test "raises on invalid transition AST" do
    assert_raise ArgumentError, ~r/expected `from ~> to` in FSM DSL/, fn ->
      Code.eval_quoted(
        quote do
          import Choreo.Lab.DSL.FSM

          fsm do
            edge :not_an_arrow, "go"
          end
        end
      )
    end
  end

  test "raises on unsupported modifier" do
    assert_raise ArgumentError, ~r/unsupported FSM transition modifier/, fn ->
      Code.eval_quoted(
        quote do
          import Choreo.Lab.DSL.FSM

          fsm do
            idle = initial("Idle")
            done = final("Done")
            idle ~> done |> bad_modifier()
          end
        end
      )
    end
  end

  test "raises on invalid state constructor positional count" do
    assert_raise ArgumentError,
                 ~r/state constructors take at most one positional label\/id/,
                 fn ->
                   Code.eval_quoted(
                     quote do
                       import Choreo.Lab.DSL.FSM

                       fsm do
                         state("A", "B")
                       end
                     end
                   )
                 end
  end

  test "raises on inline state constructor without label or id" do
    assert_raise ArgumentError, ~r/inline FSM state constructors need a label\/id/, fn ->
      Code.eval_quoted(
        quote do
          import Choreo.Lab.DSL.FSM

          fsm do
            state()
          end
        end
      )
    end
  end
end
