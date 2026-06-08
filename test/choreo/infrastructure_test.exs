defmodule Choreo.InfrastructureTest do
  use ExUnit.Case, async: true

  alias Choreo.Infrastructure

  test "building an infrastructure topology" do
    infra =
      Infrastructure.new()
      |> Infrastructure.add_internet(:gateway, label: "Internet")
      |> Infrastructure.add_vpc("vpc_prod", label: "Prod VPC")
      |> Infrastructure.add_subnet_public("subnet_dmz", label: "DMZ", parent: "vpc_prod")
      |> Infrastructure.add_subnet_private("subnet_app", label: "App Subnet", parent: "vpc_prod")
      |> Infrastructure.add_load_balancer(:alb, label: "ALB", cluster: "subnet_dmz")
      |> Infrastructure.add_compute(:app, label: "App Server", cluster: "subnet_app")
      |> Infrastructure.add_managed_db(:db, label: "Postgres RDS", cluster: "subnet_app")
      |> Infrastructure.add_storage(:s3, label: "Blob storage")
      |> Infrastructure.connect(:gateway, :alb, protocol: :https, label: "Traffic")
      |> Infrastructure.connect(:alb, :app, protocol: :http)
      |> Infrastructure.connect(:app, :db, protocol: :tcp)
      |> Infrastructure.connect(:app, :s3, protocol: :https)

    assert Enum.sort(Infrastructure.nodes(infra)) == [:alb, :app, :db, :gateway, :s3]
    assert Enum.count(Infrastructure.edges(infra)) == 4

    # Verify edge metadata
    edge_meta = infra.edge_meta |> Map.values()
    assert Enum.any?(edge_meta, &(&1[:protocol] == :https and &1[:label] == "Traffic"))
    assert Enum.any?(edge_meta, &(&1[:protocol] == :http))
  end

  test "nodes/1 and edges/1 return empty for new diagram" do
    infra = Infrastructure.new()
    assert Infrastructure.nodes(infra) == []
    assert Infrastructure.edges(infra) == []
  end

  test "DOT rendering with default and custom overrides" do
    infra =
      Infrastructure.new()
      |> Infrastructure.add_load_balancer(:lb, label: "LB", fillcolor: "#ff0000", shape: :circle)
      |> Infrastructure.add_compute(:web, label: "Web", penwidth: 4.5)

    dot = Infrastructure.to_dot(infra)

    assert dot =~ "digraph"
    assert dot =~ "lb ["
    assert dot =~ "fillcolor=\"#ff0000\""
    assert dot =~ "shape=\"circle\""
    assert dot =~ "web ["
    assert dot =~ "penwidth=\"4.5\""
  end

  test "DOT rendering with all node attribute overrides" do
    infra =
      Infrastructure.new()
      |> Infrastructure.add_compute(:app,
        label: "App",
        description: "Main application",
        fontcolor: "#ffffff",
        style: "rounded",
        image: "app.png"
      )

    dot = Infrastructure.to_dot(infra)
    assert dot =~ "tooltip=\"Main application\""
    assert dot =~ "fontcolor=\"#ffffff\""
    assert dot =~ "style=\"rounded\""
    assert dot =~ "image=\"app.png\""
  end

  test "DOT rendering with edge label and highlighted edges" do
    infra =
      Infrastructure.new()
      |> Infrastructure.add_internet(:gw)
      |> Infrastructure.add_compute(:app)
      |> Infrastructure.connect(:gw, :app, protocol: :https, label: "TLS")

    dot = Infrastructure.to_dot(infra, highlighted_edges: [{:gw, :app}])
    assert dot =~ "label=\"TLS\""
    assert dot =~ "color=\"#ef4444\""
    assert dot =~ "penwidth=\"2.0\""
  end

  test "DOT rendering with highlighted nodes and string edge ids" do
    infra =
      Infrastructure.new()
      |> Infrastructure.add_internet(:gw)
      |> Infrastructure.add_compute(:app)
      |> Infrastructure.connect(:gw, :app)

    dot =
      Infrastructure.to_dot(infra, highlighted_nodes: [:gw], highlighted_edges: ["some_edge_id"])

    assert dot =~ "gw ["
  end

  test "DOT rendering with unknown cluster type falls back gracefully" do
    infra =
      Infrastructure.new()
      |> Infrastructure.add_compute(:app)

    # Inject a cluster with an unknown type manually
    infra = put_in(infra.clusters["cluster_unknown"], %{cluster_type: :unknown, label: "Unknown"})
    infra = update_in(infra.graph.nodes[:app], &Map.put(&1, :cluster, "cluster_unknown"))

    dot = Infrastructure.to_dot(infra)
    assert dot =~ "digraph"
  end

  test "DOT rendering with all themes" do
    infra =
      Infrastructure.new()
      |> Infrastructure.add_internet(:gw)
      |> Infrastructure.add_compute(:app)
      |> Infrastructure.connect(:gw, :app)

    for theme <- [:default, :dark, :warm, :forest, :ocean, :minimal] do
      assert Infrastructure.to_dot(infra, theme: theme) =~ "digraph"
    end
  end

  test "DOT rendering with custom cluster fillcolor and color overrides" do
    infra =
      Infrastructure.new()
      |> Infrastructure.add_vpc("vpc", fillcolor: "#eeeeee", color: "#333333")
      |> Infrastructure.add_compute(:app, cluster: "vpc")

    dot = Infrastructure.to_dot(infra)
    assert dot =~ "fillcolor=\"#eeeeee\""
    assert dot =~ "color=\"#333333\""
  end

  test "Mermaid rendering with public and private subnets" do
    infra =
      Infrastructure.new()
      |> Infrastructure.add_vpc("vpc_a")
      |> Infrastructure.add_subnet_public("pub", parent: "vpc_a")
      |> Infrastructure.add_load_balancer(:alb, cluster: "pub")
      |> Infrastructure.add_compute(:web, cluster: "pub")
      |> Infrastructure.connect(:alb, :web)

    mermaid = Infrastructure.to_mermaid(infra)

    assert mermaid =~ "graph TD"

    # vpc_a has no direct nodes (only contains sub-cluster pub), so it won't appear as a subgraph in Mermaid
    assert mermaid =~ "subgraph pub"
    assert mermaid =~ "style"
  end

  test "Mermaid rendering with all themes and directions" do
    infra =
      Infrastructure.new()
      |> Infrastructure.add_internet(:gw)
      |> Infrastructure.add_compute(:app)
      |> Infrastructure.connect(:gw, :app)

    for theme <- [:default, :dark, :warm, :forest, :ocean, :minimal] do
      assert Infrastructure.to_mermaid(infra, theme: theme) =~ "graph TD"
    end

    assert Infrastructure.to_mermaid(infra, direction: :lr) =~ "graph LR"
    assert Infrastructure.to_mermaid(infra, direction: :bt) =~ "graph BT"
  end

  test "Mermaid rendering with node fillcolor and penwidth overrides" do
    infra =
      Infrastructure.new()
      |> Infrastructure.add_compute(:app, fillcolor: "#ff0000", penwidth: 3.0)

    mermaid = Infrastructure.to_mermaid(infra)
    assert mermaid =~ "app"
    assert mermaid =~ "#ff0000"
    assert mermaid =~ "stroke-width:3.0px"
  end

  test "Mermaid rendering with unknown node type falls back to rounded_rect" do
    infra = Infrastructure.new() |> Infrastructure.add_compute(:app)
    # Override node type to something unknown
    infra = put_in(infra.graph.nodes[:app].node_type, :unknown_type)

    mermaid = Infrastructure.to_mermaid(infra)
    assert mermaid =~ "app"
  end

  test "Mermaid rendering with highlighted edges by tuple and edge id" do
    infra =
      Infrastructure.new()
      |> Infrastructure.add_internet(:gw)
      |> Infrastructure.add_compute(:app)
      |> Infrastructure.connect(:gw, :app, protocol: :https)

    # Get actual edge id from the graph
    edge_id = infra.graph.edges |> Map.keys() |> List.first()

    mermaid =
      Infrastructure.to_mermaid(infra,
        highlighted_edges: [{:gw, :app}, edge_id],
        highlighted_nodes: [:gw]
      )

    assert mermaid =~ "gw"
    assert mermaid =~ "app"
  end

  test "virtual_edge_meta protocol callback" do
    infra = Infrastructure.new()
    meta = Choreo.Viewable.virtual_edge_meta(infra)
    assert meta.edge_type == :virtual
    assert meta.cost == 1
  end

  test "connect/3 raises when nodes do not exist" do
    infra =
      Infrastructure.new()
      |> Infrastructure.add_compute(:app, label: "App")

    assert_raise ArgumentError, "Node :db does not exist in infrastructure diagram", fn ->
      Infrastructure.connect(infra, :app, :db)
    end

    assert_raise ArgumentError, "Node :gateway does not exist in infrastructure diagram", fn ->
      Infrastructure.connect(infra, :gateway, :app)
    end
  end

  test "connect/3 with cost option" do
    infra =
      Infrastructure.new()
      |> Infrastructure.add_internet(:gw)
      |> Infrastructure.add_compute(:app)
      |> Infrastructure.connect(:gw, :app, cost: 10)

    assert [{:gw, :app, 10}] = Infrastructure.edges(infra)
  end

  test "Theme defaults in DOT rendering" do
    infra =
      Infrastructure.new()
      |> Infrastructure.add_vpc("vpc")
      |> Infrastructure.add_subnet_public("pub", parent: "vpc")
      |> Infrastructure.add_subnet_private("priv", parent: "vpc")
      |> Infrastructure.add_load_balancer(:lb, cluster: "pub")
      |> Infrastructure.add_compute(:app, cluster: "priv")
      |> Infrastructure.add_managed_db(:db, cluster: "priv")

    # Light theme rendering
    dot_light = Infrastructure.to_dot(infra, theme: :default)
    # VPC
    assert dot_light =~ "fillcolor=\"#f8fafc\""
    # public subnet
    assert dot_light =~ "fillcolor=\"#f0fdf4\""
    # private subnet
    assert dot_light =~ "fillcolor=\"#fef2f2\""

    # Dark theme rendering
    dot_dark = Infrastructure.to_dot(infra, theme: :dark)
    # VPC
    assert dot_dark =~ "fillcolor=\"#1e293b\""
    # public subnet
    assert dot_dark =~ "fillcolor=\"#064e3b\""
    # private subnet
    assert dot_dark =~ "fillcolor=\"#7f1d1d\""
  end

  test "Choreo.DOT protocol dispatches to Infrastructure.to_dot/2" do
    infra =
      Infrastructure.new()
      |> Infrastructure.add_compute(:app)

    assert Choreo.to_dot(infra) =~ "digraph"
  end

  test "Choreo.Mermaid protocol dispatches to Infrastructure.to_mermaid/2" do
    infra =
      Infrastructure.new()
      |> Infrastructure.add_compute(:app)

    assert Choreo.to_mermaid(infra) =~ "graph TD"
  end
end
