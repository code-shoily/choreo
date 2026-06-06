defmodule Choreo.C4 do
  @moduledoc """
  C4 Model architecture diagram builder on top of Yog.

  `Choreo.C4` lets you document software architecture using the
  [C4 model](https://c4model.com/) — a simple hierarchical approach
  for visualising software architecture at different levels of abstraction.

  ## The four levels

    * **L1 System Context** — people and software systems
    * **L2 Containers** — applications and data stores inside a system
    * **L3 Components** — building blocks inside a container
    * **L4 Code** — classes / interfaces (delegate to `Choreo.UML`)

  ## When to use

  Use `Choreo.C4` when you need to communicate architecture to both
  technical and non-technical stakeholders. The zoom levels map directly
  to the C4 abstraction levels, so you can generate Context, Container,
  and Component diagrams from a single model.

  ## Quick Start

      c4 =
        Choreo.C4.new()
        |> Choreo.C4.add_person(:customer, label: "Customer",
             description: "A user of the bank")
        |> Choreo.C4.add_software_system(:banking, label: "Internet Banking",
             description: "Allows customers to check balances", scope: :in)
        |> Choreo.C4.add_software_system(:mainframe, label: "Mainframe",
             description: "Stores core banking info", scope: :out)
        |> Choreo.C4.add_relationship(:customer, :banking,
             label: "Views balances using")
        |> Choreo.C4.add_relationship(:banking, :mainframe,
             label: "Gets account info from")
        # L2 — Containers inside the in-scope system
        |> Choreo.C4.add_container(:web_app, label: "Web App",
             technology: "JavaScript, React", parent: :banking)
        |> Choreo.C4.add_container(:api, label: "API",
             technology: "Elixir, Phoenix", parent: :banking)
        |> Choreo.C4.add_container(:db, label: "Database",
             technology: "Postgres", parent: :banking)
        |> Choreo.C4.add_relationship(:customer, :web_app, label: "Uses")
        |> Choreo.C4.add_relationship(:web_app, :api, label: "Makes API calls to")
        |> Choreo.C4.add_relationship(:api, :db, label: "Reads from and writes to")
        |> Choreo.C4.add_relationship(:api, :mainframe, label: "Makes RPC calls to")
        # L3 — Components inside a container
        |> Choreo.C4.add_component(:signin, label: "Sign In Controller",
             technology: "Phoenix Controller", parent: :api)
        |> Choreo.C4.add_component(:accounts, label: "Accounts Context",
             technology: "Domain logic", parent: :api)
        |> Choreo.C4.add_relationship(:signin, :accounts, label: "Uses")

      # Generate diagrams at different zoom levels
      context   = Choreo.View.zoom(c4, level: 0)
      container = Choreo.View.zoom(c4, level: 1)
      component = Choreo.View.zoom(c4, level: 2)

      dot = Choreo.C4.to_dot(c4)
      mermaid = Choreo.C4.to_mermaid(c4)

  ## Analysis

      # Find containers with no relationships
      Choreo.C4.Analysis.orphan_nodes(c4)

      # Validate structural soundness
      Choreo.C4.Analysis.validate(c4)

      # Find missing descriptions
      Choreo.C4.Analysis.missing_descriptions(c4)

      # Find missing technology labels
      Choreo.C4.Analysis.missing_technology(c4)
  """

  @type t :: %__MODULE__{
          graph: Yog.Multi.Graph.t(),
          edge_meta: %{optional(Yog.Multi.Graph.edge_id()) => map()},
          clusters: %{String.t() => map()},
          scope: Yog.node_id() | nil
        }

  defstruct graph: nil, edge_meta: %{}, clusters: %{}, scope: nil

  @node_schema [
    label: [
      type: :string,
      required: false,
      doc: "Display label for the node."
    ],
    description: [
      type: :string,
      required: false,
      doc: "Longer description shown as tooltip."
    ],
    technology: [
      type: :string,
      required: false,
      doc: "Technology stack (e.g. 'Elixir, Phoenix')."
    ],
    shape: [
      type: :atom,
      required: false,
      doc: "Shape override for DOT output."
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
      doc: "Image/icon path or URL override."
    ]
  ]

  @add_person_schema @node_schema

  @add_software_system_schema [
                                scope: [
                                  type: {:in, [:in, :out]},
                                  required: false,
                                  default: :out,
                                  doc:
                                    "Whether this system is in scope (:in) or external (:out) of the diagram being produced."
                                ]
                              ] ++ @node_schema

  @add_container_schema [
                          parent: [
                            type: {:or, [:atom, :string]},
                            required: false,
                            doc: "Parent software system node ID."
                          ]
                        ] ++ @node_schema

  @add_component_schema [
                          parent: [
                            type: {:or, [:atom, :string]},
                            required: false,
                            doc: "Parent container node ID."
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
      doc: "Visual style."
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

  @add_relationship_schema [
    label: [
      type: :string,
      required: false,
      doc: "Description of the relationship."
    ],
    technology: [
      type: :string,
      required: false,
      doc: "Technology used for the relationship (e.g. 'HTTPS', 'gRPC')."
    ]
  ]

  # ============================================================================
  # Creation
  # ============================================================================

  @doc """
  Creates a new empty C4 model.

  ## Examples

      iex> c4 = Choreo.C4.new()
      iex> Choreo.C4.nodes(c4)
      []
      iex> Choreo.C4.edges(c4)
      []
      iex> c4.scope
      nil
  """
  @spec new() :: t()
  def new do
    %__MODULE__{
      graph: Yog.Multi.new(:directed),
      edge_meta: %{},
      clusters: %{},
      scope: nil
    }
  end

  # ============================================================================
  # Scope
  # ============================================================================

  @doc """
  Sets the in-scope node for drill-down diagrams.

  When generating a Container diagram, the scope is typically the
  software system being expanded. For a Component diagram, the scope
  is the container being expanded.

  ## Examples

      iex> c4 = Choreo.C4.new() |> Choreo.C4.add_software_system(:banking, scope: :in)
      iex> c4 = Choreo.C4.set_scope(c4, :banking)
      iex> c4.scope
      :banking
  """
  @spec set_scope(t(), Yog.node_id()) :: t()
  def set_scope(%__MODULE__{} = c4, scope_id) do
    unless Map.has_key?(c4.graph.nodes, scope_id) do
      raise ArgumentError, "Scope node #{inspect(scope_id)} does not exist"
    end

    %{c4 | scope: scope_id}
  end

  @doc """
  Clears the current scope.

  ## Examples

      iex> c4 = Choreo.C4.new() |> Choreo.C4.add_software_system(:banking)
      iex> c4 = Choreo.C4.set_scope(c4, :banking)
      iex> c4 = Choreo.C4.clear_scope(c4)
      iex> c4.scope
      nil
  """
  @spec clear_scope(t()) :: t()
  def clear_scope(%__MODULE__{} = c4), do: %{c4 | scope: nil}

  # ============================================================================
  # Node builders — L1 System Context
  # ============================================================================

  @doc """
  Adds a person (user, actor, or role).

  ## Options

  #{NimbleOptions.docs(@add_person_schema)}

  ## Examples

      iex> c4 = Choreo.C4.new() |> Choreo.C4.add_person(:customer, label: "Customer")
      iex> :customer in Choreo.C4.nodes(c4)
      true
      iex> Map.get(c4.graph.nodes, :customer).node_type
      :person
  """
  @spec add_person(t(), Yog.node_id(), keyword()) :: t()
  def add_person(%__MODULE__{} = c4, id, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @add_person_schema)
    add_typed_node(c4, id, :person, opts)
  end

  @doc """
  Adds a software system.

  ## Options

  #{NimbleOptions.docs(@add_software_system_schema)}

  ## Examples

      iex> c4 = Choreo.C4.new() |> Choreo.C4.add_software_system(:banking, label: "Banking", scope: :in)
      iex> :banking in Choreo.C4.nodes(c4)
      true
      iex> Map.get(c4.graph.nodes, :banking).node_type
      :software_system
      iex> Map.get(c4.graph.nodes, :banking).scope
      :in
  """
  @spec add_software_system(t(), Yog.node_id(), keyword()) :: t()
  def add_software_system(%__MODULE__{} = c4, id, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @add_software_system_schema)
    add_typed_node(c4, id, :software_system, opts)
  end

  # ============================================================================
  # Node builders — L2 Containers
  # ============================================================================

  @doc """
  Adds a container (application or data store within a software system).

  ## Options

  #{NimbleOptions.docs(@add_container_schema)}

  ## Examples

      iex> c4 = Choreo.C4.new()
      ...>   |> Choreo.C4.add_software_system(:banking)
      ...>   |> Choreo.C4.add_container(:api, label: "API", technology: "Phoenix", parent: :banking)
      iex> :api in Choreo.C4.nodes(c4)
      true
      iex> Map.get(c4.graph.nodes, :api).node_type
      :container
      iex> Map.get(c4.graph.nodes, :api).parent
      :banking
  """
  @spec add_container(t(), Yog.node_id(), keyword()) :: t()
  def add_container(%__MODULE__{} = c4, id, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @add_container_schema)
    add_typed_node(c4, id, :container, opts)
  end

  # ============================================================================
  # Node builders — L3 Components
  # ============================================================================

  @doc """
  Adds a component (building block inside a container).

  ## Options

  #{NimbleOptions.docs(@add_component_schema)}

  ## Examples

      iex> c4 = Choreo.C4.new()
      ...>   |> Choreo.C4.add_software_system(:banking)
      ...>   |> Choreo.C4.add_container(:api, parent: :banking)
      ...>   |> Choreo.C4.add_component(:auth, label: "Auth Controller", technology: "Phoenix", parent: :api)
      iex> :auth in Choreo.C4.nodes(c4)
      true
      iex> Map.get(c4.graph.nodes, :auth).node_type
      :component
      iex> Map.get(c4.graph.nodes, :auth).parent
      :api
  """
  @spec add_component(t(), Yog.node_id(), keyword()) :: t()
  def add_component(%__MODULE__{} = c4, id, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @add_component_schema)
    add_typed_node(c4, id, :component, opts)
  end

  # ============================================================================
  # Clusters
  # ============================================================================

  @doc """
  Defines a cluster (subgraph) for grouping nodes visually.

  In C4 diagrams clusters are often used to group containers by
  their parent software system or components by their parent container.

  ## Options

  #{NimbleOptions.docs(@add_cluster_schema)}

  ## Examples

      iex> c4 = Choreo.C4.new() |> Choreo.C4.add_cluster("banking", label: "Internet Banking")
      iex> c4.clusters["cluster_banking"].label
      "Internet Banking"
  """
  @spec add_cluster(t(), String.t() | atom(), keyword()) :: t()
  def add_cluster(%__MODULE__{} = c4, name, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @add_cluster_schema)
    name = Choreo.Internal.ensure_cluster_prefix(name)
    cluster = Map.new(opts)
    clusters = Map.put(c4.clusters, name, cluster)
    %{c4 | clusters: clusters}
  end

  # ============================================================================
  # Relationship builder
  # ============================================================================

  @doc """
  Adds a relationship (directed edge) between two C4 elements.

  ## Options

  #{NimbleOptions.docs(@add_relationship_schema)}

  ## Examples

      iex> c4 = Choreo.C4.new()
      ...>   |> Choreo.C4.add_person(:customer)
      ...>   |> Choreo.C4.add_software_system(:banking)
      ...>   |> Choreo.C4.add_relationship(:customer, :banking, label: "Uses")
      iex> Choreo.C4.edges(c4)
      [{:customer, :banking, 1}]
  """
  @spec add_relationship(t(), Yog.node_id(), Yog.node_id(), keyword()) :: t()
  def add_relationship(%__MODULE__{} = c4, from, to, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @add_relationship_schema)

    c4 =
      if Map.has_key?(c4.graph.nodes, from) do
        c4
      else
        add_software_system(c4, from, label: to_string(from))
      end

    c4 =
      if Map.has_key?(c4.graph.nodes, to) do
        c4
      else
        add_software_system(c4, to, label: to_string(to))
      end

    meta =
      opts
      |> Map.new()
      |> Map.put_new(:label, nil)

    {graph, edge_id} = Yog.Multi.add_edge(c4.graph, from, to, 1)
    edge_meta = Map.put(c4.edge_meta, edge_id, meta)

    %{c4 | graph: graph, edge_meta: edge_meta}
  end

  # ============================================================================
  # Queries
  # ============================================================================

  @doc """
  Returns all node IDs in the C4 model.

  ## Examples

      iex> c4 = Choreo.C4.new() |> Choreo.C4.add_person(:a) |> Choreo.C4.add_software_system(:b)
      iex> Enum.sort(Choreo.C4.nodes(c4))
      [:a, :b]
  """
  @spec nodes(t()) :: [Yog.node_id()]
  def nodes(%__MODULE__{graph: graph}), do: Map.keys(graph.nodes)

  @doc """
  Returns all edges as `{from, to, weight}` tuples.

  ## Examples

      iex> c4 = Choreo.C4.new()
      ...>   |> Choreo.C4.add_person(:a)
      ...>   |> Choreo.C4.add_software_system(:b)
      ...>   |> Choreo.C4.add_relationship(:a, :b)
      iex> Choreo.C4.edges(c4)
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

  ## Examples

      iex> c4 = Choreo.C4.new()
      ...>   |> Choreo.C4.add_person(:a)
      ...>   |> Choreo.C4.add_software_system(:b)
      ...>   |> Choreo.C4.add_relationship(:a, :b, label: "Uses")
      iex> [{_, _, _, meta}] = Choreo.C4.edges_with_meta(c4)
      iex> meta.label
      "Uses"
  """
  @spec edges_with_meta(t()) :: [{Yog.node_id(), Yog.node_id(), number(), map()}]
  def edges_with_meta(%__MODULE__{graph: graph, edge_meta: edge_meta}) do
    Enum.map(graph.edges, fn {edge_id, {from, to, weight}} ->
      {from, to, weight, Map.get(edge_meta, edge_id, %{})}
    end)
  end

  @doc """
  Returns all nodes of a given C4 type.

  ## Examples

      iex> c4 = Choreo.C4.new()
      ...>   |> Choreo.C4.add_person(:a)
      ...>   |> Choreo.C4.add_person(:b)
      ...>   |> Choreo.C4.add_software_system(:c)
      iex> Enum.sort(Choreo.C4.nodes_of_type(c4, :person))
      [:a, :b]
      iex> Choreo.C4.nodes_of_type(c4, :software_system)
      [:c]
  """
  @spec nodes_of_type(t(), atom()) :: [Yog.node_id()]
  def nodes_of_type(%__MODULE__{graph: graph}, type) do
    graph.nodes
    |> Enum.filter(fn {_id, data} -> data[:node_type] == type end)
    |> Enum.map(fn {id, _data} -> id end)
  end

  @doc """
  Returns the parent ID of a node, or `nil`.

  ## Examples

      iex> c4 = Choreo.C4.new()
      ...>   |> Choreo.C4.add_software_system(:banking)
      ...>   |> Choreo.C4.add_container(:api, parent: :banking)
      iex> Choreo.C4.parent(c4, :api)
      :banking
      iex> Choreo.C4.parent(c4, :banking)
      nil
  """
  @spec parent(t(), Yog.node_id()) :: Yog.node_id() | nil
  def parent(%__MODULE__{graph: graph}, id) do
    case Map.fetch(graph.nodes, id) do
      {:ok, data} -> data[:parent]
      :error -> nil
    end
  end

  @doc """
  Returns all children of a given parent node.

  ## Examples

      iex> c4 = Choreo.C4.new()
      ...>   |> Choreo.C4.add_software_system(:banking)
      ...>   |> Choreo.C4.add_container(:api, parent: :banking)
      ...>   |> Choreo.C4.add_container(:web, parent: :banking)
      iex> Enum.sort(Choreo.C4.children(c4, :banking))
      [:api, :web]
  """
  @spec children(t(), Yog.node_id()) :: [Yog.node_id()]
  def children(%__MODULE__{graph: graph}, parent_id) do
    graph.nodes
    |> Enum.filter(fn {_id, data} -> data[:parent] == parent_id end)
    |> Enum.map(fn {id, _data} -> id end)
    |> Enum.sort()
  end

  @doc """
  Returns the scope node ID, or `nil`.

  ## Examples

      iex> c4 = Choreo.C4.new() |> Choreo.C4.add_software_system(:banking)
      iex> c4 = Choreo.C4.set_scope(c4, :banking)
      iex> Choreo.C4.scope(c4)
      :banking
  """
  @spec scope(t()) :: Yog.node_id() | nil
  def scope(%__MODULE__{scope: scope}), do: scope

  @doc """
  Returns the raw `Yog.Multi.Graph` struct underpinning the model.

  ## Examples

      iex> c4 = Choreo.C4.new()
      iex> graph = Choreo.C4.to_graph(c4)
      iex> graph.kind
      :directed
  """
  @spec to_graph(t()) :: Yog.Multi.Graph.t()
  def to_graph(%__MODULE__{graph: graph}), do: graph

  # ============================================================================
  # Rendering
  # ============================================================================

  @doc """
  Renders the C4 model to DOT format.

  ## Options

    * `:theme` — `:default`, `:dark`, `:warm`, `:forest`, `:ocean`, or a `Choreo.Theme` struct
    * `:syntax` — `:default` (C4-style boxes) or `:nested` (clusters by parent)

  ## Examples

      iex> c4 = Choreo.C4.new() |> Choreo.C4.add_person(:a)
      iex> dot = Choreo.C4.to_dot(c4)
      iex> String.contains?(dot, "digraph")
      true
  """
  @spec to_dot(t(), keyword()) :: String.t()
  def to_dot(%__MODULE__{} = c4, opts \\ []) do
    Choreo.C4.Render.DOT.to_dot(c4, opts)
  end

  @doc """
  Renders the C4 model to Mermaid.js flowchart syntax.

  ## Options

    * `:theme` — `:default`, `:dark`, `:warm`, `:forest`, `:ocean`, or a `Choreo.Theme` struct
    * `:direction` — `:lr` (default), `:td`, `:rl`, `:bt`

  ## Examples

      iex> c4 = Choreo.C4.new() |> Choreo.C4.add_person(:a)
      iex> mermaid = Choreo.C4.to_mermaid(c4)
      iex> String.contains?(mermaid, "graph LR")
      true
  """
  @spec to_mermaid(t(), keyword()) :: String.t()
  def to_mermaid(%__MODULE__{} = c4, opts \\ []) do
    Choreo.C4.Render.Mermaid.to_mermaid(c4, opts)
  end

  @doc """
  Returns a theme for `Choreo.C4` diagrams.

  ## Examples

      iex> theme = Choreo.C4.theme(:default)
      iex> theme.name
      :c4_default
  """
  @spec theme(atom(), keyword()) :: Choreo.Theme.t()
  def theme(name \\ :default, overrides \\ []) do
    Choreo.C4.Render.DOT.theme(name, overrides)
  end

  # ============================================================================
  # Private helpers
  # ============================================================================

  defp add_typed_node(%__MODULE__{graph: graph} = c4, id, type, opts) do
    {parent, rest_opts} = Keyword.pop(opts, :parent)
    {scope, rest_opts} = Keyword.pop(rest_opts, :scope)

    data =
      rest_opts
      |> Map.new()
      |> Map.merge(%{
        type: :c4_element,
        node_type: type,
        label: Keyword.get(rest_opts, :label, to_string(id))
      })

    data = if parent, do: Map.put(data, :parent, parent), else: data
    data = if scope, do: Map.put(data, :scope, scope), else: data

    # Auto-assign to cluster based on parent if not explicitly clustered
    data =
      if not is_nil(parent) and not Map.has_key?(data, :cluster) do
        Map.put(data, :cluster, Choreo.Internal.ensure_cluster_prefix(parent))
      else
        data
      end

    %{c4 | graph: Yog.Multi.add_node(graph, id, data)}
  end
end

# ============================================================================
# Protocol implementations
# ============================================================================

defimpl Choreo.Viewable, for: Choreo.C4 do
  def rebuild(c4, new_graph) do
    new_edge_meta = Map.take(c4.edge_meta, Map.keys(new_graph.edges))

    existing_ids = MapSet.new(Map.keys(new_edge_meta))

    new_edge_meta =
      Enum.reduce(Map.keys(new_graph.edges), new_edge_meta, fn eid, acc ->
        if MapSet.member?(existing_ids, eid) do
          acc
        else
          Map.put(acc, eid, virtual_edge_meta(c4))
        end
      end)

    new_scope =
      if c4.scope && Map.has_key?(new_graph.nodes, c4.scope) do
        c4.scope
      else
        nil
      end

    %{c4 | graph: new_graph, edge_meta: new_edge_meta, scope: new_scope}
  end

  # Level 0 — System Context: people and software systems only
  def zoom_predicate(_c4, 0),
    do: fn _id, data -> data[:node_type] in [:person, :software_system] end

  # Level 1 — Container: context + containers
  def zoom_predicate(_c4, 1),
    do: fn _id, data -> data[:node_type] in [:person, :software_system, :container] end

  # Level 2 — Component: context + containers + components
  def zoom_predicate(_c4, 2),
    do: fn _id, data ->
      data[:node_type] in [:person, :software_system, :container, :component]
    end

  # Level 3+ — everything
  def zoom_predicate(_c4, _level), do: fn _id, _data -> true end

  def virtual_edge_meta(_c4), do: %{edge_type: :virtual, label: nil}
end

defimpl Choreo.DOT, for: Choreo.C4 do
  def to_dot(c4, opts), do: Choreo.C4.Render.DOT.to_dot(c4, opts)
end

defimpl Choreo.Mermaid, for: Choreo.C4 do
  def to_mermaid(c4, opts), do: Choreo.C4.Render.Mermaid.to_mermaid(c4, opts)
end
