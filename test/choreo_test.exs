defmodule ChoreoTest do
  use ExUnit.Case

  alias Choreo

  doctest Choreo

  describe "creation" do
    test "new/0 creates a directed system by default" do
      system = Choreo.new()
      assert %Choreo{} = system
      assert Yog.type(system.graph) == :directed
    end

    test "new/1 can create an undirected system" do
      system = Choreo.new(directed: false)
      assert Yog.type(system.graph) == :undirected
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

    test "add_dataflow/4" do
      system =
        Choreo.new()
        |> Choreo.add_service(:a)
        |> Choreo.add_service(:b)
        |> Choreo.add_dataflow(:a, :b, cost: 5)

      assert [{:a, :b, 5}] = Choreo.edges(system)
      assert get_in(system.edge_meta, [{:a, :b}, :type]) == :dataflow
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
end
