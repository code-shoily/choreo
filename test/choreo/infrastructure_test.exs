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
end
