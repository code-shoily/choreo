defmodule Choreo do
  @moduledoc """
  A domain-specific layer on top of Yog for modeling system architectures.

  Choreo lets you define infrastructure diagrams (databases, caches,
  services, networks, etc.) as graphs and render them to DOT format or
  Mermaid.js syntax with system-diagram theming. You can also run graph
  algorithms such as MST and topological sort to analyze your architecture.

  ## When to use

  Use `Choreo` when you need to document, communicate, or analyze the
  infrastructure of a system — whether for architecture review, onboarding
  docs, cost optimisation, or resilience planning.

  ## Quick Start

      system =
        Choreo.new()
        |> Choreo.add_database(:db, label: "Postgres", kind: :postgres)
        |> Choreo.add_cache(:cache, label: "Redis", kind: :redis)
        |> Choreo.add_service(:api, label: "API Gateway")
        |> Choreo.connect(:api, :cache, cost: 5)
        |> Choreo.connect(:api, :db, cost: 10)

      dot = Choreo.to_dot(system)
      mermaid = Choreo.to_mermaid(system)

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
  require Logger

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
    label: [
      type: :string,
      required: false,
      doc: "Display label (defaults to the node id)."
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
    ],
    image: [
      type: :string,
      required: false,
      doc: "Image/icon path or URL override."
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
    cluster_type: [
      type: :atom,
      required: false,
      doc: "Semantic cluster type (e.g. `:vpc`, `:subnet_public`, `:subnet_private`)."
    ],
    style: [
      type: {:or, [:string, :atom]},
      required: false,
      doc: "Visual style (e.g. :filled, :rounded)."
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
    ],
    strict: [
      type: :boolean,
      required: false,
      default: false,
      doc: "Whether to raise an error if the source or target node does not exist."
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

  @trace_schema [
    type: [
      type: :atom,
      required: false,
      default: :executes,
      doc: "Semantic trace type (e.g. :executes, :stores, :implements)."
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
      iex> Choreo.nodes(system)[:db].node_type
      :database
      iex> Choreo.nodes(system)[:db].kind
      :postgres
      iex> Choreo.nodes(system)[:db].label
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
      iex> Choreo.nodes(system)[:cache].node_type
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

      iex> system = Choreo.new() |> Choreo.add_service(:api, label: "Gateway")
      iex> Choreo.nodes(system)[:api].node_type
      :service
      iex> Choreo.nodes(system)[:api].label
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
      iex> Choreo.nodes(system)[:vpc].node_type
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
      iex> Choreo.nodes(system)[:client].node_type
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
      iex> Choreo.nodes(system)[:lb].node_type
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
      iex> Choreo.nodes(system)[:q].node_type
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
      iex> Choreo.nodes(system)[:s3].node_type
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
  Adds an internet gateway or public internet entrypoint node.

  ## Options

  #{NimbleOptions.docs(@add_typed_node_schema)}

  ## Examples

      iex> system = Choreo.new() |> Choreo.add_internet(:gw)
      iex> Choreo.nodes(system)[:gw].node_type
      :internet
  """
  @spec add_internet(t(), Yog.node_id(), keyword()) :: t()
  def add_internet(system, id, opts \\ []) do
    add_typed_node(system, id, :internet, opts)
  end

  @doc """
  Adds a compute workload runner node (EC2, ECS task, Kubernetes pod).

  ## Options

  #{NimbleOptions.docs(@add_typed_node_schema)}

  ## Examples

      iex> system = Choreo.new() |> Choreo.add_compute(:app)
      iex> Choreo.nodes(system)[:app].node_type
      :compute
  """
  @spec add_compute(t(), Yog.node_id(), keyword()) :: t()
  def add_compute(system, id, opts \\ []) do
    add_typed_node(system, id, :compute, opts)
  end

  @doc """
  Adds a managed database node (RDS, Aurora, Cloud SQL).

  ## Options

  #{NimbleOptions.docs(@add_typed_node_schema)}

  ## Examples

      iex> system = Choreo.new() |> Choreo.add_managed_db(:db)
      iex> Choreo.nodes(system)[:db].node_type
      :managed_db
  """
  @spec add_managed_db(t(), Yog.node_id(), keyword()) :: t()
  def add_managed_db(system, id, opts \\ []) do
    add_typed_node(system, id, :managed_db, opts)
  end

  @doc """
  Adds a generic node to the system.

  Use this when none of the typed builders fit.

  ## Examples

      iex> system = Choreo.new() |> Choreo.add_node(:misc, label: "Custom")
      iex> Choreo.nodes(system)[:misc].node_type
      :generic
      iex> Choreo.nodes(system)[:misc].label
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
  Adds a VPC cluster network boundary.

  ## Options

  #{NimbleOptions.docs(@add_cluster_schema)}
  """
  @spec add_vpc(t(), String.t(), keyword()) :: t()
  def add_vpc(system, name, opts \\ []) do
    add_typed_cluster(system, name, :vpc, opts)
  end

  @doc """
  Adds a public subnet cluster boundary.

  ## Options

  #{NimbleOptions.docs(@add_cluster_schema)}
  """
  @spec add_subnet_public(t(), String.t(), keyword()) :: t()
  def add_subnet_public(system, name, opts \\ []) do
    add_typed_cluster(system, name, :subnet_public, opts)
  end

  @doc """
  Adds a private subnet cluster boundary.

  ## Options

  #{NimbleOptions.docs(@add_cluster_schema)}
  """
  @spec add_subnet_private(t(), String.t(), keyword()) :: t()
  def add_subnet_private(system, name, opts \\ []) do
    add_typed_cluster(system, name, :subnet_private, opts)
  end

  defp add_typed_cluster(%__MODULE__{} = system, name, type, opts) do
    opts = NimbleOptions.validate!(opts, @add_cluster_schema)
    name = Choreo.Internal.ensure_cluster_prefix(name)

    cluster =
      opts
      |> Map.new()
      |> Map.put(:cluster_type, type)
      |> Map.put_new(:label, name)

    cluster =
      if parent = cluster[:parent] do
        Map.put(cluster, :parent, Choreo.Internal.ensure_cluster_prefix(parent))
      else
        cluster
      end

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
        clean_name = String.replace_prefix(to_string(c_name), "cluster_", "")
        new_name = Choreo.Internal.ensure_cluster_prefix(cluster_prefix <> clean_name)

        new_meta =
          if parent = c_meta[:parent] do
            clean_parent = String.replace_prefix(to_string(parent), "cluster_", "")

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
            clean_c = String.replace_prefix(to_string(c), "cluster_", "")
            Choreo.Internal.ensure_cluster_prefix(cluster_prefix <> clean_c)
          else
            Choreo.Internal.ensure_cluster_prefix(cluster_name)
          end

        node_name = node_data[:label] || to_string(node_id)

        new_data =
          node_data
          |> Map.put(:cluster, node_cluster)
          |> Map.put(:name, node_name)

        Yog.Multi.add_node(acc_graph, prefixed_id, new_data)
      end)

    # 3. Extract edges
    child_edge_meta = Map.get(child_diagram, :edge_meta, %{})
    is_multigraph = match?(%Yog.Multi.Graph{}, child_diagram.graph)

    updated_state =
      if is_multigraph do
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
      else
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
      end

    {final_graph, final_edge_meta} = updated_state
    %{system | graph: final_graph, edge_meta: final_edge_meta, clusters: updated_clusters}
  end

  @doc """
  Declares a semantic trace (cross-diagram link) between two nodes in a composed system.

  Trace links are kept separate from the visual layout by default and are only shown
  when `:show_traces` is set to `true`.

  ## Options

  #{NimbleOptions.docs(@trace_schema)}

  ## Examples

      iex> system = Choreo.new() |> Choreo.add_service(:api) |> Choreo.add_database(:db)
      iex> system = Choreo.trace(system, :api, :db, type: :stores)
      iex> [{:api, :db, 1, meta}] = Choreo.edges_with_meta(system)
      iex> meta.edge_type
      :trace
  """
  @spec trace(t(), Yog.node_id(), Yog.node_id(), keyword()) :: t()
  def trace(%__MODULE__{} = system, from, to, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @trace_schema)
    type = opts[:type]

    system =
      if Map.has_key?(system.graph.nodes, from) do
        system
      else
        add_node(system, from, label: to_string(from))
      end

    system =
      if Map.has_key?(system.graph.nodes, to) do
        system
      else
        add_node(system, to, label: to_string(to))
      end

    meta = %{
      edge_type: :trace,
      type: type,
      label: to_string(type)
    }

    {graph, edge_id} = Yog.Multi.add_edge(system.graph, from, to, 1)
    edge_meta = Map.put(system.edge_meta, edge_id, meta)

    %{system | graph: graph, edge_meta: edge_meta}
  end

  defp add_typed_node(%__MODULE__{graph: graph} = system, id, type, opts) do
    schema = if type == :generic, do: @node_schema, else: @add_typed_node_schema
    opts = NimbleOptions.validate!(opts, schema)
    {cluster, rest_opts} = Keyword.pop(opts, :cluster)

    data =
      rest_opts
      |> Map.new()
      |> Map.put(:node_type, type)
      |> Map.put_new(:label, to_string(id))

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
    strict = opts[:strict]

    if strict do
      if not Map.has_key?(system.graph.nodes, from) do
        raise ArgumentError, "source node #{inspect(from)} does not exist in strict mode"
      end

      if not Map.has_key?(system.graph.nodes, to) do
        raise ArgumentError, "target node #{inspect(to)} does not exist in strict mode"
      end
    else
      if not Map.has_key?(system.graph.nodes, from) and not Map.has_key?(system.graph.nodes, to) do
        Logger.warning(
          "Both endpoints #{inspect(from)} and #{inspect(to)} do not exist and will be auto-created"
        )
      end
    end

    system =
      if Map.has_key?(system.graph.nodes, from) do
        system
      else
        add_node(system, from, label: to_string(from))
      end

    system =
      if Map.has_key?(system.graph.nodes, to) do
        system
      else
        add_node(system, to, label: to_string(to))
      end

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

    * `:theme` - `:default`, `:dark`, `:minimal`, `:warm`, `:forest`, or `:ocean`
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
  Renders the system diagram to Mermaid.js syntax.

  ## Options

    * `:syntax` - `:flowchart` (default) or `:architecture` (native
      `architecture-beta` diagram type)
    * `:theme` - `:default`, `:dark`, `:minimal`, `:warm`, `:forest`, or `:ocean`
    * `:direction` - `:td`, `:lr`, `:bt`, or `:rl`
    * Any option accepted by `Yog.Multi.Mermaid.to_mermaid/2`

  ## Examples

      iex> system = Choreo.new() |> Choreo.add_service(:api)
      iex> mermaid = Choreo.to_mermaid(system)
      iex> String.contains?(mermaid, "graph TD")
      true
      iex> String.contains?(mermaid, "api")
      true

      iex> system = Choreo.new() |> Choreo.add_service(:api)
      iex> mermaid = Choreo.to_mermaid(system, syntax: :architecture)
      iex> String.contains?(mermaid, "architecture-beta")
      true
      iex> String.contains?(mermaid, "api")
      true
  """
  @spec to_mermaid(any(), keyword()) :: String.t()
  def to_mermaid(diagram, opts \\ []) do
    Choreo.Mermaid.to_mermaid(diagram, opts)
  end

  @doc """
  Returns a theme for `Choreo` infrastructure diagrams.

  ## Examples

      iex> theme = Choreo.theme(:default, graph_rankdir: :lr)
      iex> theme.graph_rankdir
      :lr
  """
  @spec theme(atom(), keyword()) :: Choreo.Theme.t()
  def theme(name \\ :default, overrides \\ []) do
    Choreo.Render.DOT.theme(name, overrides)
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

defimpl Choreo.Viewable, for: Choreo do
  def rebuild(system, new_graph) do
    new_edge_meta = Map.take(system.edge_meta, Map.keys(new_graph.edges))

    existing_ids = MapSet.new(Map.keys(new_edge_meta))

    new_edge_meta =
      Enum.reduce(Map.keys(new_graph.edges), new_edge_meta, fn eid, acc ->
        if MapSet.member?(existing_ids, eid) do
          acc
        else
          Map.put(acc, eid, virtual_edge_meta(system))
        end
      end)

    %{system | graph: new_graph, edge_meta: new_edge_meta}
  end

  # Maps zoom tier → the node types visible at that level.
  # Each tier is a superset of the previous; tier 0 is the most zoomed-out.
  # When a new add_* builder introduces a type, add it here — one place only.
  @zoom_tiers %{
    0 => [:service],
    1 => [:service, :database, :cache, :queue, :storage],
    2 => [:service, :database, :cache, :queue, :storage, :load_balancer, :network]
  }

  def zoom_predicate(_, level) when is_map_key(@zoom_tiers, level) do
    types = @zoom_tiers[level]
    fn _, d -> d[:node_type] in types end
  end

  def zoom_predicate(_, _), do: fn _, _ -> true end

  def virtual_edge_meta(_), do: %{edge_type: :virtual, type: :connection, label: nil}
end

defimpl Choreo.DOT, for: Choreo do
  def to_dot(system, opts), do: Choreo.Render.DOT.to_dot(system, opts)
end

defimpl Choreo.Mermaid, for: Choreo do
  def to_mermaid(system, opts), do: Choreo.Render.Mermaid.to_mermaid(system, opts)
end
