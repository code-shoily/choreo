defmodule Choreo.UML.Analysis do
  @moduledoc """
  Architectural analysis suite for `Choreo.UML` class/struct diagrams.

  Provides static analysis tools optimized for functional and OOP software design:
    * `cycles/1` — identifies circular dependency loops.
    * `broken_contracts/1` — flags incomplete behavior/protocol realizations.
    * `coupling_metrics/1` — computes Afferent/Efferent coupling and Instability.
  """

  @doc """
  Identifies all circular dependency paths in the UML diagram.

  Cycles in structural diagrams indicate high coupling and are a major source
  of compilation cascades in Elixir applications.

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
    graph = uml.graph
    nodes = Map.keys(graph.nodes)

    {cycles, _visited} =
      Enum.reduce(nodes, {[], MapSet.new()}, fn node, {c_acc, v_acc} ->
        dfs_cycles(graph, node, v_acc, [], MapSet.new(), c_acc)
      end)

    cycles
    |> Enum.map(&normalize_cycle/1)
    |> Enum.uniq()
  end

  defp dfs_cycles(graph, node, visited, path_list, path_set, cycles) do
    cond do
      MapSet.member?(path_set, node) ->
        cycle = [node | Enum.take_while(path_list, &(&1 != node)) |> Enum.reverse()]
        {[cycle | cycles], visited}

      MapSet.member?(visited, node) ->
        {cycles, visited}

      true ->
        path_set = MapSet.put(path_set, node)
        path_list = [node | path_list]

        successors =
          Yog.Multi.successors(graph, node) |> Enum.map(fn {dest, _eid, _w} -> dest end)

        {cycles, visited} =
          Enum.reduce(successors, {cycles, visited}, fn succ, {c_acc, v_acc} ->
            dfs_cycles(graph, succ, v_acc, path_list, path_set, c_acc)
          end)

        visited = MapSet.put(visited, node)
        {cycles, visited}
    end
  end

  defp normalize_cycle(cycle) do
    min_element = Enum.min(cycle)
    {left, right} = Enum.split_while(cycle, &(&1 != min_element))
    right ++ left
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
      iex> [{:provider, :auth, [%{name: "verify", arity: 1}]}] = Choreo.UML.Analysis.broken_contracts(contract)
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
          from_node = graph.nodes[from]
          to_node = graph.nodes[to]

          if to_node[:type] in [:behavior, :protocol, :interface] do
            target_funcs = to_node[:functions] || []
            source_funcs = from_node[:functions] || []

            missing =
              Enum.filter(target_funcs, fn tf ->
                not Enum.any?(source_funcs, fn sf ->
                  sf[:name] == tf[:name] and (is_nil(tf[:arity]) or sf[:arity] == tf[:arity])
                end)
              end)

            if missing != [] do
              [{from, to, missing} | acc]
            else
              acc
            end
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
    graph = uml.graph
    nodes = Map.keys(graph.nodes)

    nodes
    |> Enum.reduce(%{}, fn node_id, acc ->
      succs =
        Yog.Multi.successors(graph, node_id)
        |> Enum.map(fn {dest, _eid, _w} -> dest end)
        |> Enum.uniq()

      preds =
        Yog.Multi.predecessors(graph, node_id)
        |> Enum.map(fn {src, _eid, _w} -> src end)
        |> Enum.uniq()

      ce = length(succs)
      ca = length(preds)

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
end
