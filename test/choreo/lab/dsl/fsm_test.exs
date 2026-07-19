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
end
