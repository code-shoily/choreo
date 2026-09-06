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
          scenarios: %{atom() => map()},
          highlighted_nodes: [Yog.node_id()],
          highlighted_edges: [Yog.Multi.Graph.edge_id() | {Yog.node_id(), Yog.node_id()}]
        }

  defstruct graph: nil,
            edge_meta: %{},
            clusters: %{},
            scenarios: %{},
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
    ],
    subdomain: [
      type: {:in, [:core, :supporting, :generic]},
      required: false,
      doc: "Strategic DDD subdomain classification."
    ],
    owner: [
      type: :string,
      required: false,
      doc: "Owning team or group for the domain element."
    ],
    invariants: [
      type: {:list, :string},
      required: false,
      doc: "Business invariants protected by an aggregate or workflow."
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

  @context_relationships [
    :shared_kernel,
    :customer_supplier,
    :conformist,
    :open_host_service,
    :published_language,
    :acl
  ]

  @domain_relationships [
    :initiates,
    :handles,
    :emits,
    :triggers,
    :projects_to,
    :notifies,
    :translates_via
  ]

  @relationships @context_relationships ++ @domain_relationships

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
      type: {:in, [:sequence, :context_mapping, :domain_relationship, :virtual]},
      required: false,
      default: :sequence,
      doc: "Connection type override."
    ],
    relationship: [
      type: {:in, @relationships},
      required: false,
      doc: "DDD relationship type (stored on context-mapping edges)."
    ]
  ]

  @connect_contexts_schema [
    relationship: [
      type: {:in, @context_relationships},
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

  @scenario_schema [
    label: [
      type: :string,
      required: false,
      doc: "Human-readable scenario label."
    ],
    path: [
      type: {:list, :any},
      required: true,
      doc: "Ordered domain node IDs that describe this scenario."
    ],
    description: [
      type: :string,
      required: false,
      doc: "Scenario description or business narrative."
    ]
  ]

  # ============================================================================
  # Creation
  # ============================================================================

  @doc """
  Initializes a new empty domain model.
  """
  @spec new(keyword()) :: t()
  def new(_opts \\ []) do
    %__MODULE__{
      graph: Yog.Multi.new(:directed),
      edge_meta: %{},
      clusters: %{},
      scenarios: %{}
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

  Prefer the semantic helpers (`initiates/4`, `handles/4`, `emits/4`,
  `triggers/4`, `projects_to/4`, `notifies/4`, and `translates_via/4`) when
  the edge has DDD/Event Modeling meaning. Use `connect/4` as the generic
  escape hatch.
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
  Connects an actor, UI, or external trigger to a command.
  """
  @spec initiates(t(), Yog.node_id(), Yog.node_id(), keyword()) :: t()
  def initiates(%Domain{} = domain, trigger_id, command_id, opts \\ []) do
    semantic_connect(
      domain,
      trigger_id,
      command_id,
      :initiates,
      Keyword.put_new(opts, :label, "initiates")
    )
  end

  @doc """
  Connects a command to the aggregate or workflow that handles it.
  """
  @spec handles(t(), Yog.node_id(), Yog.node_id(), keyword()) :: t()
  def handles(%Domain{} = domain, command_id, handler_id, opts \\ []) do
    semantic_connect(
      domain,
      command_id,
      handler_id,
      :handles,
      Keyword.put_new(opts, :label, "handles")
    )
  end

  @doc """
  Connects an aggregate, workflow, or external system to an emitted domain event.
  """
  @spec emits(t(), Yog.node_id(), Yog.node_id(), keyword()) :: t()
  def emits(%Domain{} = domain, emitter_id, event_id, opts \\ []) do
    semantic_connect(domain, emitter_id, event_id, :emits, Keyword.put_new(opts, :label, "emits"))
  end

  @doc """
  Connects an event or policy to a command, policy, workflow, or other reaction.
  """
  @spec triggers(t(), Yog.node_id(), Yog.node_id(), keyword()) :: t()
  def triggers(%Domain{} = domain, cause_id, effect_id, opts \\ []) do
    semantic_connect(
      domain,
      cause_id,
      effect_id,
      :triggers,
      Keyword.put_new(opts, :label, "triggers")
    )
  end

  @doc """
  Connects an event to a read model/projection that it updates.
  """
  @spec projects_to(t(), Yog.node_id(), Yog.node_id(), keyword()) :: t()
  def projects_to(%Domain{} = domain, event_id, read_model_id, opts \\ []) do
    semantic_connect(
      domain,
      event_id,
      read_model_id,
      :projects_to,
      Keyword.put_new(opts, :label, "projects to")
    )
  end

  @doc """
  Connects an event to an actor/user notification.
  """
  @spec notifies(t(), Yog.node_id(), Yog.node_id(), keyword()) :: t()
  def notifies(%Domain{} = domain, event_id, actor_id, opts \\ []) do
    semantic_connect(
      domain,
      event_id,
      actor_id,
      :notifies,
      Keyword.put_new(opts, :label, "notifies")
    )
  end

  @doc """
  Connects an upstream model/system to a downstream model/system through an ACL
  or translation gateway.
  """
  @spec translates_via(t(), Yog.node_id(), Yog.node_id(), keyword()) :: t()
  def translates_via(%Domain{} = domain, from_id, to_id, opts \\ []) do
    semantic_connect(
      domain,
      from_id,
      to_id,
      :translates_via,
      Keyword.put_new(opts, :label, "translates via")
    )
  end

  @doc """
  Connects two strategic Bounded Context nodes with DDD relationship semantics.
  """
  @spec connect_contexts(t(), Yog.node_id(), Yog.node_id(), keyword()) :: t()
  def connect_contexts(%Domain{} = domain, upstream_id, downstream_id, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @connect_contexts_schema)
    rel = opts[:relationship]
    custom_lbl = opts[:label]

    for id <- [upstream_id, downstream_id] do
      case Map.get(domain.graph.nodes, id) do
        %{type: :context} ->
          :ok

        %{type: type} ->
          raise ArgumentError,
                "connect_contexts/4 requires both endpoints to be :context nodes, " <>
                  "but #{inspect(id)} is #{inspect(type)}"

        nil ->
          raise ArgumentError,
                "connect_contexts/4 requires both endpoints to exist, but #{inspect(id)} does not"
      end
    end

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

    connect(domain, upstream_id, downstream_id,
      label: lbl,
      type: :context_mapping,
      relationship: rel
    )
  end

  # ============================================================================
  # Scenario Highlight Lenses
  # ============================================================================

  @doc """
  Adds a named business scenario as an ordered domain path.

  Scenarios are useful for documenting use cases and rendering a selected path
  as a Mermaid `eventmodeling` timeline.
  """
  @spec add_scenario(t(), atom(), keyword()) :: t()
  def add_scenario(%Domain{} = domain, name, opts) when is_atom(name) do
    opts = NimbleOptions.validate!(opts, @scenario_schema)

    scenario =
      opts
      |> Map.new()
      |> Map.put_new(:label, name |> to_string() |> String.replace("_", " "))

    %{domain | scenarios: Map.put(domain.scenarios, name, scenario)}
  end

  @doc """
  Returns all named scenarios.
  """
  @spec scenarios(t()) :: %{atom() => map()}
  def scenarios(%Domain{} = domain), do: domain.scenarios

  @doc """
  Returns a named scenario, or `nil` when it is not present.
  """
  @spec scenario(t(), atom()) :: map() | nil
  def scenario(%Domain{} = domain, name) when is_atom(name), do: Map.get(domain.scenarios, name)

  @doc """
  Focuses the diagram on a named scenario path.
  """
  @spec focus_scenario(t(), atom()) :: t()
  def focus_scenario(%Domain{} = domain, name) when is_atom(name) do
    case scenario(domain, name) do
      %{path: path} -> focus_path(domain, path)
      nil -> raise ArgumentError, "Scenario #{inspect(name)} does not exist in domain model"
    end
  end

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
  Clears the current scenario highlight.

  ## Examples

      iex> domain = Choreo.Domain.new()
      ...>   |> Choreo.Domain.add_actor(:customer)
      ...>   |> Choreo.Domain.add_command(:place_order)
      ...>   |> Choreo.Domain.focus_path([:customer, :place_order])
      ...>   |> Choreo.Domain.clear_focus()
      iex> domain.highlighted_nodes
      []
      iex> domain.highlighted_edges
      []
  """
  @spec clear_focus(t()) :: t()
  def clear_focus(%Domain{} = domain) do
    %{domain | highlighted_nodes: [], highlighted_edges: []}
  end

  @doc """
  Returns all ancestor causes of a target node.

  This is a **set**, not an ordered path — for branching cause graphs
  (DAGs with multiple parents), all ancestors are returned collapsed into
  one list with no path structure.

  ## Examples

      iex> domain = Choreo.Domain.new()
      ...>   |> Choreo.Domain.add_actor(:customer)
      ...>   |> Choreo.Domain.add_command(:place_order)
      ...>   |> Choreo.Domain.add_aggregate(:order_agg)
      ...>   |> Choreo.Domain.add_event(:order_placed)
      ...>   |> Choreo.Domain.connect(:customer, :place_order)
      ...>   |> Choreo.Domain.connect(:place_order, :order_agg)
      ...>   |> Choreo.Domain.connect(:order_agg, :order_placed)
      iex> ancestors = Choreo.Domain.causes(domain, :order_placed)
      iex> :customer in ancestors
      true
      iex> :order_agg in ancestors
      true
  """
  @spec causes(t(), Yog.node_id()) :: [Yog.node_id()]
  def causes(%Domain{graph: graph}, target) do
    if Map.has_key?(graph.nodes, target) do
      traverse_backwards(graph, [target], MapSet.new([target]))
    else
      []
    end
  end

  @doc false
  @deprecated "Use causes/2 instead"
  def trace_cause(domain, target), do: causes(domain, target)

  @doc """
  Returns all downstream effects reachable from a source node.

  This is a **set**, not an ordered path — for branching graphs, all reachable
  descendants are returned collapsed into one list with no path structure.

  ## Examples

      iex> domain = Choreo.Domain.new()
      ...>   |> Choreo.Domain.add_actor(:customer)
      ...>   |> Choreo.Domain.add_command(:place_order)
      ...>   |> Choreo.Domain.add_aggregate(:order_agg)
      ...>   |> Choreo.Domain.connect(:customer, :place_order)
      ...>   |> Choreo.Domain.connect(:place_order, :order_agg)
      iex> descendants = Choreo.Domain.downstream(domain, :customer)
      iex> :place_order in descendants
      true
      iex> :order_agg in descendants
      true
  """
  @spec downstream(t(), Yog.node_id()) :: [Yog.node_id()]
  def downstream(%Domain{graph: graph}, source) do
    if Map.has_key?(graph.nodes, source) do
      traverse_forwards(graph, [source], MapSet.new([source]))
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
    * `:syntax` - `:flowchart` (default), `:class_diagram`, `:erd`, or
      `:event_modeling`
    * `:path` - ordered node IDs for `:event_modeling` timeline rendering
    * `:scenario` - named scenario to render with `:event_modeling`
    * Other options matching the selected syntax engine
  """
  @spec to_mermaid(t(), keyword()) :: String.t()
  def to_mermaid(%Domain{} = domain, opts \\ []) do
    case Keyword.get(opts, :syntax, :flowchart) do
      :class_diagram ->
        to_native_class_diagram(domain, opts)

      :erd ->
        to_native_erd(domain, opts)

      :event_modeling ->
        to_native_event_modeling(domain, opts)

      :flowchart ->
        opts =
          opts
          |> Keyword.put_new(:highlighted_nodes, domain.highlighted_nodes)
          |> Keyword.put_new(:highlighted_edges, domain.highlighted_edges)

        Choreo.Render.Mermaid.to_mermaid(domain, opts)
    end
  end

  @doc """
  Returns a theme for `Choreo.Domain`.

  ## Examples

      iex> theme = Choreo.Domain.theme(:default, graph_rankdir: :lr)
      iex> theme.graph_rankdir
      :lr
  """
  @spec theme(atom(), keyword()) :: Choreo.Theme.t()
  def theme(name \\ :default, overrides \\ []) do
    Choreo.theme(name, overrides)
  end

  defp to_native_class_diagram(domain, opts) do
    direction = Keyword.get(opts, :direction, :td)
    direction_part = "  direction #{String.upcase(to_string(direction))}\n"

    class_defs =
      domain.graph.nodes
      |> Enum.sort_by(fn {id, _data} -> id end)
      |> Enum.map_join("\n", fn {id, data} ->
        stereotype =
          if data[:type] do
            "    <<#{data[:type]}>>"
          else
            ""
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

  defp to_native_event_modeling(domain, opts) do
    path = event_modeling_path(domain, opts)

    frames =
      path
      |> Enum.map(&{&1, Map.get(domain.graph.nodes, &1)})
      |> Enum.reject(fn {_id, data} ->
        is_nil(data) or is_nil(event_modeling_type(data[:type]))
      end)
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {{id, data}, index} ->
        number = index |> Integer.to_string() |> String.pad_leading(2, "0")
        entity = event_modeling_entity_id(domain, id, data)
        "tf #{number} #{event_modeling_type(data[:type])} #{entity}"
      end)

    "eventmodeling\n\n" <> frames <> "\n"
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

  defp semantic_connect(domain, from, to, relationship, opts) do
    opts =
      opts
      |> Keyword.put(:type, :domain_relationship)
      |> Keyword.put(:relationship, relationship)

    connect(domain, from, to, opts)
  end

  defp event_modeling_path(domain, opts) do
    cond do
      path = Keyword.get(opts, :path) ->
        path

      scenario_name = Keyword.get(opts, :scenario) ->
        case scenario(domain, scenario_name) do
          %{path: path} ->
            path

          nil ->
            raise ArgumentError,
                  "Scenario #{inspect(scenario_name)} does not exist in domain model"
        end

      domain.highlighted_nodes != [] ->
        domain.highlighted_nodes

      true ->
        infer_event_modeling_path(domain)
    end
  end

  defp infer_event_modeling_path(%Domain{} = domain) do
    nodes = Map.keys(domain.graph.nodes)
    incoming_counts = Map.new(nodes, &{&1, 0})

    incoming_counts =
      Enum.reduce(domain.graph.edges, incoming_counts, fn {_edge_id, {_from, to, _weight}}, acc ->
        Map.update(acc, to, 1, &(&1 + 1))
      end)

    roots =
      incoming_counts |> Enum.filter(fn {_id, count} -> count == 0 end) |> Enum.map(&elem(&1, 0))

    case roots do
      [root] ->
        traverse_single_path(domain.graph, root, [])

      _ ->
        raise ArgumentError,
              "Cannot infer Event Modeling timeline for a branching domain graph; pass :path or :scenario."
    end
  end

  defp traverse_single_path(graph, current, acc) do
    outgoing =
      graph.edges
      |> Enum.filter(fn {_edge_id, {from, _to, _weight}} -> from == current end)
      |> Enum.map(fn {_edge_id, {_from, to, _weight}} -> to end)

    case outgoing do
      [] ->
        Enum.reverse([current | acc])

      [next] ->
        traverse_single_path(graph, next, [current | acc])

      _ ->
        raise ArgumentError,
              "Cannot infer Event Modeling timeline for a branching domain graph; pass :path or :scenario."
    end
  end

  defp event_modeling_type(:actor), do: "ui"
  defp event_modeling_type(:external_system), do: "pcr"
  defp event_modeling_type(:workflow), do: "pcr"
  defp event_modeling_type(:policy), do: "pcr"
  defp event_modeling_type(:acl), do: "pcr"
  defp event_modeling_type(:command), do: "cmd"
  defp event_modeling_type(:read_model), do: "rmo"
  defp event_modeling_type(:event), do: "evt"
  defp event_modeling_type(_), do: nil

  defp event_modeling_entity_id(domain, id, data) do
    base = data[:label] || data[:name] || id
    entity = sanitize_event_modeling_id(base)

    case data[:cluster] do
      nil ->
        entity

      cluster ->
        namespace =
          domain.clusters
          |> Map.get(cluster, %{})
          |> Map.get(:label, String.replace_prefix(cluster, "cluster_", ""))
          |> sanitize_event_modeling_id()

        namespace <> "." <> entity
    end
  end

  defp sanitize_event_modeling_id(value) do
    value
    |> to_string()
    |> String.replace(~r/[^a-zA-Z0-9_]+/, " ")
    |> String.split()
    |> Enum.map_join("", &String.capitalize/1)
    |> case do
      "" -> "Entity"
      sanitized -> sanitized
    end
  end

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
        incoming =
          Enum.filter(graph.edges, fn {_eid, {_from, to, _w}} -> to == current end)
          |> Enum.map(fn {_eid, {from, _to, _w}} -> from end)
          |> Enum.reject(&MapSet.member?(visited, &1))

        new_queue = rest ++ incoming
        new_visited = MapSet.union(visited, MapSet.new(incoming))
        traverse_backwards(graph, new_queue, new_visited)
    end
  end

  defp traverse_forwards(graph, queue, visited) do
    case queue do
      [] ->
        MapSet.to_list(visited)

      [current | rest] ->
        outgoing =
          Enum.filter(graph.edges, fn {_eid, {from, _to, _w}} -> from == current end)
          |> Enum.map(fn {_eid, {_from, to, _w}} -> to end)
          |> Enum.reject(&MapSet.member?(visited, &1))

        new_queue = rest ++ outgoing
        new_visited = MapSet.union(visited, MapSet.new(outgoing))
        traverse_forwards(graph, new_queue, new_visited)
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

    kept_ids = MapSet.new(Map.keys(new_graph.nodes))

    highlighted_nodes =
      Enum.filter(domain.highlighted_nodes, &MapSet.member?(kept_ids, &1))

    highlighted_edges =
      Enum.filter(domain.highlighted_edges, fn {a, b} ->
        MapSet.member?(kept_ids, a) and MapSet.member?(kept_ids, b)
      end)

    %{
      domain
      | graph: new_graph,
        edge_meta: new_edge_meta,
        highlighted_nodes: highlighted_nodes,
        highlighted_edges: highlighted_edges
    }
  end

  def zoom_predicate(_, 0), do: fn _id, d -> d[:type] in [:context, :actor] end

  def zoom_predicate(_, 1),
    do: fn _id, d -> d[:type] in [:context, :actor, :command, :aggregate, :event] end

  def zoom_predicate(_, _), do: fn _id, _ -> true end

  def virtual_edge_meta(_domain), do: %{edge_type: :virtual, cost: 1}
end

defimpl Choreo.DOT, for: Choreo.Domain do
  def to_dot(domain, opts), do: Choreo.Domain.to_dot(domain, opts)
end

defimpl Choreo.Mermaid, for: Choreo.Domain do
  def to_mermaid(domain, opts), do: Choreo.Domain.to_mermaid(domain, opts)
end
