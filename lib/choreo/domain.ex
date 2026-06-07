defmodule Choreo.Domain do
  @moduledoc """
  Domain-Driven Design (DDD) and Event Storming domain-modeling preset for Choreo.

  `Choreo.Domain` is a domain-specific vocabulary layer that adds DDD concepts —
  Bounded Contexts, Aggregates, Commands, Domain Events, Policies, and Workflows —
  on top of Choreo's underlying graph and rendering engine.

  It draws inspiration from Scott Wlaschin's *Domain Modeling Made Functional*
  and classic tactical/strategic DDD patterns.

  ## Tactical Node Types (Event Storming & Workflows)
  * `:actor` - The user or external trigger initiating a command.
  * `:command` - An action requested (blue sticky note).
  * `:aggregate` - Consistency boundary / entity (yellow sticky note).
  * `:event` - Business domain event (orange sticky note).
  * `:read_model` - Projection / dashboard (green sticky note).
  * `:policy` - Saga or reaction policy (purple/lilac sticky note).
  * `:external_system` - Third-party system boundary (red/rose).
  * `:type` - Algebraic data type (Slate table card displaying field names and types).
  * `:workflow` - Wlaschin-style pipeline action (Teal rounded box).
  * `:acl` - Anti-Corruption Layer translation gateway.

  ## Strategic Modeling (Context Mapping)
  * `add_context/3` - Adds a Bounded Context node for high-level mapping.
  * `add_context_boundary/3` - Adds a Bounded Context cluster boundary for tactical grouping.
  * `connect_contexts/4` - Connects Bounded Context nodes with relationship labels (e.g. ACL, Shared Kernel).
  """

  alias __MODULE__

  @type t :: %__MODULE__{
          graph: Yog.Multi.Graph.t(),
          edge_meta: %{optional(Yog.Multi.Graph.edge_id()) => map()},
          clusters: %{String.t() => map()},
          highlighted_nodes: [Yog.node_id()],
          highlighted_edges: [Yog.Multi.Graph.edge_id() | {Yog.node_id(), Yog.node_id()}]
        }

  defstruct graph: nil,
            edge_meta: %{},
            clusters: %{},
            highlighted_nodes: [],
            highlighted_edges: []

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
      doc: "Bounded Context boundary where this node belongs."
    ],
    fields: [
      type: :any,
      required: false,
      doc: "List of fields for algebraic types or aggregates. Format: `[{name, type}]`."
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
      doc: "Image URL override."
    ],
    icon: [
      type: :atom,
      required: false,
      doc: "Standard icon key."
    ]
  ]

  @cluster_schema [
    parent: [
      type: :string,
      required: false,
      doc: "Parent context/cluster."
    ],
    label: [
      type: :string,
      required: false,
      doc: "Display label for the cluster."
    ],
    style: [
      type: :string,
      required: false,
      doc: "Border style."
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
      doc: "Weight metric."
    ],
    label: [
      type: :string,
      required: false,
      doc: "Edge connection label."
    ],
    type: [
      type: :atom,
      required: false,
      doc: "Connection type override."
    ]
  ]

  @relationships [
    :shared_kernel,
    :customer_supplier,
    :conformist,
    :open_host_service,
    :published_language,
    :acl
  ]

  @connect_contexts_schema [
    relationship: [
      type: {:in, @relationships},
      required: true,
      doc:
        "DDD relationship: :shared_kernel, :customer_supplier, :conformist, :open_host_service, :published_language, or :acl."
    ],
    label: [
      type: :string,
      required: false,
      doc: "Additional custom label text."
    ]
  ]

  # ============================================================================
  # Creation
  # ============================================================================

  @doc """
  Initializes a new empty domain model.
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
  # Strategic Context Mapping Builders
  # ============================================================================

  @doc """
  Adds a Bounded Context node for high-level Strategic Context Maps.
  """
  @spec add_context(t(), Yog.node_id(), keyword()) :: t()
  def add_context(domain, id, opts \\ []) do
    add_typed_node(domain, id, :context, opts)
  end

  @doc """
  Adds a Bounded Context cluster boundary for Tactical design layouts.
  """
  @spec add_context_boundary(t(), String.t(), keyword()) :: t()
  def add_context_boundary(domain, name, opts \\ []) do
    add_typed_cluster(domain, name, :context_boundary, opts)
  end

  # ============================================================================
  # Tactical Sticky-Note Builders
  # ============================================================================

  @doc """
  Adds a user or actor initiating a command.
  """
  @spec add_actor(t(), Yog.node_id(), keyword()) :: t()
  def add_actor(domain, id, opts \\ []) do
    add_typed_node(domain, id, :actor, opts)
  end

  @doc """
  Adds a Command node (actions requested).
  """
  @spec add_command(t(), Yog.node_id(), keyword()) :: t()
  def add_command(domain, id, opts \\ []) do
    add_typed_node(domain, id, :command, opts)
  end

  @doc """
  Adds an Aggregate/Entity boundary node.
  """
  @spec add_aggregate(t(), Yog.node_id(), keyword()) :: t()
  def add_aggregate(domain, id, opts \\ []) do
    add_typed_node(domain, id, :aggregate, opts)
  end

  @doc """
  Adds a Domain Event node.
  """
  @spec add_event(t(), Yog.node_id(), keyword()) :: t()
  def add_event(domain, id, opts \\ []) do
    add_typed_node(domain, id, :event, opts)
  end

  @doc """
  Adds a Read Model / Projection node.
  """
  @spec add_read_model(t(), Yog.node_id(), keyword()) :: t()
  def add_read_model(domain, id, opts \\ []) do
    add_typed_node(domain, id, :read_model, opts)
  end

  @doc """
  Adds a Policy / Saga handler node.
  """
  @spec add_policy(t(), Yog.node_id(), keyword()) :: t()
  def add_policy(domain, id, opts \\ []) do
    add_typed_node(domain, id, :policy, opts)
  end

  @doc """
  Adds an External System node.
  """
  @spec add_external_system(t(), Yog.node_id(), keyword()) :: t()
  def add_external_system(domain, id, opts \\ []) do
    add_typed_node(domain, id, :external_system, opts)
  end

  @doc """
  Adds an Algebraic Data Type node.
  """
  @spec add_type(t(), Yog.node_id(), keyword()) :: t()
  def add_type(domain, id, opts \\ []) do
    add_typed_node(domain, id, :type, opts)
  end

  @doc """
  Adds a Workflow pipeline function node.
  """
  @spec add_workflow(t(), Yog.node_id(), keyword()) :: t()
  def add_workflow(domain, id, opts \\ []) do
    add_typed_node(domain, id, :workflow, opts)
  end

  @doc """
  Adds an Anti-Corruption Layer translation gateway component.
  """
  @spec add_acl(t(), Yog.node_id(), keyword()) :: t()
  def add_acl(domain, id, opts \\ []) do
    add_typed_node(domain, id, :acl, opts)
  end

  # ============================================================================
  # Connections & Context Mapping
  # ============================================================================

  @doc """
  Connects two domain nodes.
  """
  @spec connect(t(), Yog.node_id(), Yog.node_id(), keyword()) :: t()
  def connect(%Domain{} = domain, from, to, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @connect_schema)
    cost = opts[:cost]

    unless Map.has_key?(domain.graph.nodes, from) do
      raise ArgumentError, "Node #{inspect(from)} does not exist in domain model"
    end

    unless Map.has_key?(domain.graph.nodes, to) do
      raise ArgumentError, "Node #{inspect(to)} does not exist in domain model"
    end

    meta = Map.new(opts)
    {graph, edge_id} = Yog.Multi.add_edge(domain.graph, from, to, cost)
    edge_meta = Map.put(domain.edge_meta, edge_id, meta)

    %{domain | graph: graph, edge_meta: edge_meta}
  end

  @doc """
  Connects two strategic Bounded Context nodes with DDD relationship semantics.
  """
  @spec connect_contexts(t(), Yog.node_id(), Yog.node_id(), keyword()) :: t()
  def connect_contexts(%Domain{} = domain, upstream_id, downstream_id, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @connect_contexts_schema)
    rel = opts[:relationship]
    custom_lbl = opts[:label]

    lbl =
      case rel do
        :shared_kernel -> "[Shared Kernel]"
        :customer_supplier -> "[U: Supplier] -> [D: Customer]"
        :conformist -> "[U: Supplier] -> [D: Conformist]"
        :open_host_service -> "[U: OHS] -> [D]"
        :published_language -> "[U: PL] -> [D]"
        :acl -> "[U] -> [ACL] -> [D]"
      end

    lbl = if custom_lbl, do: "#{lbl} (#{custom_lbl})", else: lbl

    connect(domain, upstream_id, downstream_id, label: lbl, type: :context_mapping)
  end

  # ============================================================================
  # Scenario Highlight Lenses
  # ============================================================================

  @doc """
  Focuses the diagram on a specific execution path scenario, highlighting it
  while leaving the rest of the diagram visible.
  """
  @spec focus_path(t(), [Yog.node_id()]) :: t()
  def focus_path(%Domain{} = domain, path) when is_list(path) do
    # Convert consecutive nodes to edge pairs
    edges =
      if length(path) >= 2 do
        path
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.map(fn [a, b] -> {a, b} end)
      else
        []
      end

    %{domain | highlighted_nodes: path, highlighted_edges: edges}
  end

  @doc """
  Traces the root cause sequence leading to a target node.
  Returns a list of node IDs showing the path from the root triggers.
  """
  @spec trace_cause(t(), Yog.node_id()) :: [Yog.node_id()]
  def trace_cause(%Domain{graph: graph}, target) do
    if Map.has_key?(graph.nodes, target) do
      # Simple BFS/DFS traversal going backwards (predecessors)
      traverse_backwards(graph, [target], MapSet.new([target]))
      |> Enum.reverse()
    else
      []
    end
  end

  # ============================================================================
  # Queries
  # ============================================================================

  @doc """
  Returns all node definitions in the domain model.
  """
  @spec nodes(t()) :: %{Yog.node_id() => map()}
  def nodes(%Domain{graph: graph}) do
    graph.nodes
  end

  @doc """
  Returns all edges in the domain model.
  """
  @spec edges(t()) :: [{Yog.node_id(), Yog.node_id(), number()}]
  def edges(%Domain{graph: graph}) do
    Enum.map(graph.edges, fn {_edge_id, {from, to, weight}} ->
      {from, to, weight}
    end)
  end

  # ============================================================================
  # Rendering
  # ============================================================================

  @doc """
  Renders the domain model to DOT format.
  """
  @spec to_dot(t(), keyword()) :: String.t()
  def to_dot(%Domain{} = domain, opts \\ []) do
    opts =
      opts
      |> Keyword.put_new(:highlighted_nodes, domain.highlighted_nodes)
      |> Keyword.put_new(:highlighted_edges, domain.highlighted_edges)

    Choreo.Render.DOT.to_dot(domain, opts)
  end

  @doc """
  Renders the domain model to Mermaid.js native syntax.

  ## Options
    * `:syntax` - `:flowchart` (default), `:class_diagram`, or `:erd`
    * Other options matching selected syntax engine
  """
  @spec to_mermaid(t(), keyword()) :: String.t()
  def to_mermaid(%Domain{} = domain, opts \\ []) do
    case Keyword.get(opts, :syntax, :flowchart) do
      :class_diagram ->
        to_native_class_diagram(domain, opts)

      :erd ->
        to_native_erd(domain, opts)

      :flowchart ->
        opts =
          opts
          |> Keyword.put_new(:highlighted_nodes, domain.highlighted_nodes)
          |> Keyword.put_new(:highlighted_edges, domain.highlighted_edges)

        Choreo.Render.Mermaid.to_mermaid(domain, opts)
    end
  end

  defp to_native_class_diagram(domain, opts) do
    direction = Keyword.get(opts, :direction, :td)
    direction_part = "  direction #{String.upcase(to_string(direction))}\n"

    class_defs =
      domain.graph.nodes
      |> Enum.sort_by(fn {id, _data} -> id end)
      |> Enum.map_join("\n", fn {id, data} ->
        stereotype =
          case data[:type] do
            :class -> ""
            type -> "    <<#{type}>>"
          end

        fields =
          (data[:fields] || [])
          |> Enum.map_join("\n", fn
            {field_name, field_type} when is_list(field_type) ->
              choices = Enum.map_join(field_type, " | ", &to_string/1)
              "    +#{field_name} #{choices}"

            {field_name, field_type} ->
              "    +#{field_name} #{field_type}"
          end)

        body =
          [stereotype, fields]
          |> Enum.filter(&(&1 != ""))
          |> Enum.join("\n")

        "  class #{id} {\n#{body}\n  }"
      end)

    relations =
      domain.graph.edges
      |> Map.keys()
      |> Enum.sort()
      |> Enum.map_join("\n", fn edge_id ->
        {from, to, _weight} = Map.get(domain.graph.edges, edge_id)
        meta = Map.get(domain.edge_meta, edge_id, %{})
        label = if l = meta[:label], do: " : #{l}", else: ""
        "  #{from} --> #{to}#{label}"
      end)

    "classDiagram\n" <> direction_part <> class_defs <> "\n" <> relations <> "\n"
  end

  defp to_native_erd(domain, _opts) do
    entity_defs =
      domain.graph.nodes
      |> Enum.sort_by(fn {id, _data} -> id end)
      |> Enum.map_join("\n", fn {id, data} ->
        fields =
          (data[:fields] || [])
          |> Enum.map_join("\n", fn
            {field_name, field_type} when is_list(field_type) ->
              choices = Enum.map_join(field_type, "|", &to_string/1)
              safe_type = clean_erd_type(choices)
              "    #{safe_type} #{field_name}"

            {field_name, field_type} ->
              safe_type = clean_erd_type(to_string(field_type))
              "    #{safe_type} #{field_name}"
          end)

        if fields != "" do
          "  #{id} {\n#{fields}\n  }"
        else
          "  #{id}"
        end
      end)

    relations =
      domain.graph.edges
      |> Map.keys()
      |> Enum.sort()
      |> Enum.map_join("\n", fn edge_id ->
        {from, to, _weight} = Map.get(domain.graph.edges, edge_id)
        meta = Map.get(domain.edge_meta, edge_id, %{})
        label = if l = meta[:label], do: " : \"#{l}\"", else: " : \"relates\""
        "  #{from} }|..|{ #{to}#{label}"
      end)

    "erDiagram\n" <> entity_defs <> "\n" <> relations <> "\n"
  end

  # ============================================================================
  # Internal helpers
  # ============================================================================

  defp add_typed_cluster(%Domain{} = domain, name, type, opts) do
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

    clusters = Map.put(domain.clusters, prefixed_name, cluster_meta)
    %{domain | clusters: clusters}
  end

  defp add_typed_node(%Domain{graph: graph} = domain, id, type, opts) do
    opts = NimbleOptions.validate!(opts, @node_schema)
    {cluster, rest_opts} = Keyword.pop(opts, :cluster)

    data =
      rest_opts
      |> Map.new()
      |> Map.merge(%{
        type: type,
        name: Keyword.get(rest_opts, :label, to_string(id))
      })

    data =
      if cluster,
        do: Map.put(data, :cluster, Choreo.Internal.ensure_cluster_prefix(cluster)),
        else: data

    %{domain | graph: Yog.Multi.add_node(graph, id, data)}
  end

  defp traverse_backwards(graph, queue, visited) do
    case queue do
      [] ->
        MapSet.to_list(visited)

      [current | rest] ->
        # Find incoming nodes
        incoming =
          Enum.filter(graph.edges, fn {_eid, {_from, to, _w}} -> to == current end)
          |> Enum.map(fn {_eid, {from, _to, _w}} -> from end)
          |> Enum.reject(&MapSet.member?(visited, &1))

        new_queue = rest ++ incoming
        new_visited = MapSet.union(visited, MapSet.new(incoming))
        traverse_backwards(graph, new_queue, new_visited)
    end
  end

  defp clean_erd_type(type_str) do
    type_str
    |> String.replace(" ", "_")
    |> String.replace("|", "_or_")
    # Strip any character that is not alphanumeric or underscore
    |> String.replace(~r/[^a-zA-Z0-9_]/, "")
    # Deduplicate multiple underscores
    |> String.replace(~r/__+/, "_")
  end
end

defimpl Choreo.Viewable, for: Choreo.Domain do
  def rebuild(domain, new_graph) do
    new_edge_meta = Map.take(domain.edge_meta, Map.keys(new_graph.edges))

    new_edge_meta =
      Enum.reduce(Map.keys(new_graph.edges), new_edge_meta, fn eid, acc ->
        Map.put_new(acc, eid, %{edge_type: :virtual, cost: 1})
      end)

    %{domain | graph: new_graph, edge_meta: new_edge_meta}
  end

  def zoom_predicate(_, 0), do: fn _id, d -> d[:type] in [:context, :actor] end
  def zoom_predicate(_, 1), do: fn _id, d -> d[:type] in [:context, :actor, :command, :event] end
  def zoom_predicate(_, _), do: fn _id, _ -> true end

  def virtual_edge_meta(_domain), do: %{edge_type: :virtual, cost: 1}
end

defimpl Choreo.DOT, for: Choreo.Domain do
  def to_dot(domain, opts), do: Choreo.Domain.to_dot(domain, opts)
end

defimpl Choreo.Mermaid, for: Choreo.Domain do
  def to_mermaid(domain, opts), do: Choreo.Domain.to_mermaid(domain, opts)
end
