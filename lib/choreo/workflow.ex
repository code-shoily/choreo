defmodule Choreo.Workflow do
  @moduledoc """
  Workflow / task orchestration diagram builder on top of Yog.

  `Choreo.Workflow` models automated task orchestration where nodes are
  process steps and edges are execution dependencies. It supports:

    * **Tasks** — automated steps with timeout and retry config
    * **Decisions** — conditional branching
    * **Fork / Join** — parallel execution paths
    * **Compensations** — Saga-pattern rollback handlers
    * **Events** — triggers, timers, signals
    * **Swimlanes** — group tasks by team, service, or domain

  ## When to use

  Use `Choreo.Workflow` when designing distributed business processes,
  Saga transactions, CI/CD pipelines, or approval flows. It identifies
  the critical path, finds parallelizable tasks, and verifies that every
  failure scenario has a compensation route.

  ## Further reading

    * [Saga Pattern (Microsoft)](https://learn.microsoft.com/en-us/azure/architecture/reference-architectures/saga/saga)
    * [BPMN 2.0 Specification](https://www.omg.org/spec/BPMN/2.0/)
    * [Workflow Patterns Initiative](http://www.workflowpatterns.com/)

  ## Quick Start

      workflow =
        Choreo.Workflow.new()
        |> Choreo.Workflow.add_start(:order_received)
        |> Choreo.Workflow.add_task(:charge_card, timeout_ms: 5000, retry: 3)
        |> Choreo.Workflow.add_task(:reserve_inventory, timeout_ms: 3000)
        |> Choreo.Workflow.add_decision(:sufficient_stock)
        |> Choreo.Workflow.add_task(:pack_items, timeout_ms: 10_000)
        |> Choreo.Workflow.add_task(:ship_order, timeout_ms: 5000)
        |> Choreo.Workflow.add_compensation(:refund_payment, for: :charge_card)
        |> Choreo.Workflow.add_end(:done)
        |> Choreo.Workflow.connect(:order_received, :charge_card)
        |> Choreo.Workflow.connect(:charge_card, :reserve_inventory)
        |> Choreo.Workflow.connect(:reserve_inventory, :sufficient_stock)
        |> Choreo.Workflow.connect(:sufficient_stock, :pack_items, condition: "yes")
        |> Choreo.Workflow.connect(:sufficient_stock, :refund_payment, condition: "no", edge_type: :compensation)
        |> Choreo.Workflow.connect(:pack_items, :ship_order)
        |> Choreo.Workflow.connect(:ship_order, :done)

      dot = Choreo.Workflow.to_dot(workflow)

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=TB, splines=spline, nodesep=0.6, ranksep=1.2];
      node [shape=box, style=filled, fillcolor="white", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [arrowhead=normal, color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];

      done [label="done", penwidth="2.0", fillcolor="#ef4444", shape="doublecircle"];
      order_received [label="order_received", penwidth="2.0", fillcolor="#10b981", shape="circle"];
      charge_card [label="charge_card\n(5000ms)\nretry: 3", fillcolor="#3b82f6", shape="box3d"];
      reserve_inventory [label="reserve_inventory\n(3000ms)", fillcolor="#3b82f6", shape="box3d"];
      sufficient_stock [label="sufficient_stock", fillcolor="#8b5cf6", shape="diamond"];
      pack_items [label="pack_items\n(10000ms)", fillcolor="#3b82f6", shape="box3d"];
      ship_order [label="ship_order\n(5000ms)", fillcolor="#3b82f6", shape="box3d"];
      refund_payment [label="refund_payment", color="#ef4444", style="filled,dashed", fillcolor="#f87171", shape="note"];

      order_received -> charge_card [label="", style="solid", penwidth="1.0", fontcolor="#64748b", color="#64748b"];
      charge_card -> reserve_inventory [label="", style="solid", penwidth="1.0", fontcolor="#64748b", color="#64748b"];
      reserve_inventory -> sufficient_stock [label="", style="solid", penwidth="1.0", fontcolor="#64748b", color="#64748b"];
      sufficient_stock -> pack_items [style="solid", penwidth="1.0", fontcolor="#64748b", color="#64748b", label="yes"];
      sufficient_stock -> refund_payment [style="dashed", penwidth="1.5", fontcolor="#ef4444", color="#ef4444", label="no"];
      pack_items -> ship_order [label="", style="solid", penwidth="1.0", fontcolor="#64748b", color="#64748b"];
      ship_order -> done [label="", style="solid", penwidth="1.0", fontcolor="#64748b", color="#64748b"];
    }
  </div>

  ## Analysis

      # Longest-latency path through the workflow
      {:ok, path, latency} = Choreo.Workflow.Analysis.critical_path(workflow)

      # Tasks that can run in parallel
      Choreo.Workflow.Analysis.parallelizable_tasks(workflow)

      # Tasks with missing compensations
      Choreo.Workflow.Analysis.missing_compensations(workflow)

      # Validation
      Choreo.Workflow.Analysis.validate(workflow)
  """

  @type t :: %__MODULE__{
          graph: Yog.Multi.Graph.t(),
          edge_meta: %{optional(Yog.Multi.Graph.edge_id()) => map()},
          clusters: %{String.t() => map()}
        }

  defstruct graph: nil, edge_meta: %{}, clusters: %{}

  @add_swimlane_schema [
    label: [
      type: :string,
      required: false
    ]
  ]

  @node_schema [
    label: [
      type: :string,
      required: false
    ],
    description: [
      type: :string,
      required: false
    ],
    swimlane: [
      type: :string,
      required: false
    ],
    shape: [
      type: :atom,
      required: false
    ],
    fillcolor: [
      type: :string,
      required: false
    ],
    fontcolor: [
      type: :string,
      required: false
    ],
    style: [
      type: :string,
      required: false
    ],
    penwidth: [
      type: {:or, [:integer, :float]},
      required: false
    ],
    image: [
      type: :string,
      required: false
    ]
  ]

  @add_start_schema @node_schema
  @add_end_schema @node_schema

  @add_task_schema [
                     timeout_ms: [
                       type: :integer,
                       required: false
                     ],
                     retry: [
                       type: :integer,
                       required: false
                     ],
                     retry_backoff_ms: [
                       type: :integer,
                       required: false
                     ],
                     handler: [
                       type: {:or, [:atom, :string]},
                       required: false
                     ]
                   ] ++ @node_schema

  @add_decision_schema @node_schema
  @add_fork_schema @node_schema
  @add_join_schema @node_schema

  @add_compensation_schema [
    for: [
      type: {:or, [:atom, :string]},
      required: false
    ],
    label: [
      type: :string,
      required: false
    ],
    handler: [
      type: {:or, [:atom, :string]},
      required: false
    ],
    description: [
      type: :string,
      required: false
    ],
    swimlane: [
      type: :string,
      required: false
    ],
    shape: [
      type: :atom,
      required: false
    ],
    fillcolor: [
      type: :string,
      required: false
    ],
    fontcolor: [
      type: :string,
      required: false
    ],
    style: [
      type: :string,
      required: false
    ],
    penwidth: [
      type: {:or, [:integer, :float]},
      required: false
    ]
  ]

  @add_event_schema [
    label: [
      type: :string,
      required: false
    ],
    description: [
      type: :string,
      required: false
    ],
    swimlane: [
      type: :string,
      required: false
    ],
    shape: [
      type: :atom,
      required: false
    ],
    fillcolor: [
      type: :string,
      required: false
    ],
    fontcolor: [
      type: :string,
      required: false
    ],
    style: [
      type: :string,
      required: false
    ],
    penwidth: [
      type: {:or, [:integer, :float]},
      required: false
    ]
  ]

  @connect_schema [
    condition: [
      type: :string,
      required: false
    ],
    edge_type: [
      type: {:in, [:sequence, :compensation, :retry, :failure, :timeout, :error]},
      required: false
    ],
    weight: [
      type: {:or, [:integer, :float]},
      required: false
    ],
    label: [
      type: :string,
      required: false
    ]
  ]

  # ============================================================================
  # Creation
  # ============================================================================

  @doc """
  Creates a new empty workflow graph.

  Workflow graphs are always directed.

  ## Examples

      iex> workflow = Choreo.Workflow.new()
      iex> Choreo.Workflow.nodes(workflow)
      []
      iex> Choreo.Workflow.starts(workflow)
      []
      iex> Choreo.Workflow.ends(workflow)
      []
  """
  @spec new() :: t()
  def new do
    %__MODULE__{
      graph: Yog.Multi.new(:directed),
      edge_meta: %{},
      clusters: %{}
    }
  end

  # ============================================================================
  # Node builders
  # ============================================================================

  @doc """
  Adds a start node (entry point).

  ## Examples

      iex> workflow = Choreo.Workflow.new()
      iex> workflow = Choreo.Workflow.add_start(workflow, :begin, label: "Start")
      iex> Choreo.Workflow.starts(workflow)
      [:begin]
      iex> Map.get(workflow.graph.nodes, :begin).node_type
      :start

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=TB, splines=spline, nodesep=0.6, ranksep=1.2];
      node [shape=box, style=filled, fillcolor="white", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [arrowhead=normal, color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];

      begin [label="Start", penwidth="2.0", fillcolor="#10b981", shape="circle"];
    }
  </div>
  """
  @spec add_start(t(), Yog.node_id(), keyword()) :: t()
  def add_start(%__MODULE__{} = workflow, id, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @add_start_schema)
    add_typed_node(workflow, id, :start, opts)
  end

  @doc """
  Adds an end node (terminal).

  ## Examples

      iex> workflow = Choreo.Workflow.new()
      iex> workflow = Choreo.Workflow.add_end(workflow, :finish, label: "End")
      iex> Choreo.Workflow.ends(workflow)
      [:finish]
      iex> Map.get(workflow.graph.nodes, :finish).node_type
      :end

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=TB, splines=spline, nodesep=0.6, ranksep=1.2];
      node [shape=box, style=filled, fillcolor="white", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [arrowhead=normal, color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];

      finish [label="End", penwidth="2.0", fillcolor="#ef4444", shape="doublecircle"];
    }
  </div>
  """
  @spec add_end(t(), Yog.node_id(), keyword()) :: t()
  def add_end(%__MODULE__{} = workflow, id, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @add_end_schema)
    add_typed_node(workflow, id, :end, opts)
  end

  @doc """
  Adds an automated task node.

  ## Options

  #{NimbleOptions.docs(@add_task_schema)}

  ## Examples

      iex> workflow = Choreo.Workflow.new()
      iex> workflow = Choreo.Workflow.add_task(workflow, :process, timeout_ms: 5000, retry: 3)
      iex> Choreo.Workflow.tasks(workflow)
      [:process]
      iex> Map.get(workflow.graph.nodes, :process).timeout_ms
      5000
      iex> Map.get(workflow.graph.nodes, :process).retry
      3

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=TB, splines=spline, nodesep=0.6, ranksep=1.2];
      node [shape=box, style=filled, fillcolor="white", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [arrowhead=normal, color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];

      process [label="process\n(5000ms)\nretry: 3", fillcolor="#3b82f6", shape="box3d"];
    }
  </div>
  """
  def add_task(%__MODULE__{} = workflow, id, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @add_task_schema)
    add_typed_node(workflow, id, :task, opts)
  end

  @doc """
  Adds a decision / gateway node for conditional branching.

  ## Examples

      iex> workflow = Choreo.Workflow.new()
      iex> workflow = Choreo.Workflow.add_decision(workflow, :check)
      iex> Map.get(workflow.graph.nodes, :check).node_type
      :decision

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=TB, splines=spline, nodesep=0.6, ranksep=1.2];
      node [shape=box, style=filled, fillcolor="white", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [arrowhead=normal, color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];

      check [label="check", fillcolor="#8b5cf6", shape="diamond"];
    }
  </div>
  """
  def add_decision(%__MODULE__{} = workflow, id, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @add_decision_schema)
    add_typed_node(workflow, id, :decision, opts)
  end

  @doc """
  Adds a fork node that splits execution into parallel paths.

  ## Examples

      iex> workflow = Choreo.Workflow.new()
      iex> workflow = Choreo.Workflow.add_fork(workflow, :split)
      iex> Map.get(workflow.graph.nodes, :split).node_type
      :fork
  """
  @spec add_fork(t(), Yog.node_id(), keyword()) :: t()
  def add_fork(%__MODULE__{} = workflow, id, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @add_fork_schema)
    add_typed_node(workflow, id, :fork, opts)
  end

  @doc """
  Adds a join node that merges parallel paths.

  ## Examples

      iex> workflow = Choreo.Workflow.new()
      iex> workflow = Choreo.Workflow.add_join(workflow, :merge)
      iex> Map.get(workflow.graph.nodes, :merge).node_type
      :join
  """
  def add_join(%__MODULE__{} = workflow, id, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @add_join_schema)
    add_typed_node(workflow, id, :join, opts)
  end

  @doc """
  Adds a compensation / rollback node (Saga pattern).

  ## Options

  #{NimbleOptions.docs(@add_compensation_schema)}

  ## Examples

      iex> workflow = Choreo.Workflow.new()
      iex> workflow = Choreo.Workflow.add_compensation(workflow, :rollback, for: :process)
      iex> Choreo.Workflow.compensations(workflow)
      [:rollback]
      iex> Map.get(workflow.graph.nodes, :rollback).target_task
      :process

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=TB, splines=spline, nodesep=0.6, ranksep=1.2];
      node [shape=box, style=filled, fillcolor="white", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [arrowhead=normal, color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];

      rollback [label="rollback", color="#ef4444", style="filled,dashed", fillcolor="#f87171", shape="note"];
    }
  </div>
  """
  @spec add_compensation(t(), Yog.node_id(), keyword()) :: t()
  def add_compensation(%__MODULE__{} = workflow, id, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @add_compensation_schema)

    data = %{
      type: :workflow_node,
      node_type: :compensation,
      label: Keyword.get(opts, :label, to_string(id)),
      target_task: opts[:for],
      handler: opts[:handler],
      description: opts[:description]
    }

    data = put_swimlane(data, opts[:swimlane])
    %{workflow | graph: Yog.Multi.add_node(workflow.graph, id, data)}
  end

  @doc """
  Adds an event node (trigger, timer, signal).

  ## Examples

      iex> workflow = Choreo.Workflow.new()
      iex> workflow = Choreo.Workflow.add_event(workflow, :timer)
      iex> Map.get(workflow.graph.nodes, :timer).node_type
      :event
  """
  def add_event(%__MODULE__{} = workflow, id, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @add_event_schema)
    add_typed_node(workflow, id, :event, opts)
  end

  # ============================================================================
  # Edge builder
  # ============================================================================

  @doc """
  Connects two workflow nodes with an execution dependency.

  Multiple connections are allowed per `(from, to)` pair (parallel edges).

  ## Options

  #{NimbleOptions.docs(@connect_schema)}

  ## Examples

      iex> workflow = Choreo.Workflow.new()
      iex> workflow = workflow
      ...>   |> Choreo.Workflow.add_start(:a)
      ...>   |> Choreo.Workflow.add_task(:b)
      ...>   |> Choreo.Workflow.connect(:a, :b)
      iex> Choreo.Workflow.edges(workflow)
      iex> [{:a, :b, _, meta}] = Choreo.Workflow.edges_with_meta(workflow)
      iex> meta.edge_type
      :sequence

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=TB, splines=spline, nodesep=0.6, ranksep=1.2];
      node [shape=box, style=filled, fillcolor="white", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [arrowhead=normal, color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];

      a [label="a", penwidth="2.0", fillcolor="#10b981", shape="circle"];
      b [label="b", fillcolor="#3b82f6", shape="box3d"];

      a -> b [label="", style="solid", penwidth="1.0", fontcolor="#64748b", color="#64748b"];
    }
  </div>
  """
  def connect(%__MODULE__{} = workflow, from, to, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @connect_schema)
    edge_type = Keyword.get(opts, :edge_type, :sequence)
    condition = opts[:condition]

    weight =
      opts[:weight] || default_weight(workflow.graph, to, edge_type)

    label = opts[:label] || condition || edge_type_label(edge_type)

    meta = %{
      label: label,
      condition: condition,
      edge_type: edge_type,
      weight: weight
    }

    {graph, edge_id} = Yog.Multi.add_edge(workflow.graph, from, to, weight)
    edge_meta = Map.put(workflow.edge_meta, edge_id, meta)

    %{workflow | graph: graph, edge_meta: edge_meta}
  end

  # ============================================================================
  # Swimlanes
  # ============================================================================

  @doc """
  Adds a swimlane grouping.

  Swimlanes are rendered as subgraph clusters. Nodes can be assigned to a
  swimlane via the `:swimlane` option in node builders.

  ## Examples

      iex> workflow = Choreo.Workflow.new()
      iex> workflow = workflow
      ...>   |> Choreo.Workflow.add_swimlane("backend", label: "Backend Services")
      ...>   |> Choreo.Workflow.add_task(:api, swimlane: "backend")
      iex> Map.get(workflow.graph.nodes, :api)[:cluster]
      "cluster_backend"
  """
  @spec add_swimlane(t(), String.t() | atom(), keyword()) :: t()
  def add_swimlane(%__MODULE__{} = workflow, name, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @add_swimlane_schema)
    name = Choreo.Internal.ensure_cluster_prefix(name)
    clusters = Map.put(workflow.clusters || %{}, name, Map.new(opts))
    %{workflow | clusters: clusters}
  end

  # ============================================================================
  # Rendering
  # ============================================================================

  @doc """
  Renders the workflow to DOT format.

  ## Options

    * `:theme` — `:default`, `:dark`, or a `Choreo.Theme` struct

  ## Examples

      iex> workflow = Choreo.Workflow.new()
      iex> workflow = workflow
      ...>   |> Choreo.Workflow.add_start(:start)
      ...>   |> Choreo.Workflow.add_task(:process)
      ...>   |> Choreo.Workflow.add_end(:end)
      ...>   |> Choreo.Workflow.connect(:start, :process)
      ...>   |> Choreo.Workflow.connect(:process, :end)
      iex> dot = Choreo.Workflow.to_dot(workflow)
      iex> String.contains?(dot, "digraph")
      true
      iex> String.contains?(dot, "process")
      true
  """
  @spec to_dot(t(), keyword()) :: String.t()
  def to_dot(%__MODULE__{} = workflow, opts \\ []) do
    Choreo.Workflow.Render.DOT.to_dot(workflow, opts)
  end

  # ============================================================================
  # Queries
  # ============================================================================

  @doc """
  Returns all node IDs in the workflow.

  ## Examples

      iex> workflow = Choreo.Workflow.new()
      iex> workflow = workflow
      ...>   |> Choreo.Workflow.add_start(:a)
      ...>   |> Choreo.Workflow.add_task(:b)
      iex> Enum.sort(Choreo.Workflow.nodes(workflow))
      [:a, :b]
  """
  @spec nodes(t()) :: [Yog.node_id()]
  def nodes(%__MODULE__{graph: graph}) do
    Map.keys(graph.nodes)
  end

  @doc """
  Returns all edges as `{from, to, weight}` tuples.

  ## Examples

      iex> workflow = Choreo.Workflow.new()
      iex> workflow = workflow
      ...>   |> Choreo.Workflow.add_start(:a)
      ...>   |> Choreo.Workflow.add_task(:b)
      ...>   |> Choreo.Workflow.connect(:a, :b)
      iex> Choreo.Workflow.edges(workflow)
      [{:a, :b, 1}]
  """
  @spec edges(t()) :: [{Yog.node_id(), Yog.node_id(), number()}]
  def edges(%__MODULE__{graph: graph}) do
    Enum.map(graph.edges, fn {_edge_id, {from, to, weight}} ->
      {from, to, weight}
    end)
  end

  @doc """
  Returns all edges with their metadata as `{from, to, weight, meta}` tuples.
  """
  @spec edges_with_meta(t()) :: [{Yog.node_id(), Yog.node_id(), number(), map()}]
  def edges_with_meta(%__MODULE__{graph: graph, edge_meta: edge_meta}) do
    Enum.map(graph.edges, fn {edge_id, {from, to, weight}} ->
      {from, to, weight, Map.get(edge_meta, edge_id, %{})}
    end)
  end

  @doc """
  Collapses parallel edges into a simple Graph for algorithm analysis.
  """
  @spec to_simple_graph(t(), keyword()) :: Yog.Graph.t()
  def to_simple_graph(%__MODULE__{graph: graph}, opts \\ []) do
    combine = Keyword.get(opts, :combine, &min/2)
    Yog.Multi.to_simple_graph(graph, combine)
  end

  @doc """
  Returns all task node IDs.

  ## Examples

      iex> workflow = Choreo.Workflow.new()
      iex> workflow = workflow
      ...>   |> Choreo.Workflow.add_task(:a)
      ...>   |> Choreo.Workflow.add_task(:b)
      ...>   |> Choreo.Workflow.add_start(:s)
      iex> Enum.sort(Choreo.Workflow.tasks(workflow))
      [:a, :b]
  """
  @spec tasks(t()) :: [Yog.node_id()]
  def tasks(%__MODULE__{graph: graph}) do
    graph.nodes
    |> Enum.filter(fn {_id, data} -> data[:node_type] == :task end)
    |> Enum.map(fn {id, _data} -> id end)
  end

  @doc """
  Returns all start node IDs.

  ## Examples

      iex> workflow = Choreo.Workflow.new()
      iex> workflow = workflow
      ...>   |> Choreo.Workflow.add_start(:a)
      ...>   |> Choreo.Workflow.add_start(:b)
      iex> Enum.sort(Choreo.Workflow.starts(workflow))
      [:a, :b]
  """
  @spec starts(t()) :: [Yog.node_id()]
  def starts(%__MODULE__{graph: graph}) do
    graph.nodes
    |> Enum.filter(fn {_id, data} -> data[:node_type] == :start end)
    |> Enum.map(fn {id, _data} -> id end)
  end

  @doc """
  Returns all end node IDs.

  ## Examples

      iex> workflow = Choreo.Workflow.new()
      iex> workflow = workflow
      ...>   |> Choreo.Workflow.add_end(:a)
      ...>   |> Choreo.Workflow.add_end(:b)
      iex> Enum.sort(Choreo.Workflow.ends(workflow))
      [:a, :b]
  """
  @spec ends(t()) :: [Yog.node_id()]
  def ends(%__MODULE__{graph: graph}) do
    graph.nodes
    |> Enum.filter(fn {_id, data} -> data[:node_type] == :end end)
    |> Enum.map(fn {id, _data} -> id end)
  end

  @doc """
  Returns all compensation node IDs.

  ## Examples

      iex> workflow = Choreo.Workflow.new()
      iex> workflow = workflow
      ...>   |> Choreo.Workflow.add_compensation(:rollback, for: :task_a)
      ...>   |> Choreo.Workflow.add_compensation(:undo, for: :task_b)
      iex> Enum.sort(Choreo.Workflow.compensations(workflow))
      [:rollback, :undo]
  """
  @spec compensations(t()) :: [Yog.node_id()]
  def compensations(%__MODULE__{graph: graph}) do
    graph.nodes
    |> Enum.filter(fn {_id, data} -> data[:node_type] == :compensation end)
    |> Enum.map(fn {id, _data} -> id end)
  end

  @doc """
  Returns the raw `Yog.Graph` struct underpinning the workflow.

  ## Examples

      iex> workflow = Choreo.Workflow.new()
      iex> graph = Choreo.Workflow.to_graph(workflow)
      iex> graph.kind
      :directed
  """
  @spec to_graph(t()) :: Yog.graph()
  def to_graph(%__MODULE__{graph: graph}), do: graph

  # ============================================================================
  # Private helpers
  # ============================================================================

  defp add_typed_node(%__MODULE__{graph: graph} = workflow, id, type, opts) do
    data =
      opts
      |> Map.new()
      |> Map.merge(%{
        type: :workflow_node,
        node_type: type,
        label: Keyword.get(opts, :label, to_string(id))
      })

    data = put_swimlane(data, opts[:swimlane])
    %{workflow | graph: Yog.Multi.add_node(graph, id, data)}
  end

  defp put_swimlane(data, nil), do: data

  defp put_swimlane(data, swimlane),
    do: Map.put(data, :cluster, Choreo.Internal.ensure_cluster_prefix(swimlane))

  defp default_weight(_graph, _to, :compensation), do: 0
  defp default_weight(_graph, _to, :retry), do: 0
  defp default_weight(_graph, _to, :failure), do: 0
  defp default_weight(_graph, _to, :timeout), do: 0

  defp default_weight(graph, to, _edge_type) do
    case Map.get(graph.nodes, to) do
      %{timeout_ms: ms} when is_number(ms) and ms > 0 -> ms
      _ -> 1
    end
  end

  defp edge_type_label(:sequence), do: nil
  defp edge_type_label(:compensation), do: "compensate"
  defp edge_type_label(:retry), do: "retry"
  defp edge_type_label(:failure), do: "failure"
  defp edge_type_label(:timeout), do: "timeout"
  defp edge_type_label(_), do: nil
end

defimpl Choreo.DOT, for: Choreo.Workflow do
  def to_dot(workflow, opts), do: Choreo.Workflow.Render.DOT.to_dot(workflow, opts)
end
