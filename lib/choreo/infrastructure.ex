defmodule Choreo.Infrastructure do
  @moduledoc """
  Cloud network and infrastructure topology preset built on top of Choreo's rendering primitives.

  `Choreo.Infrastructure` is a **domain-specific vocabulary layer** that adds cloud-network
  concepts — VPCs, subnets, compute, load balancers, managed databases, storage — on top of
  the same graph, cluster, and rendering stack used by `Choreo`. It is *not* a parallel
  implementation: it shares `Choreo.Theme`, `Choreo.Internal`, and the `Yog` rendering pipeline
  directly.

  The key additions over plain `Choreo` are:

    * **Typed cluster boundaries** — `:vpc`, `:subnet_public`, `:subnet_private` carry security
      semantics (e.g. databases should not be in public subnets) that generic clusters do not.
    * **`Choreo.Infrastructure.Analysis`** — structural audit rules that inspect topology against
      those security semantics (direct internet-to-private-subnet links, misplaced databases, etc.).
    * **Network vocabulary** — `add_vpc/3`, `add_compute/3`, `add_managed_db/3` etc. as
      intent-revealing builders instead of the generic `add_cluster/3` / `add_service/3`.

  Node colors and shapes are resolved through `Choreo.Theme` (`:internet`, `:compute`, and
  `:managed_db` are first-class theme types), so the full theme system — including `:dark`,
  `:warm`, `:forest`, `:ocean` — applies to infrastructure diagrams without any extra
  configuration.

  ## Element types

    * `:internet` — public gateway or client zone
    * `:load_balancer` — traffic proxy (e.g. ALB, ingress)
    * `:compute` — application runner (EC2, ECS task, Kubernetes pod)
    * `:managed_db` — stateful database (RDS, Aurora)
    * `:storage` — blob/file storage (S3, EFS)

  ## Network boundaries (Clusters)

    * `:vpc` — Virtual Private Cloud container
    * `:subnet_public` — Public subnet zone (internet-facing)
    * `:subnet_private` — Private subnet zone (isolated)

  ## Quick Start

      infra =
        Choreo.Infrastructure.new()
        |> Choreo.Infrastructure.add_internet(:gateway, label: "Internet Gateway")
        |> Choreo.Infrastructure.add_vpc("vpc_main", label: "Production VPC")
        |> Choreo.Infrastructure.add_subnet_public("subnet_dmz", label: "Public Subnet", parent: "vpc_main")
        |> Choreo.Infrastructure.add_subnet_private("subnet_app", label: "Private Subnet", parent: "vpc_main")
        |> Choreo.Infrastructure.add_load_balancer(:alb, label: "ALB", cluster: "subnet_dmz")
        |> Choreo.Infrastructure.add_compute(:api, label: "API Service", cluster: "subnet_app")
        |> Choreo.Infrastructure.add_managed_db(:db, label: "Postgres RDS", cluster: "subnet_app")
        |> Choreo.Infrastructure.connect(:gateway, :alb)
        |> Choreo.Infrastructure.connect(:alb, :api)
        |> Choreo.Infrastructure.connect(:api, :db)

      # Check for architecture warning violations
      warnings = Choreo.Infrastructure.Analysis.warnings(infra)

      dot = Choreo.Infrastructure.to_dot(infra)
      mermaid = Choreo.Infrastructure.to_mermaid(infra)
  """

  @type t :: %__MODULE__{
          graph: Yog.Multi.Graph.t(),
          edge_meta: %{optional(Yog.Multi.Graph.edge_id()) => map()},
          clusters: %{String.t() => map()}
        }

  defstruct graph: nil, edge_meta: %{}, clusters: %{}

  @node_schema [
    label: [
      type: :string,
      required: false,
      doc: "Display label for the node."
    ],
    description: [
      type: :string,
      required: false,
      doc: "Tooltip / details description."
    ],
    cluster: [
      type: :string,
      required: false,
      doc: "VPC or Subnet cluster name where the node belongs."
    ],
    shape: [
      type: :atom,
      required: false,
      doc: "Shape override."
    ],
    fillcolor: [
      type: :string,
      required: false,
      doc: "Fillcolor override."
    ],
    fontcolor: [
      type: :string,
      required: false,
      doc: "Fontcolor override."
    ],
    style: [
      type: :string,
      required: false,
      doc: "Style override."
    ],
    penwidth: [
      type: {:or, [:integer, :float]},
      required: false,
      doc: "Border thickness override."
    ],
    image: [
      type: :string,
      required: false,
      doc: "Image URL or path override."
    ]
  ]

  @cluster_schema [
    parent: [
      type: :string,
      required: false,
      doc: "Parent cluster name (e.g., nesting subnets inside a VPC)."
    ],
    label: [
      type: :string,
      required: false,
      doc: "Display label for the cluster boundary."
    ],
    style: [
      type: :string,
      required: false,
      doc: "Cluster outline style."
    ],
    fillcolor: [
      type: :string,
      required: false,
      doc: "Cluster background fillcolor override."
    ],
    color: [
      type: :string,
      required: false,
      doc: "Cluster border outline color override."
    ]
  ]

  @connect_schema [
    cost: [
      type: {:or, [:integer, :float]},
      required: false,
      default: 1,
      doc: "Weight/metric value."
    ],
    label: [
      type: :string,
      required: false,
      doc: "Edge connection label."
    ],
    protocol: [
      type: {:or, [:atom, :string]},
      required: false,
      doc: "Network protocol (e.g., :https, :tcp)."
    ],
    type: [
      type: :atom,
      required: false,
      doc: "Connection type."
    ]
  ]

  # ============================================================================
  # Creation
  # ============================================================================

  @doc """
  Creates a new empty cloud infrastructure diagram.
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
  # Network Boundaries (Clusters)
  # ============================================================================

  @doc """
  Adds a VPC cluster network boundary.
  """
  @spec add_vpc(t(), String.t(), keyword()) :: t()
  def add_vpc(infra, name, opts \\ []) do
    add_typed_cluster(infra, name, :vpc, opts)
  end

  @doc """
  Adds a public subnet cluster boundary.
  """
  @spec add_subnet_public(t(), String.t(), keyword()) :: t()
  def add_subnet_public(infra, name, opts \\ []) do
    add_typed_cluster(infra, name, :subnet_public, opts)
  end

  @doc """
  Adds a private subnet cluster boundary.
  """
  @spec add_subnet_private(t(), String.t(), keyword()) :: t()
  def add_subnet_private(infra, name, opts \\ []) do
    add_typed_cluster(infra, name, :subnet_private, opts)
  end

  # ============================================================================
  # Compute & Stateful Nodes
  # ============================================================================

  @doc """
  Adds an internet gateway or public internet entrypoint node.
  """
  @spec add_internet(t(), Yog.node_id(), keyword()) :: t()
  def add_internet(infra, id, opts \\ []) do
    add_typed_node(infra, id, :internet, opts)
  end

  @doc """
  Adds a load balancer proxy node (ALB, Ingress Controller).
  """
  @spec add_load_balancer(t(), Yog.node_id(), keyword()) :: t()
  def add_load_balancer(infra, id, opts \\ []) do
    add_typed_node(infra, id, :load_balancer, opts)
  end

  @doc """
  Adds a compute workload runner node (EC2, ECS task, Kubernetes pod).
  """
  @spec add_compute(t(), Yog.node_id(), keyword()) :: t()
  def add_compute(infra, id, opts \\ []) do
    add_typed_node(infra, id, :compute, opts)
  end

  @doc """
  Adds a managed database node (RDS, Aurora, DynamoDB).
  """
  @spec add_managed_db(t(), Yog.node_id(), keyword()) :: t()
  def add_managed_db(infra, id, opts \\ []) do
    add_typed_node(infra, id, :managed_db, opts)
  end

  @doc """
  Adds a storage bucket or block storage node (S3, EFS).
  """
  @spec add_storage(t(), Yog.node_id(), keyword()) :: t()
  def add_storage(infra, id, opts \\ []) do
    add_typed_node(infra, id, :storage, opts)
  end

  # ============================================================================
  # Node Connections
  # ============================================================================

  @doc """
  Connects two infrastructure nodes together.
  """
  @spec connect(t(), Yog.node_id(), Yog.node_id(), keyword()) :: t()
  def connect(%__MODULE__{} = infra, from, to, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @connect_schema)
    cost = opts[:cost]

    unless Map.has_key?(infra.graph.nodes, from) do
      raise ArgumentError, "Node #{inspect(from)} does not exist in infrastructure diagram"
    end

    unless Map.has_key?(infra.graph.nodes, to) do
      raise ArgumentError, "Node #{inspect(to)} does not exist in infrastructure diagram"
    end

    meta = Map.new(opts)
    {graph, edge_id} = Yog.Multi.add_edge(infra.graph, from, to, cost)
    edge_meta = Map.put(infra.edge_meta, edge_id, meta)

    %{infra | graph: graph, edge_meta: edge_meta}
  end

  # ============================================================================
  # Queries
  # ============================================================================

  @doc """
  Returns all node IDs.
  """
  @spec nodes(t()) :: [Yog.node_id()]
  def nodes(%__MODULE__{graph: graph}) do
    Map.keys(graph.nodes)
  end

  @doc """
  Returns all edges.
  """
  @spec edges(t()) :: [{Yog.node_id(), Yog.node_id(), any()}]
  def edges(%__MODULE__{graph: graph}) do
    Enum.map(graph.edges, fn {_edge_id, {from, to, weight}} ->
      {from, to, weight}
    end)
  end

  # ============================================================================
  # Render wrappers
  # ============================================================================

  @doc """
  Renders the infrastructure topology to DOT format.

  ## Options

    * `:theme` — `:default`, `:dark`, `:warm`, `:forest`, `:ocean`, or a `Choreo.Theme` struct
    * `:highlighted_nodes` — list of node IDs to highlight
    * `:highlighted_edges` — list of edge IDs or `{from, to}` tuples to highlight
  """
  @spec to_dot(t(), keyword()) :: String.t()
  def to_dot(%__MODULE__{} = infra, opts \\ []) do
    Choreo.to_dot(to_choreo(infra), opts)
  end

  @doc """
  Renders the infrastructure topology to Mermaid.js syntax.

  ## Options

    * `:theme` — `:default`, `:dark`, `:warm`, `:forest`, `:ocean`, or a `Choreo.Theme` struct
    * `:direction` — `:td` (default), `:lr`, `:rl`, `:bt`
    * `:highlighted_nodes` — list of node IDs to highlight
    * `:highlighted_edges` — list of edge IDs or `{from, to}` tuples to highlight
  """
  @spec to_mermaid(t(), keyword()) :: String.t()
  def to_mermaid(%__MODULE__{} = infra, opts \\ []) do
    Choreo.to_mermaid(to_choreo(infra), opts)
  end

  def to_choreo(%__MODULE__{} = infra) do
    %Choreo{
      graph: infra.graph,
      edge_meta: infra.edge_meta,
      clusters: infra.clusters
    }
  end

  # ============================================================================
  # Internal helpers
  # ============================================================================

  defp add_typed_cluster(%__MODULE__{} = infra, name, type, opts) do
    opts = NimbleOptions.validate!(opts, @cluster_schema)
    prefixed_name = Choreo.Internal.ensure_cluster_prefix(name)

    cluster_meta =
      opts
      |> Map.new()
      |> Map.put(:cluster_type, type)
      |> Map.put_new(:label, name)

    cluster_meta =
      if parent = cluster_meta[:parent] do
        Map.put(cluster_meta, :parent, Choreo.Internal.ensure_cluster_prefix(parent))
      else
        cluster_meta
      end

    clusters = Map.put(infra.clusters, prefixed_name, cluster_meta)
    %{infra | clusters: clusters}
  end

  defp add_typed_node(%__MODULE__{graph: graph} = infra, id, type, opts) do
    opts = NimbleOptions.validate!(opts, @node_schema)
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

    %{infra | graph: Yog.Multi.add_node(graph, id, data)}
  end
end

defimpl Choreo.Viewable, for: Choreo.Infrastructure do
  def rebuild(infra, new_graph) do
    rebuilt = Choreo.Viewable.rebuild(Choreo.Infrastructure.to_choreo(infra), new_graph)
    %{infra | graph: rebuilt.graph, edge_meta: rebuilt.edge_meta, clusters: rebuilt.clusters}
  end

  def zoom_predicate(_, 0), do: fn _id, d -> d[:node_type] in [:internet, :load_balancer] end

  def zoom_predicate(_, 1),
    do: fn _id, d ->
      d[:node_type] in [:internet, :load_balancer, :compute, :managed_db, :storage]
    end

  def zoom_predicate(_, _), do: fn _id, _ -> true end

  def virtual_edge_meta(_infra), do: %{edge_type: :virtual, cost: 1}
end

defimpl Choreo.DOT, for: Choreo.Infrastructure do
  def to_dot(infra, opts), do: Choreo.to_dot(Choreo.Infrastructure.to_choreo(infra), opts)
end

defimpl Choreo.Mermaid, for: Choreo.Infrastructure do
  def to_mermaid(infra, opts), do: Choreo.to_mermaid(Choreo.Infrastructure.to_choreo(infra), opts)
end
