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

    test "implicitly registers missing nodes as module nodes" do
      deps =
        Dependency.new()
        |> Dependency.depends_on(:api, :auth)

      assert :api in Dependency.nodes(deps)
      assert :auth in Dependency.nodes(deps)
      assert Map.get(deps.graph.nodes, :api).node_type == :module
      assert Map.get(deps.graph.nodes, :auth).node_type == :module
    end

    test "renders node IDs containing spaces or special characters without syntax errors" do
      deps =
        Dependency.new()
        |> Dependency.depends_on("my api", "my auth module")

      dot = Dependency.to_dot(deps)
      assert String.contains?(dot, "\"my api\"")
      assert String.contains?(dot, "\"my auth module\"")
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

  describe "strict options validation" do
    test "add_application/3 raises on unknown options" do
      assert_raise NimbleOptions.ValidationError, fn ->
        Dependency.new() |> Dependency.add_application(:a, unknown: true)
      end
    end

    test "depends_on/4 raises on invalid type" do
      assert_raise NimbleOptions.ValidationError, fn ->
        Dependency.new()
        |> Dependency.add_application(:a)
        |> Dependency.add_module(:b)
        |> Dependency.depends_on(:a, :b, type: :invalid)
      end
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

  describe "Choreo.Viewable" do
    test "zoom level 0 keeps only applications" do
      deps =
        Dependency.new()
        |> Dependency.add_application(:api)
        |> Dependency.add_library(:phx)
        |> Dependency.add_module(:auth)
        |> Dependency.add_interface(:contract)
        |> Dependency.add_test(:auth_test)
        |> Dependency.depends_on(:api, :phx)
        |> Dependency.depends_on(:api, :auth)

      zoomed = Choreo.View.zoom(deps, level: 0)
      assert Dependency.nodes(zoomed) == [:api]
    end

    test "zoom level 1 keeps applications and libraries" do
      deps =
        Dependency.new()
        |> Dependency.add_application(:api)
        |> Dependency.add_library(:phx)
        |> Dependency.add_module(:auth)
        |> Dependency.add_interface(:contract)
        |> Dependency.depends_on(:api, :phx)
        |> Dependency.depends_on(:api, :auth)

      zoomed = Choreo.View.zoom(deps, level: 1)
      assert Enum.sort(Dependency.nodes(zoomed)) == [:api, :phx]
    end

    test "zoom level 2 keeps applications, libraries, and modules" do
      deps =
        Dependency.new()
        |> Dependency.add_application(:api)
        |> Dependency.add_library(:phx)
        |> Dependency.add_module(:auth)
        |> Dependency.add_interface(:contract)
        |> Dependency.depends_on(:api, :phx)
        |> Dependency.depends_on(:api, :auth)

      zoomed = Choreo.View.zoom(deps, level: 2)
      assert Enum.sort(Dependency.nodes(zoomed)) == [:api, :auth, :phx]
    end

    test "zoom level 3 keeps everything except tests" do
      deps =
        Dependency.new()
        |> Dependency.add_application(:api)
        |> Dependency.add_library(:phx)
        |> Dependency.add_module(:auth)
        |> Dependency.add_interface(:contract)
        |> Dependency.add_test(:auth_test)
        |> Dependency.depends_on(:api, :phx)
        |> Dependency.depends_on(:api, :auth)
        |> Dependency.depends_on(:auth, :contract)

      zoomed = Choreo.View.zoom(deps, level: 3)
      assert Enum.sort(Dependency.nodes(zoomed)) == [:api, :auth, :contract, :phx]
    end

    test "focus keeps node and neighbourhood on multigraph" do
      deps =
        Dependency.new()
        |> Dependency.add_application(:api)
        |> Dependency.add_library(:phx)
        |> Dependency.add_module(:auth)
        |> Dependency.depends_on(:api, :phx)
        |> Dependency.depends_on(:api, :auth)

      focused = Choreo.View.focus(deps, :api, radius: 1)
      assert Enum.sort(Dependency.nodes(focused)) == [:api, :auth, :phx]
    end

    test "filter removes matching nodes on multigraph" do
      deps =
        Dependency.new()
        |> Dependency.add_application(:api)
        |> Dependency.add_library(:phx)
        |> Dependency.add_module(:auth)
        |> Dependency.depends_on(:api, :phx)
        |> Dependency.depends_on(:api, :auth)

      filtered =
        Choreo.View.filter(deps, fn _id, data ->
          data[:node_type] != :module
        end)

      assert Enum.sort(Dependency.nodes(filtered)) == [:api, :phx]
    end

    test "transitive edges add virtual metadata on multigraph" do
      deps =
        Dependency.new()
        |> Dependency.add_application(:api)
        |> Dependency.add_library(:phx)
        |> Dependency.add_module(:auth)
        |> Dependency.depends_on(:api, :auth)
        |> Dependency.depends_on(:auth, :phx)

      filtered =
        Choreo.View.filter(
          deps,
          fn _id, data ->
            data[:node_type] != :module
          end,
          transitive: true
        )

      assert Enum.sort(Dependency.nodes(filtered)) == [:api, :phx]

      edges = Dependency.edges_with_meta(filtered)
      assert length(edges) == 1

      {_from, _to, _weight, meta} = hd(edges)
      assert meta[:edge_type] == :virtual
    end

    test "focus_between finds shortest path on multigraph" do
      deps =
        Dependency.new()
        |> Dependency.add_application(:api)
        |> Dependency.add_module(:auth)
        |> Dependency.add_module(:repo)
        |> Dependency.add_library(:phx)
        |> Dependency.depends_on(:api, :auth)
        |> Dependency.depends_on(:auth, :repo)
        |> Dependency.depends_on(:repo, :phx)

      path = Choreo.View.focus_between(deps, :api, :phx)
      assert Enum.sort(Dependency.nodes(path)) == [:api, :auth, :phx, :repo]
    end

    test "collapse aggregates nodes on multigraph" do
      deps =
        Dependency.new()
        |> Dependency.add_application(:api)
        |> Dependency.add_module(:auth)
        |> Dependency.add_module(:repo)
        |> Dependency.depends_on(:api, :auth)
        |> Dependency.depends_on(:api, :repo)

      collapsed =
        Choreo.View.collapse(
          deps,
          fn _id, data ->
            data[:node_type] == :module
          end,
          :core
        )

      assert :core in Dependency.nodes(collapsed)
      assert :api in Dependency.nodes(collapsed)
      refute :auth in Dependency.nodes(collapsed)
      refute :repo in Dependency.nodes(collapsed)

      edges = Dependency.edges(collapsed)
      assert {:api, :core, _} = Enum.find(edges, fn {f, t, _} -> f == :api and t == :core end)
    end

    test "renderer styles virtual edges" do
      deps =
        Dependency.new()
        |> Dependency.add_application(:api)
        |> Dependency.add_module(:auth)
        |> Dependency.add_library(:phx)
        |> Dependency.depends_on(:api, :auth)
        |> Dependency.depends_on(:auth, :phx)

      filtered =
        Choreo.View.filter(
          deps,
          fn _id, data ->
            data[:node_type] != :module
          end,
          transitive: true
        )

      dot = Dependency.to_dot(filtered)
      assert String.contains?(dot, "#cbd5e1")
    end
  end
end
