defmodule Choreo.CompositionTest do
  use ExUnit.Case, async: true

  alias Choreo
  alias Choreo.Analysis.Tracing
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
      |> Choreo.add_service(:api, label: "Gateway")
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

    # Verify custom node label preservation
    assert nodes[:flow_parser].label == "Custom Parser"
  end

  test "declares traces and performs semantic impact analysis and pathfinding" do
    # 1. Define child diagrams (C4, Workflow, ERD)
    c4 =
      Choreo.C4.new()
      |> Choreo.C4.add_software_system(:banking, scope: :in)
      |> Choreo.C4.add_container(:api, parent: :banking)
      |> Choreo.C4.add_component(:auth, parent: :api)

    flow =
      Choreo.Workflow.new()
      |> Choreo.Workflow.add_start(:start)
      |> Choreo.Workflow.add_task(:login)
      |> Choreo.Workflow.add_end(:stop)
      |> Choreo.Workflow.connect(:start, :login)
      |> Choreo.Workflow.connect(:login, :stop)

    erd =
      Choreo.ERD.new()
      |> Choreo.ERD.add_table(:users, columns: [%{name: :id, type: :integer}])

    # 2. Embed all into a system map
    system =
      Choreo.new()
      |> Choreo.add_cluster("banking_cluster")
      |> Choreo.embed(c4, "banking_cluster", prefix: "c4_")
      |> Choreo.embed(flow, "banking_cluster", prefix: "wf_")
      |> Choreo.embed(erd, "banking_cluster", prefix: "erd_")

    # 3. Add traces
    system =
      system
      |> Choreo.trace(:wf_login, :c4_auth, type: :executes)
      |> Choreo.trace(:c4_auth, :erd_users, type: :stores)

    # Verify edge metadata has trace type
    edges = Choreo.edges_with_meta(system)
    trace_edges = Enum.filter(edges, fn {_, _, _, meta} -> meta[:edge_type] == :trace end)
    assert length(trace_edges) == 2

    # 4. Perform tracing impact analysis (walking transposed path)
    # erd_users is at the bottom, so changes to it flow back to c4_auth and wf_login
    impacted = Tracing.impact_analysis(system, :erd_users)
    assert :c4_auth in impacted
    assert :wf_login in impacted

    # 5. Trace path
    {:ok, path} = Tracing.trace_path(system, :wf_login, :erd_users)
    assert path == [:wf_login, :c4_auth, :erd_users]

    # 5b. Run analyze/3 nested analysis
    {:ok, analysis} = Tracing.analyze(system, :wf_login, :erd_users)
    assert analysis.path == [:wf_login, :c4_auth, :erd_users]
    assert length(analysis.findings) == 3

    [wf_find, c4_find, erd_find] = analysis.findings
    assert wf_find.domain == :workflow
    assert wf_find.type == :task

    assert c4_find.domain == :c4

    assert erd_find.domain == :erd
    assert erd_find.type == :table

    # 5c. Run Choreo.View.focus_trace/4
    focused = Choreo.View.focus_trace(system, :wf_login, :erd_users)
    assert Enum.sort(Map.keys(Choreo.nodes(focused))) == [:c4_auth, :erd_users, :wf_login]

    # 6. Verify default rendering filters out traces
    dot = Choreo.to_dot(system)
    refute String.contains?(dot, "executes")

    # Verify rendering with show_traces: true includes them
    dot_with_traces = Choreo.to_dot(system, show_traces: true)
    assert String.contains?(dot_with_traces, "executes")
    assert String.contains?(dot_with_traces, "stores")

    # Mermaid rendering checks
    mermaid = Choreo.to_mermaid(system)
    refute String.contains?(mermaid, "executes")

    mermaid_with_traces = Choreo.to_mermaid(system, show_traces: true)
    assert String.contains?(mermaid_with_traces, "executes")
  end

  test "Tracing handles disconnected paths, unknown nodes, bottlenecks, and domain types" do
    # 1. Unknown node impact_analysis
    system = Choreo.new() |> Choreo.add_service(:svc)
    assert Tracing.impact_analysis(system, :unknown_node) == []

    # 2. Disconnected path
    system =
      system
      |> Choreo.add_service(:other)

    assert Tracing.trace_path(system, :svc, :other) == :error
    assert Tracing.analyze(system, :svc, :other) == :error

    # 3. Path threading across workflow bottleneck, threat model risk, ERD sensitive col,
    #    dataflow node, dependency node, and generic node.
    system =
      Choreo.new()
      |> Choreo.add_service(:wf_task, label: "Slow Task")
      |> Choreo.add_service(:tm_proc, label: "Secure Proc")
      |> Choreo.add_service(:erd_tab, label: "Accounts")
      |> Choreo.add_service(:df_node, label: "Stream")
      |> Choreo.add_service(:dep_node, label: "Lib")
      |> Choreo.add_service(:gen_node, label: "Generic Box")
      |> Choreo.trace(:wf_task, :tm_proc, type: :calls)
      |> Choreo.trace(:tm_proc, :erd_tab, type: :stores)
      |> Choreo.trace(:erd_tab, :df_node, type: :streams)
      |> Choreo.trace(:df_node, :dep_node, type: :uses)
      |> Choreo.trace(:dep_node, :gen_node, type: :links)

    system =
      system
      |> put_in([Access.key(:graph), Access.key(:nodes), :wf_task, :node_type], :task)
      |> put_in([Access.key(:graph), Access.key(:nodes), :wf_task, :timeout_ms], 6000)
      |> put_in([Access.key(:graph), Access.key(:nodes), :tm_proc, :element_type], :process)
      |> put_in([Access.key(:graph), Access.key(:nodes), :tm_proc, :sensitivity], :confidential)
      |> put_in([Access.key(:graph), Access.key(:nodes), :erd_tab, :type], :table)
      |> put_in([Access.key(:graph), Access.key(:nodes), :erd_tab, :columns], [
        %{name: :ssn, sensitivity: :restricted}
      ])
      |> put_in([Access.key(:graph), Access.key(:nodes), :df_node, :type], :dataflow_node)
      |> put_in([Access.key(:graph), Access.key(:nodes), :df_node, :node_type], :transform)
      |> put_in([Access.key(:graph), Access.key(:nodes), :dep_node, :type], :dependency_node)
      |> put_in([Access.key(:graph), Access.key(:nodes), :dep_node, :node_type], :library)

    {:ok, analysis} = Tracing.analyze(system, :wf_task, :gen_node)

    assert analysis.has_bottleneck? == true
    assert analysis.has_high_risk? == true
    assert length(analysis.findings) == 6

    domains = Enum.map(analysis.findings, & &1.domain)
    assert domains == [:workflow, :threat_model, :erd, :dataflow, :dependency, :generic]
  end
end
