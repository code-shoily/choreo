defmodule Choreo do
  @moduledoc """
  A domain-specific layer on top of Yog for modeling system architectures.

  Choreo lets you define infrastructure diagrams (databases, caches,
  services, networks, etc.) as graphs and render them to DOT format with
  system-diagram theming. You can also run graph algorithms such as MST
  and topological sort to analyze your architecture.

  ## When to use

  Use `Choreo` when you need to document, communicate, or analyze the
  infrastructure of a system — whether for architecture review, onboarding
  docs, cost optimisation, or resilience planning.

  ## Quick Start

      system =
        Choreo.new()
        |> Choreo.add_database(:db, name: "Postgres", kind: :postgres)
        |> Choreo.add_cache(:cache, name: "Redis", kind: :redis)
        |> Choreo.add_service(:api, name: "API Gateway")
        |> Choreo.connect(:api, :cache, cost: 5)
        |> Choreo.connect(:api, :db, cost: 10)

      dot = Choreo.to_dot(system)

  ## Algorithms

      # Minimum spanning tree for cost optimisation
      {:ok, mst} = Choreo.Analysis.mst(system)

      # Topological sort for data-flow ordering
      {:ok, order} = Choreo.Analysis.topological_sort(system)

  ## Diagram

  <div class="graphviz">
      digraph G {
      graph [rankdir=TB, splines=spline, nodesep=0.6, ranksep=1.2];
      node [shape=ellipse, style=filled, fillcolor="lightblue", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];

      cache [label="Redis", style="filled", fontcolor="white", fillcolor="#f59e0b", shape="octagon"];
      api [label="API Gateway", style="filled", fontcolor="white", fillcolor="#10b981", shape="box3d"];
      db [label="Postgres", style="filled", fontcolor="white", fillcolor="#3b82f6", shape="cylinder"];

      api -> cache [label="5", penwidth="1.0", color="#64748b"];
      api -> db [label="10", penwidth="1.0", color="#64748b", headport="n"];
    }
  </div>
  """

  alias __MODULE__

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
  Creates a new empty system diagram.

  ## Options

    * `:directed` - whether the underlying graph is directed (default: `true`)

  ## Examples

      iex> Choreo.new()
      iex> Choreo.new(directed: false)
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    kind = if Keyword.get(opts, :directed, true), do: :directed, else: :undirected

    %__MODULE__{
      graph: Yog.new(kind),
      edge_meta: %{},
      clusters: %{}
    }
  end

  # ============================================================================
  # Node builders
  # ============================================================================

  @doc """
  Adds a database node to the system.

  ## Options

    * `:kind` - `:postgres`, `:mysql`, `:mongodb`, `:dynamodb`, etc.
    * `:name` - display name (defaults to the node id)
    * `:description` - tooltip / annotation text

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=TB, splines=spline, nodesep=0.6, ranksep=1.2];
      node [shape=ellipse, style=filled, fillcolor="lightblue", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];
      db [label="db", style="filled", fontcolor="white", fillcolor="#14b8a6", shape="tab"];
    }
  </div>

  """
  @spec add_database(t(), Yog.node_id(), keyword()) :: t()
  def add_database(system, id, opts \\ []) do
    add_typed_node(system, id, :database, opts)
  end

  @doc """
  Adds a cache node to the system.

  ## Diagram

  <div class="graphviz">
      digraph G {
        graph [rankdir=TB, splines=spline, nodesep=0.6, ranksep=1.2];
        node [shape=ellipse, style=filled, fillcolor="lightblue", fontname="Helvetica", fontsize=12, fontcolor="white"];
        edge [color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];
        cache [label="Redis", style="filled", fontcolor="white", fillcolor="#f59e0b", shape="octagon"];
      }
  </div>

  ## Options

    * `:kind` - `:redis`, `:memcached`, etc.
    * `:name` - display name
    * `:description` - tooltip / annotation text
  """
  @spec add_cache(t(), Yog.node_id(), keyword()) :: t()
  def add_cache(system, id, opts \\ []) do
    add_typed_node(system, id, :cache, opts)
  end

  @doc """
  Adds a service / application node to the system.

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=TB, splines=spline, nodesep=0.6, ranksep=1.2];
      node [shape=ellipse, style=filled, fillcolor="lightblue", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];
      auth [label="auth", style="filled", fontcolor="white", fillcolor="#10b981", shape="box3d"];
    }
  </div>

  ## Options

    * `:kind` - `:api`, `:worker`, `:web`, `:microservice`, etc.
    * `:name` - display name
    * `:description` - tooltip / annotation text
  """
  @spec add_service(t(), Yog.node_id(), keyword()) :: t()
  def add_service(system, id, opts \\ []) do
    add_typed_node(system, id, :service, opts)
  end

  @doc """
  Adds a network / infrastructure boundary node.

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=TB, splines=spline, nodesep=0.6, ranksep=1.2];
      node [shape=ellipse, style=filled, fillcolor="lightblue", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];

      cloudflare [label="cloudflare", style="filled", fontcolor="white", fillcolor="#6366f1", shape="cloud"];
    }
  </div>

  ## Options

    * `:kind` - `:vpc`, `:subnet`, `:cdn`, `:dns`, `:firewall`, etc.
    * `:name` - display name
    * `:description` - tooltip / annotation text
  """
  @spec add_network(t(), Yog.node_id(), keyword()) :: t()
  def add_network(system, id, opts \\ []) do
    add_typed_node(system, id, :network, opts)
  end

  @doc """
  Adds a user / external actor node to the system.

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=TB, splines=spline, nodesep=0.6, ranksep=1.2];
      node [shape=ellipse, style=filled, fillcolor="lightblue", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];
      user [label="user", style="filled", fontcolor="white", fillcolor="#ef4444", shape="doublecircle"];
    }
  </div>

  ## Options

    * `:kind` - `:person`, `:device`, `:external_service`, etc.
    * `:name` - display name
    * `:description` - tooltip / annotation text
  """
  @spec add_user(t(), Yog.node_id(), keyword()) :: t()
  def add_user(system, id, opts \\ []) do
    add_typed_node(system, id, :user, opts)
  end

  @doc """
  Adds a load-balancer node to the system.

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=TB, splines=spline, nodesep=0.6, ranksep=1.2];
      node [shape=ellipse, style=filled, fillcolor="lightblue", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];
      lb [label="lb", style="filled", fontcolor="white", fillcolor="#8b5cf6", shape="hexagon"];
    }
  </div>

  ## Options

    * `:kind` - `:nginx`, `:haproxy`, `:alb`, `:cloudflare`, etc.
    * `:name` - display name
    * `:description` - tooltip / annotation text
  """
  @spec add_load_balancer(t(), Yog.node_id(), keyword()) :: t()
  def add_load_balancer(system, id, opts \\ []) do
    add_typed_node(system, id, :load_balancer, opts)
  end

  @doc """
  Adds a queue / messaging node to the system.

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=TB, splines=spline, nodesep=0.6, ranksep=1.2];
      node [shape=ellipse, style=filled, fillcolor="lightblue", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];

      queue [label="queue", style="filled", fontcolor="white", fillcolor="#ec4899", shape="component"];
    }
  </div>

  ## Options

    * `:kind` - `:kafka`, `:rabbitmq`, `:sqs`, `:pubsub`, etc.
    * `:name` - display name
    * `:description` - tooltip / annotation text
  """
  @spec add_queue(t(), Yog.node_id(), keyword()) :: t()
  def add_queue(system, id, opts \\ []) do
    add_typed_node(system, id, :queue, opts)
  end

  @doc """
  Adds a storage / blob node to the system.

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=TB, splines=spline, nodesep=0.6, ranksep=1.2];
      node [shape=ellipse, style=filled, fillcolor="lightblue", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];
      storage [label="storage", style="filled", fontcolor="white", fillcolor="#6366f1", shape="box"];
    }
  </div>

  ## Options

    * `:kind` - `:s3`, `:nfs`, `:block`, `:glacier`, etc.
    * `:name` - display name
    * `:description` - tooltip / annotation text
  """
  @spec add_storage(t(), Yog.node_id(), keyword()) :: t()
  def add_storage(system, id, opts \\ []) do
    add_typed_node(system, id, :storage, opts)
  end

  @doc """
  Adds a generic node to the system.

  Use this when none of the typed builders fit.
  """
  @spec add_node(t(), Yog.node_id(), keyword()) :: t()
  def add_node(system, id, opts \\ []) do
    add_typed_node(system, id, :generic, opts)
  end

  @doc """
  Defines a cluster (subgraph) for grouping nodes visually.

  ## Options

    * `:parent` - name of the parent cluster for nesting (e.g. VPC → AZ)
    * `:label` - display label (defaults to the cluster name)
    * `:style` - `:filled`, `:rounded`, etc.
    * `:fillcolor` - background colour
    * `:color` - border colour

  ## Examples

      system =
        Choreo.new()
        |> Choreo.add_cluster("vpc", label: "VPC", fillcolor: "lightgrey")
        |> Choreo.add_cluster("az1", label: "AZ-1", parent: "vpc")
        |> Choreo.add_service(:api, cluster: "az1")
  """
  @spec add_cluster(t(), String.t(), keyword()) :: t()
  def add_cluster(%__MODULE__{} = system, name, opts \\ []) do
    name = Choreo.Internal.ensure_cluster_prefix(name)
    cluster = Map.new(opts)
    clusters = Map.put(system.clusters, name, cluster)
    %{system | clusters: clusters}
  end

  defp add_typed_node(%__MODULE__{graph: graph} = system, id, type, opts) do
    {cluster, rest_opts} = Keyword.pop(opts, :cluster)

    data =
      rest_opts
      |> Map.new()
      |> Map.put(:type, type)
      |> Map.put_new(:name, to_string(id))

    data =
      if cluster,
        do: Map.put(data, :cluster, Choreo.Internal.ensure_cluster_prefix(cluster)),
        else: data

    %{system | graph: Yog.add_node(graph, id, data)}
  end

  # ============================================================================
  # Edge builders
  # ============================================================================

  @doc """
  Connects two nodes with a weighted edge.

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=TB, splines=spline, nodesep=0.6, ranksep=1.2];
      node [shape=ellipse, style=filled, fillcolor="lightblue", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];

      a [label="a", style="filled", fontcolor="white", fillcolor="#10b981", shape="box3d"];
      b [label="b", style="filled", fontcolor="white", fillcolor="#10b981", shape="box3d"];

      a -> b [label="5", penwidth="1.0", color="#64748b"];

    }
  </div>

  ## Options

    * `:cost` - numeric weight used by MST and other algorithms (default: `1`)
    * `:label` - display label for the edge
    * `:protocol` - `:http`, `:https`, `:grpc`, `:tcp`, etc.
  """
  @spec connect(t(), Yog.node_id(), Yog.node_id(), keyword()) :: t()
  def connect(%__MODULE__{} = system, from, to, opts \\ []) do
    cost = Keyword.get(opts, :cost, 1)

    meta =
      opts
      |> Map.new()
      |> Map.put_new(:label, nil)

    edge_meta = Map.put(system.edge_meta, {from, to}, meta)
    graph = Yog.add_edge_ensure(system.graph, from, to, cost)

    %{system | graph: graph, edge_meta: edge_meta}
  end

  @doc """
  Adds a data-flow edge between two nodes.

  This is semantically identical to `connect/4` but renders with a
  different default style (dashed, data-flow colour).
  """
  @spec add_dataflow(t(), Yog.node_id(), Yog.node_id(), keyword()) :: t()
  def add_dataflow(%__MODULE__{} = system, from, to, opts \\ []) do
    opts = Keyword.put_new(opts, :type, :dataflow)
    connect(system, from, to, opts)
  end

  # ============================================================================
  # Queries
  # ============================================================================

  @doc """
  Returns all nodes in the system as a map of `id => data`.
  """
  @spec nodes(t()) :: %{Yog.node_id() => map()}
  def nodes(%__MODULE__{graph: graph}) do
    graph.nodes
  end

  @doc """
  Returns all edges in the system as a list of `{from, to, cost}` tuples.
  """
  @spec edges(t()) :: [{Yog.node_id(), Yog.node_id(), number()}]
  def edges(%__MODULE__{graph: graph}) do
    Yog.all_edges(graph)
  end

  @doc """
  Returns the raw `Yog.Graph` struct underpinning the system.

  Useful when you want to drop down to the raw Yog API.
  """
  @spec to_graph(t()) :: Yog.graph()
  def to_graph(%__MODULE__{graph: graph}), do: graph

  # ============================================================================
  # Rendering
  # ============================================================================

  @doc """
  Renders the system diagram to DOT format.

  ## Options

    * `:theme` - `:default`, `:dark`, or `:minimal`
    * Any option accepted by `Yog.Render.DOT.to_dot/2`

  ## Examples

      iex> dot = Choreo.to_dot(system)
      iex> dot = Choreo.to_dot(system, theme: :dark)
  """
  @spec to_dot(t(), keyword()) :: String.t()
  def to_dot(%__MODULE__{} = system, opts \\ []) do
    Choreo.Render.DOT.to_dot(system, opts)
  end

  @doc """
  Returns all cluster definitions in the system.
  """
  @spec clusters(t()) :: %{String.t() => map()}
  def clusters(%__MODULE__{clusters: clusters}), do: clusters
end
