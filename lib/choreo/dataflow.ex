defmodule Choreo.Dataflow do
  @moduledoc """
  Dataflow / pipeline diagram builder on top of Yog.

  `Choreo.Dataflow` models stream-processing and ETL pipelines where
  nodes are processing stages and edges are data streams. It is a natural
  complement to `Choreo` architecture diagrams: those show *what*
  infrastructure exists; dataflow shows *how data moves through it*.

  ## When to use

  Use `Choreo.Dataflow` when designing, reviewing, or debugging pipelines
  — event-driven systems, ETL jobs, stream processors, or microservice
  data flows. It helps identify bottlenecks, orphan stages, and critical
  paths before they hit production.

  ## Node types

    * `:source` — entry point that produces data
    * `:sink` — terminal consumer that persists or emits data
    * `:transform` — stateless operation (map, filter, aggregate)
    * `:buffer` — queue, topic, or back-pressure buffer
    * `:conditional` — branch / split based on a predicate
    * `:merge` — join multiple streams into one

  ## Further reading

    * [Dataflow Programming (Wikipedia)](https://en.wikipedia.org/wiki/Dataflow_programming)
    * [Streaming Systems (O'Reilly)](https://www.oreilly.com/library/view/streaming-systems/9781491983867/)
    * [Enterprise Integration Patterns](https://www.enterpriseintegrationpatterns.com/)

  ## Quick Start

      pipeline =
        Choreo.Dataflow.new()
        |> Choreo.Dataflow.add_source(:sensor, label: "IoT Sensor")
        |> Choreo.Dataflow.add_transform(:parse, label: "JSON Parser")
        |> Choreo.Dataflow.add_buffer(:kafka, label: "Kafka Topic")
        |> Choreo.Dataflow.add_transform(:aggregate, label: "Window Agg")
        |> Choreo.Dataflow.add_sink(:db, label: "TimescaleDB")
        |> Choreo.Dataflow.connect(:sensor, :parse, data_type: "raw bytes")
        |> Choreo.Dataflow.connect(:parse, :kafka, data_type: "event")
        |> Choreo.Dataflow.connect(:kafka, :aggregate, data_type: "event")
        |> Choreo.Dataflow.connect(:aggregate, :db, data_type: "metrics")

      dot = Choreo.Dataflow.to_dot(pipeline)

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=LR, splines=spline, nodesep=0.6, ranksep=1.2];
      node [shape=box, style=filled, fillcolor="white", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [arrowhead=normal, color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];

      parse [label="JSON Parser", fillcolor="#3b82f6", shape="box3d"];
      aggregate [label="Window Agg", fillcolor="#3b82f6", shape="box3d"];
      sensor [label="IoT Sensor", fillcolor="#10b981", shape="house"];
      kafka [label="Kafka Topic", fillcolor="#f59e0b", shape="cylinder"];
      db [label="TimescaleDB", fillcolor="#f43f5e", shape="invhouse"];

      parse -> kafka [style="solid", penwidth="1.0", color="#64748b", label="event"];
      aggregate -> db [style="solid", penwidth="1.0", color="#64748b", label="metrics"];
      sensor -> parse [style="solid", penwidth="1.0", color="#64748b", label="raw bytes"];
      kafka -> aggregate [style="solid", penwidth="1.0", color="#64748b", label="event"];
    }
  </div>

  ## Analysis

      # Detect feedback loops (usually a bug in dataflow)
      Choreo.Dataflow.Analysis.cyclic?(pipeline)

      # Execution order for a DAG
      {:ok, order} = Choreo.Dataflow.Analysis.topological_sort(pipeline)

      # Find orphan stages with no upstream source
      Choreo.Dataflow.Analysis.orphan_nodes(pipeline)

      # Find dead-end stages that never reach a sink
      Choreo.Dataflow.Analysis.dead_ends(pipeline)

      # Longest latency path (critical path)
      {:ok, path, latency} = Choreo.Dataflow.Analysis.longest_path(pipeline)

      # Throughput simulation
      Choreo.Dataflow.Analysis.simulate(pipeline)
  """

  @type t :: %__MODULE__{
          graph: Yog.graph(),
          edge_meta: %{optional({Yog.node_id(), Yog.node_id()}) => map()},
          clusters: %{String.t() => map()}
        }

  defstruct graph: nil, edge_meta: %{}, clusters: %{}

  # ============================================================================
  # Creation
  # ============================================================================

  @doc """
  Creates a new empty dataflow graph.

  Dataflow graphs are always directed.

  ## Examples

      iex> flow = Choreo.Dataflow.new()
      iex> Choreo.Dataflow.nodes(flow)
      []
      iex> Choreo.Dataflow.edges(flow)
      []
  """
  @spec new() :: t()
  def new do
    %__MODULE__{
      graph: Yog.directed(),
      edge_meta: %{},
      clusters: %{}
    }
  end

  # ============================================================================
  # Node builders
  # ============================================================================

  @doc """
  Adds a source node (data producer / entry point).

  ## Options

    * `:label` — display label (defaults to the node id)
    * `:description` — tooltip text
    * `:rate` — throughput in events/sec (used by simulation)
    * `:cluster` — cluster name for grouping

  ## Examples

      iex> flow = Choreo.Dataflow.new()
      iex> flow = Choreo.Dataflow.add_source(flow, :sensor, label: "IoT Sensor")
      iex> Choreo.Dataflow.nodes(flow)
      [:sensor]
      iex> Yog.node(flow.graph, :sensor).node_type
      :source
      iex> Yog.node(flow.graph, :sensor).label
      "IoT Sensor"

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=LR, splines=spline, nodesep=0.6, ranksep=1.2];
      node [shape=box, style=filled, fillcolor="white", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [arrowhead=normal, color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];

      sensor [label="IoT Sensor", fillcolor="#10b981", shape="house"];
    }
  </div>
  """
  @spec add_source(t(), Yog.node_id(), keyword()) :: t()
  def add_source(flow, id, opts \\ []) do
    add_typed_node(flow, id, :source, opts)
  end

  @doc """
  Adds a sink node (data consumer / terminal).

  ## Options

    * `:label` — display label (defaults to the node id)
    * `:description` — tooltip text
    * `:cluster` — cluster name for grouping

  ## Examples

      iex> flow = Choreo.Dataflow.new()
      iex> flow = Choreo.Dataflow.add_sink(flow, :db, label: "TimescaleDB")
      iex> Choreo.Dataflow.nodes(flow)
      [:db]
      iex> Yog.node(flow.graph, :db).node_type
      :sink

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=LR, splines=spline, nodesep=0.6, ranksep=1.2];
      node [shape=box, style=filled, fillcolor="white", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [arrowhead=normal, color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];

      db [label="TimescaleDB", fillcolor="#f43f5e", shape="invhouse"];
    }
  </div>
  """
  @spec add_sink(t(), Yog.node_id(), keyword()) :: t()
  def add_sink(flow, id, opts \\ []) do
    add_typed_node(flow, id, :sink, opts)
  end

  @doc """
  Adds a transform node (stateless processing).

  ## Options

    * `:label` — display label (defaults to the node id)
    * `:description` — tooltip text
    * `:latency_ms` — processing latency in milliseconds (used by simulation)
    * `:cluster` — cluster name for grouping

  ## Examples

      iex> flow = Choreo.Dataflow.new()
      iex> flow = Choreo.Dataflow.add_transform(flow, :parse, label: "JSON Parser")
      iex> Choreo.Dataflow.nodes(flow)
      [:parse]
      iex> Yog.node(flow.graph, :parse).node_type
      :transform

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=LR, splines=spline, nodesep=0.6, ranksep=1.2];
      node [shape=box, style=filled, fillcolor="white", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [arrowhead=normal, color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];

      parse [label="JSON Parser", fillcolor="#3b82f6", shape="box3d"];
    }
  </div>
  """
  @spec add_transform(t(), Yog.node_id(), keyword()) :: t()
  def add_transform(flow, id, opts \\ []) do
    add_typed_node(flow, id, :transform, opts)
  end

  @doc """
  Adds a buffer node (queue, topic, back-pressure reservoir).

  ## Options

    * `:label` — display label (defaults to the node id)
    * `:description` — tooltip text
    * `:capacity` — annotated capacity (visual only)
    * `:latency_ms` — buffering latency in milliseconds (used by simulation)
    * `:cluster` — cluster name for grouping

  ## Examples

      iex> flow = Choreo.Dataflow.new()
      iex> flow = Choreo.Dataflow.add_buffer(flow, :kafka, label: "Kafka Topic", capacity: 1000)
      iex> Choreo.Dataflow.nodes(flow)
      [:kafka]
      iex> Yog.node(flow.graph, :kafka).node_type
      :buffer
      iex> Yog.node(flow.graph, :kafka).capacity
      1000

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=LR, splines=spline, nodesep=0.6, ranksep=1.2];
      node [shape=box, style=filled, fillcolor="white", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [arrowhead=normal, color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];

      kafka [label="Kafka Topic\n(cap: 1000)", fillcolor="#f59e0b", shape="cylinder"];
    }
  </div>
  """
  @spec add_buffer(t(), Yog.node_id(), keyword()) :: t()
  def add_buffer(flow, id, opts \\ []) do
    add_typed_node(flow, id, :buffer, opts)
  end

  @doc """
  Adds a conditional / split node (branching).

  ## Options

    * `:label` — display label (defaults to the node id)
    * `:description` — tooltip text
    * `:cluster` — cluster name for grouping

  ## Examples

      iex> flow = Choreo.Dataflow.new()
      iex> flow = Choreo.Dataflow.add_conditional(flow, :valid, label: "If valid")
      iex> Choreo.Dataflow.nodes(flow)
      [:valid]
      iex> Yog.node(flow.graph, :valid).node_type
      :conditional

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=LR, splines=spline, nodesep=0.6, ranksep=1.2];
      node [shape=box, style=filled, fillcolor="white", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [arrowhead=normal, color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];

      valid [label="If valid", fillcolor="#8b5cf6", shape="diamond"];
    }
  </div>
  """
  @spec add_conditional(t(), Yog.node_id(), keyword()) :: t()
  def add_conditional(flow, id, opts \\ []) do
    add_typed_node(flow, id, :conditional, opts)
  end

  @doc """
  Adds a merge / join node (combining multiple streams).

  ## Options

    * `:label` — display label (defaults to the node id)
    * `:description` — tooltip text
    * `:cluster` — cluster name for grouping

  ## Examples

      iex> flow = Choreo.Dataflow.new()
      iex> flow = Choreo.Dataflow.add_merge(flow, :join, label: "Join")
      iex> Choreo.Dataflow.nodes(flow)
      [:join]
      iex> Yog.node(flow.graph, :join).node_type
      :merge

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=LR, splines=spline, nodesep=0.6, ranksep=1.2];
      node [shape=box, style=filled, fillcolor="white", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [arrowhead=normal, color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];

      join [label="Join", fillcolor="#06b6d4", shape="trapezium"];
    }
  </div>
  """
  @spec add_merge(t(), Yog.node_id(), keyword()) :: t()
  def add_merge(flow, id, opts \\ []) do
    add_typed_node(flow, id, :merge, opts)
  end

  # ============================================================================
  # Clusters
  # ============================================================================

  @doc """
  Defines a cluster (subgraph) for grouping nodes visually.

  ## Options

    * `:parent` — name of the parent cluster for nesting
    * `:label` — display label (defaults to the cluster name)
    * `:style` — `:filled`, `:rounded`, etc.
    * `:fillcolor` — background colour
    * `:color` — border colour

  ## Examples

      iex> flow = Choreo.Dataflow.new()
      iex> flow = Choreo.Dataflow.add_cluster(flow, "ingest", label: "Ingestion")
      iex> flow.clusters["cluster_ingest"].label
      "Ingestion"
  """
  @spec add_cluster(t(), String.t(), keyword()) :: t()
  def add_cluster(%__MODULE__{} = flow, name, opts \\ []) do
    name = Choreo.Internal.ensure_cluster_prefix(name)
    cluster = Map.new(opts)
    clusters = Map.put(flow.clusters, name, cluster)
    %{flow | clusters: clusters}
  end

  # ============================================================================
  # Edge builders
  # ============================================================================

  @doc """
  Connects two stages with a data-flow edge.

  > ### Limitation
  > At most one edge is allowed per `(from, to)` pair.
  > Adding a second connection between the same stages raises
  > `ArgumentError`. Multigraph support (parallel edges) is planned
  > for a future release.

  ## Options

    * `:data_type` — type of data travelling the edge (rendered as label)
    * `:label` — override label (defaults to `data_type`)
    * `:rate` — throughput annotation (visual only)
    * `:path_type` — `:normal` (default), `:error`, `:retry`, `:dead_letter`
    * `:weight` — numeric weight for critical-path analysis (default: `1`)

  ## Examples

      iex> flow = Choreo.Dataflow.new()
      iex> flow = flow
      ...>   |> Choreo.Dataflow.add_source(:a)
      ...>   |> Choreo.Dataflow.add_transform(:b)
      ...>   |> Choreo.Dataflow.connect(:a, :b, data_type: "event")
      iex> Choreo.Dataflow.edges(flow)
      [{:a, :b, 1}]
      iex> flow.edge_meta[{:a, :b}].label
      "event"
      iex> flow.edge_meta[{:a, :b}].path_type
      :normal

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=LR, splines=spline, nodesep=0.6, ranksep=1.2];
      node [shape=box, style=filled, fillcolor="white", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [arrowhead=normal, color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];

      b [label="b", fillcolor="#3b82f6", shape="box3d"];
      a [label="a", fillcolor="#10b981", shape="house"];

      a -> b [style="solid", penwidth="1.0", color="#64748b", label="event"];
    }
  </div>
  """
  @spec connect(t(), Yog.node_id(), Yog.node_id(), keyword()) :: t()
  def connect(%__MODULE__{} = flow, from, to, opts \\ []) do
    data_type = opts[:data_type]
    label = opts[:label] || data_type

    meta =
      opts
      |> Map.new()
      |> Map.put(:label, label)
      |> Map.put_new(:path_type, :normal)

    weight = opts[:weight] || 1

    if Yog.has_edge?(flow.graph, from, to) do
      raise ArgumentError,
            "connection from #{inspect(from)} to #{inspect(to)} already exists"
    end

    edge_meta = Map.put(flow.edge_meta, {from, to}, meta)
    graph = Yog.add_edge_ensure(flow.graph, from, to, weight)

    %{flow | graph: graph, edge_meta: edge_meta}
  end

  @doc """
  Adds an error-path edge between two stages.

  Error paths are rendered in red with a dashed style.

  ## Examples

      iex> flow = Choreo.Dataflow.new()
      iex> flow = flow
      ...>   |> Choreo.Dataflow.add_transform(:a)
      ...>   |> Choreo.Dataflow.add_sink(:b)
      ...>   |> Choreo.Dataflow.add_error_path(:a, :b)
      iex> flow.edge_meta[{:a, :b}].path_type
      :error
  """
  @spec add_error_path(t(), Yog.node_id(), Yog.node_id(), keyword()) :: t()
  def add_error_path(%__MODULE__{} = flow, from, to, opts \\ []) do
    connect(flow, from, to, Keyword.put(opts, :path_type, :error))
  end

  @doc """
  Adds a retry-path edge between two stages.

  Retry paths are rendered in orange with a dotted style.

  ## Examples

      iex> flow = Choreo.Dataflow.new()
      iex> flow = flow
      ...>   |> Choreo.Dataflow.add_transform(:a)
      ...>   |> Choreo.Dataflow.add_sink(:b)
      ...>   |> Choreo.Dataflow.add_retry_path(:a, :b)
      iex> flow.edge_meta[{:a, :b}].path_type
      :retry
  """
  @spec add_retry_path(t(), Yog.node_id(), Yog.node_id(), keyword()) :: t()
  def add_retry_path(%__MODULE__{} = flow, from, to, opts \\ []) do
    connect(flow, from, to, Keyword.put(opts, :path_type, :retry))
  end

  @doc """
  Adds a dead-letter-path edge between two stages.

  Dead-letter paths are rendered in grey with a dashed style.

  ## Examples

      iex> flow = Choreo.Dataflow.new()
      iex> flow = flow
      ...>   |> Choreo.Dataflow.add_transform(:a)
      ...>   |> Choreo.Dataflow.add_sink(:b)
      ...>   |> Choreo.Dataflow.add_dead_letter_path(:a, :b)
      iex> flow.edge_meta[{:a, :b}].path_type
      :dead_letter
  """
  @spec add_dead_letter_path(t(), Yog.node_id(), Yog.node_id(), keyword()) :: t()
  def add_dead_letter_path(%__MODULE__{} = flow, from, to, opts \\ []) do
    connect(flow, from, to, Keyword.put(opts, :path_type, :dead_letter))
  end

  # ============================================================================
  # Queries
  # ============================================================================

  @doc """
  Returns all node IDs in the dataflow.

  ## Examples

      iex> flow = Choreo.Dataflow.new()
      iex> flow = flow
      ...>   |> Choreo.Dataflow.add_source(:a)
      ...>   |> Choreo.Dataflow.add_transform(:b)
      iex> Enum.sort(Choreo.Dataflow.nodes(flow))
      [:a, :b]
  """
  @spec nodes(t()) :: [Yog.node_id()]
  def nodes(%__MODULE__{graph: graph}) do
    Map.keys(graph.nodes)
  end

  @doc """
  Returns all edges as `{from, to, weight}` tuples.

  ## Examples

      iex> flow = Choreo.Dataflow.new()
      iex> flow = flow
      ...>   |> Choreo.Dataflow.add_source(:a)
      ...>   |> Choreo.Dataflow.add_transform(:b)
      ...>   |> Choreo.Dataflow.connect(:a, :b)
      iex> Choreo.Dataflow.edges(flow)
      [{:a, :b, 1}]
  """
  @spec edges(t()) :: [{Yog.node_id(), Yog.node_id(), number()}]
  def edges(%__MODULE__{graph: graph}) do
    Yog.all_edges(graph)
  end

  @doc """
  Returns all nodes of a given type.

  ## Examples

      iex> flow = Choreo.Dataflow.new()
      iex> flow = flow
      ...>   |> Choreo.Dataflow.add_source(:a)
      ...>   |> Choreo.Dataflow.add_source(:b)
      ...>   |> Choreo.Dataflow.add_sink(:c)
      iex> Enum.sort(Choreo.Dataflow.nodes_of_type(flow, :source))
      [:a, :b]
      iex> Choreo.Dataflow.nodes_of_type(flow, :sink)
      [:c]
      iex> Choreo.Dataflow.nodes_of_type(flow, :transform)
      []
  """
  @spec nodes_of_type(t(), atom()) :: [Yog.node_id()]
  def nodes_of_type(%__MODULE__{graph: graph}, type) do
    graph.nodes
    |> Enum.filter(fn {_id, data} -> data[:node_type] == type end)
    |> Enum.map(fn {id, _data} -> id end)
  end

  @doc """
  Returns the raw `Yog.Graph` struct underpinning the dataflow.

  ## Examples

      iex> flow = Choreo.Dataflow.new()
      iex> graph = Choreo.Dataflow.to_graph(flow)
      iex> graph.kind
      :directed
  """
  @spec to_graph(t()) :: Yog.graph()
  def to_graph(%__MODULE__{graph: graph}), do: graph

  # ============================================================================
  # Rendering
  # ============================================================================

  @doc """
  Renders the dataflow to DOT format.

  ## Options

    * `:theme` — `:default`, `:dark`, or a `Choreo.Theme` struct

  ## Examples

      iex> flow = Choreo.Dataflow.new()
      iex> flow = flow
      ...>   |> Choreo.Dataflow.add_source(:in, label: "Input")
      ...>   |> Choreo.Dataflow.add_transform(:proc, label: "Process")
      ...>   |> Choreo.Dataflow.add_sink(:out, label: "Output")
      ...>   |> Choreo.Dataflow.connect(:in, :proc, data_type: "raw")
      ...>   |> Choreo.Dataflow.connect(:proc, :out, data_type: "result")
      iex> dot = Choreo.Dataflow.to_dot(flow)
      iex> String.contains?(dot, "digraph")
      true
      iex> String.contains?(dot, "Input")
      true
      iex> String.contains?(dot, "Output")
      true
  """
  @spec to_dot(t(), keyword()) :: String.t()
  def to_dot(%__MODULE__{} = flow, opts \\ []) do
    Choreo.Dataflow.Render.DOT.to_dot(flow, opts)
  end

  # ============================================================================
  # Private helpers
  # ============================================================================

  defp add_typed_node(%__MODULE__{graph: graph} = flow, id, type, opts) do
    {cluster, rest_opts} = Keyword.pop(opts, :cluster)

    data = %{
      type: :dataflow_node,
      node_type: type,
      label: Keyword.get(rest_opts, :label, to_string(id)),
      description: rest_opts[:description],
      capacity: rest_opts[:capacity],
      rate: rest_opts[:rate],
      latency_ms: rest_opts[:latency_ms]
    }

    data =
      if cluster,
        do: Map.put(data, :cluster, Choreo.Internal.ensure_cluster_prefix(cluster)),
        else: data

    %{flow | graph: Yog.add_node(graph, id, data)}
  end
end
