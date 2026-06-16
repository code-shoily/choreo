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

  test "coupling_metrics/1 handles empty and isolated diagrams" do
    assert Analysis.coupling_metrics(UML.new()) == %{}

    isolated =
      UML.new()
      |> UML.add_class(:a)
      |> UML.add_class(:b)

    metrics = Analysis.coupling_metrics(isolated)
    assert metrics[:a] == %{afferent: 0, efferent: 0, instability: 0.0}
    assert metrics[:b] == %{afferent: 0, efferent: 0, instability: 0.0}
  end

  test "broken_contracts/1 returns empty when contract is satisfied" do
    uml =
      UML.new()
      |> UML.add_class(:auth_behavior,
        type: :behavior,
        functions: [%{name: "verify", arity: 1}]
      )
      |> UML.add_class(:provider,
        type: :struct,
        functions: [%{name: "verify", arity: 1}]
      )
      |> UML.add_relationship(:provider, :auth_behavior, type: :realizes)

    assert Analysis.broken_contracts(uml) == []
  end

  test "broken_contracts/1 returns empty for unrelated relationships" do
    uml =
      UML.new()
      |> UML.add_class(:a)
      |> UML.add_class(:b)
      |> UML.add_relationship(:a, :b, type: :depends)

    assert Analysis.broken_contracts(uml) == []
  end

  test "law_of_demeter_violations/1 returns empty for empty and acyclic diagrams" do
    assert Analysis.law_of_demeter_violations(UML.new()) == []

    acyclic =
      UML.new()
      |> UML.add_class(:a)
      |> UML.add_class(:b)
      |> UML.add_class(:c)
      |> UML.add_relationship(:a, :b, type: :depends)
      |> UML.add_relationship(:b, :c, type: :depends)

    assert Analysis.law_of_demeter_violations(acyclic) == []
  end

  describe "dependency analyses" do
    test "affected_by/2 returns transitive dependents" do
      uml =
        UML.new()
        |> UML.add_class(:api)
        |> UML.add_class(:service)
        |> UML.add_class(:repo)
        |> UML.add_relationship(:api, :service, type: :depends)
        |> UML.add_relationship(:service, :repo, type: :depends)

      assert Enum.sort(Analysis.affected_by(uml, :repo)) == [:api, :service]
      assert Enum.sort(Analysis.affected_by(uml, :service)) == [:api]
      assert Analysis.affected_by(uml, :api) == []
    end

    test "depends_on/2 returns transitive dependencies" do
      uml =
        UML.new()
        |> UML.add_class(:api)
        |> UML.add_class(:service)
        |> UML.add_class(:repo)
        |> UML.add_relationship(:api, :service, type: :depends)
        |> UML.add_relationship(:service, :repo, type: :depends)

      assert Enum.sort(Analysis.depends_on(uml, :api)) == [:repo, :service]
      assert Enum.sort(Analysis.depends_on(uml, :service)) == [:repo]
      assert Analysis.depends_on(uml, :repo) == []
    end

    test "affected_by/2 and depends_on/2 handle missing targets" do
      uml = UML.new() |> UML.add_class(:a)
      assert Analysis.affected_by(uml, :missing) == []
      assert Analysis.depends_on(uml, :missing) == []
    end

    test "transitive_reduction/1 identifies redundant edges" do
      uml =
        UML.new()
        |> UML.add_class(:api)
        |> UML.add_class(:service)
        |> UML.add_class(:repo)
        |> UML.add_relationship(:api, :service, type: :depends)
        |> UML.add_relationship(:service, :repo, type: :depends)
        |> UML.add_relationship(:api, :repo, type: :depends)

      assert Analysis.transitive_reduction(uml) == [{:api, :repo}]
    end

    test "transitive_reduction/1 returns empty for cycles" do
      uml =
        UML.new()
        |> UML.add_class(:a)
        |> UML.add_class(:b)
        |> UML.add_class(:c)
        |> UML.add_relationship(:a, :b, type: :depends)
        |> UML.add_relationship(:b, :c, type: :depends)
        |> UML.add_relationship(:c, :a, type: :depends)

      assert Analysis.transitive_reduction(uml) == []
    end

    test "validate/1 reports cycles, broken contracts, and isolated classes" do
      uml =
        UML.new()
        |> UML.add_class(:a)
        |> UML.add_class(:b)
        |> UML.add_class(:lonely)
        |> UML.add_relationship(:a, :b, type: :associates)
        |> UML.add_relationship(:b, :a, type: :depends)

      issues = Analysis.validate(uml)
      assert Enum.any?(issues, fn {sev, msg} -> sev == :error and msg =~ "Circular" end)
      assert Enum.any?(issues, fn {sev, msg} -> sev == :warning and msg =~ "lonely" end)
    end

    test "validate/1 reports broken contracts as errors" do
      uml =
        UML.new()
        |> UML.add_class(:auth_behavior,
          type: :behavior,
          functions: [%{name: "verify", arity: 1}]
        )
        |> UML.add_class(:provider, type: :struct, functions: [])
        |> UML.add_relationship(:provider, :auth_behavior, type: :realizes)

      issues = Analysis.validate(uml)
      assert Enum.any?(issues, fn {sev, msg} -> sev == :error and msg =~ "missing functions" end)
    end

    test "validate/1 reports Law of Demeter violations as warnings" do
      uml =
        UML.new()
        |> UML.add_class(:a)
        |> UML.add_class(:b)
        |> UML.add_class(:c)
        |> UML.add_relationship(:a, :b, type: :depends)
        |> UML.add_relationship(:b, :c, type: :depends)
        |> UML.add_relationship(:a, :c, type: :depends)

      issues = Analysis.validate(uml)
      assert Enum.any?(issues, fn {sev, msg} -> sev == :warning and msg =~ "Law of Demeter" end)
    end

    test "validate/1 returns empty for clean diagrams" do
      uml =
        UML.new()
        |> UML.add_class(:a)
        |> UML.add_class(:b)
        |> UML.add_relationship(:a, :b, type: :depends)

      assert Analysis.validate(uml) == []
    end
  end
end
