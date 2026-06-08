defmodule Choreo.UML.Analysis do
  @moduledoc """
  Architectural analysis suite for `Choreo.UML` class/struct diagrams.

  Provides static analysis tools optimized for functional and OOP software design:
    * `cycles/1` — identifies circular dependency loops.
    * `broken_contracts/1` — flags incomplete behavior/protocol realizations.
    * `coupling_metrics/1` — computes Afferent/Efferent coupling and Instability.
    * `law_of_demeter_violations/1` — identifies structural Law of Demeter violations.
  """

  @doc """
  Identifies all circular dependency paths in the UML diagram.

  Cycles in structural diagrams indicate high coupling and are a major source
  of compilation cascades in Elixir applications.

  Returns a list of cycles, where each cycle is a list of node IDs
  starting at the canonical smallest node and listing each member once.

  ## Examples

      iex> uml =
      ...>   Choreo.UML.new()
      ...>   |> Choreo.UML.add_class(:a)
      ...>   |> Choreo.UML.add_class(:b)
      ...>   |> Choreo.UML.add_relationship(:a, :b, type: :associates)
      ...>   |> Choreo.UML.add_relationship(:b, :a, type: :depends)
      iex> Choreo.UML.Analysis.cycles(uml)
      [[:a, :b]]
  """
  @spec cycles(Choreo.UML.t()) :: [[Choreo.UML.class_id()]]
  def cycles(%Choreo.UML{} = uml) do
    Choreo.Internal.dfs_cycles(uml.graph)
  end

  @doc """
  Identifies components which have declared a `:realizes` or `:inherits` relationship
  to a `:behavior`, `:protocol`, or `:interface` component but do not implement all
  the functions specified by that contract.

  Returns a list of tuples `[{component_id, contract_id, [missing_function_maps]}]`.

  ## Examples

      iex> contract = Choreo.UML.new()
      ...>   |> Choreo.UML.add_class(:auth, type: :behavior, functions: [%{name: "verify", arity: 1}])
      ...>   # Struct missing the arity 1 verify function:
      ...>   |> Choreo.UML.add_class(:provider, type: :struct, functions: [%{name: "verify", arity: 2}])
      ...>   |> Choreo.UML.add_relationship(:provider, :auth, type: :realizes)
      iex> [{:provider, :auth, [missing]}] = Choreo.UML.Analysis.broken_contracts(contract)
      iex> missing[:name]
      "verify"
      iex> missing[:arity]
      1
  """
  @spec broken_contracts(Choreo.UML.t()) :: [
          {Choreo.UML.class_id(), Choreo.UML.class_id(), [map()]}
        ]
  def broken_contracts(%Choreo.UML{} = uml) do
    graph = uml.graph

    uml.edge_meta
    |> Enum.reduce([], fn {edge_id, meta}, acc ->
      case meta[:type] do
        type when type in [:realizes, :inherits] ->
          {from, to, _w} = Map.get(graph.edges, edge_id)
          missing = Choreo.Internal.unsatisfied_contract(uml, from, to)

          if missing != [] do
            [{from, to, missing} | acc]
          else
            acc
          end

        _ ->
          acc
      end
    end)
    |> Enum.reverse()
  end

  @doc """
  Computes coupling and stability metrics for all components in the UML diagram.

  Returns a map of component IDs to:
    * `:afferent` — number of incoming dependencies (who depends on me)
    * `:efferent` — number of outgoing dependencies (who do I depend on)
    * `:instability` — Ce / (Ca + Ce). Stable core modules approach 0.0, unstable leaf modules approach 1.0.

  ## Examples

      iex> uml =
      ...>   Choreo.UML.new()
      ...>   |> Choreo.UML.add_class(:a)
      ...>   |> Choreo.UML.add_class(:b)
      ...>   |> Choreo.UML.add_relationship(:a, :b, type: :associates)
      iex> metrics = Choreo.UML.Analysis.coupling_metrics(uml)
      iex> metrics[:a]
      %{afferent: 0, efferent: 1, instability: 1.0}
      iex> metrics[:b]
      %{afferent: 1, efferent: 0, instability: 0.0}
  """
  @spec coupling_metrics(Choreo.UML.t()) :: %{
          optional(Choreo.UML.class_id()) => %{
            afferent: non_neg_integer(),
            efferent: non_neg_integer(),
            instability: float()
          }
        }
  def coupling_metrics(%Choreo.UML{} = uml) do
    # Collapse multigraph to simple graph to get unique connections and remove parallel relationships
    simple_graph = Yog.Multi.to_simple_graph(uml.graph)
    nodes = Map.keys(uml.graph.nodes)

    nodes
    |> Enum.reduce(%{}, fn node_id, acc ->
      ca = length(Yog.predecessors(simple_graph, node_id))
      ce = length(Yog.successors(simple_graph, node_id))

      instability =
        if ce + ca == 0 do
          0.0
        else
          ce / (ce + ca)
        end

      Map.put(acc, node_id, %{
        afferent: ca,
        efferent: ce,
        instability: Float.round(instability, 3)
      })
    end)
  end

  @doc """
  Identifies all Law of Demeter violations in the UML class diagram.

  A violation occurs when a class `A` has a direct relationship to a class `C`,
  but also has a path through an intermediate class `B` (i.e., `A -> B`, `B -> C`,
  and `A -> C`).

  Returns a list of triplets `[{class_a, class_b, class_c}]` representing the violations.

  ## Examples

      iex> uml =
      ...>   Choreo.UML.new()
      ...>   |> Choreo.UML.add_class(:a)
      ...>   |> Choreo.UML.add_class(:b)
      ...>   |> Choreo.UML.add_class(:c)
      ...>   |> Choreo.UML.add_relationship(:a, :b, type: :associates)
      ...>   |> Choreo.UML.add_relationship(:b, :c, type: :associates)
      ...>   |> Choreo.UML.add_relationship(:a, :c, type: :associates)
      iex> Choreo.UML.Analysis.law_of_demeter_violations(uml)
      [{:a, :b, :c}]
  """
  @spec law_of_demeter_violations(Choreo.UML.t()) :: [
          {Choreo.UML.class_id(), Choreo.UML.class_id(), Choreo.UML.class_id()}
        ]
  def law_of_demeter_violations(%Choreo.UML{} = uml) do
    # Convert multigraph to simple graph to simplify path/successor checks
    graph = Yog.Multi.to_simple_graph(uml.graph)
    nodes = Map.keys(graph.nodes)

    # Pre-calculate adjacent successors (distance = 1) for efficiency
    successors_map =
      Map.new(nodes, fn node ->
        {node, MapSet.new(Yog.successor_ids(graph, node))}
      end)

    # Find all triplets {A, B, C} where A -> B, B -> C, and A -> C
    for a <- nodes,
        b <- Map.fetch!(successors_map, a),
        c <- Map.fetch!(successors_map, b),
        a != b and b != c and a != c,
        MapSet.member?(Map.fetch!(successors_map, a), c) do
      {a, b, c}
    end
    |> Enum.sort()
  end
end
