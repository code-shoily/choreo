defmodule Choreo.Dependency do
  @moduledoc """
  Software dependency graph builder on top of Yog.

  `Choreo.Dependency` models component relationships — modules, libraries,
  applications, interfaces, and tests — to help visualize and analyze coupling,
  layering, and circular dependencies.

  ## When to use

  Use `Choreo.Dependency` when refactoring a codebase, onboarding new
  developers, or enforcing architectural boundaries. It surfaces hidden
  cycles, measures instability, and identifies the deepest dependency chains
  that slow down builds and tests.

  ## Node types

    * `:application` — deployable service or app
    * `:library` — external or shared library
    * `:module` — internal code module
    * `:interface` — API, contract, or protocol definition
    * `:test` — test suite or spec

  ## Edge types

    * `:uses` — general dependency
    * `:imports` — explicit import / require
    * `:calls` — runtime function call
    * `:inherits` — inheritance / implementation
    * `:dev` — development-only dependency

  ## Further reading

    * [Dependency inversion principle](https://en.wikipedia.org/wiki/Dependency_inversion_principle)
    * [Circular dependency](https://en.wikipedia.org/wiki/Circular_dependency)
    * [Coupling (computer programming)](https://en.wikipedia.org/wiki/Coupling_(computer_programming))

  ## Quick Start

      deps =
        Choreo.Dependency.new()
        |> Choreo.Dependency.add_application(:api, label: "API Gateway")
        |> Choreo.Dependency.add_library(:phoenix, label: "Phoenix")
        |> Choreo.Dependency.add_module(:auth, label: "Auth Module")
        |> Choreo.Dependency.depends_on(:api, :phoenix, type: :uses)
        |> Choreo.Dependency.depends_on(:api, :auth, type: :calls)

      dot = Choreo.Dependency.to_dot(deps)

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=TB, splines=spline, nodesep=0.5, ranksep=1.0];
      node [shape=box, style=filled, fillcolor="white", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [arrowhead=normal, color="#64748b", style=solid, fontname="Helvetica", fontsize=9, penwidth=1.0];

      auth [label="Auth Module", fillcolor="#10b981", shape="box"];
      api [label="API Gateway", fillcolor="#3b82f6", shape="box3d"];
      phoenix [label="Phoenix", fillcolor="#f59e0b", shape="cylinder"];

      api -> auth [style="dotted", label="calls"];
      api -> phoenix [label="uses"];
    }
  </div>

  ## Analysis

      # Find circular dependencies
      Choreo.Dependency.Analysis.cyclic_dependencies(deps)
      #=> [[:repo, :service, :repo]]

      # Impact analysis: what breaks if :auth changes?
      Choreo.Dependency.Analysis.affected_by(deps, :auth)
      #=> [:api, :web]

      # Check layer violations
      layers = %{api: 3, web: 2, repo: 1}
      Choreo.Dependency.Analysis.layer_violations(deps, layers)
      #=> [{:repo, :api, "repo (layer 1) calls api (layer 3)"}]
  """

  @type t :: %__MODULE__{
          graph: Yog.Multi.Graph.t(),
          edge_meta: %{optional(Yog.Multi.Graph.edge_id()) => map()},
          clusters: %{String.t() => map()},
          strict: boolean()
        }

  defstruct graph: nil, edge_meta: %{}, clusters: %{}, strict: false

  @node_schema [
    label: [
      type: :string,
      required: false
    ],
    description: [
      type: :string,
      required: false
    ],
    cluster: [
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

  @add_application_schema @node_schema
  @add_library_schema @node_schema
  @add_module_schema @node_schema

  @add_interface_schema [
    label: [
      type: :string,
      required: false
    ],
    description: [
      type: :string,
      required: false
    ],
    cluster: [
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
    ]
  ]

  @add_test_schema [
    label: [
      type: :string,
      required: false
    ],
    description: [
      type: :string,
      required: false
    ],
    cluster: [
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
    ]
  ]

  @add_cluster_schema [
    parent: [
      type: :string,
      required: false
    ],
    label: [
      type: :string,
      required: false
    ],
    style: [
      type: :string,
      required: false
    ],
    fillcolor: [
      type: :string,
      required: false
    ],
    color: [
      type: :string,
      required: false
    ]
  ]

  @depends_on_schema [
    type: [
      type: {:in, [:uses, :imports, :calls, :inherits, :dev]},
      required: false
    ],
    label: [
      type: :string,
      required: false
    ]
  ]

  # ============================================================================
  # Creation
  # ============================================================================

  @doc """
  Creates a new empty dependency graph.

  Dependency graphs are always directed.

  ## Options

    * `:strict` — if `true`, `depends_on/4` raises when an endpoint does not
      already exist. Default `false` (auto-creates missing nodes as `:module`).

  ## Examples

      iex> deps = Choreo.Dependency.new()
      iex> Choreo.Dependency.nodes(deps)
      []
      iex> Choreo.Dependency.edges(deps)
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
  # Node builders
  # ============================================================================

  @doc """
  Adds an application node (deployable service or app).

  ## Options

  #{NimbleOptions.docs(@add_application_schema)}

  ## Examples

      iex> deps = Choreo.Dependency.new()
      iex> deps = Choreo.Dependency.add_application(deps, :api, label: "API")
      iex> Choreo.Dependency.nodes(deps)
      [:api]
      iex> Map.get(deps.graph.nodes, :api).node_type
      :application
      iex> Map.get(deps.graph.nodes, :api).label
      "API"

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=TB, splines=spline, nodesep=0.5, ranksep=1.0];
      node [shape=box, style=filled, fillcolor="white", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [arrowhead=normal, color="#64748b", style=solid, fontname="Helvetica", fontsize=9, penwidth=1.0];

      api [label="API Gateway", fillcolor="#3b82f6", shape="box3d"];
    }
  </div>
  """
  def add_application(deps, id, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @add_application_schema)
    add_typed_node(deps, id, :application, opts)
  end

  @doc """
  Adds a library node (external or shared dependency).

  ## Options

  #{NimbleOptions.docs(@add_library_schema)}

  ## Examples

      iex> deps = Choreo.Dependency.new()
      iex> deps = Choreo.Dependency.add_library(deps, :phx, label: "Phoenix")
      iex> Choreo.Dependency.nodes(deps)
      [:phx]
      iex> Map.get(deps.graph.nodes, :phx).node_type
      :library

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=TB, splines=spline, nodesep=0.5, ranksep=1.0];
      node [shape=box, style=filled, fillcolor="white", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [arrowhead=normal, color="#64748b", style=solid, fontname="Helvetica", fontsize=9, penwidth=1.0];

      phx [label="Phoenix", fillcolor="#f59e0b", shape="cylinder"];
    }
  </div>
  """
  def add_library(deps, id, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @add_library_schema)
    add_typed_node(deps, id, :library, opts)
  end

  @doc """
  Adds a module node (internal code unit).

  ## Options

  #{NimbleOptions.docs(@add_module_schema)}

  ## Examples

      iex> deps = Choreo.Dependency.new()
      iex> deps = Choreo.Dependency.add_module(deps, :auth)
      iex> Choreo.Dependency.nodes(deps)
      [:auth]
      iex> Map.get(deps.graph.nodes, :auth).node_type
      :module

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=TB, splines=spline, nodesep=0.5, ranksep=1.0];
      node [shape=box, style=filled, fillcolor="white", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [arrowhead=normal, color="#64748b", style=solid, fontname="Helvetica", fontsize=9, penwidth=1.0];

      auth [label="auth", fillcolor="#10b981", shape="box"];
    }
  </div>
  """
  def add_module(deps, id, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @add_module_schema)
    add_typed_node(deps, id, :module, opts)
  end

  @doc """
  Adds an interface node (API, contract, protocol).

  ## Options

  #{NimbleOptions.docs(@add_interface_schema)}

  ## Examples

      iex> deps = Choreo.Dependency.new()
      iex> deps = Choreo.Dependency.add_interface(deps, :contract)
      iex> Choreo.Dependency.nodes(deps)
      [:contract]
      iex> Map.get(deps.graph.nodes, :contract).node_type
      :interface

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=TB, splines=spline, nodesep=0.5, ranksep=1.0];
      node [shape=box, style=filled, fillcolor="white", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [arrowhead=normal, color="#64748b", style=solid, fontname="Helvetica", fontsize=9, penwidth=1.0];

      contract [label="contract", fillcolor="#8b5cf6", shape="diamond"];
    }
  </div>
  """
  def add_interface(deps, id, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @add_interface_schema)
    add_typed_node(deps, id, :interface, opts)
  end

  @doc """
  Adds a test node (test suite or spec).

  ## Options

  #{NimbleOptions.docs(@add_test_schema)}

  ## Examples

      iex> deps = Choreo.Dependency.new()
      iex> deps = Choreo.Dependency.add_test(deps, :auth_test)
      iex> Choreo.Dependency.nodes(deps)
      [:auth_test]
      iex> Map.get(deps.graph.nodes, :auth_test).node_type
      :test

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=TB, splines=spline, nodesep=0.5, ranksep=1.0];
      node [shape=box, style=filled, fillcolor="white", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [arrowhead=normal, color="#64748b", style=solid, fontname="Helvetica", fontsize=9, penwidth=1.0];

      auth_test [label="auth_test", fillcolor="#64748b", shape="note"];
    }
  </div>
  """
  def add_test(deps, id, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @add_test_schema)
    add_typed_node(deps, id, :test, opts)
  end

  # ============================================================================
  # Clusters
  # ============================================================================

  @doc """
  Defines a cluster for grouping nodes visually (e.g., by team or layer).

  ## Options

  #{NimbleOptions.docs(@add_cluster_schema)}

  ## Examples

      iex> deps = Choreo.Dependency.new()
      iex> deps = Choreo.Dependency.add_cluster(deps, "core", label: "Core")
      iex> deps.clusters["cluster_core"].label
      "Core"
  """
  @spec add_cluster(t(), String.t(), keyword()) :: t()
  def add_cluster(%__MODULE__{} = deps, name, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @add_cluster_schema)
    name = Choreo.Internal.ensure_cluster_prefix(name)
    cluster = Map.new(opts)
    clusters = Map.put(deps.clusters, name, cluster)
    %{deps | clusters: clusters}
  end

  # ============================================================================
  # Edge builders
  # ============================================================================

  @doc """
  Creates a dependency edge from one component to another.

  Direction reads as "`from` depends on `to`".

  Parallel edges are supported: the same `(from, to)` pair can be added
  multiple times with different `:type` values (e.g. `:uses` and `:dev`).

  ## Options

  #{NimbleOptions.docs(@depends_on_schema)}

  ## Examples

      iex> deps = Choreo.Dependency.new()
      iex> deps = deps
      ...>   |> Choreo.Dependency.add_application(:api)
      ...>   |> Choreo.Dependency.add_module(:auth)
      ...>   |> Choreo.Dependency.depends_on(:api, :auth)
      iex> [{_, _, _, meta}] = Choreo.Dependency.edges_with_meta(deps)
      iex> meta.type
      :uses

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=TB, splines=spline, nodesep=0.5, ranksep=1.0];
      node [shape=box, style=filled, fillcolor="white", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [arrowhead=normal, color="#64748b", style=solid, fontname="Helvetica", fontsize=9, penwidth=1.0];

      auth [label="auth", fillcolor="#10b981", shape="box"];
      api [label="api", fillcolor="#3b82f6", shape="box3d"];

      api -> auth [label="uses"];
    }
  </div>

      iex> deps = Choreo.Dependency.new()
      iex> deps = deps
      ...>   |> Choreo.Dependency.add_application(:api)
      ...>   |> Choreo.Dependency.add_module(:auth)
      ...>   |> Choreo.Dependency.depends_on(:api, :auth, type: :calls)
      iex> [{_, _, _, meta}] = Choreo.Dependency.edges_with_meta(deps)
      iex> meta.type
      :calls
      iex> meta.label
      "calls"
  """
  def depends_on(%__MODULE__{} = deps, from, to, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @depends_on_schema)
    type = Keyword.get(opts, :type, :uses)
    label = opts[:label] || type_to_label(type)

    if deps.strict and not Map.has_key?(deps.graph.nodes, from) do
      raise ArgumentError,
            "Source node #{inspect(from)} does not exist (strict mode is enabled)"
    end

    if deps.strict and not Map.has_key?(deps.graph.nodes, to) do
      raise ArgumentError,
            "Target node #{inspect(to)} does not exist (strict mode is enabled)"
    end

    deps =
      if Map.has_key?(deps.graph.nodes, from) do
        deps
      else
        add_module(deps, from, label: to_string(from))
      end

    deps =
      if Map.has_key?(deps.graph.nodes, to) do
        deps
      else
        add_module(deps, to, label: to_string(to))
      end

    meta =
      opts
      |> Map.new()
      |> Map.put(:type, type)
      |> Map.put(:label, label)

    {graph, edge_id} = Yog.Multi.add_edge(deps.graph, from, to, 1)
    edge_meta = Map.put(deps.edge_meta, edge_id, meta)

    %{deps | graph: graph, edge_meta: edge_meta}
  end

  # ============================================================================
  # Queries
  # ============================================================================

  @doc """
  Returns all node IDs in the dependency graph.

  ## Examples

      iex> deps = Choreo.Dependency.new()
      iex> deps = deps
      ...>   |> Choreo.Dependency.add_application(:api)
      ...>   |> Choreo.Dependency.add_module(:auth)
      iex> Enum.sort(Choreo.Dependency.nodes(deps))
      [:api, :auth]
  """
  @spec nodes(t()) :: [Yog.node_id()]
  def nodes(%__MODULE__{graph: graph}) do
    Map.keys(graph.nodes)
  end

  @doc """
  Returns all dependency edges as `{from, to, weight}` tuples.

  ## Examples

      iex> deps = Choreo.Dependency.new()
      iex> deps = deps
      ...>   |> Choreo.Dependency.add_application(:api)
      ...>   |> Choreo.Dependency.add_module(:auth)
      ...>   |> Choreo.Dependency.depends_on(:api, :auth)
      iex> Choreo.Dependency.edges(deps)
      [{:api, :auth, 1}]
  """
  @spec edges(t()) :: [{Yog.node_id(), Yog.node_id(), integer()}]
  def edges(%__MODULE__{graph: graph}) do
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
  Returns all nodes of a given type.

  ## Examples

      iex> deps = Choreo.Dependency.new()
      iex> deps = deps
      ...>   |> Choreo.Dependency.add_application(:a)
      ...>   |> Choreo.Dependency.add_application(:b)
      ...>   |> Choreo.Dependency.add_library(:c)
      iex> Enum.sort(Choreo.Dependency.nodes_of_type(deps, :application))
      [:a, :b]
      iex> Choreo.Dependency.nodes_of_type(deps, :library)
      [:c]
      iex> Choreo.Dependency.nodes_of_type(deps, :module)
      []
  """
  @spec nodes_of_type(t(), atom()) :: [Yog.node_id()]
  def nodes_of_type(%__MODULE__{graph: graph}, type) do
    graph.nodes
    |> Enum.filter(fn {_id, data} -> data[:node_type] == type end)
    |> Enum.map(fn {id, _data} -> id end)
  end

  @doc """
  Returns the raw `Yog.Graph` struct underpinning the dependency graph.

  ## Examples

      iex> deps = Choreo.Dependency.new()
      iex> graph = Choreo.Dependency.to_graph(deps)
      iex> graph.kind
      :directed
  """
  @spec to_graph(t()) :: Yog.graph()
  def to_graph(%__MODULE__{graph: graph}), do: graph

  # ============================================================================
  # Rendering
  # ============================================================================

  @doc """
  Renders the dependency graph to DOT format.

  ## Options

    * `:theme` — `:default`, `:dark`, `:minimal`, `:warm`, `:forest`, `:ocean`, or a `Choreo.Theme` struct
    * `:rankdir` — `:tb` (default), `:lr`, etc.
    * `:engine` — Graphviz layout engine (`"dot"`, `"neato"`, `"twopi"`, `"circo"`, `"fdp"`, etc.)
    * `:highlighted_nodes` — list of node IDs to highlight
    * `:highlighted_edges` — list of `{from, to}` tuples or edge IDs to highlight

  ## Examples

      iex> deps = Choreo.Dependency.new()
      iex> deps = deps
      ...>   |> Choreo.Dependency.add_application(:api, label: "API")
      ...>   |> Choreo.Dependency.add_module(:auth, label: "Auth")
      ...>   |> Choreo.Dependency.depends_on(:api, :auth)
      iex> dot = Choreo.Dependency.to_dot(deps)
      iex> String.contains?(dot, "digraph")
      true
      iex> String.contains?(dot, "API")
      true
      iex> String.contains?(dot, "Auth")
      true
  """
  @spec to_dot(t(), keyword()) :: String.t()
  def to_dot(%__MODULE__{} = deps, opts \\ []) do
    Choreo.Dependency.Render.DOT.to_dot(deps, opts)
  end

  @doc """
  Renders the dependency graph to Mermaid.js syntax.

  ## Options

    * `:syntax` — `:flowchart` (default) or `:class_diagram` (native `classDiagram` syntax)
    * `:theme` — `:default`, `:dark`, `:minimal`, `:warm`, `:forest`, `:ocean`, or a `Choreo.Theme` struct (for `:flowchart` syntax)
    * `:direction` — `:td` (default), `:lr`, `:bt`, `:rl`
    * `:highlighted_nodes` — list of node IDs to highlight (for `:flowchart` syntax)
    * `:highlighted_edges` — list of `{from, to}` tuples or edge IDs to highlight (for `:flowchart` syntax)

  ## Examples

      iex> deps = Choreo.Dependency.new()
      iex> deps = deps
      ...>   |> Choreo.Dependency.add_application(:api, label: "API")
      ...>   |> Choreo.Dependency.add_module(:auth, label: "Auth")
      ...>   |> Choreo.Dependency.depends_on(:api, :auth)
      iex> mermaid = Choreo.Dependency.to_mermaid(deps)
      iex> String.contains?(mermaid, "graph TD")
      true
  """
  @spec to_mermaid(t(), keyword()) :: String.t()
  def to_mermaid(%__MODULE__{} = deps, opts \\ []) do
    Choreo.Dependency.Render.Mermaid.to_mermaid(deps, opts)
  end

  @doc """
  Returns a theme for `Choreo.Dependency`.

  Supported theme names: `:default`, `:dark`, `:minimal`, `:warm`, `:forest`, `:ocean`.

  ## Examples

      iex> theme = Choreo.Dependency.theme(:default, graph_rankdir: :lr)
      iex> theme.graph_rankdir
      :lr
  """
  @spec theme(atom(), keyword()) :: Choreo.Theme.t()
  def theme(name \\ :default, overrides \\ []) do
    Choreo.Dependency.Render.DOT.theme(name, overrides)
  end

  # ============================================================================
  # Private helpers
  # ============================================================================

  defp add_typed_node(%__MODULE__{graph: graph} = deps, id, type, opts) do
    {cluster, rest_opts} = Keyword.pop(opts, :cluster)

    data =
      rest_opts
      |> Map.new()
      |> Map.merge(%{
        type: :dependency_node,
        node_type: type,
        label: Keyword.get(rest_opts, :label, to_string(id))
      })

    data =
      if cluster,
        do: Map.put(data, :cluster, Choreo.Internal.ensure_cluster_prefix(cluster)),
        else: data

    %{deps | graph: Yog.Multi.add_node(graph, id, data)}
  end

  defp type_to_label(:uses), do: "uses"
  defp type_to_label(:imports), do: "imports"
  defp type_to_label(:calls), do: "calls"
  defp type_to_label(:inherits), do: "inherits"
  defp type_to_label(:dev), do: "dev"
  defp type_to_label(_), do: ""
end

defimpl Choreo.Viewable, for: Choreo.Dependency do
  def rebuild(deps, new_graph) do
    # Keep edge_meta only for edges that still exist in the new graph
    new_edge_meta = Map.take(deps.edge_meta, Map.keys(new_graph.edges))

    # Add virtual edge metadata for edges without metadata
    existing_ids = MapSet.new(Map.keys(new_edge_meta))

    new_edge_meta =
      Enum.reduce(Map.keys(new_graph.edges), new_edge_meta, fn eid, acc ->
        if MapSet.member?(existing_ids, eid) do
          acc
        else
          Map.put(acc, eid, virtual_edge_meta(deps))
        end
      end)

    %{deps | graph: new_graph, edge_meta: new_edge_meta}
  end

  def zoom_predicate(_, 0), do: fn _, d -> d[:node_type] == :application end

  def zoom_predicate(_, 1),
    do: fn _, d -> d[:node_type] in [:application, :library] end

  def zoom_predicate(_, 2),
    do: fn _, d -> d[:node_type] in [:application, :library, :module] end

  def zoom_predicate(_, 3),
    do: fn _, d -> d[:node_type] in [:application, :library, :module, :interface] end

  def zoom_predicate(_, _), do: fn _, _ -> true end

  def virtual_edge_meta(_), do: %{edge_type: :virtual, label: nil, type: :uses}
end

defimpl Choreo.DOT, for: Choreo.Dependency do
  def to_dot(deps, opts), do: Choreo.Dependency.Render.DOT.to_dot(deps, opts)
end

defimpl Choreo.Mermaid, for: Choreo.Dependency do
  def to_mermaid(deps, opts), do: Choreo.Dependency.Render.Mermaid.to_mermaid(deps, opts)
end
