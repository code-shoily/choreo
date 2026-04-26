defmodule Choreo.ThreatModel do
  @moduledoc """
  STRIDE threat-modeling builder on top of Yog.

  `Choreo.ThreatModel` extends dataflow diagrams with security
  semantics: trust boundaries, element classification, and automated
  STRIDE threat generation.

  ## When to use

  Use `Choreo.ThreatModel` during security review, threat-modeling
  sessions, or compliance audits. It automatically generates STRIDE
  threats, flags unencrypted boundary crossings, and surfaces attack
  paths from external entities to sensitive data stores.

  ## Element types (per Microsoft Threat Modeling Tool)

    * `:external_entity` — user, browser, third-party system (outside your control)
    * `:process` — application, service, function (code you own)
    * `:data_store` — database, file, cache, queue (data at rest)

  ## Trust boundaries

  Trust boundaries are clusters that group elements by security domain.
  Data flows that cross a boundary are automatically flagged for
  elevated scrutiny.

  ## Further reading

    * [STRIDE Model (Microsoft)](https://learn.microsoft.com/en-us/azure/security/develop/threat-modeling-tool-threats)
    * [Threat Modeling: Designing for Security (Shostack)](https://shostack.org/books/threat-modeling-book)
    * [OWASP Threat Modeling Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Threat_Modeling_Cheat_Sheet.html)
    * [Data Flow Diagrams for Threat Modeling](https://learn.microsoft.com/en-us/training/modules/tm-create-a-threat-model-using-foundational-data-flow-diagram-elements/)

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

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=LR, splines=spline, nodesep=0.6, ranksep=1.2];
      node [shape=box, style=filled, fillcolor="white", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [arrowhead=normal, color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];

      user [label="User", penwidth="2.0", fillcolor="#64748b", shape="box"];
      api [label="API Gateway", fillcolor="#3b82f6", shape="circle"];
      postgres [label="Postgres", fillcolor="#f59e0b", shape="cylinder"];

      subgraph cluster_app {
        label="Application";
        style=dashed;
        fillcolor="#f8fafc";
        color="#ef4444";
        api;
      }
      subgraph cluster_db {
        label="Database Zone";
        style=dashed;
        fillcolor="#f8fafc";
        color="#ef4444";
        postgres;
      }
      subgraph cluster_internet {
        label="Internet";
        style=dashed;
        fillcolor="#f8fafc";
        color="#ef4444";
        user;
      }
      user -> api [label="HTTPS request", style="dashed", penwidth="2.0", fontcolor="#ef4444", color="#ef4444"];
      api -> postgres [label="SQL query", style="dashed", penwidth="2.0", fontcolor="#ef4444", color="#ef4444"];
    }
  </div>
  """

  @type t :: %__MODULE__{
          graph: Yog.Multi.Graph.t(),
          edge_meta: %{optional(Yog.Multi.Graph.edge_id()) => map()},
          clusters: %{String.t() => map()}
        }

  defstruct graph: nil, edge_meta: %{}, clusters: %{}

  # ============================================================================
  # Creation
  # ============================================================================

  @doc """
  Creates a new empty threat model.

  ## Examples

      iex> model = Choreo.ThreatModel.new()
      iex> Choreo.ThreatModel.elements(model)
      []
      iex> Choreo.ThreatModel.flows(model)
      []
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

      iex> model = Choreo.ThreatModel.new()
      iex> model = Choreo.ThreatModel.add_trust_boundary(model, "dmz", label: "DMZ", level: 1)
      iex> model.clusters["cluster_dmz"].label
      "DMZ"
      iex> model.clusters["cluster_dmz"].level
      1
  """
  @spec add_trust_boundary(t(), String.t(), keyword()) :: t()
  def add_trust_boundary(%__MODULE__{} = model, name, opts \\ []) do
    name = Choreo.Internal.ensure_cluster_prefix(name)
    boundary = Map.new(opts)
    clusters = Map.put(model.clusters, name, boundary)
    %{model | clusters: clusters}
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

  ## Examples

      iex> model = Choreo.ThreatModel.new()
      iex> model = Choreo.ThreatModel.add_external_entity(model, :user, label: "User")
      iex> Choreo.ThreatModel.elements(model)
      [:user]
      iex> Map.get(model.graph.nodes, :user).element_type
      :external_entity
      iex> Map.get(model.graph.nodes, :user).label
      "User"

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=LR, splines=spline, nodesep=0.6, ranksep=1.2];
      node [shape=box, style=filled, fillcolor="white", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [arrowhead=normal, color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];

      user [label="User", penwidth="2.0", fillcolor="#64748b", shape="box"];
    }
  </div>
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

  ## Examples

      iex> model = Choreo.ThreatModel.new()
      iex> model = Choreo.ThreatModel.add_process(model, :api, label: "API", privilege: :admin)
      iex> Choreo.ThreatModel.elements(model)
      [:api]
      iex> Map.get(model.graph.nodes, :api).element_type
      :process
      iex> Map.get(model.graph.nodes, :api).privilege
      :admin

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=LR, splines=spline, nodesep=0.6, ranksep=1.2];
      node [shape=box, style=filled, fillcolor="white", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [arrowhead=normal, color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];

      api [label="API\n(admin)", fillcolor="#3b82f6", shape="circle"];
    }
  </div>
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

  ## Examples

      iex> model = Choreo.ThreatModel.new()
      iex> model = Choreo.ThreatModel.add_data_store(model, :db, label: "Postgres", sensitivity: :confidential)
      iex> Choreo.ThreatModel.elements(model)
      [:db]
      iex> Map.get(model.graph.nodes, :db).element_type
      :data_store
      iex> Map.get(model.graph.nodes, :db).sensitivity
      :confidential

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=LR, splines=spline, nodesep=0.6, ranksep=1.2];
      node [shape=box, style=filled, fillcolor="white", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [arrowhead=normal, color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];

      db [label="Postgres\n[confidential]", fillcolor="#f59e0b", shape="cylinder"];
    }
  </div>
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

      iex> model = Choreo.ThreatModel.new()
      iex> model = model
      ...>   |> Choreo.ThreatModel.add_external_entity(:user)
      ...>   |> Choreo.ThreatModel.add_process(:api)
      ...>   |> Choreo.ThreatModel.data_flow(:user, :api, label: "request")
      iex> Choreo.ThreatModel.flows(model)
      [{:user, :api, "request"}]
      iex> [{_, _, _, meta}] = Choreo.ThreatModel.edges_with_meta(model)
      iex> meta.label
      "request"
      iex> meta.encrypted
      false

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=LR, splines=spline, nodesep=0.6, ranksep=1.2];
      node [shape=box, style=filled, fillcolor="white", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [arrowhead=normal, color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];

      user [label="user", penwidth="2.0", fillcolor="#64748b", shape="box"];
      api [label="api", fillcolor="#3b82f6", shape="circle"];

      user -> api [label="request", penwidth="1.0", fontcolor="#64748b", color="#64748b"];
    }
  </div>
  """
  @spec data_flow(t(), Yog.node_id(), Yog.node_id(), keyword()) :: t()
  def data_flow(%__MODULE__{} = model, from, to, opts \\ []) do
    label = opts[:label] || ""

    meta =
      opts
      |> Map.new()
      |> Map.put(:label, label)
      |> Map.put_new(:encrypted, false)

    {graph, edge_id} = Yog.Multi.add_edge(model.graph, from, to, label)
    edge_meta = Map.put(model.edge_meta, edge_id, meta)

    %{model | graph: graph, edge_meta: edge_meta}
  end

  # ============================================================================
  # Queries
  # ============================================================================

  @doc """
  Returns all element IDs in the model.

  ## Examples

      iex> model = Choreo.ThreatModel.new()
      iex> model = model
      ...>   |> Choreo.ThreatModel.add_external_entity(:user)
      ...>   |> Choreo.ThreatModel.add_process(:api)
      iex> Enum.sort(Choreo.ThreatModel.elements(model))
      [:api, :user]
  """
  @spec elements(t()) :: [Yog.node_id()]
  def elements(%__MODULE__{graph: graph}) do
    Map.keys(graph.nodes)
  end

  @doc """
  Returns all data flows as `{from, to, label}` tuples.

  ## Examples

      iex> model = Choreo.ThreatModel.new()
      iex> model = model
      ...>   |> Choreo.ThreatModel.add_external_entity(:user)
      ...>   |> Choreo.ThreatModel.add_process(:api)
      ...>   |> Choreo.ThreatModel.data_flow(:user, :api)
      iex> Choreo.ThreatModel.flows(model)
      [{:user, :api, ""}]
  """
  @spec flows(t()) :: [{Yog.node_id(), Yog.node_id(), any()}]
  def flows(%__MODULE__{graph: graph}) do
    Enum.map(graph.edges, fn {_edge_id, {from, to, weight}} ->
      {from, to, weight}
    end)
  end

  @doc """
  Returns all edges with their metadata as `{from, to, weight, meta}` tuples.
  """
  @spec edges_with_meta(t()) :: [{Yog.node_id(), Yog.node_id(), any(), map()}]
  def edges_with_meta(%__MODULE__{graph: graph, edge_meta: edge_meta}) do
    Enum.map(graph.edges, fn {edge_id, {from, to, weight}} ->
      {from, to, weight, Map.get(edge_meta, edge_id, %{})}
    end)
  end

  @doc """
  Collapses parallel edges into a simple Graph for algorithm analysis.
  """
  @spec to_simple_graph(t(), keyword()) :: Yog.Graph.t()
  def to_simple_graph(%__MODULE__{graph: graph}, opts \\ []) do
    combine = Keyword.get(opts, :combine, fn a, _b -> a end)
    Yog.Multi.to_simple_graph(graph, combine)
  end

  @doc """
  Returns all elements of a given type.

  ## Examples

      iex> model = Choreo.ThreatModel.new()
      iex> model = model
      ...>   |> Choreo.ThreatModel.add_external_entity(:user)
      ...>   |> Choreo.ThreatModel.add_process(:api)
      iex> Choreo.ThreatModel.elements_of_type(model, :external_entity)
      [:user]
      iex> Choreo.ThreatModel.elements_of_type(model, :process)
      [:api]
      iex> Choreo.ThreatModel.elements_of_type(model, :data_store)
      []
  """
  @spec elements_of_type(t(), atom()) :: [Yog.node_id()]
  def elements_of_type(%__MODULE__{graph: graph}, type) do
    graph.nodes
    |> Enum.filter(fn {_id, data} -> data[:element_type] == type end)
    |> Enum.map(fn {id, _data} -> id end)
  end

  @doc """
  Returns the trust boundary name for an element, or `nil`.

  ## Examples

      iex> model = Choreo.ThreatModel.new()
      iex> model = model
      ...>   |> Choreo.ThreatModel.add_trust_boundary("app")
      ...>   |> Choreo.ThreatModel.add_process(:api, boundary: "app")
      iex> Choreo.ThreatModel.boundary_of(model, :api)
      "cluster_app"
  """
  @spec boundary_of(t(), Yog.node_id()) :: String.t() | nil
  def boundary_of(%__MODULE__{graph: graph}, id) do
    case Map.fetch(graph.nodes, id) do
      {:ok, data} -> data[:cluster]
      :error -> nil
    end
  end

  @doc """
  Returns the numeric trust level of an element's boundary, or `nil`.

  ## Examples

      iex> model = Choreo.ThreatModel.new()
      iex> model = model
      ...>   |> Choreo.ThreatModel.add_trust_boundary("dmz", level: 1)
      ...>   |> Choreo.ThreatModel.add_process(:api, boundary: "dmz")
      iex> Choreo.ThreatModel.trust_level(model, :api)
      1
  """
  @spec trust_level(t(), Yog.node_id()) :: integer() | nil
  def trust_level(%__MODULE__{clusters: clusters} = model, id) do
    case boundary_of(model, id) do
      nil -> nil
      name -> clusters[name][:level]
    end
  end

  @doc """
  Checks whether a data flow crosses a trust boundary.

  ## Examples

      iex> model = Choreo.ThreatModel.new()
      iex> model = model
      ...>   |> Choreo.ThreatModel.add_trust_boundary("internet", level: 0)
      ...>   |> Choreo.ThreatModel.add_trust_boundary("app", level: 2)
      ...>   |> Choreo.ThreatModel.add_external_entity(:user, boundary: "internet")
      ...>   |> Choreo.ThreatModel.add_process(:api, boundary: "app")
      ...>   |> Choreo.ThreatModel.add_process(:worker, boundary: "app")
      ...>   |> Choreo.ThreatModel.data_flow(:user, :api)
      ...>   |> Choreo.ThreatModel.data_flow(:api, :worker)
      iex> Choreo.ThreatModel.crosses_boundary?(model, :user, :api)
      true
      iex> Choreo.ThreatModel.crosses_boundary?(model, :api, :worker)
      false

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=LR, splines=spline, nodesep=0.6, ranksep=1.2];
      node [shape=box, style=filled, fillcolor="white", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [arrowhead=normal, color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];

      user [label="user", penwidth="2.0", fillcolor="#64748b", shape="box"];
      worker [label="worker", fillcolor="#3b82f6", shape="circle"];
      api [label="api", fillcolor="#3b82f6", shape="circle"];

      subgraph cluster_app {
        label="cluster_app";
        style=dashed;
        fillcolor="#f8fafc";
        color="#ef4444";
        worker;
        api;
      }
      subgraph cluster_internet {
        label="cluster_internet";
        style=dashed;
        fillcolor="#f8fafc";
        color="#ef4444";
        user;
      }
      user -> api [label="", style="dashed", penwidth="2.0", fontcolor="#ef4444", color="#ef4444"];
      api -> worker [label="", penwidth="1.0", fontcolor="#64748b", color="#64748b"];
    }
  </div>
  """
  @spec crosses_boundary?(t(), Yog.node_id(), Yog.node_id()) :: boolean()
  def crosses_boundary?(%__MODULE__{} = model, from, to) do
    from_boundary = boundary_of(model, from)
    to_boundary = boundary_of(model, to)

    from_boundary != to_boundary
  end

  @doc """
  Returns the raw `Yog.Graph` struct underpinning the model.

  ## Examples

      iex> model = Choreo.ThreatModel.new()
      iex> graph = Choreo.ThreatModel.to_graph(model)
      iex> graph.kind
      :directed
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

  ## Examples

      iex> model = Choreo.ThreatModel.new()
      iex> model = model
      ...>   |> Choreo.ThreatModel.add_external_entity(:user, label: "User")
      ...>   |> Choreo.ThreatModel.add_process(:api, label: "API")
      ...>   |> Choreo.ThreatModel.data_flow(:user, :api, label: "HTTPS")
      iex> dot = Choreo.ThreatModel.to_dot(model)
      iex> String.contains?(dot, "digraph")
      true
      iex> String.contains?(dot, "User")
      true
      iex> String.contains?(dot, "API")
      true
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

    # Merge arbitrary remaining options
    data = Map.merge(Map.new(rest_opts), data)

    data =
      if boundary,
        do: Map.put(data, :cluster, Choreo.Internal.ensure_cluster_prefix(boundary)),
        else: data

    %{model | graph: Yog.Multi.add_node(graph, id, data)}
  end
end
