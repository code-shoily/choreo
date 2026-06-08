defmodule Choreo.Infrastructure.AnalysisTest do
  use ExUnit.Case, async: true

  alias Choreo.Infrastructure
  alias Choreo.Infrastructure.Analysis

  doctest Choreo.Infrastructure.Analysis

  test "detects direct internet access to private subnet nodes" do
    infra =
      Infrastructure.new()
      |> Infrastructure.add_internet(:gateway, label: "Internet Gateway")
      |> Infrastructure.add_subnet_private("subnet_priv", label: "Private DB Subnet")
      |> Infrastructure.add_compute(:app, cluster: "subnet_priv")
      # Violating edge: direct link from public internet to private subnet
      |> Infrastructure.connect(:gateway, :app)

    issues = Analysis.validate(infra)

    assert issues == [
             {:error,
              "Private resource 'app' is connected directly to public internet boundary 'gateway'."}
           ]
  end

  test "detects bidirectional internet to private violations" do
    infra =
      Infrastructure.new()
      |> Infrastructure.add_internet(:gateway)
      |> Infrastructure.add_subnet_private("priv")
      |> Infrastructure.add_compute(:app, cluster: "priv")
      |> Infrastructure.connect(:app, :gateway)

    issues = Analysis.validate(infra)

    assert issues == [
             {:error,
              "Private resource 'app' is connected directly to public internet boundary 'gateway'."}
           ]
  end

  test "no issue when internet connects to public subnet node" do
    infra =
      Infrastructure.new()
      |> Infrastructure.add_internet(:gateway)
      |> Infrastructure.add_subnet_public("pub")
      |> Infrastructure.add_compute(:app, cluster: "pub")
      |> Infrastructure.connect(:gateway, :app)

    assert Analysis.validate(infra) == []
  end

  test "no issue when private subnet node has no internet connection" do
    infra =
      Infrastructure.new()
      |> Infrastructure.add_subnet_private("priv")
      |> Infrastructure.add_compute(:app, cluster: "priv")
      |> Infrastructure.add_managed_db(:db, cluster: "priv")
      |> Infrastructure.connect(:app, :db)

    assert Analysis.validate(infra) == []
  end

  test "detects database placement violations" do
    infra_no_subnet =
      Infrastructure.new()
      |> Infrastructure.add_managed_db(:rds_raw)

    assert Analysis.validate(infra_no_subnet) == [
             {:error,
              "Managed database 'rds_raw' should be located in a private subnet, but it is outside of any subnet."}
           ]

    infra_public_subnet =
      Infrastructure.new()
      |> Infrastructure.add_subnet_public("subnet_dmz", label: "Public DMZ")
      |> Infrastructure.add_managed_db(:rds_exposed, cluster: "subnet_dmz")

    assert Analysis.validate(infra_public_subnet) == [
             {:error,
              "Managed database 'rds_exposed' should be located in a private subnet, but it is in 'Public DMZ'."}
           ]

    # Valid placement: DB in private subnet should trigger zero issues
    infra_valid =
      Infrastructure.new()
      |> Infrastructure.add_subnet_private("subnet_app", label: "Private App Zone")
      |> Infrastructure.add_managed_db(:rds_secure, cluster: "subnet_app")

    assert Analysis.validate(infra_valid) == []
  end

  test "detects storage placement violations" do
    infra_public_subnet =
      Infrastructure.new()
      |> Infrastructure.add_subnet_public("pub", label: "Public")
      |> Infrastructure.add_storage(:s3, cluster: "pub")

    assert Analysis.validate(infra_public_subnet) == [
             {:error, "Storage 's3' should not be in a public subnet, but it is in 'Public'."}
           ]

    # Storage outside any subnet is OK
    infra_no_subnet =
      Infrastructure.new()
      |> Infrastructure.add_storage(:s3)

    assert Analysis.validate(infra_no_subnet) == []

    # Storage in private subnet is OK
    infra_private =
      Infrastructure.new()
      |> Infrastructure.add_subnet_private("priv")
      |> Infrastructure.add_storage(:s3, cluster: "priv")

    assert Analysis.validate(infra_private) == []
  end

  test "validate uses cluster name when label is missing" do
    infra =
      Infrastructure.new()
      |> Infrastructure.add_subnet_public("subnet_dmz")
      |> Infrastructure.add_managed_db(:rds, cluster: "subnet_dmz")

    assert Analysis.validate(infra) == [
             {:error,
              "Managed database 'rds' should be located in a private subnet, but it is in 'subnet_dmz'."}
           ]

    # DB with no label via manual cluster injection
    infra_db =
      Infrastructure.new()
      |> Infrastructure.add_managed_db(:rds, cluster: "no_label_subnet")

    infra_db =
      put_in(infra_db.clusters["cluster_no_label_subnet"], %{cluster_type: :subnet_public})

    assert Analysis.validate(infra_db) == [
             {:error,
              "Managed database 'rds' should be located in a private subnet, but it is in 'no_label_subnet'."}
           ]

    # LB with no label via manual cluster injection
    infra_lb =
      Infrastructure.new()
      |> Infrastructure.add_load_balancer(:alb, cluster: "no_label_subnet2")

    infra_lb =
      put_in(infra_lb.clusters["cluster_no_label_subnet2"], %{cluster_type: :subnet_private})

    assert Analysis.validate(infra_lb) == [
             {:warning,
              "Load balancer 'alb' should be located in a public subnet, but it is in 'no_label_subnet2'."}
           ]
  end

  test "detects load balancer placement violations" do
    infra_no_subnet =
      Infrastructure.new()
      |> Infrastructure.add_load_balancer(:alb)

    assert Analysis.validate(infra_no_subnet) == [
             {:warning,
              "Load balancer 'alb' should be located in a public subnet, but it is outside of any subnet."}
           ]

    infra_private_subnet =
      Infrastructure.new()
      |> Infrastructure.add_subnet_private("subnet_secure", label: "Secure Area")
      |> Infrastructure.add_load_balancer(:alb_private, cluster: "subnet_secure")

    assert Analysis.validate(infra_private_subnet) == [
             {:warning,
              "Load balancer 'alb_private' should be located in a public subnet, but it is in 'Secure Area'."}
           ]
  end

  test "detects unassigned compute nodes" do
    infra =
      Infrastructure.new()
      |> Infrastructure.add_compute(:app)

    assert Analysis.validate(infra) == [
             {:warning,
              "Compute node 'app' is not assigned to any subnet. This may indicate incomplete modeling."}
           ]
  end

  test "valid load balancer in public subnet passes with zero issues" do
    infra =
      Infrastructure.new()
      |> Infrastructure.add_subnet_public("subnet_dmz", label: "Public DMZ")
      |> Infrastructure.add_load_balancer(:alb, cluster: "subnet_dmz")

    assert Analysis.validate(infra) == []
  end

  test "a secure three-tier network architecture passes with zero issues" do
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

    assert Analysis.validate(infra) == []
  end

  test "compute node in public subnet does not trigger any warnings" do
    infra =
      Infrastructure.new()
      |> Infrastructure.add_subnet_public("pub")
      |> Infrastructure.add_compute(:app, cluster: "pub")

    assert Analysis.validate(infra) == []
  end

  test "storage node outside any subnet does not trigger any warnings" do
    infra =
      Infrastructure.new()
      |> Infrastructure.add_storage(:s3)

    assert Analysis.validate(infra) == []
  end

  test "internet node in private subnet does not trigger placement warnings" do
    infra =
      Infrastructure.new()
      |> Infrastructure.add_subnet_private("priv")
      |> Infrastructure.add_internet(:gw, cluster: "priv")

    assert Analysis.validate(infra) == []
  end

  test "multiple violations are all reported" do
    infra =
      Infrastructure.new()
      |> Infrastructure.add_internet(:gateway)
      |> Infrastructure.add_subnet_private("priv")
      |> Infrastructure.add_compute(:app, cluster: "priv")
      |> Infrastructure.add_compute(:worker)
      |> Infrastructure.add_managed_db(:db)
      |> Infrastructure.add_load_balancer(:lb)
      |> Infrastructure.connect(:gateway, :app)

    issues = Analysis.validate(infra)

    assert length(issues) == 4
    assert Enum.any?(issues, fn {_, msg} -> String.contains?(msg, "Private resource 'app'") end)
    assert Enum.any?(issues, fn {_, msg} -> String.contains?(msg, "Managed database 'db'") end)
    assert Enum.any?(issues, fn {_, msg} -> String.contains?(msg, "Load balancer 'lb'") end)
    assert Enum.any?(issues, fn {_, msg} -> String.contains?(msg, "Compute node 'worker'") end)
  end
end
