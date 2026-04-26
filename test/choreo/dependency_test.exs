defmodule Choreo.DependencyTest do
  use ExUnit.Case

  doctest Choreo.Dependency
  doctest Choreo.Dependency.Render.DOT

  alias Choreo.Dependency

  describe "new/0" do
    test "creates an empty directed graph" do
      deps = Dependency.new()
      assert Dependency.nodes(deps) == []
      assert Dependency.edges(deps) == []
    end
  end

  describe "node builders" do
    test "add_application/3" do
      deps = Dependency.new() |> Dependency.add_application(:api, label: "API")
      assert :api in Dependency.nodes(deps)
      assert Map.get(deps.graph.nodes, :api).node_type == :application
      assert Map.get(deps.graph.nodes, :api).label == "API"
    end

    test "add_library/3" do
      deps = Dependency.new() |> Dependency.add_library(:phx, label: "Phoenix")
      assert :phx in Dependency.nodes(deps)
      assert Map.get(deps.graph.nodes, :phx).node_type == :library
    end

    test "add_module/3" do
      deps = Dependency.new() |> Dependency.add_module(:auth)
      assert :auth in Dependency.nodes(deps)
      assert Map.get(deps.graph.nodes, :auth).node_type == :module
    end

    test "add_interface/3" do
      deps = Dependency.new() |> Dependency.add_interface(:contract)
      assert :contract in Dependency.nodes(deps)
      assert Map.get(deps.graph.nodes, :contract).node_type == :interface
    end

    test "add_test/3" do
      deps = Dependency.new() |> Dependency.add_test(:auth_test)
      assert :auth_test in Dependency.nodes(deps)
      assert Map.get(deps.graph.nodes, :auth_test).node_type == :test
    end
  end

  describe "depends_on/4" do
    test "creates a dependency edge" do
      deps =
        Dependency.new()
        |> Dependency.add_application(:api)
        |> Dependency.add_module(:auth)
        |> Dependency.depends_on(:api, :auth)

      assert [{:api, :auth, _, meta}] = Dependency.edges_with_meta(deps)
      assert meta.type == :uses
    end

    test "stores edge type" do
      deps =
        Dependency.new()
        |> Dependency.add_application(:api)
        |> Dependency.add_module(:auth)
        |> Dependency.depends_on(:api, :auth, type: :calls)

      assert [{:api, :auth, _, meta}] = Dependency.edges_with_meta(deps)
      assert meta.type == :calls
      assert meta.label == "calls"
    end

    test "supports dev dependency" do
      deps =
        Dependency.new()
        |> Dependency.add_application(:api)
        |> Dependency.add_library(:mox)
        |> Dependency.depends_on(:api, :mox, type: :dev)

      assert [{:api, :mox, _, meta}] = Dependency.edges_with_meta(deps)
      assert meta.type == :dev
    end

    test "allows parallel connections" do
      deps =
        Dependency.new()
        |> Dependency.add_application(:api)
        |> Dependency.add_module(:auth)
        |> Dependency.depends_on(:api, :auth, type: :calls)
        |> Dependency.depends_on(:api, :auth, type: :uses)

      assert length(Dependency.edges(deps)) == 2
    end
  end

  describe "clusters" do
    test "add_cluster/3" do
      deps =
        Dependency.new()
        |> Dependency.add_cluster("core", label: "Core")

      assert deps.clusters["cluster_core"].label == "Core"
    end

    test "nodes can belong to clusters" do
      deps =
        Dependency.new()
        |> Dependency.add_cluster("core")
        |> Dependency.add_module(:auth, cluster: "core")

      assert Map.get(deps.graph.nodes, :auth).cluster == "cluster_core"
    end
  end

  describe "nodes_of_type/2" do
    test "filters by node type" do
      deps =
        Dependency.new()
        |> Dependency.add_application(:a)
        |> Dependency.add_application(:b)
        |> Dependency.add_library(:c)
        |> Dependency.add_module(:d)

      assert Enum.sort(Dependency.nodes_of_type(deps, :application)) == [:a, :b]
      assert Dependency.nodes_of_type(deps, :library) == [:c]
      assert Dependency.nodes_of_type(deps, :module) == [:d]
    end
  end

  describe "to_dot/2" do
    test "renders a non-empty DOT string" do
      deps =
        Dependency.new()
        |> Dependency.add_application(:api, label: "API")
        |> Dependency.add_module(:auth, label: "Auth")
        |> Dependency.depends_on(:api, :auth)

      dot = Dependency.to_dot(deps)
      assert String.contains?(dot, "digraph")
      assert String.contains?(dot, "API")
      assert String.contains?(dot, "Auth")
    end

    test "renders cycles in red" do
      deps =
        Dependency.new()
        |> Dependency.add_module(:a)
        |> Dependency.add_module(:b)
        |> Dependency.depends_on(:a, :b)
        |> Dependency.depends_on(:b, :a)

      dot = Dependency.to_dot(deps)
      assert String.contains?(dot, "#ef4444")
    end

    test "renders clusters" do
      deps =
        Dependency.new()
        |> Dependency.add_cluster("core", label: "Core")
        |> Dependency.add_module(:auth, cluster: "core")
        |> Dependency.add_application(:api)
        |> Dependency.depends_on(:api, :auth)

      dot = Dependency.to_dot(deps)
      assert String.contains?(dot, "subgraph cluster_core")
    end

    test "renders with dark theme" do
      deps =
        Dependency.new()
        |> Dependency.add_application(:api)
        |> Dependency.add_module(:auth)
        |> Dependency.depends_on(:api, :auth)

      dot = Dependency.to_dot(deps, theme: :dark)
      assert String.contains?(dot, "digraph")
    end
  end
end
