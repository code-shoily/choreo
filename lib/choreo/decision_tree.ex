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
  """

  @type t :: %__MODULE__{
          graph: Yog.graph(),
          root: Yog.node_id() | nil,
          edge_meta: %{optional({Yog.node_id(), Yog.node_id()}) => map()}
        }

  defstruct graph: nil, root: nil, edge_meta: %{}

  # ============================================================================
  # Creation
  # ============================================================================

  @doc """
  Creates a new empty decision tree.
  """
  @spec new() :: t()
  def new do
    %__MODULE__{
      graph: Yog.directed(),
      root: nil,
      edge_meta: %{}
    }
  end

  # ============================================================================
  # Node builders
  # ============================================================================

  @doc """
  Sets the root decision node of the tree.

  Can only be called once. Raises `ArgumentError` if the tree already has a root.

  ## Options

    * `:feature` — the attribute being tested (rendered as label)
    * `:label` — override display label
    * `:description` — tooltip text
  """
  @spec set_root(t(), Yog.node_id(), keyword()) :: t()
  def set_root(tree, id, opts \\ [])

  def set_root(%__MODULE__{root: nil} = tree, id, opts) do
    data = node_data(:root, opts)

    %{
      tree
      | graph: Yog.add_node(tree.graph, id, data),
        root: id
    }
  end

  def set_root(%__MODULE__{}, _id, _opts) do
    raise ArgumentError, "Tree already has a root"
  end

  @doc """
  Adds an internal decision node.

  ## Options

    * `:feature` — the attribute being tested
    * `:label` — display label (defaults to the node id)
    * `:description` — tooltip text
  """
  @spec add_decision(t(), Yog.node_id(), keyword()) :: t()
  def add_decision(%__MODULE__{} = tree, id, opts \\ []) do
    data = node_data(:decision, opts)
    %{tree | graph: Yog.add_node(tree.graph, id, data)}
  end

  @doc """
  Adds a leaf / outcome node.

  ## Options

    * `:class` — class label or action name
    * `:label` — display label (defaults to the node id)
    * `:description` — tooltip text
    * `:probability` — optional probability / confidence score
  """
  @spec add_outcome(t(), Yog.node_id(), keyword()) :: t()
  def add_outcome(%__MODULE__{} = tree, id, opts \\ []) do
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

      tree =
        DecisionTree.new()
        |> DecisionTree.set_root(:weather, feature: "weather")
        |> DecisionTree.add_outcome(:play, label: "Play")
        |> DecisionTree.add_outcome(:stay, label: "Stay Home")
        |> DecisionTree.branch(:weather, :play, "sunny")
        |> DecisionTree.branch(:weather, :stay, "rainy")
  """
  @spec branch(t(), Yog.node_id(), Yog.node_id(), String.t()) :: t()
  def branch(%__MODULE__{} = tree, parent, child, condition) do
    cond do
      not Yog.has_node?(tree.graph, parent) ->
        raise ArgumentError, "Parent node #{inspect(parent)} does not exist"

      not Yog.has_node?(tree.graph, child) ->
        raise ArgumentError, "Child node #{inspect(child)} does not exist"

      has_parent?(tree, child) ->
        raise ArgumentError, "Node #{inspect(child)} already has a parent"

      would_create_cycle?(tree, parent, child) ->
        raise ArgumentError, "Branch would create a cycle"

      true ->
        meta = %{condition: condition, label: condition}
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
  """
  @spec root(t()) :: Yog.node_id() | nil
  def root(%__MODULE__{root: root}), do: root

  @doc """
  Returns all node IDs in the tree.
  """
  @spec nodes(t()) :: [Yog.node_id()]
  def nodes(%__MODULE__{graph: graph}) do
    Map.keys(graph.nodes)
  end

  @doc """
  Returns all branches as `{parent, child, condition}` tuples.
  """
  @spec branches(t()) :: [{Yog.node_id(), Yog.node_id(), number()}]
  def branches(%__MODULE__{graph: graph}) do
    Yog.all_edges(graph)
  end

  @doc """
  Returns all outcome (leaf) node IDs.
  """
  @spec outcomes(t()) :: [Yog.node_id()]
  def outcomes(%__MODULE__{graph: graph}) do
    graph.nodes
    |> Enum.filter(fn {_id, data} -> data[:node_type] == :outcome end)
    |> Enum.map(fn {id, _data} -> id end)
  end

  @doc """
  Returns all decision (internal) node IDs.
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
  """
  @spec to_graph(t()) :: Yog.graph()
  def to_graph(%__MODULE__{graph: graph}), do: graph

  # ============================================================================
  # Rendering
  # ============================================================================

  @doc """
  Renders the decision tree to DOT format.

  ## Options

    * `:theme` — `:default`, `:dark`, or a `Choreo.Theme` struct
  """
  @spec to_dot(t(), keyword()) :: String.t()
  def to_dot(%__MODULE__{} = tree, opts \\ []) do
    Choreo.DecisionTree.Render.DOT.to_dot(tree, opts)
  end

  # ============================================================================
  # Private helpers
  # ============================================================================

  defp node_data(type, opts) do
    base = %{
      type: :decision_tree_node,
      node_type: type,
      label: Keyword.get(opts, :label, to_string(opts[:feature] || "")),
      description: opts[:description]
    }

    base = if feature = opts[:feature], do: Map.put(base, :feature, feature), else: base
    base = if class = opts[:class], do: Map.put(base, :class, class), else: base
    base = if prob = opts[:probability], do: Map.put(base, :probability, prob), else: base
    base
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
