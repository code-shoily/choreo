defmodule Choreo.Dependency do
  @moduledoc """
  Software dependency graph builder on top of Yog.

  `Choreo.Dependency` models component relationships — modules, libraries,
  applications, interfaces, and tests — to help visualize and analyze coupling,
  layering, and circular dependencies.

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

  ## Quick Start

      deps =
        Choreo.Dependency.new()
        |> Choreo.Dependency.add_application(:api, label: "API Gateway")
        |> Choreo.Dependency.add_library(:phoenix, label: "Phoenix")
        |> Choreo.Dependency.add_module(:auth, label: "Auth Module")
        |> Choreo.Dependency.depends_on(:api, :phoenix, type: :uses)
        |> Choreo.Dependency.depends_on(:api, :auth, type: :calls)

      dot = Choreo.Dependency.to_dot(deps)

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
          graph: Yog.graph(),
          edge_meta: %{optional({Yog.node_id(), Yog.node_id()}) => map()},
          clusters: %{String.t() => map()}
        }

  defstruct graph: nil, edge_meta: %{}, clusters: %{}

  # ============================================================================
  # Creation
  # ============================================================================

  @doc """
  Creates a new empty dependency graph.

  Dependency graphs are always directed.
  """
  @spec new() :: t()
  def new do
    %__MODULE__{
      graph: Yog.directed(),
      edge_meta: %{},
      clusters: %{}
    }
  end

  # ============================================================================
  # Node builders
  # ============================================================================

  @doc """
  Adds an application node (deployable service or app).

  ## Options

    * `:label` — display label (defaults to the node id)
    * `:description` — tooltip text
    * `:cluster` — cluster name for grouping
  """
  @spec add_application(t(), Yog.node_id(), keyword()) :: t()
  def add_application(deps, id, opts \\ []) do
    add_typed_node(deps, id, :application, opts)
  end

  @doc """
  Adds a library node (external or shared dependency).

  ## Options

    * `:label` — display label (defaults to the node id)
    * `:description` — tooltip text
    * `:cluster` — cluster name for grouping
  """
  @spec add_library(t(), Yog.node_id(), keyword()) :: t()
  def add_library(deps, id, opts \\ []) do
    add_typed_node(deps, id, :library, opts)
  end

  @doc """
  Adds a module node (internal code unit).

  ## Options

    * `:label` — display label (defaults to the node id)
    * `:description` — tooltip text
    * `:cluster` — cluster name for grouping
  """
  @spec add_module(t(), Yog.node_id(), keyword()) :: t()
  def add_module(deps, id, opts \\ []) do
    add_typed_node(deps, id, :module, opts)
  end

  @doc """
  Adds an interface node (API, contract, protocol).

  ## Options

    * `:label` — display label (defaults to the node id)
    * `:description` — tooltip text
    * `:cluster` — cluster name for grouping
  """
  @spec add_interface(t(), Yog.node_id(), keyword()) :: t()
  def add_interface(deps, id, opts \\ []) do
    add_typed_node(deps, id, :interface, opts)
  end

  @doc """
  Adds a test node (test suite or spec).

  ## Options

    * `:label` — display label (defaults to the node id)
    * `:description` — tooltip text
    * `:cluster` — cluster name for grouping
  """
  @spec add_test(t(), Yog.node_id(), keyword()) :: t()
  def add_test(deps, id, opts \\ []) do
    add_typed_node(deps, id, :test, opts)
  end

  # ============================================================================
  # Clusters
  # ============================================================================

  @doc """
  Defines a cluster for grouping nodes visually (e.g., by team or layer).

  ## Options

    * `:parent` — name of the parent cluster for nesting
    * `:label` — display label (defaults to the cluster name)
    * `:style` — `:filled`, `:rounded`, etc.
    * `:fillcolor` — background colour
    * `:color` — border colour
  """
  @spec add_cluster(t(), String.t(), keyword()) :: t()
  def add_cluster(%__MODULE__{} = deps, name, opts \\ []) do
    name = ensure_cluster_prefix(name)
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

  ## Options

    * `:type` — `:uses`, `:imports`, `:calls`, `:inherits`, `:dev` (default: `:uses`)
    * `:label` — override label

  ## Examples

      deps = Choreo.Dependency.depends_on(deps, :api, :auth, type: :calls)
  """
  @spec depends_on(t(), Yog.node_id(), Yog.node_id(), keyword()) :: t()
  def depends_on(%__MODULE__{} = deps, from, to, opts \\ []) do
    type = Keyword.get(opts, :type, :uses)
    label = opts[:label] || type_to_label(type)

    meta =
      opts
      |> Map.new()
      |> Map.put(:type, type)
      |> Map.put(:label, label)

    edge_meta = Map.put(deps.edge_meta, {from, to}, meta)
    graph = Yog.add_edge_ensure(deps.graph, from, to, 1)

    %{deps | graph: graph, edge_meta: edge_meta}
  end

  # ============================================================================
  # Queries
  # ============================================================================

  @doc """
  Returns all node IDs in the dependency graph.
  """
  @spec nodes(t()) :: [Yog.node_id()]
  def nodes(%__MODULE__{graph: graph}) do
    Map.keys(graph.nodes)
  end

  @doc """
  Returns all dependency edges as `{from, to, label}` tuples.
  """
  @spec edges(t()) :: [{Yog.node_id(), Yog.node_id(), number()}]
  def edges(%__MODULE__{graph: graph}) do
    Yog.all_edges(graph)
  end

  @doc """
  Returns all nodes of a given type.
  """
  @spec nodes_of_type(t(), atom()) :: [Yog.node_id()]
  def nodes_of_type(%__MODULE__{graph: graph}, type) do
    graph.nodes
    |> Enum.filter(fn {_id, data} -> data[:node_type] == type end)
    |> Enum.map(fn {id, _data} -> id end)
  end

  @doc """
  Returns the raw `Yog.Graph` struct underpinning the dependency graph.
  """
  @spec to_graph(t()) :: Yog.graph()
  def to_graph(%__MODULE__{graph: graph}), do: graph

  # ============================================================================
  # Rendering
  # ============================================================================

  @doc """
  Renders the dependency graph to DOT format.

  ## Options

    * `:theme` — `:default`, `:dark`, or a `Choreo.Theme` struct
  """
  @spec to_dot(t(), keyword()) :: String.t()
  def to_dot(%__MODULE__{} = deps, opts \\ []) do
    Choreo.Dependency.Render.DOT.to_dot(deps, opts)
  end

  # ============================================================================
  # Private helpers
  # ============================================================================

  defp add_typed_node(%__MODULE__{graph: graph} = deps, id, type, opts) do
    {cluster, rest_opts} = Keyword.pop(opts, :cluster)

    data = %{
      type: :dependency_node,
      node_type: type,
      label: Keyword.get(rest_opts, :label, to_string(id)),
      description: rest_opts[:description]
    }

    data = if cluster, do: Map.put(data, :cluster, ensure_cluster_prefix(cluster)), else: data

    %{deps | graph: Yog.add_node(graph, id, data)}
  end

  defp ensure_cluster_prefix(name) do
    name = to_string(name)
    if String.starts_with?(name, "cluster_"), do: name, else: "cluster_#{name}"
  end

  defp type_to_label(:uses), do: "uses"
  defp type_to_label(:imports), do: "imports"
  defp type_to_label(:calls), do: "calls"
  defp type_to_label(:inherits), do: "inherits"
  defp type_to_label(:dev), do: "dev"
  defp type_to_label(_), do: ""
end
