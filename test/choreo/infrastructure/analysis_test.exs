defmodule Choreo.Infrastructure.AnalysisTest do
  use ExUnit.Case, async: true

  alias Choreo.Infrastructure
  alias Choreo.Infrastructure.Analysis

  test "detects direct internet access to private subnet nodes" do
    infra =
      Infrastructure.new()
      |> Infrastructure.add_internet(:gateway, label: "Internet Gateway")
      |> Infrastructure.add_subnet_private("subnet_priv", label: "Private DB Subnet")
      |> Infrastructure.add_compute(:app, cluster: "subnet_priv")
      # Violating edge: direct link from public internet to private subnet
      |> Infrastructure.connect(:gateway, :app)

    warnings = Analysis.warnings(infra)

    assert warnings == [
             "Private resource 'app' is connected directly to public internet boundary 'gateway'."
           ]
  end

  test "detects bidirectional internet to private violations" do
    infra =
      Infrastructure.new()
      |> Infrastructure.add_internet(:gateway)
      |> Infrastructure.add_subnet_private("priv")
      |> Infrastructure.add_compute(:app, cluster: "priv")
      |> Infrastructure.connect(:app, :gateway)

    warnings = Analysis.warnings(infra)

    assert warnings == [
             "Private resource 'app' is connected directly to public internet boundary 'gateway'."
           ]
  end

  test "no warning when internet connects to public subnet node" do
    infra =
      Infrastructure.new()
      |> Infrastructure.add_internet(:gateway)
      |> Infrastructure.add_subnet_public("pub")
      |> Infrastructure.add_compute(:app, cluster: "pub")
      |> Infrastructure.connect(:gateway, :app)

    assert Analysis.warnings(infra) == []
  end

  test "no warning when private subnet node has no internet connection" do
    infra =
      Infrastructure.new()
      |> Infrastructure.add_subnet_private("priv")
      |> Infrastructure.add_compute(:app, cluster: "priv")
      |> Infrastructure.add_managed_db(:db, cluster: "priv")
      |> Infrastructure.connect(:app, :db)

    assert Analysis.warnings(infra) == []
  end

  test "detects database placement violations" do
    infra_no_subnet =
      Infrastructure.new()
      |> Infrastructure.add_managed_db(:rds_raw)

    assert Analysis.warnings(infra_no_subnet) == [
             "Managed database 'rds_raw' should be located in a private subnet, but it is outside of any subnet."
           ]

    infra_public_subnet =
      Infrastructure.new()
      |> Infrastructure.add_subnet_public("subnet_dmz", label: "Public DMZ")
      |> Infrastructure.add_managed_db(:rds_exposed, cluster: "subnet_dmz")

    assert Analysis.warnings(infra_public_subnet) == [
             "Managed database 'rds_exposed' should be located in a private subnet, but it is in 'Public DMZ'."
           ]

    # Valid placement: DB in private subnet should trigger zero warnings
    infra_valid =
      Infrastructure.new()
      |> Infrastructure.add_subnet_private("subnet_app", label: "Private App Zone")
      |> Infrastructure.add_managed_db(:rds_secure, cluster: "subnet_app")

    assert Analysis.warnings(infra_valid) == []
  end

  test "warnings use cluster name when label is missing" do
    infra =
      Infrastructure.new()
      |> Infrastructure.add_subnet_public("subnet_dmz")
      |> Infrastructure.add_managed_db(:rds, cluster: "subnet_dmz")

    assert Analysis.warnings(infra) == [
             "Managed database 'rds' should be located in a private subnet, but it is in 'subnet_dmz'."
           ]

    # DB with no label via manual cluster injection
    infra_db =
      Infrastructure.new()
      |> Infrastructure.add_managed_db(:rds, cluster: "no_label_subnet")

    infra_db =
      put_in(infra_db.clusters["cluster_no_label_subnet"], %{cluster_type: :subnet_public})

    assert Analysis.warnings(infra_db) == [
             "Managed database 'rds' should be located in a private subnet, but it is in 'no_label_subnet'."
           ]

    # LB with no label via manual cluster injection
    infra_lb =
      Infrastructure.new()
      |> Infrastructure.add_load_balancer(:alb, cluster: "no_label_subnet2")

    infra_lb =
      put_in(infra_lb.clusters["cluster_no_label_subnet2"], %{cluster_type: :subnet_private})

    assert Analysis.warnings(infra_lb) == [
             "Load balancer 'alb' should be located in a public subnet, but it is in 'no_label_subnet2'."
           ]
  end

  test "detects load balancer placement violations" do
    infra_no_subnet =
      Infrastructure.new()
      |> Infrastructure.add_load_balancer(:alb)

    assert Analysis.warnings(infra_no_subnet) == [
             "Load balancer 'alb' should be located in a public subnet, but it is outside of any subnet."
           ]

    infra_private_subnet =
      Infrastructure.new()
      |> Infrastructure.add_subnet_private("subnet_secure", label: "Secure Area")
      |> Infrastructure.add_load_balancer(:alb_private, cluster: "subnet_secure")

    assert Analysis.warnings(infra_private_subnet) == [
             "Load balancer 'alb_private' should be located in a public subnet, but it is in 'Secure Area'."
           ]
  end

  test "valid load balancer in public subnet passes with zero warnings" do
    infra =
      Infrastructure.new()
      |> Infrastructure.add_subnet_public("subnet_dmz", label: "Public DMZ")
      |> Infrastructure.add_load_balancer(:alb, cluster: "subnet_dmz")

    assert Analysis.warnings(infra) == []
  end

  test "a secure three-tier network architecture passes with zero warnings" do
    infra =
      Infrastructure.new()
      |> Infrastructure.add_internet(:user)
      |> Infrastructure.add_vpc("vpc")
      |> Infrastructure.add_subnet_public("public", parent: "vpc")
      |> Infrastructure.add_subnet_private("private", parent: "vpc")
      |> Infrastructure.add_load_balancer(:alb, cluster: "public")
      |> Infrastructure.add_compute(:api, cluster: "private")
      |> Infrastructure.add_managed_db(:db, cluster: "private")
      |> Infrastructure.connect(:user, :alb)
      |> Infrastructure.connect(:alb, :api)
      |> Infrastructure.connect(:api, :db)

    assert Analysis.warnings(infra) == []
  end

  test "compute node in public subnet does not trigger any warnings" do
    infra =
      Infrastructure.new()
      |> Infrastructure.add_subnet_public("pub")
      |> Infrastructure.add_compute(:app, cluster: "pub")

    assert Analysis.warnings(infra) == []
  end

  test "storage node outside any subnet does not trigger any warnings" do
    infra =
      Infrastructure.new()
      |> Infrastructure.add_storage(:s3)

    assert Analysis.warnings(infra) == []
  end

  test "internet node in private subnet does not trigger placement warnings" do
    infra =
      Infrastructure.new()
      |> Infrastructure.add_subnet_private("priv")
      |> Infrastructure.add_internet(:gw, cluster: "priv")

    assert Analysis.warnings(infra) == []
  end

  test "multiple violations are all reported" do
    infra =
      Infrastructure.new()
      |> Infrastructure.add_internet(:gateway)
      |> Infrastructure.add_subnet_private("priv")
      |> Infrastructure.add_compute(:app, cluster: "priv")
      |> Infrastructure.add_managed_db(:db)
      |> Infrastructure.add_load_balancer(:lb)
      |> Infrastructure.connect(:gateway, :app)

    warnings = Analysis.warnings(infra)

    assert length(warnings) == 3
    assert Enum.any?(warnings, &String.contains?(&1, "Private resource 'app'"))
    assert Enum.any?(warnings, &String.contains?(&1, "Managed database 'db'"))
    assert Enum.any?(warnings, &String.contains?(&1, "Load balancer 'lb'"))
  end
end
