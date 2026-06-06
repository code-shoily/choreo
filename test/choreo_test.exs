defmodule ChoreoTest do
  use ExUnit.Case

  alias Choreo

  doctest Choreo
  doctest Choreo.Theme
  doctest Choreo.Analysis

  describe "creation" do
    test "new/0 creates a directed system by default" do
      system = Choreo.new()
      assert %Choreo{} = system
      assert system.graph.kind == :directed
    end

    test "new/1 can create an undirected system" do
      system = Choreo.new(directed: false)
      assert system.graph.kind == :undirected
    end
  end

  describe "node builders" do
    test "add_database/3" do
      system = Choreo.new() |> Choreo.add_database(:db, kind: :postgres)
      assert Choreo.nodes(system)[:db].type == :database
      assert Choreo.nodes(system)[:db].kind == :postgres
      assert Choreo.nodes(system)[:db].name == "db"
    end

    test "add_cache/3" do
      system = Choreo.new() |> Choreo.add_cache(:cache, kind: :redis)
      assert Choreo.nodes(system)[:cache].type == :cache
    end

    test "add_service/3" do
      system = Choreo.new() |> Choreo.add_service(:api, name: "Gateway")
      assert Choreo.nodes(system)[:api].type == :service
      assert Choreo.nodes(system)[:api].name == "Gateway"
    end

    test "add_network/3" do
      system = Choreo.new() |> Choreo.add_network(:vpc)
      assert Choreo.nodes(system)[:vpc].type == :network
    end

    test "add_user/3" do
      system = Choreo.new() |> Choreo.add_user(:client)
      assert Choreo.nodes(system)[:client].type == :user
    end

    test "add_load_balancer/3" do
      system = Choreo.new() |> Choreo.add_load_balancer(:lb)
      assert Choreo.nodes(system)[:lb].type == :load_balancer
    end

    test "add_queue/3" do
      system = Choreo.new() |> Choreo.add_queue(:q, kind: :kafka)
      assert Choreo.nodes(system)[:q].type == :queue
    end

    test "add_storage/3" do
      system = Choreo.new() |> Choreo.add_storage(:s3)
      assert Choreo.nodes(system)[:s3].type == :storage
    end
  end

  describe "edge builders" do
    test "connect/4 creates a weighted edge" do
      system =
        Choreo.new()
        |> Choreo.add_service(:a)
        |> Choreo.add_service(:b)
        |> Choreo.connect(:a, :b, cost: 42)

      assert [{:a, :b, 42}] = Choreo.edges(system)
    end

    test "connect/4 allows parallel edges" do
      system =
        Choreo.new()
        |> Choreo.add_service(:a)
        |> Choreo.add_service(:b)
        |> Choreo.connect(:a, :b, cost: 42)
        |> Choreo.connect(:a, :b, cost: 99)

      edges = Choreo.edges(system) |> Enum.sort_by(fn {_, _, c} -> c end)
      assert [{:a, :b, 42}, {:a, :b, 99}] = edges
    end

    test "add_dataflow/4" do
      system =
        Choreo.new()
        |> Choreo.add_service(:a)
        |> Choreo.add_service(:b)
        |> Choreo.add_dataflow(:a, :b, cost: 5)

      assert [{:a, :b, 5}] = Choreo.edges(system)
      assert [{:a, :b, 5, meta}] = Choreo.edges_with_meta(system)
      assert meta.type == :dataflow
    end

    test "implicitly registers missing nodes as generic nodes" do
      system =
        Choreo.new()
        |> Choreo.connect(:api, :db)

      assert :api in Map.keys(Choreo.nodes(system))
      assert :db in Map.keys(Choreo.nodes(system))
      assert Choreo.nodes(system)[:api].type == :generic
      assert Choreo.nodes(system)[:db].type == :generic
    end
  end

  describe "rendering" do
    test "to_dot/1 produces a DOT string" do
      system =
        Choreo.new()
        |> Choreo.add_database(:db, kind: :postgres)
        |> Choreo.add_service(:api)
        |> Choreo.connect(:api, :db, cost: 10)

      dot = Choreo.to_dot(system)
      assert String.contains?(dot, "digraph")
      assert String.contains?(dot, "api")
      assert String.contains?(dot, "db")
      assert String.contains?(dot, "shape=\"cylinder\"")
      assert String.contains?(dot, "shape=\"box3d\"")
    end

    test "renders node IDs containing spaces or special characters without syntax errors in DOT" do
      system =
        Choreo.new()
        |> Choreo.connect("my service", "my cache")

      dot = Choreo.to_dot(system)
      assert String.contains?(dot, "\"my service\"")
      assert String.contains?(dot, "\"my cache\"")
    end

    test "to_dot/2 supports dark theme" do
      system =
        Choreo.new()
        |> Choreo.add_service(:api)

      dot = Choreo.to_dot(system, theme: :dark)
      assert String.contains?(dot, "bgcolor=")
    end

    test "to_dot/2 supports minimal theme" do
      system =
        Choreo.new()
        |> Choreo.add_service(:api)

      dot = Choreo.to_dot(system, theme: :minimal)
      assert String.contains?(dot, "shape=\"box\"")
    end

    test "to_dot uses splines instead of ortho" do
      system =
        Choreo.new()
        |> Choreo.add_service(:api)

      dot = Choreo.to_dot(system)
      assert String.contains?(dot, "splines=spline")
      refute String.contains?(dot, "splines=ortho")
    end

    test "to_dot uses label over protocol for edge labels" do
      system =
        Choreo.new()
        |> Choreo.add_service(:api)
        |> Choreo.add_database(:db)
        |> Choreo.connect(:api, :db, protocol: :grpc, label: "Custom Label")

      dot = Choreo.to_dot(system)
      assert String.contains?(dot, "label=\"Custom Label\"")
      refute String.contains?(dot, "label=\"grpc\"")
    end

    test "to_dot adds headport=n for database targets" do
      system =
        Choreo.new()
        |> Choreo.add_database(:db)
        |> Choreo.add_service(:api)
        |> Choreo.connect(:api, :db, cost: 10)

      dot = Choreo.to_dot(system)
      assert String.contains?(dot, "headport=\"n\"")
    end

    test "to_dot respects custom headport/tailport in edge meta" do
      system =
        Choreo.new()
        |> Choreo.add_database(:db)
        |> Choreo.add_service(:api)
        |> Choreo.connect(:api, :db, cost: 10, headport: "c", tailport: "s")

      dot = Choreo.to_dot(system)
      assert String.contains?(dot, "headport=\"c\"")
      assert String.contains?(dot, "tailport=\"s\"")
    end

    test "to_dot renders flat clusters" do
      system =
        Choreo.new()
        |> Choreo.add_cluster("vpc", label: "VPC")
        |> Choreo.add_service(:api, cluster: "vpc")
        |> Choreo.add_database(:db, cluster: "vpc")

      dot = Choreo.to_dot(system)
      assert String.contains?(dot, "subgraph cluster_vpc")
      assert String.contains?(dot, "label=\"VPC\"")
      assert String.contains?(dot, "api")
      assert String.contains?(dot, "db")
    end

    test "to_dot renders nested clusters" do
      system =
        Choreo.new()
        |> Choreo.add_cluster("vpc", label: "VPC")
        |> Choreo.add_cluster("az1", label: "AZ-1", parent: "vpc")
        |> Choreo.add_cluster("az2", label: "AZ-2", parent: "vpc")
        |> Choreo.add_service(:api1, cluster: "az1")
        |> Choreo.add_database(:db1, cluster: "az1")
        |> Choreo.add_service(:api2, cluster: "az2")

      dot = Choreo.to_dot(system)

      assert String.contains?(dot, "subgraph cluster_vpc")
      assert String.contains?(dot, "subgraph cluster_az1")
      assert String.contains?(dot, "subgraph cluster_az2")
      assert String.contains?(dot, "label=\"VPC\"")
      assert String.contains?(dot, "label=\"AZ-1\"")
      assert String.contains?(dot, "label=\"AZ-2\"")

      # Verify nesting: az1 and az2 should appear inside vpc
      assert Regex.match?(
               ~r/subgraph cluster_vpc \{[\s\S]*?subgraph cluster_az1 \{/m,
               dot
             )

      assert Regex.match?(
               ~r/subgraph cluster_vpc \{[\s\S]*?subgraph cluster_az2 \{/m,
               dot
             )
    end

    test "add_cluster auto-prefixes cluster_" do
      system = Choreo.new() |> Choreo.add_cluster("vpc", label: "VPC")
      assert Map.has_key?(system.clusters, "cluster_vpc")
    end

    test "node cluster option is auto-prefixed" do
      system =
        Choreo.new()
        |> Choreo.add_cluster("vpc")
        |> Choreo.add_service(:api, cluster: "vpc")

      assert system.graph.nodes[:api][:cluster] == "cluster_vpc"
    end

    test "to_dot with custom theme overrides colors" do
      system =
        Choreo.new()
        |> Choreo.add_database(:db)
        |> Choreo.add_service(:api)

      theme = Choreo.Theme.custom(colors: %{database: "#ff0000"})
      dot = Choreo.to_dot(system, theme: theme)

      assert String.contains?(dot, "fillcolor=\"#ff0000\"")
    end

    test "to_dot with custom theme overrides shapes" do
      system =
        Choreo.new()
        |> Choreo.add_database(:db)

      theme = Choreo.Theme.custom(shapes: %{database: :box})
      dot = Choreo.to_dot(system, theme: theme)

      assert String.contains?(dot, "shape=\"box\"")
      refute String.contains?(dot, "shape=\"cylinder\"")
    end

    test "to_dot with custom theme sets graph attrs" do
      system =
        Choreo.new()
        |> Choreo.add_service(:api)

      theme = Choreo.Theme.custom(graph_bgcolor: "#abc123", graph_rankdir: :lr)
      dot = Choreo.to_dot(system, theme: theme)

      assert String.contains?(dot, "bgcolor=\"#abc123\"")
      assert String.contains?(dot, "rankdir=LR")
    end

    test "to_dot with minimal theme uses monochrome boxes" do
      system =
        Choreo.new()
        |> Choreo.add_database(:db)
        |> Choreo.add_service(:api)

      dot = Choreo.to_dot(system, theme: :minimal)

      assert String.contains?(dot, "shape=\"box\"")
      assert String.contains?(dot, "fillcolor=\"#ffffff\"")
    end

    test "theme cluster defaults are applied to clusters" do
      system =
        Choreo.new()
        |> Choreo.add_cluster("vpc")
        |> Choreo.add_service(:api, cluster: "vpc")

      theme = Choreo.Theme.custom(cluster_fillcolor: "#e2e8f0", cluster_style: :rounded)
      dot = Choreo.to_dot(system, theme: theme)

      assert String.contains?(dot, "fillcolor=\"#e2e8f0\"")
      assert String.contains?(dot, "style=rounded")
    end

    test "exhaustive theme and render overrides coverage" do
      assert %Choreo.Theme{} = Choreo.Theme.warm()
      assert %Choreo.Theme{} = Choreo.Theme.forest()
      assert %Choreo.Theme{} = Choreo.Theme.ocean()

      system =
        Choreo.new()
        |> Choreo.add_database(:db, description: "Main DB")
        |> Choreo.add_service(:api, penwidth: 3)
        |> Choreo.connect(:api, :db, protocol: :grpc, headport: "n", tailport: "s")

      # Render across presets
      assert Choreo.to_dot(system, theme: :warm) =~ "db"
      assert Choreo.to_dot(system, theme: :forest) =~ "db"
      assert Choreo.to_dot(system, theme: :ocean) =~ "db"
    end

    test "Choreo.Theme.override/2 deep merges colors and shapes" do
      base = Choreo.Theme.default()

      overridden =
        Choreo.Theme.override(base,
          graph_rankdir: :lr,
          colors: %{database: "#ffffff"},
          shapes: %{api: :ellipse}
        )

      assert overridden.graph_rankdir == :lr
      # Existing colors should remain (use helper)
      assert Choreo.Theme.color(overridden, :cache) == Choreo.Theme.color(base, :cache)
      # Provided color should be overridden
      assert Choreo.Theme.color(overridden, :database) == "#ffffff"
      # Shapes should be overridden
      assert Choreo.Theme.shape(overridden, :api) == :ellipse
    end

    test "Choreo.theme/2 helper returns overridden theme" do
      theme = Choreo.theme(:dark, graph_rankdir: :td, colors: %{database: "#123456"})

      assert theme.graph_rankdir == :td
      assert Choreo.Theme.color(theme, :database) == "#123456"
      # Inherits from dark theme
      assert theme.graph_bgcolor == "#0f172a"
    end
  end

  describe "mermaid rendering" do
    test "to_mermaid/1 produces a Mermaid string" do
      system =
        Choreo.new()
        |> Choreo.add_database(:db, kind: :postgres)
        |> Choreo.add_service(:api)
        |> Choreo.connect(:api, :db, cost: 10)

      mermaid = Choreo.to_mermaid(system)
      assert String.contains?(mermaid, "graph TD")
      assert String.contains?(mermaid, "api")
      assert String.contains?(mermaid, "db")
      assert String.contains?(mermaid, "[(\"db\")]")
      assert String.contains?(mermaid, "[[\"api\"]]")
    end

    test "to_mermaid/2 supports dark theme" do
      system =
        Choreo.new()
        |> Choreo.add_service(:api)

      mermaid = Choreo.to_mermaid(system, theme: :dark)
      assert String.contains?(mermaid, "graph TD")
      assert String.contains?(mermaid, "api")
    end

    test "to_mermaid/2 supports minimal theme" do
      system =
        Choreo.new()
        |> Choreo.add_service(:api)

      mermaid = Choreo.to_mermaid(system, theme: :minimal)
      assert String.contains?(mermaid, "api")
    end

    test "to_mermaid respects custom direction" do
      system =
        Choreo.new()
        |> Choreo.add_service(:api)

      mermaid = Choreo.to_mermaid(system, direction: :lr)
      assert String.contains?(mermaid, "graph LR")
    end

    test "to_mermaid uses type-based shapes" do
      system =
        Choreo.new()
        |> Choreo.add_database(:db)
        |> Choreo.add_cache(:cache)
        |> Choreo.add_service(:api)
        |> Choreo.add_user(:user)
        |> Choreo.add_load_balancer(:lb)
        |> Choreo.add_queue(:q)
        |> Choreo.add_storage(:s3)

      mermaid = Choreo.to_mermaid(system)
      assert String.contains?(mermaid, "[(\"db\")]")
      assert String.contains?(mermaid, "{{\"cache\"}}")
      assert String.contains?(mermaid, "[[\"api\"]]")
      assert String.contains?(mermaid, "((\"user\"))")
      assert String.contains?(mermaid, "([\"q\"])")
    end

    test "to_mermaid renders flat clusters as subgraphs" do
      system =
        Choreo.new()
        |> Choreo.add_cluster("vpc", label: "VPC")
        |> Choreo.add_service(:api, cluster: "vpc")
        |> Choreo.add_database(:db, cluster: "vpc")

      mermaid = Choreo.to_mermaid(system)
      assert String.contains?(mermaid, "subgraph vpc")
      assert String.contains?(mermaid, "[\"VPC\"]")
      assert String.contains?(mermaid, "api")
      assert String.contains?(mermaid, "db")
    end

    test "to_mermaid with custom theme overrides colors" do
      system =
        Choreo.new()
        |> Choreo.add_database(:db)
        |> Choreo.add_service(:api)

      theme = Choreo.Theme.custom(colors: %{database: "#ff0000"})
      mermaid = Choreo.to_mermaid(system, theme: theme)

      assert String.contains?(mermaid, "#ff0000")
    end

    test "to_mermaid with custom theme overrides shapes" do
      system =
        Choreo.new()
        |> Choreo.add_database(:db)

      theme = Choreo.Theme.custom(shapes: %{database: :circle})
      mermaid = Choreo.to_mermaid(system, theme: theme)

      assert String.contains?(mermaid, "((\"db\"))")
    end

    test "to_mermaid renders dataflow edges with dashed style" do
      system =
        Choreo.new()
        |> Choreo.add_service(:a)
        |> Choreo.add_service(:b)
        |> Choreo.add_dataflow(:a, :b)

      mermaid = Choreo.to_mermaid(system)
      assert String.contains?(mermaid, "[[\"a\"]]")
      assert String.contains?(mermaid, "[[\"b\"]]")
      assert mermaid =~ ~r/n_\d+ --> n_\d+/
      assert String.contains?(mermaid, "stroke-dasharray")
    end

    test "to_mermaid renders protocol labels on edges" do
      system =
        Choreo.new()
        |> Choreo.add_service(:a)
        |> Choreo.add_service(:b)
        |> Choreo.connect(:a, :b, protocol: :https)

      mermaid = Choreo.to_mermaid(system)
      assert mermaid =~ ~r/n_\d+ -->\|https\| n_\d+/
    end

    test "to_mermaid renders explicit edge labels" do
      system =
        Choreo.new()
        |> Choreo.add_service(:a)
        |> Choreo.add_service(:b)
        |> Choreo.connect(:a, :b, label: "Custom")

      mermaid = Choreo.to_mermaid(system)
      assert mermaid =~ ~r/n_\d+ -->\|Custom\| n_\d+/
    end

    test "to_mermaid styles virtual edges lightly" do
      system =
        Choreo.new()
        |> Choreo.add_service(:api)
        |> Choreo.add_database(:db)
        |> Choreo.add_cache(:cache)
        |> Choreo.connect(:api, :db)
        |> Choreo.connect(:db, :cache)

      filtered =
        Choreo.View.filter(
          system,
          fn _id, data -> data[:type] != :database end,
          transitive: true
        )

      mermaid = Choreo.to_mermaid(filtered)
      assert String.contains?(mermaid, "#cbd5e1")
    end

    test "to_dot supports custom edge_label callback when no protocol/label set" do
      system =
        Choreo.new()
        |> Choreo.add_service(:a)
        |> Choreo.add_service(:b)
        |> Choreo.connect(:a, :b, cost: 42)

      dot =
        Choreo.Render.DOT.to_dot(system,
          edge_label: fn _edge_id, weight -> "cost=#{weight}" end
        )

      assert String.contains?(dot, "label=\"cost=42\"")
    end

    test "to_mermaid supports custom edge_label callback" do
      system =
        Choreo.new()
        |> Choreo.add_service(:a)
        |> Choreo.add_service(:b)
        |> Choreo.connect(:a, :b, cost: 42, protocol: :http)

      mermaid =
        Choreo.Render.Mermaid.to_mermaid(system,
          edge_label: fn _edge_id, weight -> "cost=#{weight}" end
        )

      assert mermaid =~ ~r/n_\d+ -->\|cost=42\| n_\d+/
    end

    test "exhaustive mermaid theme coverage" do
      system =
        Choreo.new()
        |> Choreo.add_database(:db, description: "Main DB")
        |> Choreo.add_service(:api, penwidth: 3)
        |> Choreo.connect(:api, :db, protocol: :grpc)

      assert Choreo.to_mermaid(system, theme: :warm) =~ "db"
      assert Choreo.to_mermaid(system, theme: :forest) =~ "db"
      assert Choreo.to_mermaid(system, theme: :ocean) =~ "db"
      assert Choreo.to_mermaid(system, theme: :dark) =~ "db"
      assert Choreo.to_mermaid(system, theme: :minimal) =~ "db"
    end

    test "to_mermaid respects highlighted nodes and edges" do
      system =
        Choreo.new()
        |> Choreo.add_service(:a)
        |> Choreo.add_service(:b)
        |> Choreo.connect(:a, :b)

      mermaid =
        Choreo.to_mermaid(system,
          highlighted_nodes: [:a],
          highlighted_edges: [{:a, :b}]
        )

      assert String.contains?(mermaid, ":::highlight")
      assert String.contains?(mermaid, "classDef highlight")
    end
  end

  describe "analysis" do
    test "topological_sort on a DAG" do
      system =
        Choreo.new()
        |> Choreo.add_service(:a)
        |> Choreo.add_service(:b)
        |> Choreo.add_service(:c)
        |> Choreo.add_dataflow(:a, :b)
        |> Choreo.add_dataflow(:b, :c)

      assert {:ok, [:a, :b, :c]} = Choreo.Analysis.topological_sort(system)
    end

    test "cyclic? and dag?" do
      dag =
        Choreo.new()
        |> Choreo.add_service(:a)
        |> Choreo.add_service(:b)
        |> Choreo.connect(:a, :b)

      refute Choreo.Analysis.cyclic?(dag)
      assert Choreo.Analysis.dag?(dag)

      cyc =
        Choreo.new()
        |> Choreo.add_service(:a)
        |> Choreo.add_service(:b)
        |> Choreo.connect(:a, :b)
        |> Choreo.connect(:b, :a)

      assert Choreo.Analysis.cyclic?(cyc)
      refute Choreo.Analysis.dag?(cyc)
    end

    test "mst on undirected system" do
      system =
        Choreo.new(directed: false)
        |> Choreo.add_database(:db)
        |> Choreo.add_service(:api)
        |> Choreo.add_cache(:cache)
        |> Choreo.connect(:api, :db, cost: 10)
        |> Choreo.connect(:api, :cache, cost: 5)
        |> Choreo.connect(:db, :cache, cost: 20)

      assert {:ok, result} = Choreo.Analysis.mst(system)
      assert result.total_weight == 15
    end

    test "mst on directed system converts to undirected" do
      system =
        Choreo.new()
        |> Choreo.add_database(:db)
        |> Choreo.add_service(:api)
        |> Choreo.add_cache(:cache)
        |> Choreo.connect(:api, :db, cost: 10)
        |> Choreo.connect(:api, :cache, cost: 5)
        |> Choreo.connect(:db, :cache, cost: 20)

      assert {:ok, result} = Choreo.Analysis.mst(system)
      assert result.total_weight == 15
    end

    test "strongly_connected_components" do
      system =
        Choreo.new()
        |> Choreo.add_service(:a)
        |> Choreo.add_service(:b)
        |> Choreo.add_service(:c)
        |> Choreo.connect(:a, :b)
        |> Choreo.connect(:b, :a)
        |> Choreo.connect(:b, :c)

      components = Choreo.Analysis.strongly_connected_components(system)
      # a and b are in one SCC, c is alone
      assert length(components) == 2
    end
  end

  describe "Choreo.Viewable" do
    test "zoom level 0 keeps only services" do
      system =
        Choreo.new()
        |> Choreo.add_service(:api)
        |> Choreo.add_database(:db)
        |> Choreo.add_cache(:cache)
        |> Choreo.add_network(:vpc)
        |> Choreo.add_user(:client)
        |> Choreo.connect(:api, :db)
        |> Choreo.connect(:api, :cache)

      zoomed = Choreo.View.zoom(system, level: 0)
      assert Map.keys(Choreo.nodes(zoomed)) == [:api]
    end

    test "zoom level 1 keeps services and data layer" do
      system =
        Choreo.new()
        |> Choreo.add_service(:api)
        |> Choreo.add_database(:db)
        |> Choreo.add_cache(:cache)
        |> Choreo.add_queue(:q)
        |> Choreo.add_storage(:s3)
        |> Choreo.add_network(:vpc)
        |> Choreo.add_user(:client)
        |> Choreo.connect(:api, :db)
        |> Choreo.connect(:api, :cache)

      zoomed = Choreo.View.zoom(system, level: 1)
      assert Enum.sort(Map.keys(Choreo.nodes(zoomed))) == [:api, :cache, :db, :q, :s3]
    end

    test "zoom level 2 adds infrastructure layer" do
      system =
        Choreo.new()
        |> Choreo.add_service(:api)
        |> Choreo.add_database(:db)
        |> Choreo.add_cache(:cache)
        |> Choreo.add_load_balancer(:lb)
        |> Choreo.add_network(:vpc)
        |> Choreo.add_user(:client)
        |> Choreo.connect(:api, :db)
        |> Choreo.connect(:api, :cache)

      zoomed = Choreo.View.zoom(system, level: 2)
      assert Enum.sort(Map.keys(Choreo.nodes(zoomed))) == [:api, :cache, :db, :lb, :vpc]
    end

    test "focus keeps node and neighbourhood on multigraph" do
      system =
        Choreo.new()
        |> Choreo.add_service(:api)
        |> Choreo.add_database(:db)
        |> Choreo.add_cache(:cache)
        |> Choreo.connect(:api, :db)
        |> Choreo.connect(:api, :cache)

      focused = Choreo.View.focus(system, :api, radius: 1)
      assert Enum.sort(Map.keys(Choreo.nodes(focused))) == [:api, :cache, :db]
    end

    test "filter removes matching nodes on multigraph" do
      system =
        Choreo.new()
        |> Choreo.add_service(:api)
        |> Choreo.add_database(:db)
        |> Choreo.add_cache(:cache)
        |> Choreo.connect(:api, :db)
        |> Choreo.connect(:api, :cache)

      filtered =
        Choreo.View.filter(system, fn _id, data ->
          data[:type] != :database
        end)

      assert Enum.sort(Map.keys(Choreo.nodes(filtered))) == [:api, :cache]
    end

    test "transitive edges add virtual metadata on multigraph" do
      system =
        Choreo.new()
        |> Choreo.add_service(:api)
        |> Choreo.add_database(:db)
        |> Choreo.add_cache(:cache)
        |> Choreo.connect(:api, :db)
        |> Choreo.connect(:db, :cache)

      filtered =
        Choreo.View.filter(
          system,
          fn _id, data ->
            data[:type] != :database
          end,
          transitive: true
        )

      assert Enum.sort(Map.keys(Choreo.nodes(filtered))) == [:api, :cache]

      edges = Choreo.edges_with_meta(filtered)
      assert length(edges) == 1

      {_from, _to, _weight, meta} = hd(edges)
      assert meta[:edge_type] == :virtual
    end

    test "focus_between finds shortest path on multigraph" do
      system =
        Choreo.new()
        |> Choreo.add_service(:api)
        |> Choreo.add_database(:db)
        |> Choreo.add_cache(:cache)
        |> Choreo.add_storage(:s3)
        |> Choreo.connect(:api, :db)
        |> Choreo.connect(:db, :cache)
        |> Choreo.connect(:cache, :s3)

      path = Choreo.View.focus_between(system, :api, :s3)
      assert Enum.sort(Map.keys(Choreo.nodes(path))) == [:api, :cache, :db, :s3]
    end

    test "collapse aggregates nodes on multigraph" do
      system =
        Choreo.new()
        |> Choreo.add_service(:api)
        |> Choreo.add_database(:db)
        |> Choreo.add_cache(:cache)
        |> Choreo.connect(:api, :db)
        |> Choreo.connect(:api, :cache)

      collapsed =
        Choreo.View.collapse(
          system,
          fn _id, data ->
            data[:type] in [:database, :cache]
          end,
          :data_layer
        )

      assert :data_layer in Map.keys(Choreo.nodes(collapsed))
      assert :api in Map.keys(Choreo.nodes(collapsed))
      refute :db in Map.keys(Choreo.nodes(collapsed))
      refute :cache in Map.keys(Choreo.nodes(collapsed))

      edges = Choreo.edges(collapsed)

      assert {:api, :data_layer, _} =
               Enum.find(edges, fn {f, t, _} -> f == :api and t == :data_layer end)
    end

    test "renderer styles virtual edges" do
      system =
        Choreo.new()
        |> Choreo.add_service(:api)
        |> Choreo.add_database(:db)
        |> Choreo.add_cache(:cache)
        |> Choreo.connect(:api, :db)
        |> Choreo.connect(:db, :cache)

      filtered =
        Choreo.View.filter(
          system,
          fn _id, data ->
            data[:type] != :database
          end,
          transitive: true
        )

      dot = Choreo.to_dot(filtered)
      assert String.contains?(dot, "#cbd5e1")
    end
  end
end
