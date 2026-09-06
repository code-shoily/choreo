defmodule Choreo.DecisionTree.Analysis do
  @moduledoc """
  Analysis functions for `Choreo.DecisionTree`.

  Provides path enumeration, evaluation, rule extraction, test-case
  generation, completeness checks, depth metrics, and pruning.

  ## Further reading

    * [Decision tree learning (Wikipedia)](https://en.wikipedia.org/wiki/Decision_tree_learning)
    * [Decision Tree Pruning](https://en.wikipedia.org/wiki/Decision_tree_pruning)
  """

  alias Choreo.DecisionTree

  @doc """
  Evaluates the decision tree against a map of feature values.

  Walks from the root, at each decision node reading the corresponding
  feature value and following the branch whose condition matches.

  Returns `{:ok, path, outcome_label}` or `{:error, reason}`.

  ## Examples

      iex> tree = Choreo.DecisionTree.new()
      iex> tree = tree
      ...>   |> Choreo.DecisionTree.set_root(:color, feature: "color")
      ...>   |> Choreo.DecisionTree.add_outcome(:stop, label: "Stop")
      ...>   |> Choreo.DecisionTree.add_outcome(:go, label: "Go")
      ...>   |> Choreo.DecisionTree.branch(:color, :stop, "red")
      ...>   |> Choreo.DecisionTree.branch(:color, :go, "green")
      iex> Choreo.DecisionTree.Analysis.decide(tree, %{"color" => "red"})
      {:ok, [:color, :stop], "Stop"}
      iex> Choreo.DecisionTree.Analysis.decide(tree, %{"color" => "blue"})
      {:error, "No branch for 'blue' from node :color"}
      iex> Choreo.DecisionTree.Analysis.decide(Choreo.DecisionTree.new(), %{})
      {:error, "Tree has no root"}

  This analysis answers the question: "Given feature values, what outcome does the tree predict?"
  """
  @spec decide(DecisionTree.t(), %{String.t() => String.t()}) ::
          {:ok, [Yog.node_id()], String.t()} | {:error, String.t()}
  def decide(%DecisionTree{root: nil}, _features) do
    {:error, "Tree has no root"}
  end

  def decide(%DecisionTree{} = tree, features) do
    do_decide(tree, tree.root, features, [tree.root])
  end

  @doc """
  Enumerates all root-to-leaf paths.

  Each path is a list of node IDs from root to outcome.

  ## Examples

      iex> tree = Choreo.DecisionTree.new()
      iex> tree = tree
      ...>   |> Choreo.DecisionTree.set_root(:color, feature: "color")
      ...>   |> Choreo.DecisionTree.add_outcome(:stop, label: "Stop")
      ...>   |> Choreo.DecisionTree.add_outcome(:go, label: "Go")
      ...>   |> Choreo.DecisionTree.branch(:color, :stop, "red")
      ...>   |> Choreo.DecisionTree.branch(:color, :go, "green")
      iex> Enum.sort(Choreo.DecisionTree.Analysis.paths(tree))
      [[:color, :go], [:color, :stop]]

  This analysis answers the question: "What are all possible root-to-leaf paths?"
  """
  @spec paths(DecisionTree.t()) :: [[Yog.node_id()]]
  def paths(%DecisionTree{root: nil}), do: []

  def paths(%DecisionTree{} = tree) do
    do_paths(tree, tree.root, [tree.root], [])
  end

  @doc """
  Returns all root-to-leaf paths with their branch conditions.

  Each result is `{path, [{parent, child, condition}]}`.

  ## Examples

      iex> tree = Choreo.DecisionTree.new()
      iex> tree = tree
      ...>   |> Choreo.DecisionTree.set_root(:color, feature: "color")
      ...>   |> Choreo.DecisionTree.add_outcome(:stop, label: "Stop")
      ...>   |> Choreo.DecisionTree.add_outcome(:go, label: "Go")
      ...>   |> Choreo.DecisionTree.branch(:color, :stop, "red")
      ...>   |> Choreo.DecisionTree.branch(:color, :go, "green")
      iex> paths = Choreo.DecisionTree.Analysis.paths_with_conditions(tree)
      iex> {[:color, :stop], [{:color, :stop, "red"}]} in paths
      true
      iex> {[:color, :go], [{:color, :go, "green"}]} in paths
      true

  This analysis answers the question: "What are all paths with their branch conditions?"
  """
  @spec paths_with_conditions(DecisionTree.t()) :: [
          {[Yog.node_id()], [{Yog.node_id(), Yog.node_id(), String.t()}]}
        ]
  def paths_with_conditions(%DecisionTree{root: nil}), do: []

  def paths_with_conditions(%DecisionTree{} = tree) do
    do_paths_with_conditions(tree, tree.root, [tree.root], [], [])
  end

  @doc """
  Returns the maximum depth of the tree (number of edges from root
  to deepest leaf).

  A single-node tree has depth 0.

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
      iex> Choreo.DecisionTree.Analysis.depth(tree)
      2
      iex> Choreo.DecisionTree.Analysis.depth(Choreo.DecisionTree.new())
      0

  This analysis answers the question: "How deep is the tree?"
  """
  @spec depth(DecisionTree.t()) :: non_neg_integer()
  def depth(%DecisionTree{root: nil}), do: 0

  def depth(%DecisionTree{} = tree) do
    do_depth(tree, tree.root, 0)
  end

  @doc """
  Returns the number of leaf / outcome nodes.

  ## Examples

      iex> tree = Choreo.DecisionTree.new()
      iex> tree = tree
      ...>   |> Choreo.DecisionTree.set_root(:color, feature: "color")
      ...>   |> Choreo.DecisionTree.add_outcome(:stop)
      ...>   |> Choreo.DecisionTree.add_outcome(:go)
      ...>   |> Choreo.DecisionTree.add_outcome(:caution)
      ...>   |> Choreo.DecisionTree.branch(:color, :stop, "red")
      ...>   |> Choreo.DecisionTree.branch(:color, :go, "green")
      ...>   |> Choreo.DecisionTree.branch(:color, :caution, "yellow")
      iex> Choreo.DecisionTree.Analysis.breadth(tree)
      3

  This analysis answers the question: "How many leaf outcomes exist?"
  """
  @spec breadth(DecisionTree.t()) :: non_neg_integer()
  def breadth(%DecisionTree{} = tree) do
    length(DecisionTree.outcomes(tree))
  end

  @doc """
  Returns a map of feature frequencies across all decision nodes.

  Useful for understanding which features drive the most splits.

  ## Examples

      iex> tree = Choreo.DecisionTree.new()
      iex> tree = tree
      ...>   |> Choreo.DecisionTree.set_root(:weather, feature: "weather")
      ...>   |> Choreo.DecisionTree.add_decision(:wind, feature: "wind")
      ...>   |> Choreo.DecisionTree.add_outcome(:play)
      ...>   |> Choreo.DecisionTree.branch(:weather, :wind, "cloudy")
      ...>   |> Choreo.DecisionTree.branch(:wind, :play, "calm")
      iex> Choreo.DecisionTree.Analysis.feature_importance(tree)
      %{"weather" => 1, "wind" => 1}

  This analysis answers the question: "Which features drive the most splits?"
  """
  @spec feature_importance(DecisionTree.t()) :: %{String.t() => non_neg_integer()}
  def feature_importance(%DecisionTree{graph: graph}) do
    graph.nodes
    |> Enum.filter(fn {_id, data} -> data[:node_type] in [:root, :decision] end)
    |> Enum.group_by(fn {_id, data} -> data[:feature] end)
    |> Enum.reject(fn {feature, _nodes} -> is_nil(feature) end)
    |> Enum.map(fn {feature, nodes} -> {feature, length(nodes)} end)
    |> Map.new()
  end

  @doc """
  Returns the unique set of all possible outcome classes the tree can produce.

  Only considers outcomes that are actually reachable from the root.

  ## Examples

      iex> tree = Choreo.DecisionTree.new()
      iex> tree = tree
      ...>   |> Choreo.DecisionTree.set_root(:color, feature: "color")
      ...>   |> Choreo.DecisionTree.add_outcome(:stop, class: "stop")
      ...>   |> Choreo.DecisionTree.add_outcome(:go, class: "go")
      ...>   |> Choreo.DecisionTree.branch(:color, :stop, "red")
      ...>   |> Choreo.DecisionTree.branch(:color, :go, "green")
      iex> Enum.sort(Choreo.DecisionTree.Analysis.reachable_outcomes(tree))
      ["go", "stop"]

  This analysis answers the question: "What are all possible outcome classes?"
  """
  @spec reachable_outcomes(DecisionTree.t()) :: [String.t()]
  def reachable_outcomes(%DecisionTree{root: nil}), do: []

  def reachable_outcomes(%DecisionTree{} = tree) do
    reachable = Choreo.Internal.bfs_reachable(tree.graph, [tree.root])

    tree.graph.nodes
    |> Enum.filter(fn {id, data} ->
      data[:node_type] == :outcome and MapSet.member?(reachable, id)
    end)
    |> Enum.map(fn {id, data} -> outcome_name(id, data) end)
    |> Enum.uniq()
  end

  @doc """
  Returns the distribution of reachable outcome classes across all paths.

  Counts how many reachable leaf outcomes correspond to each class (or label
  if no class is set).

  ## Examples

      iex> tree = Choreo.DecisionTree.new()
      iex> tree = tree
      ...>   |> Choreo.DecisionTree.set_root(:color, feature: "color")
      ...>   |> Choreo.DecisionTree.add_outcome(:stop, class: "stop")
      ...>   |> Choreo.DecisionTree.add_outcome(:slow, class: "stop")
      ...>   |> Choreo.DecisionTree.add_outcome(:go, class: "go")
      ...>   |> Choreo.DecisionTree.branch(:color, :stop, "red")
      ...>   |> Choreo.DecisionTree.branch(:color, :slow, "yellow")
      ...>   |> Choreo.DecisionTree.branch(:color, :go, "green")
      iex> Choreo.DecisionTree.Analysis.outcome_distribution(tree)
      %{"go" => 1, "stop" => 2}

  This analysis answers the question: "How are reachable outcomes distributed across classes?"
  """
  @spec outcome_distribution(DecisionTree.t()) :: %{String.t() => non_neg_integer()}
  def outcome_distribution(%DecisionTree{root: nil}), do: %{}

  def outcome_distribution(%DecisionTree{} = tree) do
    reachable = Choreo.Internal.bfs_reachable(tree.graph, [tree.root])

    tree.graph.nodes
    |> Enum.filter(fn {id, data} ->
      data[:node_type] == :outcome and MapSet.member?(reachable, id)
    end)
    |> Enum.map(fn {id, data} -> outcome_name(id, data) end)
    |> Enum.frequencies()
  end

  defp outcome_name(id, data) do
    cond do
      data[:class] && data[:class] != "" -> to_string(data[:class])
      data[:label] && data[:label] != "" -> to_string(data[:label])
      true -> to_string(id)
    end
  end

  @doc """
  Returns nodes that are not reachable from the root.

  In a well-formed tree every declared node should be reachable. Nodes
  added without a connecting branch are reported as orphans.

  ## Examples

      iex> tree = Choreo.DecisionTree.new()
      iex> tree = tree
      ...>   |> Choreo.DecisionTree.set_root(:a, feature: "a")
      ...>   |> Choreo.DecisionTree.add_outcome(:x)
      ...>   |> Choreo.DecisionTree.add_outcome(:y)
      ...>   |> Choreo.DecisionTree.branch(:a, :x, "1")
      iex> Choreo.DecisionTree.Analysis.orphan_nodes(tree)
      [:y]

  This analysis answers the question: "Which declared nodes are unreachable?"
  """
  @spec orphan_nodes(DecisionTree.t()) :: [Yog.node_id()]
  def orphan_nodes(%DecisionTree{root: nil}), do: []

  def orphan_nodes(%DecisionTree{} = tree) do
    reachable = Choreo.Internal.bfs_reachable(tree.graph, [tree.root])
    all = MapSet.new(Map.keys(tree.graph.nodes))

    MapSet.difference(all, reachable)
    |> MapSet.to_list()
    |> Enum.sort()
  end

  @doc """
  Returns nodes that cannot reach any outcome (terminal leaf) node.

  In a well-formed tree, every decision node should eventually lead to an
  outcome. Nodes with no path to an outcome represent dead-end logic.

  ## Examples

      iex> tree = Choreo.DecisionTree.new()
      iex> tree = tree
      ...>   |> Choreo.DecisionTree.set_root(:a, feature: "a")
      ...>   |> Choreo.DecisionTree.add_decision(:b, feature: "b")
      ...>   |> Choreo.DecisionTree.add_outcome(:x)
      ...>   |> Choreo.DecisionTree.branch(:a, :x, "1")
      ...>   |> Choreo.DecisionTree.branch(:a, :b, "2")
      iex> Choreo.DecisionTree.Analysis.dead_ends(tree)
      [:b]

  This analysis answers the question: "Which decision paths lead nowhere?"
  """
  @spec dead_ends(DecisionTree.t()) :: [Yog.node_id()]
  def dead_ends(%DecisionTree{root: nil}), do: []

  def dead_ends(%DecisionTree{} = tree) do
    outcome_ids = DecisionTree.outcomes(tree)

    if outcome_ids == [] do
      DecisionTree.nodes(tree) |> Enum.sort()
    else
      transposed = Yog.transpose(tree.graph)
      can_reach_outcome = Choreo.Internal.bfs_reachable(transposed, outcome_ids)
      all = DecisionTree.nodes(tree) |> MapSet.new()
      MapSet.difference(all, can_reach_outcome) |> MapSet.to_list() |> Enum.sort()
    end
  end

  @doc """
  Extracts IF-THEN rules from the decision tree.

  Each rule maps the conditions along a root-to-leaf path to the outcome
  reached at that leaf.

  ## Examples

      iex> tree = Choreo.DecisionTree.new()
      iex> tree = tree
      ...>   |> Choreo.DecisionTree.set_root(:color, feature: "color")
      ...>   |> Choreo.DecisionTree.add_outcome(:stop, label: "Stop", class: "stop")
      ...>   |> Choreo.DecisionTree.add_outcome(:go, label: "Go", class: "go")
      ...>   |> Choreo.DecisionTree.branch(:color, :stop, "red")
      ...>   |> Choreo.DecisionTree.branch(:color, :go, "green")
      iex> rules = Choreo.DecisionTree.Analysis.rules(tree)
      iex> length(rules)
      2
      iex> Enum.find(rules, fn r -> r.outcome.class == "stop" end)
      %{conditions: %{"color" => "red"}, outcome: %{class: "stop", label: "Stop"}}

  This analysis answers the question: "What IF-THEN rules does the tree encode?"
  """
  @spec rules(DecisionTree.t()) :: [
          %{
            conditions: %{String.t() => String.t()},
            outcome: %{class: String.t() | nil, label: String.t() | nil}
          }
        ]
  def rules(%DecisionTree{root: nil}), do: []

  def rules(%DecisionTree{} = tree) do
    tree
    |> paths_with_conditions()
    |> Enum.filter(fn {path, _branches} ->
      leaf = List.last(path)
      data = Yog.node(tree.graph, leaf)
      data[:node_type] == :outcome
    end)
    |> Enum.map(fn {path, branches} ->
      outcome_id = List.last(path)
      outcome_data = Yog.node(tree.graph, outcome_id)

      %{
        conditions: branches_to_features(tree, branches),
        outcome: %{
          class: outcome_data[:class],
          label: outcome_data[:label]
        }
      }
    end)
  end

  @doc """
  Generates feature maps that cover every reachable leaf path.

  Each generated map can be passed to `decide/2` to reach a distinct
  outcome. This is useful for testing or for validating that every
  rule in the tree is exercisable.

  ## Examples

      iex> tree = Choreo.DecisionTree.new()
      iex> tree = tree
      ...>   |> Choreo.DecisionTree.set_root(:color, feature: "color")
      ...>   |> Choreo.DecisionTree.add_outcome(:stop, label: "Stop")
      ...>   |> Choreo.DecisionTree.add_outcome(:go, label: "Go")
      ...>   |> Choreo.DecisionTree.branch(:color, :stop, "red")
      ...>   |> Choreo.DecisionTree.branch(:color, :go, "green")
      iex> test_cases = Choreo.DecisionTree.Analysis.generate_test_cases(tree)
      iex> length(test_cases)
      2
      iex> %{"color" => "red"} in test_cases
      true
      iex> %{"color" => "green"} in test_cases
      true

  This analysis answers the question: "What inputs exercise every path?"
  """
  @spec generate_test_cases(DecisionTree.t()) :: [%{String.t() => String.t()}]
  def generate_test_cases(%DecisionTree{root: nil}), do: []

  def generate_test_cases(%DecisionTree{} = tree) do
    tree
    |> paths_with_conditions()
    |> Enum.filter(fn {path, _branches} ->
      leaf = List.last(path)
      data = Yog.node(tree.graph, leaf)
      data[:node_type] == :outcome
    end)
    |> Enum.map(fn {_path, branches} -> branches_to_features(tree, branches) end)
  end

  @doc """
  Finds decision nodes whose outgoing branches do not cover an expected
  set of feature values.

  Accepts a map of `feature => [expected_values]`. For each decision node
  testing that feature, returns `{node_id, feature, missing_values}` when
  values are absent.

  ## Examples

      iex> tree = Choreo.DecisionTree.new()
      iex> tree = tree
      ...>   |> Choreo.DecisionTree.set_root(:color, feature: "color")
      ...>   |> Choreo.DecisionTree.add_outcome(:stop)
      ...>   |> Choreo.DecisionTree.add_outcome(:go)
      ...>   |> Choreo.DecisionTree.branch(:color, :stop, "red")
      ...>   |> Choreo.DecisionTree.branch(:color, :go, "green")
      iex> Choreo.DecisionTree.Analysis.missing_branches(tree, %{"color" => ["red", "green", "blue"]})
      [{:color, "color", ["blue"]}]

      iex> tree = Choreo.DecisionTree.new()
      iex> tree = tree
      ...>   |> Choreo.DecisionTree.set_root(:a, feature: "a")
      ...>   |> Choreo.DecisionTree.add_outcome(:x)
      ...>   |> Choreo.DecisionTree.branch(:a, :x, "1")
      iex> Choreo.DecisionTree.Analysis.missing_branches(tree, %{"a" => ["1"]})
      []

  This analysis answers the question: "Which expected branches are missing?"
  """
  @spec missing_branches(DecisionTree.t(), %{String.t() => [String.t()]}) :: [
          {Yog.node_id(), String.t(), [String.t()]}
        ]
  def missing_branches(%DecisionTree{root: nil}, _domains), do: []

  def missing_branches(%DecisionTree{} = tree, domains) do
    tree.graph.nodes
    |> Enum.filter(fn {_id, data} -> data[:node_type] in [:root, :decision] end)
    |> Enum.flat_map(fn {id, data} ->
      feature = data[:feature]
      expected = Map.get(domains, feature)

      if is_nil(feature) or is_nil(expected) do
        []
      else
        actual =
          tree.graph
          |> Yog.successors(id)
          |> Enum.map(fn {_to, condition} -> condition end)
          |> MapSet.new()

        expected_set = MapSet.new(expected)
        missing = MapSet.difference(expected_set, actual) |> MapSet.to_list()

        if missing == [] do
          []
        else
          [{id, feature, missing}]
        end
      end
    end)
  end

  @doc """
  Finds logically impossible paths where a feature is checked against
  mutually exclusive conditions.

  Returns a list of tuples `{path, [features_with_conflicts]}`.

  ## Examples

      iex> tree = Choreo.DecisionTree.new()
      iex> tree = tree
      ...>   |> Choreo.DecisionTree.set_root(:color, feature: "color")
      ...>   |> Choreo.DecisionTree.add_decision(:shade, feature: "color")
      ...>   |> Choreo.DecisionTree.add_outcome(:stop, label: "Stop")
      ...>   |> Choreo.DecisionTree.add_outcome(:go1, label: "Go")
      ...>   |> Choreo.DecisionTree.add_outcome(:go2, label: "Go")
      ...>   |> Choreo.DecisionTree.branch(:color, :shade, "red")
      ...>   |> Choreo.DecisionTree.branch(:color, :go1, "green")
      ...>   |> Choreo.DecisionTree.branch(:shade, :stop, "dark")
      ...>   |> Choreo.DecisionTree.branch(:shade, :go2, "light")
      iex> inconsistencies = Choreo.DecisionTree.Analysis.inconsistent_paths(tree)
      iex> length(inconsistencies)
      2
      iex> Enum.any?(inconsistencies, fn {_path, features} -> "color" in features end)
      true

  This analysis answers the question: "Are there logically impossible paths?"
  """
  @spec inconsistent_paths(DecisionTree.t()) :: [{[Yog.node_id()], [String.t()]}]
  def inconsistent_paths(%DecisionTree{} = tree) do
    paths = paths_with_conditions(tree)

    paths
    |> Enum.flat_map(fn {path_nodes, branches} ->
      checks =
        branches
        |> Enum.map(fn {parent, _child, condition} ->
          data = Yog.node(tree.graph, parent)
          {data[:feature], condition}
        end)
        |> Enum.reject(fn {f, _c} -> is_nil(f) end)

      inconsistencies =
        checks
        |> Enum.group_by(fn {f, _c} -> f end, fn {_f, c} -> c end)
        |> Enum.filter(fn {_f, conditions} ->
          length(Enum.uniq(conditions)) > 1
        end)
        |> Enum.map(fn {f, _conditions} -> to_string(f) end)

      if inconsistencies == [] do
        []
      else
        [{path_nodes, inconsistencies}]
      end
    end)
  end

  @doc """
  Prunes redundant decision nodes.

  A decision is redundant when **all** of its descendant leaves share
  the same class label. The decision node is replaced by an outcome
  node with that label.

  Returns a new tree.

  ## Examples

      iex> tree = Choreo.DecisionTree.new()
      iex> tree = tree
      ...>   |> Choreo.DecisionTree.set_root(:color, feature: "color")
      ...>   |> Choreo.DecisionTree.add_decision(:shade, feature: "shade")
      ...>   |> Choreo.DecisionTree.add_outcome(:stop_light, label: "Stop", class: "stop")
      ...>   |> Choreo.DecisionTree.add_outcome(:stop_dark, label: "Stop", class: "stop")
      ...>   |> Choreo.DecisionTree.branch(:color, :shade, "red")
      ...>   |> Choreo.DecisionTree.branch(:shade, :stop_light, "light")
      ...>   |> Choreo.DecisionTree.branch(:shade, :stop_dark, "dark")
      iex> pruned = Choreo.DecisionTree.Analysis.prune_redundant(tree)
      iex> Choreo.DecisionTree.outcomes(pruned)
      [:color]
      iex> :color in Choreo.DecisionTree.decisions(pruned)
      false

  This analysis answers the question: "Which decision nodes can be simplified?"
  """
  @spec prune_redundant(DecisionTree.t()) :: DecisionTree.t()
  def prune_redundant(%DecisionTree{root: nil} = tree), do: tree

  def prune_redundant(%DecisionTree{} = tree) do
    {new_tree, _changed?} = prune_node(tree, tree.root)
    new_tree
  end

  @doc """
  Checks whether the decision tree contains a directed cycle.

  In a well-formed tree, cycles are prohibited.

  ## Examples

      iex> tree = Choreo.DecisionTree.new()
      iex> tree = tree
      ...>   |> Choreo.DecisionTree.set_root(:a, feature: "a")
      ...>   |> Choreo.DecisionTree.add_outcome(:x)
      ...>   |> Choreo.DecisionTree.branch(:a, :x, "1")
      iex> Choreo.DecisionTree.Analysis.cyclic?(tree)
      false

  This analysis answers the question: "Does the decision tree contain any cycles?"
  """
  @spec cyclic?(DecisionTree.t()) :: boolean()
  def cyclic?(%DecisionTree{graph: graph}) do
    Yog.cyclic?(graph)
  end

  @doc """
  Validates tree completeness and structural invariants.

  Checks for:
    * missing root
    * cycles in the hierarchy
    * multiple parents (converging branches)
    * decision nodes with no branches
    * outcome nodes with branches (should be leaves)
    * duplicate conditions from the same parent
    * orphan nodes (not reachable from root)

  Returns a list of `{severity, message}` tuples.

  ## Examples

      iex> tree = Choreo.DecisionTree.new()
      iex> tree = tree
      ...>   |> Choreo.DecisionTree.set_root(:color, feature: "color")
      ...>   |> Choreo.DecisionTree.add_outcome(:stop)
      ...>   |> Choreo.DecisionTree.add_outcome(:go)
      ...>   |> Choreo.DecisionTree.branch(:color, :stop, "red")
      ...>   |> Choreo.DecisionTree.branch(:color, :go, "green")
      iex> Choreo.DecisionTree.Analysis.validate(tree)
      []

      iex> tree = Choreo.DecisionTree.new()
      iex> Choreo.DecisionTree.Analysis.validate(tree)
      [{:error, "Tree has no root"}]

  This analysis answers the question: "Is the tree structurally valid?"
  """
  @spec validate(DecisionTree.t()) :: [{:error | :warning, String.t()}]
  def validate(%DecisionTree{} = tree) do
    []
    |> check_root(tree)
    |> check_cycles(tree)
    |> check_multiple_parents(tree)
    |> check_leaf_branches(tree)
    |> check_empty_decisions(tree)
    |> check_duplicate_conditions(tree)
    |> check_orphans(tree)
  end

  # ============================================================================
  # Private helpers — decide
  # ============================================================================

  defp do_decide(_tree, nil, _features, path) do
    {:error, "Reached nil node along path #{inspect(path)}"}
  end

  defp do_decide(tree, current, features, path) do
    data = Yog.node(tree.graph, current)

    if data[:node_type] == :outcome do
      {:ok, Enum.reverse(path), data[:label] || to_string(current)}
    else
      feature = data[:feature]
      value = if feature, do: Map.get(features, feature), else: nil

      if is_nil(value) do
        {:error, "Feature '#{feature}' not provided for node #{inspect(current)}"}
      else
        case find_branch(tree, current, value) do
          {:ok, child} ->
            do_decide(tree, child, features, [child | path])

          :error ->
            {:error, "No branch for '#{value}' from node #{inspect(current)}"}
        end
      end
    end
  end

  defp find_branch(tree, parent, value) do
    tree.graph
    |> Yog.successors(parent)
    |> Enum.find(fn {_to, condition} -> condition == value end)
    |> case do
      {child, _condition} -> {:ok, child}
      nil -> :error
    end
  end

  # ============================================================================
  # Private helpers — paths
  # ============================================================================

  defp do_paths(tree, current, path, acc) do
    children = Yog.successor_ids(tree.graph, current)

    if children == [] do
      [Enum.reverse(path) | acc]
    else
      Enum.reduce(children, acc, fn child, acc ->
        do_paths(tree, child, [child | path], acc)
      end)
    end
  end

  defp do_paths_with_conditions(tree, current, path, branches, acc) do
    children = Yog.successors(tree.graph, current)

    if children == [] do
      [{Enum.reverse(path), Enum.reverse(branches)} | acc]
    else
      Enum.reduce(children, acc, fn {child, condition}, acc ->
        do_paths_with_conditions(
          tree,
          child,
          [child | path],
          [{current, child, condition} | branches],
          acc
        )
      end)
    end
  end

  defp branches_to_features(tree, branches) do
    branches
    |> Enum.map(fn {parent, _child, condition} ->
      data = Yog.node(tree.graph, parent)
      {to_string(data[:feature]), condition}
    end)
    |> Map.new()
  end

  # ============================================================================
  # Private helpers — depth
  # ============================================================================

  defp do_depth(tree, current, depth) do
    children = Yog.successor_ids(tree.graph, current)

    if children == [] do
      depth
    else
      children
      |> Enum.map(fn child -> do_depth(tree, child, depth + 1) end)
      |> Enum.max()
    end
  end

  # ============================================================================
  # Private helpers — prune
  # ============================================================================

  defp prune_node(tree, id) do
    children = Yog.successor_ids(tree.graph, id)

    if children == [] do
      # Leaf — nothing to prune
      {tree, false}
    else
      # Prune children first (post-order)
      {tree, changed?} =
        Enum.reduce(children, {tree, false}, fn child, {tree, changed?} ->
          {tree, child_changed?} = prune_node(tree, child)
          {tree, changed? or child_changed?}
        end)

      # After pruning children, check if all current children are identical outcomes
      current_children = Yog.successor_ids(tree.graph, id)

      case uniform_outcome(tree, current_children) do
        {:ok, class, label} ->
          # Replace this decision with an outcome
          new_tree = replace_with_outcome(tree, id, class, label)
          {new_tree, true}

        :error ->
          {tree, changed?}
      end
    end
  end

  # Outcomes built without :class and without :label would silently skip pruning
  # (no class label = can't merge safely). That's defensible — we only collapse
  # when every descendant leaf has an identical, non-nil class+label pair.
  defp uniform_outcome(_tree, []), do: :error

  defp uniform_outcome(tree, children) do
    classes =
      children
      |> Enum.map(fn child ->
        data = Yog.node(tree.graph, child)
        {data[:class], data[:label]}
      end)

    first = hd(classes)

    if first != {nil, nil} and Enum.all?(classes, &(&1 == first)) do
      {class, label} = first
      {:ok, class, label}
    else
      :error
    end
  end

  defp replace_with_outcome(tree, id, class, label) do
    # Remove all outgoing edges and orphaned children
    children = Yog.successor_ids(tree.graph, id)
    graph = Enum.reduce(children, tree.graph, &Yog.remove_edge(&2, id, &1))

    # Remove orphaned child nodes (no longer reachable after edge removal)
    graph = Enum.reduce(children, graph, &Yog.remove_node(&2, &1))

    # Remove edge metadata for the removed edges
    edge_meta =
      Enum.reduce(children, tree.edge_meta, fn child, acc ->
        Map.delete(acc, {id, child})
      end)

    # Update node data
    old_data = Yog.node(graph, id)

    new_data =
      old_data
      |> Map.put(:node_type, :outcome)
      |> Map.put(:class, class)
      |> Map.put(:label, label || old_data[:label])

    graph = Yog.update_node(graph, id, old_data, fn _ -> new_data end)
    %{tree | graph: graph, edge_meta: edge_meta}
  end

  # ============================================================================
  # Private helpers — validation
  # ============================================================================

  defp check_root(acc, tree) do
    if is_nil(tree.root) do
      [{:error, "Tree has no root"} | acc]
    else
      acc
    end
  end

  defp check_cycles(acc, tree) do
    if cyclic?(tree) do
      [{:error, "Cycle detected in decision tree"} | acc]
    else
      acc
    end
  end

  defp check_multiple_parents(acc, tree) do
    violations =
      tree.graph.nodes
      |> Enum.flat_map(fn {id, _data} ->
        preds = Yog.predecessors(tree.graph, id)

        if length(preds) > 1 do
          parent_ids = Enum.map(preds, fn {p, _w} -> p end) |> Enum.sort()
          [{:error, "Node #{inspect(id)} has multiple parents: #{inspect(parent_ids)}"}]
        else
          []
        end
      end)

    violations ++ acc
  end

  defp check_leaf_branches(acc, tree) do
    outcomes = DecisionTree.outcomes(tree)

    violations =
      outcomes
      |> Enum.filter(fn id -> Yog.out_degree(tree.graph, id) > 0 end)
      |> Enum.map(fn id ->
        {:error, "Outcome node #{inspect(id)} has outgoing branches"}
      end)

    violations ++ acc
  end

  defp check_empty_decisions(acc, tree) do
    decisions = DecisionTree.decisions(tree)

    violations =
      decisions
      |> Enum.filter(fn id -> Yog.out_degree(tree.graph, id) == 0 end)
      |> Enum.map(fn id ->
        {:error, "Decision node #{inspect(id)} has no branches"}
      end)

    violations ++ acc
  end

  defp check_duplicate_conditions(acc, tree) do
    violations =
      tree.graph.nodes
      |> Enum.flat_map(fn {id, _data} ->
        conditions =
          tree.graph
          |> Yog.successors(id)
          |> Enum.map(fn {_to, cond} -> cond end)

        duplicates =
          conditions
          |> Enum.group_by(& &1)
          |> Enum.filter(fn {_cond, list} -> length(list) > 1 end)
          |> Enum.map(fn {cond, _list} -> cond end)

        Enum.map(duplicates, fn cond ->
          {:warning, "Duplicate condition '#{cond}' from node #{inspect(id)}"}
        end)
      end)

    violations ++ acc
  end

  defp check_orphans(acc, tree) do
    case orphan_nodes(tree) do
      [] ->
        acc

      nodes ->
        [{:warning, "Orphan nodes: #{inspect(nodes)}"} | acc]
    end
  end
end
