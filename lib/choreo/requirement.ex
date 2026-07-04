defmodule Choreo.Requirement do
  @moduledoc """
  Requirements traceability diagram builder on top of Yog.

  `Choreo.Requirement` models software requirements, the components that
  satisfy them, the tests that verify them, and the stakeholders that own
  them. It is aimed at software architects who need practical traceability
  and risk analysis rather than strict SysML compliance.

  ## When to use

  Use `Choreo.Requirement` when you need to:

    * document feature requirements alongside the services and tests that
      implement them
  * find gaps in test coverage or implementation
  * propagate risk from high-level requirements down to components
  * perform impact analysis before a change

  ## Node types

    * `:requirement` — a need, feature, or constraint
    * `:component` — a service, module, or other implementation item
    * `:test` — a test or verification activity
    * `:stakeholder` — a person, team, or source of a requirement

  ## Edge types

    * `:satisfies` — component fulfills a requirement
    * `:verifies` — test proves a requirement
    * `:refines` — child requirement elaborates a parent requirement
    * `:depends` — requirement needs another requirement first
    * `:traces` — generic traceability link
    * `:contains` — parent requirement contains a child requirement
    * `:derives` — requirement is derived from another

  ## Quick start

      model =
        Choreo.Requirement.new("Auth v2")
        |> Choreo.Requirement.add_requirement(:mfa,
          id: "REQ-001",
          text: "Users must authenticate with MFA",
          risk: :high
        )
        |> Choreo.Requirement.add_component(:auth_service, label: "Auth Service")
        |> Choreo.Requirement.add_test(:mfa_test, label: "MFA login test")
        |> Choreo.Requirement.satisfies(:auth_service, :mfa)
        |> Choreo.Requirement.verifies(:mfa_test, :mfa)

      Choreo.Requirement.to_mermaid(model)
      Choreo.Requirement.to_dot(model)

  ## Analysis

      # Coverage gaps
      Choreo.Requirement.Analysis.coverage(model)

      # Risk propagation
      Choreo.Requirement.Analysis.high_risk_gaps(model)

      # Impact of changing a component
      Choreo.Requirement.Analysis.impact_of(model, :auth_service)

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=TB, splines=spline, nodesep=0.6, ranksep=1.2];
      node [shape=ellipse, style=filled, fillcolor="white", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];

      mfa [label="REQ-001\\nMFA", fillcolor="#f59e0b", shape="box"];
      auth_service [label="Auth Service", fillcolor="#3b82f6", shape="roundedbox"];
      mfa_test [label="MFA login test", fillcolor="#10b981", shape="stadium"];

      auth_service -> mfa [label="satisfies"];
      mfa_test -> mfa [label="verifies"];
    }
  </div>
  """

  @type t :: %__MODULE__{
          graph: Yog.Multi.Graph.t(),
          edge_meta: %{optional(Yog.Multi.Graph.edge_id()) => map()},
          name: String.t() | nil
        }

  defstruct graph: nil, edge_meta: %{}, name: nil

  @risk_levels [:low, :medium, :high, :critical]
  @verification_methods [:analysis, :inspection, :test, :demonstration]
  @requirement_kinds [
    :requirement,
    :functional,
    :interface,
    :performance,
    :physical,
    :design_constraint
  ]

  @node_schema [
    label: [
      type: :string,
      required: false,
      doc: "Display label (defaults to the node id)."
    ],
    type: [
      type: :string,
      required: false,
      doc: "Free-form type string for components/tests/stakeholders."
    ],
    docref: [
      type: :string,
      required: false,
      doc: "Optional documentation reference."
    ]
  ]

  @requirement_schema [
    id: [
      type: :string,
      required: true,
      doc: "Human-readable requirement identifier."
    ],
    text: [
      type: :string,
      required: true,
      doc: "Requirement description."
    ],
    risk: [
      type: {:in, @risk_levels},
      required: false,
      default: :medium,
      doc: "Risk level: :low, :medium, :high, or :critical."
    ],
    verification: [
      type: {:in, @verification_methods},
      required: false,
      default: :test,
      doc: "Verification method: :analysis, :inspection, :test, or :demonstration."
    ],
    kind: [
      type: {:in, @requirement_kinds},
      required: false,
      default: :requirement,
      doc:
        "Requirement kind: :requirement, :functional, :interface, :performance, :physical, or :design_constraint."
    ]
  ]

  @relate_schema [
    type: [
      type: :atom,
      required: false,
      default: :traces,
      doc: "Relationship type."
    ],
    label: [
      type: :string,
      required: false,
      doc: "Optional edge label used in DOT rendering."
    ]
  ]

  # ============================================================================
  # Creation
  # ============================================================================

  @doc """
  Creates a new empty requirements diagram.

  Accepts an optional name string or keyword options.

  ## Examples

      iex> req = Choreo.Requirement.new("Auth v2")
      iex> req.name
      "Auth v2"
      iex> req.graph.kind
      :directed
  """
  @spec new(keyword() | String.t() | nil) :: t()
  def new(name_or_opts \\ [])

  def new(nil), do: new([])

  def new(name) when is_binary(name) do
    %__MODULE__{
      name: name,
      graph: Yog.Multi.directed(),
      edge_meta: %{}
    }
  end

  def new(opts) when is_list(opts) do
    %__MODULE__{
      name: Keyword.get(opts, :name),
      graph: Yog.Multi.directed(),
      edge_meta: %{}
    }
  end

  # ============================================================================
  # Node builders
  # ============================================================================

  @doc """
  Adds a requirement node.

  ## Options

  #{NimbleOptions.docs(@requirement_schema)}

  ## Examples

      iex> req = Choreo.Requirement.new()
      ...>   |> Choreo.Requirement.add_requirement(:mfa,
      ...>     id: "REQ-001",
      ...>     text: "Users must authenticate with MFA",
      ...>     risk: :high
      ...>   )
      iex> Choreo.Requirement.node(req, :mfa).id
      "REQ-001"
      iex> Choreo.Requirement.node(req, :mfa).risk
      :high
  """
  @spec add_requirement(t(), Yog.node_id(), keyword()) :: t()
  def add_requirement(%__MODULE__{} = req, id, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @requirement_schema)

    data =
      opts
      |> Map.new()
      |> Map.merge(%{
        node_type: :requirement,
        label: Keyword.get(opts, :id, to_string(id))
      })

    %{req | graph: Yog.Multi.add_node(req.graph, id, data)}
  end

  @doc """
  Adds a component node.

  Components are implementation items (services, modules, libraries) that
  satisfy requirements.

  ## Options

  #{NimbleOptions.docs(@node_schema)}

  ## Examples

      iex> req = Choreo.Requirement.new()
      ...>   |> Choreo.Requirement.add_component(:auth, label: "Auth Service")
      iex> Choreo.Requirement.components(req)
      [:auth]
  """
  @spec add_component(t(), Yog.node_id(), keyword()) :: t()
  def add_component(%__MODULE__{} = req, id, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @node_schema)
    data = node_data(:component, id, opts)
    %{req | graph: Yog.Multi.add_node(req.graph, id, data)}
  end

  @doc """
  Adds a test node.

  Tests verify requirements.

  ## Options

  #{NimbleOptions.docs(@node_schema)}

  ## Examples

      iex> req = Choreo.Requirement.new()
      ...>   |> Choreo.Requirement.add_test(:t1, label: "Login test")
      iex> Choreo.Requirement.tests(req)
      [:t1]
  """
  @spec add_test(t(), Yog.node_id(), keyword()) :: t()
  def add_test(%__MODULE__{} = req, id, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @node_schema)
    data = node_data(:test, id, opts)
    %{req | graph: Yog.Multi.add_node(req.graph, id, data)}
  end

  @doc """
  Adds a stakeholder node.

  Stakeholders are people, teams, or sources of requirements.

  ## Options

  #{NimbleOptions.docs(@node_schema)}

  ## Examples

      iex> req = Choreo.Requirement.new()
      ...>   |> Choreo.Requirement.add_stakeholder(:security, label: "Security Team")
      iex> Choreo.Requirement.stakeholders(req)
      [:security]
  """
  @spec add_stakeholder(t(), Yog.node_id(), keyword()) :: t()
  def add_stakeholder(%__MODULE__{} = req, id, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @node_schema)
    data = node_data(:stakeholder, id, opts)
    %{req | graph: Yog.Multi.add_node(req.graph, id, data)}
  end

  # ============================================================================
  # Relationship builders
  # ============================================================================

  @doc """
  Creates a `satisfies` relationship: a component fulfills a requirement.

  ## Examples

      iex> req = Choreo.Requirement.new()
      ...>   |> Choreo.Requirement.add_component(:auth)
      ...>   |> Choreo.Requirement.add_requirement(:mfa, id: "REQ-001", text: "MFA")
      ...>   |> Choreo.Requirement.satisfies(:auth, :mfa)
      iex> [{:auth, :mfa, _}] = Choreo.Requirement.edges(req)
  """
  @spec satisfies(t(), Yog.node_id(), Yog.node_id(), keyword()) :: t()
  def satisfies(%__MODULE__{} = req, component, requirement, opts \\ []) do
    add_relationship(req, component, requirement, :satisfies, opts)
  end

  @doc """
  Creates a `verifies` relationship: a test proves a requirement.
  """
  @spec verifies(t(), Yog.node_id(), Yog.node_id(), keyword()) :: t()
  def verifies(%__MODULE__{} = req, test, requirement, opts \\ []) do
    add_relationship(req, test, requirement, :verifies, opts)
  end

  @doc """
  Creates a `refines` relationship: a child requirement elaborates a parent.
  """
  @spec refines(t(), Yog.node_id(), Yog.node_id(), keyword()) :: t()
  def refines(%__MODULE__{} = req, child, parent, opts \\ []) do
    add_relationship(req, child, parent, :refines, opts)
  end

  @doc """
  Creates a `depends` relationship: a requirement needs another requirement first.
  """
  @spec depends(t(), Yog.node_id(), Yog.node_id(), keyword()) :: t()
  def depends(%__MODULE__{} = req, requirement, prerequisite, opts \\ []) do
    add_relationship(req, requirement, prerequisite, :depends, opts)
  end

  @doc """
  Creates a generic `traces` relationship.
  """
  @spec traces(t(), Yog.node_id(), Yog.node_id(), keyword()) :: t()
  def traces(%__MODULE__{} = req, from, to, opts \\ []) do
    add_relationship(req, from, to, :traces, opts)
  end

  @doc """
  Creates a `contains` relationship: a parent requirement contains a child.
  """
  @spec contains(t(), Yog.node_id(), Yog.node_id(), keyword()) :: t()
  def contains(%__MODULE__{} = req, parent, child, opts \\ []) do
    add_relationship(req, parent, child, :contains, opts)
  end

  @doc """
  Creates a `derives` relationship: a requirement is derived from another.
  """
  @spec derives(t(), Yog.node_id(), Yog.node_id(), keyword()) :: t()
  def derives(%__MODULE__{} = req, derived, source, opts \\ []) do
    add_relationship(req, derived, source, :derives, opts)
  end

  @doc """
  Creates a custom relationship between two nodes.

  ## Options

  #{NimbleOptions.docs(@relate_schema)}

  ## Examples

      iex> req = Choreo.Requirement.new()
      ...>   |> Choreo.Requirement.add_component(:auth)
      ...>   |> Choreo.Requirement.add_requirement(:mfa, id: "REQ-001", text: "MFA")
      ...>   |> Choreo.Requirement.relate(:auth, :mfa, type: :implements)
      iex> meta = req.edge_meta |> Map.values() |> List.first()
      iex> meta.type
      :implements
  """
  @spec relate(t(), Yog.node_id(), Yog.node_id(), keyword()) :: t()
  def relate(%__MODULE__{} = req, from, to, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @relate_schema)
    type = opts[:type]
    add_relationship(req, from, to, type, opts)
  end

  defp add_relationship(%__MODULE__{} = req, from, to, type, opts) do
    opts = NimbleOptions.validate!(opts, @relate_schema)
    label = Keyword.get(opts, :label, to_string(type))

    {graph, edge_id} = Yog.Multi.add_edge(req.graph, from, to, 1)

    meta = %{
      type: type,
      label: label
    }

    %{req | graph: graph, edge_meta: Map.put(req.edge_meta, edge_id, meta)}
  end

  # ============================================================================
  # Queries
  # ============================================================================

  @doc """
  Returns the diagram name, or `nil` if not set.
  """
  @spec name(t()) :: String.t() | nil
  def name(%__MODULE__{name: name}), do: name

  @doc """
  Returns all node IDs in the diagram.
  """
  @spec nodes(t()) :: [Yog.node_id()]
  def nodes(%__MODULE__{graph: graph}) do
    Map.keys(graph.nodes)
  end

  @doc """
  Returns all requirement node IDs.
  """
  @spec requirements(t()) :: [Yog.node_id()]
  def requirements(%__MODULE__{graph: graph}) do
    graph.nodes
    |> Enum.filter(fn {_id, data} -> data[:node_type] == :requirement end)
    |> Enum.map(fn {id, _data} -> id end)
  end

  @doc """
  Returns all component node IDs.
  """
  @spec components(t()) :: [Yog.node_id()]
  def components(%__MODULE__{graph: graph}) do
    graph.nodes
    |> Enum.filter(fn {_id, data} -> data[:node_type] == :component end)
    |> Enum.map(fn {id, _data} -> id end)
  end

  @doc """
  Returns all test node IDs.
  """
  @spec tests(t()) :: [Yog.node_id()]
  def tests(%__MODULE__{graph: graph}) do
    graph.nodes
    |> Enum.filter(fn {_id, data} -> data[:node_type] == :test end)
    |> Enum.map(fn {id, _data} -> id end)
  end

  @doc """
  Returns all stakeholder node IDs.
  """
  @spec stakeholders(t()) :: [Yog.node_id()]
  def stakeholders(%__MODULE__{graph: graph}) do
    graph.nodes
    |> Enum.filter(fn {_id, data} -> data[:node_type] == :stakeholder end)
    |> Enum.map(fn {id, _data} -> id end)
  end

  @doc """
  Returns all edges as `{from, to, weight}` tuples.
  """
  @spec edges(t()) :: [{Yog.node_id(), Yog.node_id(), number()}]
  def edges(%__MODULE__{graph: graph}) do
    graph.edges
    |> Enum.sort_by(fn {edge_id, _} -> edge_id end)
    |> Enum.map(fn {_edge_id, {from, to, weight}} -> {from, to, weight} end)
  end

  @doc """
  Returns all edges with their metadata as `{from, to, weight, meta}` tuples.
  """
  @spec edges_with_meta(t()) :: [{Yog.node_id(), Yog.node_id(), number(), map()}]
  def edges_with_meta(%__MODULE__{graph: graph, edge_meta: edge_meta}) do
    graph.edges
    |> Enum.map(fn {edge_id, {from, to, weight}} ->
      {from, to, weight, Map.get(edge_meta, edge_id, %{})}
    end)
  end

  @doc """
  Returns the raw node data for a given node ID.
  """
  @spec node(t(), Yog.node_id()) :: map() | nil
  def node(%__MODULE__{graph: graph}, id) do
    Map.get(graph.nodes, id)
  end

  @doc """
  Returns the raw `Yog.Multi.Graph` struct underpinning the diagram.
  """
  @spec to_graph(t()) :: Yog.Multi.Graph.t()
  def to_graph(%__MODULE__{graph: graph}), do: graph

  # ============================================================================
  # Rendering
  # ============================================================================

  @doc """
  Renders the requirements diagram to DOT format.

  ## Options

    * `:theme` — `:default`, `:dark`, `:warm`, `:forest`, `:ocean`, or a
      `Choreo.Theme` struct

  ## Examples

      iex> req = Choreo.Requirement.new() |> Choreo.Requirement.add_requirement(:a, id: "R1", text: "A")
      iex> dot = Choreo.Requirement.to_dot(req)
      iex> String.contains?(dot, "digraph")
      true
  """
  @spec to_dot(t(), keyword()) :: String.t()
  def to_dot(%__MODULE__{} = req, opts \\ []) do
    Choreo.Requirement.Render.DOT.to_dot(req, opts)
  end

  @doc """
  Renders the requirements diagram to Mermaid.js `requirementDiagram` syntax.

  ## Options

    * `:direction` — `:td` (default), `:lr`, `:rl`, `:bt`
    * `:theme` — used only for styling hints where supported

  ## Examples

      iex> req = Choreo.Requirement.new() |> Choreo.Requirement.add_requirement(:a, id: "R1", text: "A")
      iex> mermaid = Choreo.Requirement.to_mermaid(req)
      iex> String.contains?(mermaid, "requirementDiagram")
      true
  """
  @spec to_mermaid(t(), keyword()) :: String.t()
  def to_mermaid(%__MODULE__{} = req, opts \\ []) do
    Choreo.Requirement.Render.Mermaid.to_mermaid(req, opts)
  end

  @doc """
  Returns a theme for `Choreo.Requirement` diagrams.
  """
  @spec theme(atom(), keyword()) :: Choreo.Theme.t()
  def theme(name \\ :default, overrides \\ []) do
    Choreo.Requirement.Render.DOT.theme(name, overrides)
  end

  # ============================================================================
  # Private helpers
  # ============================================================================

  defp node_data(type, id, opts) do
    opts
    |> Map.new()
    |> Map.merge(%{
      node_type: type,
      label: Keyword.get(opts, :label, to_string(id))
    })
  end
end

defimpl Choreo.DOT, for: Choreo.Requirement do
  def to_dot(req, opts), do: Choreo.Requirement.Render.DOT.to_dot(req, opts)
end

defimpl Choreo.Mermaid, for: Choreo.Requirement do
  def to_mermaid(req, opts), do: Choreo.Requirement.Render.Mermaid.to_mermaid(req, opts)
end

defimpl Choreo.Viewable, for: Choreo.Requirement do
  def rebuild(req, new_graph) do
    existing_ids = MapSet.new(Map.keys(new_graph.edges))

    new_edge_meta =
      Enum.reduce(req.edge_meta, %{}, fn {edge_id, meta}, acc ->
        if MapSet.member?(existing_ids, edge_id) do
          Map.put(acc, edge_id, meta)
        else
          acc
        end
      end)

    new_edge_meta =
      Enum.reduce(Map.keys(new_graph.edges), new_edge_meta, fn edge_id, acc ->
        if Map.has_key?(acc, edge_id) do
          acc
        else
          Map.put(acc, edge_id, virtual_edge_meta(req))
        end
      end)

    %{req | graph: new_graph, edge_meta: new_edge_meta}
  end

  def zoom_predicate(req, 0) do
    fn id, data ->
      data[:node_type] == :requirement and not has_parent_requirement?(req, id)
    end
  end

  def zoom_predicate(_req, 1) do
    fn _id, data ->
      data[:node_type] == :requirement
    end
  end

  def zoom_predicate(_req, 2) do
    fn _id, data ->
      data[:node_type] in [:requirement, :component, :test, :stakeholder]
    end
  end

  def zoom_predicate(_req, _level) do
    fn _id, _data -> true end
  end

  defp has_parent_requirement?(req, id) do
    Enum.any?(req.graph.edges, fn {edge_id, {from, to, _weight}} ->
      meta = Map.get(req.edge_meta, edge_id, %{})

      (meta[:type] == :refines and from == id) or
        (meta[:type] == :contains and to == id)
    end)
  end

  def virtual_edge_meta(_req), do: %{type: :virtual, label: "virtual"}
end
