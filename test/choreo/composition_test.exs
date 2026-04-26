defmodule Choreo.CompositionTest do
  use ExUnit.Case, async: true

  alias Choreo
  alias Choreo.Dataflow
  alias Choreo.Workflow

  test "embeds a Dataflow diagram inside a Choreo infrastructure cluster" do
    # 1. Define nested child diagram
    flow =
      Dataflow.new()
      |> Dataflow.add_source(:sensor, label: "IoT Sensor")
      |> Dataflow.add_transform(:parser)
      |> Dataflow.add_sink(:db_writer)
      |> Dataflow.connect(:sensor, :parser)
      |> Dataflow.connect(:parser, :db_writer)

    # 2. Define parent diagram
    system =
      Choreo.new()
      |> Choreo.add_cluster("vpc", label: "VPC Infrastructure")
      |> Choreo.add_service(:api, name: "Gateway")
      |> Choreo.embed(flow, "vpc", prefix: "flow_")

    # Verify nodes embedded
    nodes = Choreo.nodes(system)
    assert Map.has_key?(nodes, :flow_sensor)
    assert Map.has_key?(nodes, :flow_parser)
    assert Map.has_key?(nodes, :flow_db_writer)

    # Verify cluster assignments
    assert nodes[:flow_sensor].cluster == "cluster_vpc"
    assert nodes[:flow_parser].cluster == "cluster_vpc"

    # Verify edges successfully extracted
    edges = Choreo.edges(system)
    # There should be 2 edges from the flow
    assert length(edges) == 2

    # Verify we can manually connect from parent node to internal child node
    system = Choreo.connect(system, :api, :flow_sensor)
    assert length(Choreo.edges(system)) == 3
  end

  test "embeds a Workflow diagram with internal parallel edges" do
    workflow =
      Workflow.new()
      |> Workflow.add_start(:begin)
      |> Workflow.add_task(:process)
      |> Workflow.add_end(:finish)
      |> Workflow.connect(:begin, :process)
      |> Workflow.connect(:process, :finish)

    system =
      Choreo.new()
      |> Choreo.add_cluster("orch")
      |> Choreo.embed(workflow, "orch", prefix: "wf_")

    nodes = Choreo.nodes(system)
    assert Map.has_key?(nodes, :wf_begin)
    assert Map.has_key?(nodes, :wf_process)
    assert Map.has_key?(nodes, :wf_finish)

    edges = Choreo.edges(system)
    assert length(edges) == 2
  end

  test "embeds a Dataflow diagram with nested clusters and custom names" do
    flow =
      Dataflow.new()
      |> Dataflow.add_cluster("outer", label: "Outer Scope")
      |> Dataflow.add_cluster("inner", label: "Inner Scope", parent: "outer")
      |> Dataflow.add_source(:sensor, label: "IoT Sensor", cluster: "inner")
      |> Dataflow.add_transform(:parser, label: "Custom Parser")
      |> Dataflow.connect(:sensor, :parser)

    system =
      Choreo.new()
      |> Choreo.add_cluster("vpc")
      |> Choreo.embed(flow, "vpc", prefix: "flow_")

    nodes = Choreo.nodes(system)
    assert Map.has_key?(nodes, :flow_sensor)
    assert Map.has_key?(nodes, :flow_parser)

    # Verify cluster mapping
    clusters = Choreo.clusters(system)
    assert Map.has_key?(clusters, "cluster_flow_outer")
    assert Map.has_key?(clusters, "cluster_flow_inner")

    assert clusters["cluster_flow_outer"].parent == "cluster_vpc"
    assert clusters["cluster_flow_inner"].parent == "cluster_flow_outer"

    # Verify node cluster assignment
    assert nodes[:flow_sensor].cluster == "cluster_flow_inner"
    assert nodes[:flow_parser].cluster == "cluster_vpc"

    # Verify custom node name preservation
    assert nodes[:flow_parser].name == "Custom Parser"
  end
end
