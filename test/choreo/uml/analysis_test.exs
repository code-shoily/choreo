defmodule Choreo.UML.AnalysisTest do
  use ExUnit.Case, async: true

  alias Choreo.UML
  alias Choreo.UML.Analysis
  doctest Choreo.UML.Analysis

  test "cycles/1 detects circular dependency loops" do
    uml =
      UML.new()
      |> UML.add_class(:a)
      |> UML.add_class(:b)
      |> UML.add_class(:c)
      |> UML.add_relationship(:a, :b, type: :associates)
      |> UML.add_relationship(:b, :c, type: :depends)
      |> UML.add_relationship(:c, :a, type: :depends)

    assert Analysis.cycles(uml) == [[:a, :b, :c]]
  end

  test "broken_contracts/1 flags missing functions & arities" do
    # 1. Behavior contract
    uml =
      UML.new()
      |> UML.add_class(:auth_behavior,
        type: :behavior,
        functions: [
          %{name: "verify", arity: 1, return: :ok},
          %{name: "cleanup", arity: 0}
        ]
      )
      # 2. Struct implementing it, but:
      # - missing "cleanup" entirely
      # - "verify" is arity 2 instead of 1
      |> UML.add_class(:user_auth,
        type: :struct,
        functions: [
          %{name: "verify", arity: 2}
        ]
      )
      |> UML.add_relationship(:user_auth, :auth_behavior, type: :realizes)

    broken = Analysis.broken_contracts(uml)
    assert length(broken) == 1
    [{:user_auth, :auth_behavior, missing}] = broken

    assert Enum.any?(
             missing,
             &(Keyword.get(&1, :name) == "verify" and Keyword.get(&1, :arity) == 1)
           )

    assert Enum.any?(
             missing,
             &(Keyword.get(&1, :name) == "cleanup" and Keyword.get(&1, :arity) == 0)
           )
  end

  test "coupling_metrics/1 calculates correct afferent, efferent, and instability" do
    uml =
      UML.new()
      |> UML.add_class(:a)
      |> UML.add_class(:b)
      |> UML.add_class(:c)
      # a depends on b
      |> UML.add_relationship(:a, :b, type: :depends)
      # b depends on c
      |> UML.add_relationship(:b, :c, type: :associates)

    metrics = Analysis.coupling_metrics(uml)

    # A: Ca = 0, Ce = 1 -> I = 1.0
    assert metrics[:a] == %{afferent: 0, efferent: 1, instability: 1.0}

    # B: Ca = 1, Ce = 1 -> I = 0.5
    assert metrics[:b] == %{afferent: 1, efferent: 1, instability: 0.5}

    # C: Ca = 1, Ce = 0 -> I = 0.0
    assert metrics[:c] == %{afferent: 1, efferent: 0, instability: 0.0}
  end

  test "law_of_demeter_violations/1 detects bypass relationships" do
    uml =
      UML.new()
      |> UML.add_class(:a)
      |> UML.add_class(:b)
      |> UML.add_class(:c)
      |> UML.add_class(:d)
      # a -> b -> c (and a -> c directly = violation!)
      |> UML.add_relationship(:a, :b, type: :depends)
      |> UML.add_relationship(:b, :c, type: :depends)
      |> UML.add_relationship(:a, :c, type: :depends)
      # a -> d, but no d -> c, so no violation here
      |> UML.add_relationship(:a, :d, type: :depends)

    assert Analysis.law_of_demeter_violations(uml) == [{:a, :b, :c}]
  end
end
