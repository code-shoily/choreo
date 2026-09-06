defmodule Choreo.DecisionTree do
  @moduledoc """
  Decision-tree builder on top of Yog.

  `Choreo.DecisionTree` models classification and choice trees where
  internal nodes are decisions (tests on features) and leaf nodes are
  outcomes (class labels or actions). Paths from root to leaf represent
  complete decision chains.

  ## When to use

  Use `Choreo.DecisionTree` when you need to document, validate, or
  visualize decision logic — business rules, ML classification trees,
  troubleshooting guides, or configuration selectors. It enforces tree
  invariants and detects logically inconsistent paths automatically.

  The builder enforces **tree invariants**:

    * exactly one root node
    * every non-root node has exactly one parent
    * no cycles

  ## Node types

    * `:root` — the starting decision node (exactly one per tree)
    * `:decision` — internal node testing a feature / attribute
    * `:outcome` — terminal leaf with a class label or action

  ## Further reading

    * [Decision tree learning (Wikipedia)](https://en.wikipedia.org/wiki/Decision_tree_learning)
    * [CART Algorithm](https://en.wikipedia.org/wiki/Predictive_analytics#Classification_and_regression_trees_(CART))
    * [Random forest](https://en.wikipedia.org/wiki/Random_forest)

  ## Quick Start

      tree =
        Choreo.DecisionTree.new()
        |> Choreo.DecisionTree.set_root(:color, feature: "color")
        |> Choreo.DecisionTree.add_outcome(:red_stop, label: "Stop")
        |> Choreo.DecisionTree.add_outcome(:green_go, label: "Go")
        |> Choreo.DecisionTree.branch(:color, :red_stop, "red")
        |> Choreo.DecisionTree.branch(:color, :green_go, "green")

      Choreo.DecisionTree.Analysis.decide(tree, %{"color" => "red"})
      #=> {:ok, [:color, :red_stop], "Stop"}

      dot = Choreo.DecisionTree.to_dot(tree)
      mermaid = Choreo.DecisionTree.to_mermaid(tree)

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=TB, splines=spline, nodesep=0.7, ranksep=1.2];
      node [shape=box, style=filled, fillcolor="white", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [arrowhead=normal, color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];

      color [label="color", penwidth="2.0", fillcolor="#8b5cf6", shape="diamond"];
      red_stop [label="Stop", fillcolor="#10b981", style="rounded,filled", shape="box"];
      green_go [label="Go", fillcolor="#10b981", style="rounded,filled", shape="box"];

      color -> red_stop [fontcolor="#64748b", color="#64748b", label="red"];
      color -> green_go [fontcolor="#64748b", color="#64748b", label="green"];

      { rank=same; green_go; red_stop; }
    }
  </div>
  """

  @type t :: %__MODULE__{
          graph: Yog.graph(),
          root: Yog.node_id() | nil,
          edge_meta: %{optional({Yog.node_id(), Yog.node_id()}) => map()},
          strict: boolean()
        }

  defstruct graph: nil, root: nil, edge_meta: %{}, strict: false

  @node_schema [
    label: [
      type: :string,
      required: false
    ],
    description: [
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

  @set_root_schema [
                     feature: [
                       type: :string,
                       required: false
                     ]
                   ] ++ @node_schema

  @add_decision_schema [
                         feature: [
                           type: :string,
                           required: false
                         ]
                       ] ++ @node_schema

  @add_outcome_schema [
                        class: [
                          type: :string,
                          required: false
                        ],
                        probability: [
                          type: {:or, [:integer, :float]},
                          required: false
                        ]
                      ] ++ @node_schema

  # ============================================================================
  # Creation
  # ============================================================================

  @doc """
  Creates a new empty decision tree.

  ## Options

    * `:strict` — if `true`, `branch/4` raises when parent or child does not
      already exist in the tree. Default `false` (auto-creates missing nodes
      as `:decision`).

  ## Examples

      iex> tree = Choreo.DecisionTree.new()
      iex> Choreo.DecisionTree.nodes(tree)
      []
      iex> Choreo.DecisionTree.root(tree)
      nil
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      graph: Yog.directed(),
      root: nil,
      edge_meta: %{},
      strict: Keyword.get(opts, :strict, false)
    }
  end

  # ============================================================================
  # Node builders
  # ============================================================================

  @doc """
  Sets the root decision node of the tree.

  Can only be called once. Raises `ArgumentError` if the tree already has a root.

  ## Options

  #{NimbleOptions.docs(@set_root_schema)}

  ## Examples

      iex> tree = Choreo.DecisionTree.new()
      iex> tree = Choreo.DecisionTree.set_root(tree, :weather, feature: "weather")
      iex> Choreo.DecisionTree.root(tree)
      :weather
      iex> Yog.node(tree.graph, :weather).node_type
      :root
      iex> Yog.node(tree.graph, :weather).feature
      "weather"

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=TB, splines=spline, nodesep=0.7, ranksep=1.2];
      node [shape=box, style=filled, fillcolor="white", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [arrowhead=normal, color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];

      weather [label="weather", penwidth="2.0", fillcolor="#8b5cf6", shape="diamond"];
    }
  </div>

      iex> tree = Choreo.DecisionTree.new() |> Choreo.DecisionTree.set_root(:a, feature: "x")
      iex> Choreo.DecisionTree.set_root(tree, :b, feature: "y")
      ** (ArgumentError) Tree already has root :a
  """
  @spec set_root(t(), Yog.node_id(), keyword()) :: t()
  def set_root(tree, id, opts \\ [])

  def set_root(%__MODULE__{root: nil} = tree, id, opts) do
    opts = NimbleOptions.validate!(opts, @set_root_schema)
    data = node_data(:root, opts)

    %{
      tree
      | graph: Yog.add_node(tree.graph, id, data),
        root: id
    }
  end

  def set_root(%__MODULE__{root: root}, _id, _opts) do
    raise ArgumentError, "Tree already has root #{inspect(root)}"
  end

  @doc """
  Adds an internal decision node.

  ## Options

  #{NimbleOptions.docs(@add_decision_schema)}

  ## Examples

      iex> tree = Choreo.DecisionTree.new()
      iex> tree = Choreo.DecisionTree.add_decision(tree, :temp, feature: "temp")
      iex> :temp in Choreo.DecisionTree.nodes(tree)
      true
      iex> Yog.node(tree.graph, :temp).node_type
      :decision

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=TB, splines=spline, nodesep=0.7, ranksep=1.2];
      node [shape=box, style=filled, fillcolor="white", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [arrowhead=normal, color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];

      temp [label="temp", fillcolor="#3b82f6", shape="diamond"];
    }
  </div>
  """
  @spec add_decision(t(), Yog.node_id(), keyword()) :: t()
  def add_decision(%__MODULE__{} = tree, id, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @add_decision_schema)
    data = node_data(:decision, opts)
    %{tree | graph: Yog.add_node(tree.graph, id, data)}
  end

  @doc """
  Adds a leaf / outcome node.

  ## Options

  #{NimbleOptions.docs(@add_outcome_schema)}

  ## Examples

      iex> tree = Choreo.DecisionTree.new()
      iex> tree = Choreo.DecisionTree.add_outcome(tree, :play, label: "Play", class: "yes")
      iex> :play in Choreo.DecisionTree.nodes(tree)
      true
      iex> Yog.node(tree.graph, :play).node_type
      :outcome
      iex> Yog.node(tree.graph, :play).class
      "yes"

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=TB, splines=spline, nodesep=0.7, ranksep=1.2];
      node [shape=box, style=filled, fillcolor="white", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [arrowhead=normal, color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];

      play [label="Play", fillcolor="#10b981", style="rounded,filled", shape="box"];
    }
  </div>
  """
  @spec add_outcome(t(), Yog.node_id(), keyword()) :: t()
  def add_outcome(%__MODULE__{} = tree, id, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @add_outcome_schema)
    data = node_data(:outcome, opts)
    %{tree | graph: Yog.add_node(tree.graph, id, data)}
  end

  # ============================================================================
  # Edge builder
  # ============================================================================

  @doc """
  Creates a branch from parent to child with a condition label.

  Enforces tree invariants:

    * child must not already have a parent
    * adding the edge must not create a cycle

  Returns the updated tree. Raises `ArgumentError` on invariant violation.

  ## Examples

      iex> tree = Choreo.DecisionTree.new()
      iex> tree = tree
      ...>   |> Choreo.DecisionTree.set_root(:color, feature: "color")
      ...>   |> Choreo.DecisionTree.add_outcome(:stop)
      ...>   |> Choreo.DecisionTree.branch(:color, :stop, "red")
      iex> Yog.has_edge?(tree.graph, :color, :stop)
      true
      iex> Choreo.DecisionTree.condition(tree, :color, :stop)
      "red"

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=TB, splines=spline, nodesep=0.7, ranksep=1.2];
      node [shape=box, style=filled, fillcolor="white", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [arrowhead=normal, color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];

      stop [label="", fillcolor="#10b981", style="rounded,filled", shape="box"];
      color [label="color", penwidth="2.0", fillcolor="#8b5cf6", shape="diamond"];

      color -> stop [fontcolor="#64748b", color="#64748b", label="red"];
    }
  </div>

      iex> tree = Choreo.DecisionTree.new()
      iex> tree = tree
      ...>   |> Choreo.DecisionTree.set_root(:a, feature: "a")
      ...>   |> Choreo.DecisionTree.add_outcome(:x)
      ...>   |> Choreo.DecisionTree.add_outcome(:y)
      ...>   |> Choreo.DecisionTree.branch(:a, :x, "1")
      iex> Choreo.DecisionTree.branch(tree, :y, :x, "2")
      ** (ArgumentError) Node :x already has a parent
  """
  @spec branch(t(), Yog.node_id(), Yog.node_id(), String.t(), keyword()) :: t()
  def branch(%__MODULE__{} = tree, parent, child, condition, opts \\ []) do
    if tree.strict and not Yog.has_node?(tree.graph, parent) do
      raise ArgumentError,
            "Parent node #{inspect(parent)} does not exist (strict mode is enabled)"
    end

    if tree.strict and not Yog.has_node?(tree.graph, child) do
      raise ArgumentError,
            "Child node #{inspect(child)} does not exist (strict mode is enabled)"
    end

    tree =
      if Yog.has_node?(tree.graph, parent) do
        tree
      else
        add_decision(tree, parent, label: to_string(parent))
      end

    tree =
      if Yog.has_node?(tree.graph, child) do
        tree
      else
        add_decision(tree, child, label: to_string(child))
      end

    cond do
      has_parent?(tree, child) ->
        raise ArgumentError, "Node #{inspect(child)} already has a parent"

      Yog.node(tree.graph, parent).node_type == :outcome ->
        raise ArgumentError, "Decision trees do not allow outcomes to have children"

      would_create_cycle?(tree, parent, child) ->
        raise ArgumentError, "Branch would create a cycle"

      true ->
        meta =
          opts
          |> Enum.into(%{})
          |> Map.put(:condition, condition)
          |> Map.put_new(:label, condition)

        edge_meta = Map.put(tree.edge_meta, {parent, child}, meta)
        graph = Yog.add_edge_ensure(tree.graph, parent, child, condition)

        %{tree | graph: graph, edge_meta: edge_meta}
    end
  end

  # ============================================================================
  # Queries
  # ============================================================================

  @doc """
  Returns the root node id, or `nil` if not set.

  ## Examples

      iex> tree = Choreo.DecisionTree.new()
      iex> Choreo.DecisionTree.root(tree)
      nil
      iex> tree = Choreo.DecisionTree.set_root(tree, :a, feature: "a")
      iex> Choreo.DecisionTree.root(tree)
      :a
  """
  @spec root(t()) :: Yog.node_id() | nil
  def root(%__MODULE__{root: root}), do: root

  @doc """
  Returns all node IDs in the tree.

  ## Examples

      iex> tree = Choreo.DecisionTree.new()
      iex> tree = tree
      ...>   |> Choreo.DecisionTree.set_root(:a, feature: "a")
      ...>   |> Choreo.DecisionTree.add_outcome(:x)
      iex> Enum.sort(Choreo.DecisionTree.nodes(tree))
      [:a, :x]
  """
  @spec nodes(t()) :: [Yog.node_id()]
  def nodes(%__MODULE__{graph: graph}) do
    Map.keys(graph.nodes)
  end

  @doc """
  Returns all branches as `{parent, child, condition}` tuples.

  ## Examples

      iex> tree = Choreo.DecisionTree.new()
      iex> tree = tree
      ...>   |> Choreo.DecisionTree.set_root(:a, feature: "a")
      ...>   |> Choreo.DecisionTree.add_outcome(:x)
      ...>   |> Choreo.DecisionTree.branch(:a, :x, "yes")
      iex> Choreo.DecisionTree.branches(tree)
      [{:a, :x, "yes"}]
  """
  @spec branches(t()) :: [{Yog.node_id(), Yog.node_id(), number()}]
  def branches(%__MODULE__{graph: graph}) do
    Yog.all_edges(graph)
  end

  @doc """
  Returns all outcome (leaf) node IDs.

  ## Examples

      iex> tree = Choreo.DecisionTree.new()
      iex> tree = tree
      ...>   |> Choreo.DecisionTree.set_root(:a, feature: "a")
      ...>   |> Choreo.DecisionTree.add_decision(:b, feature: "b")
      ...>   |> Choreo.DecisionTree.add_outcome(:x)
      ...>   |> Choreo.DecisionTree.add_outcome(:y)
      ...>   |> Choreo.DecisionTree.branch(:a, :b, "1")
      ...>   |> Choreo.DecisionTree.branch(:b, :x, "2")
      ...>   |> Choreo.DecisionTree.branch(:b, :y, "3")
      iex> Enum.sort(Choreo.DecisionTree.outcomes(tree))
      [:x, :y]
  """
  @spec outcomes(t()) :: [Yog.node_id()]
  def outcomes(%__MODULE__{graph: graph}) do
    graph.nodes
    |> Enum.filter(fn {_id, data} -> data[:node_type] == :outcome end)
    |> Enum.map(fn {id, _data} -> id end)
  end

  @doc """
  Returns all decision (internal) node IDs.

  ## Examples

      iex> tree = Choreo.DecisionTree.new()
      iex> tree = tree
      ...>   |> Choreo.DecisionTree.set_root(:a, feature: "a")
      ...>   |> Choreo.DecisionTree.add_decision(:b, feature: "b")
      ...>   |> Choreo.DecisionTree.add_outcome(:x)
      ...>   |> Choreo.DecisionTree.branch(:a, :b, "1")
      ...>   |> Choreo.DecisionTree.branch(:b, :x, "2")
      iex> Enum.sort(Choreo.DecisionTree.decisions(tree))
      [:a, :b]
  """
  @spec decisions(t()) :: [Yog.node_id()]
  def decisions(%__MODULE__{graph: graph}) do
    graph.nodes
    |> Enum.filter(fn {_id, data} ->
      data[:node_type] in [:decision, :root]
    end)
    |> Enum.map(fn {id, _data} -> id end)
  end

  @doc """
  Returns the condition label on the branch from parent to child.

  ## Examples

      iex> tree = Choreo.DecisionTree.new()
      iex> tree = tree
      ...>   |> Choreo.DecisionTree.set_root(:a, feature: "a")
      ...>   |> Choreo.DecisionTree.add_outcome(:x)
      ...>   |> Choreo.DecisionTree.branch(:a, :x, "yes")
      iex> Choreo.DecisionTree.condition(tree, :a, :x)
      "yes"
      iex> Choreo.DecisionTree.condition(tree, :a, :missing)
      nil
  """
  @spec condition(t(), Yog.node_id(), Yog.node_id()) :: String.t() | nil
  def condition(%__MODULE__{edge_meta: edge_meta}, parent, child) do
    case Map.fetch(edge_meta, {parent, child}) do
      {:ok, meta} -> meta[:condition]
      :error -> nil
    end
  end

  @doc """
  Returns the raw `Yog.Graph` struct underpinning the tree.

  ## Examples

      iex> tree = Choreo.DecisionTree.new()
      iex> graph = Choreo.DecisionTree.to_graph(tree)
      iex> graph.kind
      :directed
  """
  @spec to_graph(t()) :: Yog.graph()
  def to_graph(%__MODULE__{graph: graph}), do: graph

  # ============================================================================
  # Rendering
  # ============================================================================

  @doc """
  Renders the decision tree to DOT format.

  ## Options

    * `:theme` — `:default`, `:dark`, `:minimal`, `:warm`, `:forest`, `:ocean`, or a `Choreo.Theme` struct
    * `:rankdir` — `:tb` (default), `:lr`, etc.
    * `:highlighted_nodes` — list of node IDs to highlight
    * `:highlighted_edges` — list of `{from, to}` tuples to highlight

  ## Examples

      iex> tree = Choreo.DecisionTree.new()
      iex> tree = tree
      ...>   |> Choreo.DecisionTree.set_root(:color, feature: "color")
      ...>   |> Choreo.DecisionTree.add_outcome(:stop, label: "Stop")
      ...>   |> Choreo.DecisionTree.add_outcome(:go, label: "Go")
      ...>   |> Choreo.DecisionTree.branch(:color, :stop, "red")
      ...>   |> Choreo.DecisionTree.branch(:color, :go, "green")
      iex> dot = Choreo.DecisionTree.to_dot(tree)
      iex> String.contains?(dot, "digraph")
      true
      iex> String.contains?(dot, "red")
      true
      iex> String.contains?(dot, "green")
      true
  """
  @spec to_dot(t(), keyword()) :: String.t()
  def to_dot(%__MODULE__{} = tree, opts \\ []) do
    Choreo.DecisionTree.Render.DOT.to_dot(tree, opts)
  end

  @doc """
  Renders the decision tree to Mermaid.js flowchart syntax.

  ## Options

    * `:theme` — `:default`, `:dark`, `:minimal`, `:warm`, `:forest`, `:ocean`, or a `Choreo.Theme` struct
    * `:direction` — `:td` (default), `:lr`, `:bt`, `:rl`
    * `:highlighted_nodes` — list of node IDs to highlight
    * `:highlighted_edges` — list of `{from, to}` tuples to highlight

  ## Examples

      iex> tree = Choreo.DecisionTree.new()
      iex> tree = tree
      ...>   |> Choreo.DecisionTree.set_root(:color, feature: "color")
      ...>   |> Choreo.DecisionTree.add_outcome(:stop, label: "Stop")
      ...>   |> Choreo.DecisionTree.add_outcome(:go, label: "Go")
      ...>   |> Choreo.DecisionTree.branch(:color, :stop, "red")
      ...>   |> Choreo.DecisionTree.branch(:color, :go, "green")
      iex> mermaid = Choreo.DecisionTree.to_mermaid(tree)
      iex> String.contains?(mermaid, "graph TD")
      true
      iex> String.contains?(mermaid, "red")
      true
      iex> String.contains?(mermaid, "green")
      true
  """
  @spec to_mermaid(t(), keyword()) :: String.t()
  def to_mermaid(%__MODULE__{} = tree, opts \\ []) do
    Choreo.DecisionTree.Render.Mermaid.to_mermaid(tree, opts)
  end

  @doc """
  Returns a theme for `Choreo.DecisionTree`.

  Supported theme names: `:default`, `:dark`, `:minimal`, `:warm`, `:forest`, `:ocean`.

  ## Examples

      iex> theme = Choreo.DecisionTree.theme(:default, graph_rankdir: :lr)
      iex> theme.graph_rankdir
      :lr
  """
  @spec theme(atom(), keyword()) :: Choreo.Theme.t()
  def theme(name \\ :default, overrides \\ []) do
    Choreo.DecisionTree.Render.DOT.theme(name, overrides)
  end

  # ============================================================================
  # Private helpers
  # ============================================================================

  defp node_data(type, opts) do
    opts
    |> Map.new()
    |> Map.merge(%{
      type: :decision_tree_node,
      node_type: type,
      label: Keyword.get(opts, :label, to_string(opts[:feature] || ""))
    })
  end

  defp has_parent?(%__MODULE__{graph: graph}, child) do
    Yog.in_degree(graph, child) > 0
  end

  defp would_create_cycle?(%__MODULE__{graph: graph}, parent, child) do
    # If child can already reach parent, adding parent -> child creates a cycle
    reachable = Choreo.Internal.bfs_reachable(graph, [child])
    MapSet.member?(reachable, parent)
  end
end

defimpl Choreo.DOT, for: Choreo.DecisionTree do
  def to_dot(tree, opts), do: Choreo.DecisionTree.Render.DOT.to_dot(tree, opts)
end

defimpl Choreo.Mermaid, for: Choreo.DecisionTree do
  def to_mermaid(tree, opts), do: Choreo.DecisionTree.Render.Mermaid.to_mermaid(tree, opts)
end

defimpl Choreo.Viewable, for: Choreo.DecisionTree do
  def rebuild(tree, new_graph) do
    new_edge_meta =
      tree.edge_meta
      |> Enum.filter(fn {{from, to}, _meta} ->
        Map.has_key?(new_graph.nodes, from) and Map.has_key?(new_graph.nodes, to)
      end)
      |> Map.new()

    # Add virtual edge metadata for any graph edges that lack it
    vmeta = virtual_edge_meta(tree)

    new_edge_meta =
      new_graph
      |> Yog.all_edges()
      |> Enum.reduce(new_edge_meta, fn {from, to, _weight}, acc ->
        if Map.has_key?(acc, {from, to}) do
          acc
        else
          Map.put(acc, {from, to}, vmeta)
        end
      end)

    {new_root, new_graph} =
      if Map.has_key?(new_graph.nodes, tree.root) do
        {tree.root, new_graph}
      else
        new_graph.nodes
        |> Enum.sort_by(fn {id, data} ->
          {node_priority(data[:node_type]), Yog.in_degree(new_graph, id)}
        end)
        |> List.first()
        |> case do
          {id, data} ->
            # Retype the promoted node to :root so renderers style it correctly
            new_data = Map.put(data, :node_type, :root)
            new_graph = Yog.update_node(new_graph, id, data, fn _ -> new_data end)
            {id, new_graph}

          nil ->
            {nil, new_graph}
        end
      end

    %{tree | graph: new_graph, edge_meta: new_edge_meta, root: new_root}
  end

  def zoom_predicate(_tree, 0), do: fn _id, data -> data[:node_type] == :root end
  def zoom_predicate(_tree, 1), do: fn _id, data -> data[:node_type] in [:root, :decision] end
  def zoom_predicate(_tree, _level), do: fn _id, _data -> true end

  def virtual_edge_meta(_tree), do: %{edge_type: :virtual, label: nil}

  defp node_priority(:root), do: 0
  defp node_priority(:decision), do: 1
  defp node_priority(:outcome), do: 2
  defp node_priority(_), do: 99
end
