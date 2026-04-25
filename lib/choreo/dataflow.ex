defmodule Choreo.Dataflow do
  @moduledoc """
  Dataflow / pipeline diagram builder on top of Yog.

  `Choreo.Dataflow` models stream-processing and ETL pipelines where
  nodes are processing stages and edges are data streams. It is a natural
  complement to `Choreo` architecture diagrams: those show *what*
  infrastructure exists; dataflow shows *how data moves through it*.

  ## Node types

    * `:source` — entry point that produces data
    * `:sink` — terminal consumer that persists or emits data
    * `:transform` — stateless operation (map, filter, aggregate)
    * `:buffer` — queue, topic, or back-pressure buffer
    * `:conditional` — branch / split based on a predicate
    * `:merge` — join multiple streams into one

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

      pipeline =
        Choreo.Dataflow.new()
        |> Choreo.Dataflow.add_cluster("ingest", label: "Ingestion", fillcolor: "#ecfdf5")
        |> Choreo.Dataflow.add_source(:sensor, cluster: "ingest")
  """
  @spec add_cluster(t(), String.t(), keyword()) :: t()
  def add_cluster(%__MODULE__{} = flow, name, opts \\ []) do
    name = ensure_cluster_prefix(name)
    cluster = Map.new(opts)
    clusters = Map.put(flow.clusters, name, cluster)
    %{flow | clusters: clusters}
  end

  # ============================================================================
  # Edge builders
  # ============================================================================

  @doc """
  Connects two stages with a data-flow edge.

  ## Options

    * `:data_type` — type of data travelling the edge (rendered as label)
    * `:label` — override label (defaults to `data_type`)
    * `:rate` — throughput annotation (visual only)
    * `:path_type` — `:normal` (default), `:error`, `:retry`, `:dead_letter`
    * `:weight` — numeric weight for critical-path analysis (default: `1`)

  ## Examples

      flow = Choreo.Dataflow.connect(flow, :parse, :kafka, data_type: "Event")
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

    edge_meta = Map.put(flow.edge_meta, {from, to}, meta)
    graph = Yog.add_edge_ensure(flow.graph, from, to, weight)

    %{flow | graph: graph, edge_meta: edge_meta}
  end

  @doc """
  Adds an error-path edge between two stages.

  Error paths are rendered in red with a dashed style.
  """
  @spec add_error_path(t(), Yog.node_id(), Yog.node_id(), keyword()) :: t()
  def add_error_path(%__MODULE__{} = flow, from, to, opts \\ []) do
    connect(flow, from, to, Keyword.put(opts, :path_type, :error))
  end

  @doc """
  Adds a retry-path edge between two stages.

  Retry paths are rendered in orange with a dotted style.
  """
  @spec add_retry_path(t(), Yog.node_id(), Yog.node_id(), keyword()) :: t()
  def add_retry_path(%__MODULE__{} = flow, from, to, opts \\ []) do
    connect(flow, from, to, Keyword.put(opts, :path_type, :retry))
  end

  @doc """
  Adds a dead-letter-path edge between two stages.

  Dead-letter paths are rendered in grey with a dashed style.
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
  """
  @spec nodes(t()) :: [Yog.node_id()]
  def nodes(%__MODULE__{graph: graph}) do
    Map.keys(graph.nodes)
  end

  @doc """
  Returns all edges as `{from, to, weight}` tuples.
  """
  @spec edges(t()) :: [{Yog.node_id(), Yog.node_id(), number()}]
  def edges(%__MODULE__{graph: graph}) do
    Yog.all_edges(graph)
  end

  @doc """
  Returns all nodes of a given type.

  ## Examples

      Choreo.Dataflow.nodes_of_type(flow, :source)
      #=> [:sensor, :webhook]
  """
  @spec nodes_of_type(t(), atom()) :: [Yog.node_id()]
  def nodes_of_type(%__MODULE__{graph: graph}, type) do
    graph.nodes
    |> Enum.filter(fn {_id, data} -> data[:node_type] == type end)
    |> Enum.map(fn {id, _data} -> id end)
  end

  @doc """
  Returns the raw `Yog.Graph` struct underpinning the dataflow.
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

    data = if cluster, do: Map.put(data, :cluster, ensure_cluster_prefix(cluster)), else: data

    %{flow | graph: Yog.add_node(graph, id, data)}
  end

  defp ensure_cluster_prefix(name) do
    name = to_string(name)
    if String.starts_with?(name, "cluster_"), do: name, else: "cluster_#{name}"
  end
end
