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

  alias Choreo.ThreatModel.Analysis

  @type t :: %__MODULE__{
          graph: Yog.Multi.Graph.t(),
          edge_meta: %{optional(Yog.Multi.Graph.edge_id()) => map()},
          clusters: %{String.t() => map()},
          strict: boolean(),
          highlighted_nodes: [Yog.node_id()],
          highlighted_edges: [Yog.Multi.Graph.edge_id() | {Yog.node_id(), Yog.node_id()}]
        }

  defstruct graph: nil,
            edge_meta: %{},
            clusters: %{},
            strict: false,
            highlighted_nodes: [],
            highlighted_edges: []

  @add_trust_boundary_schema [
    label: [
      type: :string,
      required: false
    ],
    level: [
      type: :integer,
      required: false
    ],
    style: [
      type: :string,
      required: false
    ],
    color: [
      type: :string,
      required: false
    ],
    fillcolor: [
      type: :string,
      required: false
    ]
  ]

  @node_schema [
    label: [
      type: :string,
      required: false
    ],
    description: [
      type: :string,
      required: false
    ],
    boundary: [
      type: :string,
      required: false
    ],
    shape: [
      type: :atom,
      required: false
    ],
    fillcolor: [
      type: :string,
      required: false
    ],
    fontcolor: [
      type: :string,
      required: false
    ],
    style: [
      type: :string,
      required: false
    ],
    penwidth: [
      type: {:or, [:integer, :float]},
      required: false
    ],
    image: [
      type: :string,
      required: false
    ]
  ]

  @add_external_entity_schema [
                                role: [
                                  type:
                                    {:in, [:anonymous, :user, :partner, :admin, :third_party]},
                                  required: false
                                ],
                                privilege: [
                                  type: {:in, [:none, :user, :admin, :system]},
                                  required: false
                                ],
                                controls: [
                                  type: {:list, :atom},
                                  required: false,
                                  default: []
                                ]
                              ] ++ @node_schema

  @add_process_schema [
                        privilege: [
                          type: {:in, [:none, :user, :admin, :system]},
                          required: false
                        ],
                        controls: [
                          type: {:list, :atom},
                          required: false,
                          default: []
                        ]
                      ] ++ @node_schema

  @add_data_store_schema [
                           sensitivity: [
                             type: {:in, [:public, :internal, :confidential, :restricted]},
                             required: false
                           ],
                           retention: [
                             type: {:or, [:integer, :string]},
                             required: false
                           ],
                           controls: [
                             type: {:list, :atom},
                             required: false,
                             default: []
                           ]
                         ] ++ @node_schema

  @data_flow_schema [
    label: [
      type: :string,
      required: false
    ],
    protocol: [
      type: {:or, [:atom, :string]},
      required: false
    ],
    encrypted: [
      type: :boolean,
      required: false,
      default: false
    ],
    authenticated: [
      type: :boolean,
      required: false,
      default: false
    ],
    data: [
      type: {:or, [:atom, :string]},
      required: false
    ],
    sensitivity: [
      type: {:in, [:public, :internal, :confidential, :restricted]},
      required: false
    ],
    controls: [
      type: {:list, :atom},
      required: false,
      default: []
    ]
  ]

  # ============================================================================
  # Creation
  # ============================================================================

  @doc """
  Creates a new empty threat model.

  ## Options

    * `:strict` — if `true`, `data_flow/4` raises when an endpoint does not
      already exist. Default `false` (auto-creates missing elements as `:process`).

  ## Examples

      iex> model = Choreo.ThreatModel.new()
      iex> Choreo.ThreatModel.elements(model)
      []
      iex> Choreo.ThreatModel.flows(model)
      []
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      graph: Yog.Multi.new(:directed),
      edge_meta: %{},
      clusters: %{},
      strict: Keyword.get(opts, :strict, false)
    }
  end

  # ============================================================================
  # Trust boundaries
  # ============================================================================

  @doc """
  Defines a trust boundary (security zone).

  ## Options

  #{NimbleOptions.docs(@add_trust_boundary_schema)}

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
    opts = NimbleOptions.validate!(opts, @add_trust_boundary_schema)
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

  #{NimbleOptions.docs(@add_external_entity_schema)}

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
  def add_external_entity(model, id, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @add_external_entity_schema)
    add_typed_node(model, id, :external_entity, opts)
  end

  @doc """
  Adds a process (application, service, function).

  ## Options

  #{NimbleOptions.docs(@add_process_schema)}

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
  def add_process(model, id, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @add_process_schema)
    add_typed_node(model, id, :process, opts)
  end

  @doc """
  Adds a data store (database, file, cache, queue).

  ## Options

  #{NimbleOptions.docs(@add_data_store_schema)}

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
  def add_data_store(model, id, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @add_data_store_schema)
    add_typed_node(model, id, :data_store, opts)
  end

  # ============================================================================
  # Edge builder
  # ============================================================================

  @doc """
  Creates a data-flow edge between two elements.

  ## Options

  #{NimbleOptions.docs(@data_flow_schema)}

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
  def data_flow(%__MODULE__{} = model, from, to, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @data_flow_schema)
    label = opts[:label] || ""

    if model.strict and not Map.has_key?(model.graph.nodes, from) do
      raise ArgumentError,
            "Source element #{inspect(from)} does not exist (strict mode is enabled)"
    end

    if model.strict and not Map.has_key?(model.graph.nodes, to) do
      raise ArgumentError,
            "Target element #{inspect(to)} does not exist (strict mode is enabled)"
    end

    model =
      if Map.has_key?(model.graph.nodes, from) do
        model
      else
        add_process(model, from, label: to_string(from))
      end

    model =
      if Map.has_key?(model.graph.nodes, to) do
        model
      else
        add_process(model, to, label: to_string(to))
      end

    meta =
      opts
      |> Map.new()
      |> Map.put(:label, label)
      |> Map.put_new(:encrypted, false)
      |> Map.put_new(:authenticated, false)
      |> Map.put_new(:controls, [])

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

  The internal `cluster_` prefix is stripped so the returned name matches
  the name originally passed to `add_trust_boundary/3`.

  ## Examples

      iex> model = Choreo.ThreatModel.new()
      iex> model = model
      ...>   |> Choreo.ThreatModel.add_trust_boundary("app")
      ...>   |> Choreo.ThreatModel.add_process(:api, boundary: "app")
      iex> Choreo.ThreatModel.boundary_of(model, :api)
      "app"
  """
  @spec boundary_of(t(), Yog.node_id()) :: String.t() | nil
  def boundary_of(%__MODULE__{graph: graph}, id) do
    case Map.fetch(graph.nodes, id) do
      {:ok, data} ->
        case data[:cluster] do
          nil -> nil
          name -> String.replace_prefix(name, "cluster_", "")
        end

      :error ->
        nil
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
      name -> Map.get(clusters, "cluster_#{name}", %{})[:level]
    end
  end

  @doc """
  Checks whether a data flow crosses a trust boundary.

  Returns `false` if either element has no assigned boundary, since a
  crossing requires both sides to be in defined security zones.

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

      api [label="api", fillcolor="#3b82f6", shape="circle"];
      user [label="user", penwidth="2.0", fillcolor="#64748b", shape="box"];
      worker [label="worker", fillcolor="#3b82f6", shape="circle"];

      subgraph cluster_app {
        label="app";
        style=dashed;
        fillcolor="#f8fafc";
        color="#ef4444";
        api;
        worker;
      }
      subgraph cluster_internet {
        label="internet";
        style=dashed;
        fillcolor="#f8fafc";
        color="#ef4444";
        user;
      }
      api -> worker [label="", penwidth="1.0", fontcolor="#64748b", color="#64748b"];
      user -> api [label="", style="dashed", penwidth="2.0", fontcolor="#ef4444", color="#ef4444"];
    }
  </div>
  """
  @spec crosses_boundary?(t(), Yog.node_id(), Yog.node_id()) :: boolean()
  def crosses_boundary?(%__MODULE__{} = model, from, to) do
    from_boundary = boundary_of(model, from)
    to_boundary = boundary_of(model, to)

    from_boundary != nil and to_boundary != nil and from_boundary != to_boundary
  end

  @doc """
  Identifies external entry points entering trusted zones.
  Delegates to `Choreo.ThreatModel.Analysis.entry_points/1`.
  """
  @spec entry_points(t()) :: [map()]
  def entry_points(%__MODULE__{} = model), do: Analysis.entry_points(model)

  @doc """
  Identifies egress exit points leaving trusted zones.
  Delegates to `Choreo.ThreatModel.Analysis.exit_points/1`.
  """
  @spec exit_points(t()) :: [map()]
  def exit_points(%__MODULE__{} = model), do: Analysis.exit_points(model)

  @doc """
  Computes the downstream blast radius if `element_id` is compromised.
  Delegates to `Choreo.ThreatModel.Analysis.blast_radius/2`.
  """
  @spec blast_radius(t(), Yog.node_id()) :: map()
  def blast_radius(%__MODULE__{} = model, element_id),
    do: Analysis.blast_radius(model, element_id)

  @doc """
  Calculates residual risk after applied controls.
  Delegates to `Choreo.ThreatModel.Analysis.residual_risk_score/2`.
  """
  @spec residual_risk_score(t(), keyword()) :: map()
  def residual_risk_score(%__MODULE__{} = model, opts \\ []),
    do: Analysis.residual_risk_score(model, opts)

  @doc """
  Returns inferred security control gaps.
  Delegates to `Choreo.ThreatModel.Analysis.control_gaps/1`.
  """
  @spec control_gaps(t()) :: [map()]
  def control_gaps(%__MODULE__{} = model), do: Analysis.control_gaps(model)

  @doc """
  Returns sensitive-data paths that can leave the system toward external entities.
  Delegates to `Choreo.ThreatModel.Analysis.exfiltration_paths/2`.
  """
  @spec exfiltration_paths(t(), keyword()) :: [[Yog.node_id()]]
  def exfiltration_paths(%__MODULE__{} = model, opts \\ []),
    do: Analysis.exfiltration_paths(model, opts)

  @doc """
  Summarises data flows between trust boundaries.
  Delegates to `Choreo.ThreatModel.Analysis.boundary_matrix/1`.
  """
  @spec boundary_matrix(t()) :: map()
  def boundary_matrix(%__MODULE__{} = model), do: Analysis.boundary_matrix(model)

  @doc """
  Returns prioritized security-review findings.
  Delegates to `Choreo.ThreatModel.Analysis.prioritized_findings/2`.
  """
  @spec prioritized_findings(t(), keyword()) :: [map()]
  def prioritized_findings(%__MODULE__{} = model, opts \\ []),
    do: Analysis.prioritized_findings(model, opts)

  @doc """
  Highlights attack paths in the model by setting `:highlighted_nodes` and `:highlighted_edges`.
  Delegates to `Choreo.ThreatModel.Analysis.highlight_attack_paths/2`.
  """
  @spec highlight_attack_paths(t(), keyword()) :: t()
  def highlight_attack_paths(%__MODULE__{} = model, opts \\ []),
    do: Analysis.highlight_attack_paths(model, opts)

  @doc """
  Clears the current scenario / attack path highlights.
  """
  @spec clear_highlight(t()) :: t()
  def clear_highlight(%__MODULE__{} = model),
    do: %{model | highlighted_nodes: [], highlighted_edges: []}

  @doc """
  Generates a GitHub Flavored Markdown threat table.
  Delegates to `Choreo.ThreatModel.Analysis.to_markdown/2`.
  """
  @spec to_markdown(t(), keyword()) :: String.t()
  def to_markdown(%__MODULE__{} = model, opts \\ []),
    do: Analysis.to_markdown(model, opts)

  @doc """
  Returns only unmitigated threats.
  Delegates to `Choreo.ThreatModel.Analysis.unmitigated_threats/2`.
  """
  @spec unmitigated_threats(t(), keyword()) :: [map()]
  def unmitigated_threats(%__MODULE__{} = model, opts \\ []),
    do: Analysis.unmitigated_threats(model, opts)

  @doc """
  Returns threats targeting a specific element or flow.
  Delegates to `Choreo.ThreatModel.Analysis.threats_for/3`.
  """
  @spec threats_for(t(), Yog.node_id() | {Yog.node_id(), Yog.node_id()}, keyword()) :: [map()]
  def threats_for(%__MODULE__{} = model, target, opts \\ []),
    do: Analysis.threats_for(model, target, opts)

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
    opts =
      opts
      |> Keyword.put_new(:highlighted_nodes, model.highlighted_nodes)
      |> Keyword.put_new(:highlighted_edges, model.highlighted_edges)

    Choreo.ThreatModel.Render.DOT.to_dot(model, opts)
  end

  @doc """
  Renders the threat model to Mermaid.js flowchart syntax.

  ## Options

    * `:theme` — `:default`, `:dark`, `:warm`, `:forest`, `:ocean`, or a `Choreo.Theme` struct
    * `:direction` — `:lr` (default), `:td`, `:rl`, `:bt`

  ## Examples

      iex> model = Choreo.ThreatModel.new()
      iex> model = model
      ...>   |> Choreo.ThreatModel.add_external_entity(:user, label: "User")
      ...>   |> Choreo.ThreatModel.add_process(:api, label: "API")
      ...>   |> Choreo.ThreatModel.data_flow(:user, :api, label: "HTTPS")
      iex> mermaid = Choreo.ThreatModel.to_mermaid(model)
      iex> String.contains?(mermaid, "graph LR")
      true
  """
  @spec to_mermaid(t(), keyword()) :: String.t()
  def to_mermaid(%__MODULE__{} = model, opts \\ []) do
    opts =
      opts
      |> Keyword.put_new(:highlighted_nodes, model.highlighted_nodes)
      |> Keyword.put_new(:highlighted_edges, model.highlighted_edges)

    Choreo.ThreatModel.Render.Mermaid.to_mermaid(model, opts)
  end

  @doc """
  Renders the data flows in a threat model to a Mermaid sequence diagram string.

  External entities render as `actor`, processes and data stores as `participant`.
  Unencrypted flows crossing trust boundaries use dashed arrows (`-->`) to
  visually flag insecure communication.

  ## Options

  No options are currently used, but the argument is reserved for future use.

  ## Examples

      iex> model = Choreo.ThreatModel.new()
      iex> model = Choreo.ThreatModel.add_external_entity(model, :user, label: "Customer")
      iex> model = Choreo.ThreatModel.add_process(model, :web_api, label: "Web API")
      iex> model = Choreo.ThreatModel.data_flow(model, :user, :web_api, label: "HTTPS login")
      iex> seq = Choreo.ThreatModel.to_sequence(model)
      iex> String.contains?(seq, "sequenceDiagram")
      true
      iex> String.contains?(seq, "actor user")
      true
  """
  @spec to_sequence(t(), keyword()) :: String.t()
  def to_sequence(%__MODULE__{} = model, opts \\ []) do
    Choreo.ThreatModel.Render.Mermaid.to_sequence(model, opts)
  end

  @doc """
  Renders the data flows in a threat model to a PlantUML sequence diagram string.

  ## Examples

      iex> model = Choreo.ThreatModel.new()
      iex> model = Choreo.ThreatModel.add_external_entity(model, :user, label: "Customer")
      iex> model = Choreo.ThreatModel.add_process(model, :web_api, label: "Web API")
      iex> model = Choreo.ThreatModel.data_flow(model, :user, :web_api, label: "HTTPS login")
      iex> puml = Choreo.ThreatModel.to_plantuml(model)
      iex> String.contains?(puml, "@startuml")
      true
      iex> String.contains?(puml, "user -> web_api")
      true
  """
  @spec to_plantuml(t(), keyword()) :: String.t()
  def to_plantuml(%__MODULE__{} = model, _opts \\ []) do
    Choreo.ThreatModel.Render.PlantUML.to_sequence(model)
  end

  @doc """
  Returns a theme for `Choreo.ThreatModel`.

  ## Examples

      iex> theme = Choreo.ThreatModel.theme(:default, graph_rankdir: :tb)
      iex> theme.graph_rankdir
      :tb
  """
  @spec theme(atom(), keyword()) :: Choreo.Theme.t()
  def theme(name \\ :default, overrides \\ []) do
    Choreo.ThreatModel.Render.DOT.theme(name, overrides)
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
      description: rest_opts[:description]
    }

    # Only include type-specific fields when they have meaning
    data =
      case type do
        :external_entity ->
          data
          |> Map.put(:role, rest_opts[:role])
          |> Map.put(:privilege, rest_opts[:privilege])
          |> Map.put(:controls, rest_opts[:controls] || [])

        :process ->
          data
          |> Map.put(:privilege, rest_opts[:privilege])
          |> Map.put(:controls, rest_opts[:controls] || [])

        :data_store ->
          data
          |> Map.put(:sensitivity, rest_opts[:sensitivity])
          |> Map.put(:retention, rest_opts[:retention])
          |> Map.put(:controls, rest_opts[:controls] || [])

        _ ->
          data
      end

    # Merge arbitrary remaining options (shape, fillcolor, etc.)
    data = Map.merge(Map.new(rest_opts), data)

    data =
      if boundary,
        do: Map.put(data, :cluster, Choreo.Internal.ensure_cluster_prefix(boundary)),
        else: data

    %{model | graph: Yog.Multi.add_node(graph, id, data)}
  end
end

defimpl Choreo.Viewable, for: Choreo.ThreatModel do
  def rebuild(diagram, new_graph) do
    # Keep edge_meta only for edges that still exist in the new graph
    new_edge_meta = Map.take(diagram.edge_meta, Map.keys(new_graph.edges))

    # Add virtual edge metadata for edges without metadata
    existing_ids = MapSet.new(Map.keys(new_edge_meta))

    new_edge_meta =
      Enum.reduce(Map.keys(new_graph.edges), new_edge_meta, fn eid, acc ->
        if MapSet.member?(existing_ids, eid) do
          acc
        else
          Map.put(acc, eid, virtual_edge_meta(diagram))
        end
      end)

    %{diagram | graph: new_graph, edge_meta: new_edge_meta}
  end

  def zoom_predicate(_, 0), do: fn _, d -> d[:element_type] == :external_entity end

  def zoom_predicate(_, 1),
    do: fn _, d -> d[:element_type] in [:external_entity, :process] end

  def zoom_predicate(_, _), do: fn _, _ -> true end

  def virtual_edge_meta(_), do: %{edge_type: :virtual, label: nil, encrypted: false}
end

defimpl Choreo.DOT, for: Choreo.ThreatModel do
  def to_dot(model, opts), do: Choreo.ThreatModel.Render.DOT.to_dot(model, opts)
end

defimpl Choreo.Mermaid, for: Choreo.ThreatModel do
  def to_mermaid(model, opts), do: Choreo.ThreatModel.Render.Mermaid.to_mermaid(model, opts)
end
