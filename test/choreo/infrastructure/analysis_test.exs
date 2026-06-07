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
end
