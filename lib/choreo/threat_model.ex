defmodule Choreo.ThreatModel do
  @moduledoc """
  STRIDE threat-modeling builder on top of Yog.

  `Choreo.ThreatModel` extends dataflow diagrams with security
  semantics: trust boundaries, element classification, and automated
  STRIDE threat generation.

  ## Element types (per Microsoft Threat Modeling Tool)

    * `:external_entity` — user, browser, third-party system (outside your control)
    * `:process` — application, service, function (code you own)
    * `:data_store` — database, file, cache, queue (data at rest)

  ## Trust boundaries

  Trust boundaries are clusters that group elements by security domain.
  Data flows that cross a boundary are automatically flagged for
  elevated scrutiny.

  ## Quick Start

      model =
        Choreo.ThreatModel.new()
        |> Choreo.ThreatModel.add_trust_boundary("internet", label: "Internet", level: 0)
        |> Choreo.ThreatModel.add_trust_boundary("app", label: "Application", level: 2)
        |> Choreo.ThreatModel.add_trust_boundary("db", label: "Database Zone", level: 3)
        |> Choreo.ThreatModel.add_external_entity(:user, label: "User", boundary: "internet")
        |> Choreo.ThreatModel.add_process(:api, label: "API Gateway", boundary: "app")
        |> Choreo.ThreatModel.add_data_store(:postgres, label: "Postgres", boundary: "db")
        |> Choreo.ThreatModel.data_flow(:user, :api, label: "HTTPS request")
        |> Choreo.ThreatModel.data_flow(:api, :postgres, label: "SQL query")

      threats = Choreo.ThreatModel.Analysis.stride_threats(model)
      dot = Choreo.ThreatModel.to_dot(model)
  """

  @type t :: %__MODULE__{
          graph: Yog.graph(),
          edge_meta: %{optional({Yog.node_id(), Yog.node_id()}) => map()},
          boundaries: %{String.t() => map()}
        }

  defstruct graph: nil, edge_meta: %{}, boundaries: %{}

  # ============================================================================
  # Creation
  # ============================================================================

  @doc """
  Creates a new empty threat model.
  """
  @spec new() :: t()
  def new do
    %__MODULE__{
      graph: Yog.directed(),
      edge_meta: %{},
      boundaries: %{}
    }
  end

  # ============================================================================
  # Trust boundaries
  # ============================================================================

  @doc """
  Defines a trust boundary (security zone).

  ## Options

    * `:label` — display label
    * `:level` — numeric trust level (higher = more trusted)
    * `:style` — visual style override
    * `:color` — border colour override
    * `:fillcolor` — background colour override

  ## Examples

      model =
        Choreo.ThreatModel.new()
        |> Choreo.ThreatModel.add_trust_boundary("dmz", label: "DMZ", level: 1)
  """
  @spec add_trust_boundary(t(), String.t(), keyword()) :: t()
  def add_trust_boundary(%__MODULE__{} = model, name, opts \\ []) do
    name = ensure_boundary_prefix(name)
    boundary = Map.new(opts)
    boundaries = Map.put(model.boundaries, name, boundary)
    %{model | boundaries: boundaries}
  end

  # ============================================================================
  # Element builders
  # ============================================================================

  @doc """
  Adds an external entity (user, browser, third-party system).

  ## Options

    * `:label` — display label
    * `:description` — tooltip text
    * `:boundary` — trust boundary name
  """
  @spec add_external_entity(t(), Yog.node_id(), keyword()) :: t()
  def add_external_entity(model, id, opts \\ []) do
    add_typed_node(model, id, :external_entity, opts)
  end

  @doc """
  Adds a process (application, service, function).

  ## Options

    * `:label` — display label
    * `:description` — tooltip text
    * `:boundary` — trust boundary name
    * `:privilege` — privilege level (e.g., `:user`, `:admin`, `:system`)
  """
  @spec add_process(t(), Yog.node_id(), keyword()) :: t()
  def add_process(model, id, opts \\ []) do
    add_typed_node(model, id, :process, opts)
  end

  @doc """
  Adds a data store (database, file, cache, queue).

  ## Options

    * `:label` — display label
    * `:description` — tooltip text
    * `:boundary` — trust boundary name
    * `:sensitivity` — data sensitivity (`:public`, `:internal`, `:confidential`, `:restricted`)
  """
  @spec add_data_store(t(), Yog.node_id(), keyword()) :: t()
  def add_data_store(model, id, opts \\ []) do
    add_typed_node(model, id, :data_store, opts)
  end

  # ============================================================================
  # Edge builder
  # ============================================================================

  @doc """
  Creates a data-flow edge between two elements.

  ## Options

    * `:label` — display label
    * `:protocol` — `:http`, `:https`, `:grpc`, `:tcp`, `:udp`, etc.
    * `:encrypted` — whether the flow is encrypted (default: `false`)

  ## Examples

      model = Choreo.ThreatModel.data_flow(model, :user, :api, label: "Login", encrypted: true)
  """
  @spec data_flow(t(), Yog.node_id(), Yog.node_id(), keyword()) :: t()
  def data_flow(%__MODULE__{} = model, from, to, opts \\ []) do
    label = opts[:label] || ""

    meta =
      opts
      |> Map.new()
      |> Map.put(:label, label)
      |> Map.put_new(:encrypted, false)

    edge_meta = Map.put(model.edge_meta, {from, to}, meta)
    graph = Yog.add_edge_ensure(model.graph, from, to, label)

    %{model | graph: graph, edge_meta: edge_meta}
  end

  # ============================================================================
  # Queries
  # ============================================================================

  @doc """
  Returns all element IDs in the model.
  """
  @spec elements(t()) :: [Yog.node_id()]
  def elements(%__MODULE__{graph: graph}) do
    Map.keys(graph.nodes)
  end

  @doc """
  Returns all data flows as `{from, to, label}` tuples.
  """
  @spec flows(t()) :: [{Yog.node_id(), Yog.node_id(), number()}]
  def flows(%__MODULE__{graph: graph}) do
    Yog.all_edges(graph)
  end

  @doc """
  Returns all elements of a given type.
  """
  @spec elements_of_type(t(), atom()) :: [Yog.node_id()]
  def elements_of_type(%__MODULE__{graph: graph}, type) do
    graph.nodes
    |> Enum.filter(fn {_id, data} -> data[:element_type] == type end)
    |> Enum.map(fn {id, _data} -> id end)
  end

  @doc """
  Returns the trust boundary name for an element, or `nil`.
  """
  @spec boundary_of(t(), Yog.node_id()) :: String.t() | nil
  def boundary_of(%__MODULE__{graph: graph}, id) do
    case Map.fetch(graph.nodes, id) do
      {:ok, data} -> data[:boundary]
      :error -> nil
    end
  end

  @doc """
  Returns the numeric trust level of an element's boundary, or `nil`.
  """
  @spec trust_level(t(), Yog.node_id()) :: integer() | nil
  def trust_level(%__MODULE__{boundaries: boundaries} = model, id) do
    case boundary_of(model, id) do
      nil -> nil
      name -> boundaries[name][:level]
    end
  end

  @doc """
  Checks whether a data flow crosses a trust boundary.
  """
  @spec crosses_boundary?(t(), Yog.node_id(), Yog.node_id()) :: boolean()
  def crosses_boundary?(%__MODULE__{} = model, from, to) do
    from_boundary = boundary_of(model, from)
    to_boundary = boundary_of(model, to)

    from_boundary != nil and to_boundary != nil and from_boundary != to_boundary
  end

  @doc """
  Returns the raw `Yog.Graph` struct underpinning the model.
  """
  @spec to_graph(t()) :: Yog.graph()
  def to_graph(%__MODULE__{graph: graph}), do: graph

  # ============================================================================
  # Rendering
  # ============================================================================

  @doc """
  Renders the threat model to DOT format.

  ## Options

    * `:theme` — `:default`, `:dark`, or a `Choreo.Theme` struct
    * `:show_threats` — annotate edges with STRIDE threats (default: `false`)
  """
  @spec to_dot(t(), keyword()) :: String.t()
  def to_dot(%__MODULE__{} = model, opts \\ []) do
    Choreo.ThreatModel.Render.DOT.to_dot(model, opts)
  end

  # ============================================================================
  # Private helpers
  # ============================================================================

  defp add_typed_node(%__MODULE__{graph: graph} = model, id, type, opts) do
    {boundary, rest_opts} = Keyword.pop(opts, :boundary)

    data = %{
      type: :threat_model_element,
      element_type: type,
      label: Keyword.get(rest_opts, :label, to_string(id)),
      description: rest_opts[:description],
      privilege: rest_opts[:privilege],
      sensitivity: rest_opts[:sensitivity]
    }

    data = if boundary, do: Map.put(data, :boundary, ensure_boundary_prefix(boundary)), else: data

    %{model | graph: Yog.add_node(graph, id, data)}
  end

  defp ensure_boundary_prefix(name) do
    name = to_string(name)
    if String.starts_with?(name, "boundary_"), do: name, else: "boundary_#{name}"
  end
end
