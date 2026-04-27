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
          graph: Yog.Multi.Graph.t(),
          edge_meta: %{optional(Yog.Multi.Graph.edge_id()) => map()},
          clusters: %{String.t() => map()}
        }

  defstruct graph: nil, edge_meta: %{}, clusters: %{}

  @new_schema [
    directed: [
      type: :boolean,
      required: false,
      default: true,
      doc: "Whether the underlying graph is directed."
    ]
  ]

  @node_schema [
    name: [
      type: :string,
      required: false,
      doc: "Display name (defaults to the node id)."
    ],
    description: [
      type: :string,
      required: false,
      doc: "Tooltip / annotation text."
    ],
    cluster: [
      type: :string,
      required: false,
      doc: "Cluster name for visual grouping."
    ],
    shape: [
      type: :atom,
      required: false,
      doc: "Shape override (e.g. `:box`, `:cylinder`)."
    ],
    fillcolor: [
      type: :string,
      required: false,
      doc: "Background color override."
    ],
    fontcolor: [
      type: :string,
      required: false,
      doc: "Font color override."
    ],
    style: [
      type: :string,
      required: false,
      doc: "Style override (e.g. `\"filled\"`)."
    ],
    penwidth: [
      type: {:or, [:integer, :float]},
      required: false,
      doc: "Border thickness override."
    ]
  ]

  @add_typed_node_schema [
                           kind: [
                             type: :atom,
                             required: false,
                             doc: "Specific kind of node (e.g. `:postgres`, `:redis`)."
                           ]
                         ] ++ @node_schema

  @add_cluster_schema [
    parent: [
      type: :string,
      required: false,
      doc: "Parent cluster name for nesting."
    ],
    label: [
      type: :string,
      required: false,
      doc: "Display label for the cluster."
    ],
    style: [
      type: :string,
      required: false,
      doc: "Visual style (e.g. `\"filled\"`, `\"rounded\"`)."
    ],
    fillcolor: [
      type: :string,
      required: false,
      doc: "Background color override."
    ],
    color: [
      type: :string,
      required: false,
      doc: "Border color override."
    ]
  ]

  @connect_schema [
    cost: [
      type: {:or, [:integer, :float]},
      required: false,
      default: 1,
      doc: "Numeric weight used by MST and algorithms."
    ],
    label: [
      type: :string,
      required: false,
      doc: "Display label for the edge."
    ],
    protocol: [
      type: {:or, [:atom, :string]},
      required: false,
      doc: "Communication protocol."
    ],
    type: [
      type: :atom,
      required: false,
      doc: "Internal semantic type."
    ],
    headport: [
      type: :string,
      required: false,
      doc: "Graphviz headport override."
    ],
    tailport: [
      type: :string,
      required: false,
      doc: "Graphviz tailport override."
    ]
  ]

  @embed_schema [
    prefix: [
      type: {:or, [:string, :atom]},
      required: false,
      default: "sub_",
      doc: "Prefix to prevent ID collisions."
    ]
  ]

  # ============================================================================
  # Creation
  # ============================================================================

  @doc """
  Creates a new empty system diagram.

  ## Options

  #{NimbleOptions.docs(@new_schema)}

  ## Examples

      iex> system = Choreo.new()
      iex> map_size(system.edge_meta)
      0
      iex> map_size(system.clusters)
      0
      iex> system = Choreo.new(directed: false)
      iex> system.graph.kind
      :undirected
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    opts = NimbleOptions.validate!(opts, @new_schema)
    kind = if opts[:directed], do: :directed, else: :undirected

    %__MODULE__{
      graph: Yog.Multi.new(kind),
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

  #{NimbleOptions.docs(@add_typed_node_schema)}

  ## Examples

      iex> system = Choreo.new() |> Choreo.add_database(:db, kind: :postgres)
      iex> Choreo.nodes(system)[:db].type
      :database
      iex> Choreo.nodes(system)[:db].kind
      :postgres
      iex> Choreo.nodes(system)[:db].name
      "db"

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=TB, splines=spline, nodesep=0.6, ranksep=1.2];
      node [shape=ellipse, style=filled, fillcolor="lightblue", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];
      db [label="db", style="filled", fontcolor="white", fillcolor="#3b82f6", shape="cylinder"];
    }
  </div>
  """
  @spec add_database(t(), Yog.node_id(), keyword()) :: t()
  def add_database(system, id, opts \\ []) do
    add_typed_node(system, id, :database, opts)
  end

  @doc """
  Adds a cache node to the system.

  ## Options

  #{NimbleOptions.docs(@add_typed_node_schema)}

  ## Examples

      iex> system = Choreo.new() |> Choreo.add_cache(:cache, kind: :redis)
      iex> Choreo.nodes(system)[:cache].type
      :cache

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=TB, splines=spline, nodesep=0.6, ranksep=1.2];
      node [shape=ellipse, style=filled, fillcolor="lightblue", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];
      cache [label="Redis", style="filled", fontcolor="white", fillcolor="#f59e0b", shape="octagon"];
    }
  </div>
  """
  @spec add_cache(t(), Yog.node_id(), keyword()) :: t()
  def add_cache(system, id, opts \\ []) do
    add_typed_node(system, id, :cache, opts)
  end

  @doc """
  Adds a service / application node to the system.

  ## Options

  #{NimbleOptions.docs(@add_typed_node_schema)}

  ## Examples

      iex> system = Choreo.new() |> Choreo.add_service(:api, name: "Gateway")
      iex> Choreo.nodes(system)[:api].type
      :service
      iex> Choreo.nodes(system)[:api].name
      "Gateway"

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=TB, splines=spline, nodesep=0.6, ranksep=1.2];
      node [shape=ellipse, style=filled, fillcolor="lightblue", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];
      auth [label="auth", style="filled", fontcolor="white", fillcolor="#10b981", shape="box3d"];
    }
  </div>
  """
  @spec add_service(t(), Yog.node_id(), keyword()) :: t()
  def add_service(system, id, opts \\ []) do
    add_typed_node(system, id, :service, opts)
  end

  @doc """
  Adds a network / infrastructure boundary node.

  ## Options

  #{NimbleOptions.docs(@add_typed_node_schema)}

  ## Examples

      iex> system = Choreo.new() |> Choreo.add_network(:vpc)
      iex> Choreo.nodes(system)[:vpc].type
      :network

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=TB, splines=spline, nodesep=0.6, ranksep=1.2];
      node [shape=ellipse, style=filled, fillcolor="lightblue", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];

      cloudflare [label="cloudflare", style="filled", fontcolor="white", fillcolor="#6366f1", shape="cloud"];
    }
  </div>
  """
  @spec add_network(t(), Yog.node_id(), keyword()) :: t()
  def add_network(system, id, opts \\ []) do
    add_typed_node(system, id, :network, opts)
  end

  @doc """
  Adds a user / external actor node to the system.

  ## Options

  #{NimbleOptions.docs(@add_typed_node_schema)}

  ## Examples

      iex> system = Choreo.new() |> Choreo.add_user(:client)
      iex> Choreo.nodes(system)[:client].type
      :user

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=TB, splines=spline, nodesep=0.6, ranksep=1.2];
      node [shape=ellipse, style=filled, fillcolor="lightblue", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];
      user [label="user", style="filled", fontcolor="white", fillcolor="#ef4444", shape="doublecircle"];
    }
  </div>
  """
  @spec add_user(t(), Yog.node_id(), keyword()) :: t()
  def add_user(system, id, opts \\ []) do
    add_typed_node(system, id, :user, opts)
  end

  @doc """
  Adds a load-balancer node to the system.

  ## Options

  #{NimbleOptions.docs(@add_typed_node_schema)}

  ## Examples

      iex> system = Choreo.new() |> Choreo.add_load_balancer(:lb)
      iex> Choreo.nodes(system)[:lb].type
      :load_balancer

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=TB, splines=spline, nodesep=0.6, ranksep=1.2];
      node [shape=ellipse, style=filled, fillcolor="lightblue", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];
      lb [label="lb", style="filled", fontcolor="white", fillcolor="#8b5cf6", shape="hexagon"];
    }
  </div>
  """
  @spec add_load_balancer(t(), Yog.node_id(), keyword()) :: t()
  def add_load_balancer(system, id, opts \\ []) do
    add_typed_node(system, id, :load_balancer, opts)
  end

  @doc """
  Adds a queue / messaging node to the system.

  ## Options

  #{NimbleOptions.docs(@add_typed_node_schema)}

  ## Examples

      iex> system = Choreo.new() |> Choreo.add_queue(:q, kind: :kafka)
      iex> Choreo.nodes(system)[:q].type
      :queue

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=TB, splines=spline, nodesep=0.6, ranksep=1.2];
      node [shape=ellipse, style=filled, fillcolor="lightblue", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];

      queue [label="queue", style="filled", fontcolor="white", fillcolor="#ec4899", shape="component"];
    }
  </div>
  """
  @spec add_queue(t(), Yog.node_id(), keyword()) :: t()
  def add_queue(system, id, opts \\ []) do
    add_typed_node(system, id, :queue, opts)
  end

  @doc """
  Adds a storage / blob node to the system.

  ## Options

  #{NimbleOptions.docs(@add_typed_node_schema)}

  ## Examples

      iex> system = Choreo.new() |> Choreo.add_storage(:s3)
      iex> Choreo.nodes(system)[:s3].type
      :storage

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=TB, splines=spline, nodesep=0.6, ranksep=1.2];
      node [shape=ellipse, style=filled, fillcolor="lightblue", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];
      storage [label="storage", style="filled", fontcolor="white", fillcolor="#14b8a6", shape="tab"];
    }
  </div>
  """
  @spec add_storage(t(), Yog.node_id(), keyword()) :: t()
  def add_storage(system, id, opts \\ []) do
    add_typed_node(system, id, :storage, opts)
  end

  @doc """
  Adds a generic node to the system.

  Use this when none of the typed builders fit.

  ## Examples

      iex> system = Choreo.new() |> Choreo.add_node(:misc, name: "Custom")
      iex> Choreo.nodes(system)[:misc].type
      :generic
      iex> Choreo.nodes(system)[:misc].name
      "Custom"
  """
  @spec add_node(t(), Yog.node_id(), keyword()) :: t()
  def add_node(system, id, opts \\ []) do
    add_typed_node(system, id, :generic, opts)
  end

  @doc """
  Defines a cluster (subgraph) for grouping nodes visually.

  ## Options

  #{NimbleOptions.docs(@add_cluster_schema)}

  ## Examples

      iex> system = Choreo.new() |> Choreo.add_cluster("vpc", label: "VPC")
      iex> Map.keys(Choreo.clusters(system))
      ["cluster_vpc"]
  """
  @spec add_cluster(t(), String.t(), keyword()) :: t()
  def add_cluster(%__MODULE__{} = system, name, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @add_cluster_schema)
    name = Choreo.Internal.ensure_cluster_prefix(name)
    cluster = Map.new(opts)
    clusters = Map.put(system.clusters, name, cluster)
    %{system | clusters: clusters}
  end

  @doc """
  Embeds another diagram inside a cluster of the current system.

  ## Options

  #{NimbleOptions.docs(@embed_schema)}

  ## Examples

      iex> system = Choreo.new() |> Choreo.add_cluster("vpc")
      iex> flow = Choreo.Dataflow.new() |> Choreo.Dataflow.add_source(:in)
      iex> system = Choreo.embed(system, flow, "vpc", prefix: "flow_")
      iex> Map.has_key?(Choreo.nodes(system), :flow_in)
      true
  """
  @spec embed(t(), struct(), String.t(), keyword()) :: t()
  def embed(%__MODULE__{} = system, child_diagram, cluster_name, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @embed_schema)
    prefix = to_string(opts[:prefix])
    cluster_prefix = prefix

    # 1. Reassign inner clusters
    child_clusters = Map.get(child_diagram, :clusters, %{})

    updated_clusters =
      Enum.reduce(child_clusters, system.clusters, fn {c_name, c_meta}, acc ->
        clean_name = String.replace(c_name, "cluster_", "")
        new_name = Choreo.Internal.ensure_cluster_prefix(cluster_prefix <> clean_name)

        new_meta =
          if parent = c_meta[:parent] do
            clean_parent = String.replace(parent, "cluster_", "")

            Map.put(
              c_meta,
              :parent,
              Choreo.Internal.ensure_cluster_prefix(cluster_prefix <> clean_parent)
            )
          else
            Map.put(c_meta, :parent, Choreo.Internal.ensure_cluster_prefix(cluster_name))
          end

        Map.put(acc, new_name, new_meta)
      end)

    # 2. Extract nodes
    child_nodes = get_in(child_diagram, [Access.key(:graph), Access.key(:nodes)]) || %{}

    updated_graph =
      Enum.reduce(child_nodes, system.graph, fn {node_id, node_data}, acc_graph ->
        prefixed_id = :"#{prefix}#{node_id}"

        node_cluster =
          if c = node_data[:cluster] do
            clean_c = String.replace(c, "cluster_", "")
            Choreo.Internal.ensure_cluster_prefix(cluster_prefix <> clean_c)
          else
            Choreo.Internal.ensure_cluster_prefix(cluster_name)
          end

        node_name = node_data[:name] || node_data[:label] || to_string(node_id)

        new_data =
          node_data
          |> Map.put(:cluster, node_cluster)
          |> Map.put(:name, node_name)

        Yog.Multi.add_node(acc_graph, prefixed_id, new_data)
      end)

    # 3. Extract edges
    child_edge_meta = Map.get(child_diagram, :edge_meta, %{})

    updated_state =
      case Map.keys(child_edge_meta) do
        [{_, _} | _] ->
          # Simple graph edges
          edges_list = Yog.all_edges(child_diagram.graph)

          Enum.reduce(edges_list, {updated_graph, system.edge_meta}, fn {from, to, weight},
                                                                        {g_acc, m_acc} ->
            meta = Map.get(child_edge_meta, {from, to}, %{})
            new_from = :"#{prefix}#{from}"
            new_to = :"#{prefix}#{to}"

            {g_acc, edge_id} = Yog.Multi.add_edge(g_acc, new_from, new_to, weight)
            m_acc = Map.put(m_acc, edge_id, meta)
            {g_acc, m_acc}
          end)

        _ ->
          # Multigraph parallel edges
          child_edges = get_in(child_diagram, [Access.key(:graph), Access.key(:edges)]) || %{}

          Enum.reduce(child_edge_meta, {updated_graph, system.edge_meta}, fn {edge_id, meta},
                                                                             {g_acc, m_acc} ->
            case Map.get(child_edges, edge_id) do
              {from, to, weight} ->
                new_from = :"#{prefix}#{from}"
                new_to = :"#{prefix}#{to}"

                {g_acc, new_edge_id} = Yog.Multi.add_edge(g_acc, new_from, new_to, weight)
                m_acc = Map.put(m_acc, new_edge_id, meta)
                {g_acc, m_acc}

              _ ->
                {g_acc, m_acc}
            end
          end)
      end

    {final_graph, final_edge_meta} = updated_state
    %{system | graph: final_graph, edge_meta: final_edge_meta, clusters: updated_clusters}
  end

  defp add_typed_node(%__MODULE__{graph: graph} = system, id, type, opts) do
    schema = if type == :generic, do: @node_schema, else: @add_typed_node_schema
    opts = NimbleOptions.validate!(opts, schema)
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

    %{system | graph: Yog.Multi.add_node(graph, id, data)}
  end

  # ============================================================================
  # Edge builders
  # ============================================================================

  @doc """
  Connects two nodes with a weighted edge.

  ## Options

  #{NimbleOptions.docs(@connect_schema)}

  ## Examples

      iex> system = Choreo.new() |> Choreo.add_service(:a) |> Choreo.add_service(:b) |> Choreo.connect(:a, :b, cost: 5)
      iex> Choreo.edges(system)
      [{:a, :b, 5}]

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
  """
  @spec connect(t(), Yog.node_id(), Yog.node_id(), keyword()) :: t()
  def connect(%__MODULE__{} = system, from, to, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @connect_schema)
    cost = opts[:cost]

    meta =
      opts
      |> Map.new()
      |> Map.put_new(:label, nil)

    {graph, edge_id} = Yog.Multi.add_edge(system.graph, from, to, cost)
    edge_meta = Map.put(system.edge_meta, edge_id, meta)

    %{system | graph: graph, edge_meta: edge_meta}
  end

  @doc """
  Adds a data-flow edge between two nodes.

  This is semantically identical to `connect/4` but renders with a
  different default style (dashed, data-flow colour).

  ## Examples

      iex> system = Choreo.new() |> Choreo.add_service(:a) |> Choreo.add_service(:b) |> Choreo.add_dataflow(:a, :b)
      iex> [{:a, :b, 1, meta}] = Choreo.edges_with_meta(system)
      iex> meta.type
      :dataflow
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

  ## Examples

      iex> system = Choreo.new() |> Choreo.add_service(:api)
      iex> Map.keys(Choreo.nodes(system))
      [:api]
  """
  @spec nodes(t()) :: %{Yog.node_id() => map()}
  def nodes(%__MODULE__{graph: graph}) do
    graph.nodes
  end

  @doc """
  Returns all edges in the system as a list of `{from, to, cost}` tuples.

  ## Examples

      iex> system = Choreo.new() |> Choreo.add_service(:a) |> Choreo.add_service(:b) |> Choreo.connect(:a, :b)
      iex> Choreo.edges(system)
      [{:a, :b, 1}]
  """
  @spec edges(t()) :: [{Yog.node_id(), Yog.node_id(), number()}]
  def edges(%__MODULE__{graph: graph}) do
    Enum.map(graph.edges, fn {_edge_id, {from, to, weight}} ->
      {from, to, weight}
    end)
  end

  @doc """
  Returns all edges with their metadata as `{from, to, cost, meta}` tuples.

  ## Examples

      iex> system = Choreo.new() |> Choreo.add_service(:a) |> Choreo.add_service(:b) |> Choreo.connect(:a, :b, protocol: :http)
      iex> [{:a, :b, 1, meta}] = Choreo.edges_with_meta(system)
      iex> meta.protocol
      :http
  """
  @spec edges_with_meta(t()) :: [{Yog.node_id(), Yog.node_id(), number(), map()}]
  def edges_with_meta(%__MODULE__{graph: graph, edge_meta: edge_meta}) do
    Enum.map(graph.edges, fn {edge_id, {from, to, weight}} ->
      {from, to, weight, Map.get(edge_meta, edge_id, %{})}
    end)
  end

  @doc """
  Collapses parallel edges into a simple `Yog.Graph` for algorithm analysis.

  ## Options

    * `:combine` - function to combine weights of parallel edges
      (default: `&min/2`)

  ## Examples

      iex> system = Choreo.new() |> Choreo.add_service(:a) |> Choreo.add_service(:b)
      ...> |> Choreo.connect(:a, :b, cost: 10) |> Choreo.connect(:a, :b, cost: 5)
      iex> simple = Choreo.to_simple_graph(system)
      iex> Yog.all_edges(simple)
      [{:a, :b, 5}]
  """
  @spec to_simple_graph(t(), keyword()) :: Yog.Graph.t()
  def to_simple_graph(%__MODULE__{graph: graph}, opts \\ []) do
    combine = Keyword.get(opts, :combine, &min/2)
    Yog.Multi.to_simple_graph(graph, combine)
  end

  @doc """
  Returns the raw `Yog.Multi.Graph` struct underpinning the system.

  Useful when you want to drop down to the raw Yog Multi API.

  ## Examples

      iex> system = Choreo.new()
      iex> Choreo.to_graph(system) == system.graph
      true
  """
  @spec to_graph(t()) :: Yog.Multi.Graph.t()
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

      iex> system = Choreo.new() |> Choreo.add_service(:api)
      iex> dot = Choreo.to_dot(system)
      iex> String.contains?(dot, "digraph")
      true
      iex> String.contains?(dot, "api")
      true
  """
  @spec to_dot(any(), keyword()) :: String.t()
  def to_dot(diagram, opts \\ []) do
    Choreo.DOT.to_dot(diagram, opts)
  end

  @doc """
  Returns all cluster definitions in the system.

  ## Examples

      iex> system = Choreo.new() |> Choreo.add_cluster("vpc", label: "VPC")
      iex> Choreo.clusters(system)
      %{"cluster_vpc" => %{label: "VPC"}}
  """
  @spec clusters(t()) :: %{String.t() => map()}
  def clusters(%__MODULE__{clusters: clusters}), do: clusters
end

defimpl Choreo.DOT, for: Choreo do
  def to_dot(system, opts), do: Choreo.Render.DOT.to_dot(system, opts)
end
