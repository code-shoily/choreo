defmodule Choreo.Dependency.AnalysisTest do
  use ExUnit.Case

  alias Choreo.Dependency
  alias Choreo.Dependency.Analysis

  describe "cyclic_dependencies/1" do
    test "finds a simple two-node cycle" do
      deps =
        Dependency.new()
        |> Dependency.add_module(:a)
        |> Dependency.add_module(:b)
        |> Dependency.depends_on(:a, :b)
        |> Dependency.depends_on(:b, :a)

      cycles = Analysis.cyclic_dependencies(deps)
      assert length(cycles) == 1
      [cycle] = cycles
      assert hd(cycle) == List.last(cycle)
      assert :a in cycle
      assert :b in cycle
    end

    test "finds a three-node cycle" do
      deps =
        Dependency.new()
        |> Dependency.add_module(:a)
        |> Dependency.add_module(:b)
        |> Dependency.add_module(:c)
        |> Dependency.depends_on(:a, :b)
        |> Dependency.depends_on(:b, :c)
        |> Dependency.depends_on(:c, :a)

      cycles = Analysis.cyclic_dependencies(deps)
      assert length(cycles) == 1
      [cycle] = cycles
      assert hd(cycle) == List.last(cycle)
      assert :a in cycle
      assert :b in cycle
      assert :c in cycle
    end

    test "returns empty for acyclic graph" do
      deps =
        Dependency.new()
        |> Dependency.add_module(:a)
        |> Dependency.add_module(:b)
        |> Dependency.add_module(:c)
        |> Dependency.depends_on(:a, :b)
        |> Dependency.depends_on(:b, :c)

      assert Analysis.cyclic_dependencies(deps) == []
    end

    test "returns empty for empty graph" do
      assert Analysis.cyclic_dependencies(Dependency.new()) == []
    end
  end

  describe "affected_by/2" do
    test "returns transitive dependents" do
      deps =
        Dependency.new()
        |> Dependency.add_application(:api)
        |> Dependency.add_module(:auth)
        |> Dependency.add_module(:util)
        |> Dependency.depends_on(:api, :auth)
        |> Dependency.depends_on(:auth, :util)

      assert Enum.sort(Analysis.affected_by(deps, :util)) == [:api, :auth]
      assert Analysis.affected_by(deps, :auth) == [:api]
      assert Analysis.affected_by(deps, :api) == []
    end
  end

  describe "depends_on/2" do
    test "returns transitive dependencies" do
      deps =
        Dependency.new()
        |> Dependency.add_application(:api)
        |> Dependency.add_module(:auth)
        |> Dependency.add_module(:util)
        |> Dependency.depends_on(:api, :auth)
        |> Dependency.depends_on(:auth, :util)

      assert Enum.sort(Analysis.depends_on(deps, :api)) == [:auth, :util]
      assert Analysis.depends_on(deps, :auth) == [:util]
      assert Analysis.depends_on(deps, :util) == []
    end
  end

  describe "layer_violations/2" do
    test "flags upward dependencies" do
      deps =
        Dependency.new()
        |> Dependency.add_module(:repo)
        |> Dependency.add_module(:service)
        |> Dependency.add_module(:api)
        |> Dependency.depends_on(:service, :repo)
        |> Dependency.depends_on(:repo, :api)

      layers = %{repo: 1, service: 2, api: 3}
      violations = Analysis.layer_violations(deps, layers)

      assert length(violations) == 1
      {from, to, _desc} = hd(violations)
      assert from == :repo
      assert to == :api
    end

    test "allows downward dependencies" do
      deps =
        Dependency.new()
        |> Dependency.add_module(:repo)
        |> Dependency.add_module(:service)
        |> Dependency.depends_on(:service, :repo)

      layers = %{repo: 1, service: 2}
      assert Analysis.layer_violations(deps, layers) == []
    end

    test "ignores nodes not in layer map" do
      deps =
        Dependency.new()
        |> Dependency.add_module(:a)
        |> Dependency.add_module(:b)
        |> Dependency.depends_on(:a, :b)

      assert Analysis.layer_violations(deps, %{}) == []
    end
  end

  describe "transitive_reduction/1" do
    test "finds redundant edge" do
      deps =
        Dependency.new()
        |> Dependency.add_module(:a)
        |> Dependency.add_module(:b)
        |> Dependency.add_module(:c)
        |> Dependency.depends_on(:a, :b)
        |> Dependency.depends_on(:b, :c)
        |> Dependency.depends_on(:a, :c)

      reductions = Analysis.transitive_reduction(deps)
      assert reductions == [{:a, :c}]
    end

    test "returns empty when no redundant edges" do
      deps =
        Dependency.new()
        |> Dependency.add_module(:a)
        |> Dependency.add_module(:b)
        |> Dependency.add_module(:c)
        |> Dependency.depends_on(:a, :b)
        |> Dependency.depends_on(:b, :c)

      assert Analysis.transitive_reduction(deps) == []
    end
  end

  describe "instability/1" do
    test "calculates correct instability scores" do
      deps =
        Dependency.new()
        |> Dependency.add_module(:stable)
        |> Dependency.add_module(:unstable)
        |> Dependency.add_module(:mixed)
        |> Dependency.depends_on(:unstable, :stable)
        |> Dependency.depends_on(:unstable, :mixed)
        |> Dependency.depends_on(:mixed, :stable)

      scores = Analysis.instability(deps)

      # stable has 2 incoming, 0 outgoing -> 0 / (2 + 0) = 0.0
      assert scores.stable == 0.0

      # unstable has 0 incoming, 2 outgoing -> 2 / (0 + 2) = 1.0
      assert scores.unstable == 1.0

      # mixed has 1 incoming, 1 outgoing -> 1 / (1 + 1) = 0.5
      assert scores.mixed == 0.5
    end
  end

  describe "isolated_subsystems/1" do
    test "finds isolated groups" do
      deps =
        Dependency.new()
        |> Dependency.add_module(:a1)
        |> Dependency.add_module(:a2)
        |> Dependency.depends_on(:a1, :a2)
        |> Dependency.add_module(:b1)
        |> Dependency.add_module(:b2)
        |> Dependency.depends_on(:b1, :b2)
        |> Dependency.add_module(:orphan)

      subsystems = Analysis.isolated_subsystems(deps)

      assert length(subsystems) == 3
      assert Enum.any?(subsystems, fn group -> Enum.sort(group) == [:a1, :a2] end)
      assert Enum.any?(subsystems, fn group -> Enum.sort(group) == [:b1, :b2] end)
      assert Enum.any?(subsystems, fn group -> group == [:orphan] end)
    end
  end

  describe "centrality/1" do
    test "ranks by in-degree + out-degree" do
      deps =
        Dependency.new()
        |> Dependency.add_module(:hub)
        |> Dependency.add_module(:a)
        |> Dependency.add_module(:b)
        |> Dependency.add_module(:c)
        |> Dependency.depends_on(:a, :hub)
        |> Dependency.depends_on(:b, :hub)
        |> Dependency.depends_on(:hub, :c)

      ranked = Analysis.centrality(deps)
      assert hd(ranked) == :hub
    end

    test "respects limit" do
      deps =
        Dependency.new()
        |> Dependency.add_module(:a)
        |> Dependency.add_module(:b)
        |> Dependency.add_module(:c)
        |> Dependency.depends_on(:a, :b)
        |> Dependency.depends_on(:b, :c)

      assert length(Analysis.centrality(deps, limit: 2)) == 2
    end
  end

  describe "leaves/1" do
    test "finds nodes with no dependents" do
      deps =
        Dependency.new()
        |> Dependency.add_module(:a)
        |> Dependency.add_module(:b)
        |> Dependency.add_module(:c)
        |> Dependency.depends_on(:a, :b)
        |> Dependency.depends_on(:b, :c)

      # In a dependency graph: a -> b -> c
      # a has in-degree 0 (nothing depends on a)
      assert :a in Analysis.leaves(deps)
    end
  end

  describe "roots/1" do
    test "finds nodes with no dependencies" do
      deps =
        Dependency.new()
        |> Dependency.add_module(:a)
        |> Dependency.add_module(:b)
        |> Dependency.add_module(:c)
        |> Dependency.depends_on(:a, :b)
        |> Dependency.depends_on(:b, :c)

      # a -> b -> c
      # c has out-degree 0 (c depends on nothing)
      assert :c in Analysis.roots(deps)
    end
  end

  describe "longest_dependency_chain/1" do
    test "finds longest chain" do
      deps =
        Dependency.new()
        |> Dependency.add_module(:a)
        |> Dependency.add_module(:b)
        |> Dependency.add_module(:c)
        |> Dependency.depends_on(:a, :b)
        |> Dependency.depends_on(:b, :c)

      assert {:ok, [:a, :b, :c], 2} = Analysis.longest_dependency_chain(deps)
    end

    test "picks longest branch" do
      deps =
        Dependency.new()
        |> Dependency.add_module(:root)
        |> Dependency.add_module(:left)
        |> Dependency.add_module(:right)
        |> Dependency.add_module(:deep)
        |> Dependency.depends_on(:root, :left)
        |> Dependency.depends_on(:root, :right)
        |> Dependency.depends_on(:left, :deep)

      assert {:ok, [:root, :left, :deep], 2} = Analysis.longest_dependency_chain(deps)
    end

    test "returns error for cyclic graph" do
      deps =
        Dependency.new()
        |> Dependency.add_module(:a)
        |> Dependency.add_module(:b)
        |> Dependency.depends_on(:a, :b)
        |> Dependency.depends_on(:b, :a)

      assert :error = Analysis.longest_dependency_chain(deps)
    end

    test "returns error for empty graph" do
      assert :error = Analysis.longest_dependency_chain(Dependency.new())
    end
  end

  describe "validate/1" do
    test "returns empty for clean graph" do
      deps =
        Dependency.new()
        |> Dependency.add_module(:a)
        |> Dependency.add_module(:b)
        |> Dependency.depends_on(:a, :b)

      assert Analysis.validate(deps) == []
    end

    test "flags cycles" do
      deps =
        Dependency.new()
        |> Dependency.add_module(:a)
        |> Dependency.add_module(:b)
        |> Dependency.depends_on(:a, :b)
        |> Dependency.depends_on(:b, :a)

      issues = Analysis.validate(deps)

      assert Enum.any?(issues, fn {sev, msg} ->
               sev == :error and String.contains?(msg, "Circular")
             end)
    end

    test "flags isolated nodes" do
      deps =
        Dependency.new()
        |> Dependency.add_module(:a)
        |> Dependency.add_module(:orphan)
        |> Dependency.depends_on(:a, :a)

      issues = Analysis.validate(deps)

      assert Enum.any?(issues, fn {sev, msg} ->
               sev == :warning and String.contains?(msg, "Isolated")
             end)
    end
  end
end
