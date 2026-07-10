defmodule Choreo.Requirement.Analysis do
  @moduledoc """
  Analysis algorithms for `Choreo.Requirement` diagrams.

  Provides traceability coverage, risk propagation, impact analysis, and
  structural validation.
  """

  alias Choreo.Requirement

  @doc """
  Returns requirements that have no relationships.

  ## Examples

      iex> req = Choreo.Requirement.new()
      ...>   |> Choreo.Requirement.add_requirement(:orphan, id: "R1", text: "Orphan")
      ...>   |> Choreo.Requirement.add_requirement(:sat, id: "R2", text: "Satisfied")
      ...>   |> Choreo.Requirement.add_component(:c)
      ...>   |> Choreo.Requirement.satisfies(:c, :sat)
      iex> Analysis.orphan_requirements(req)
      [:orphan]
  """
  @spec orphan_requirements(Requirement.t()) :: [Yog.node_id()]
  def orphan_requirements(%Requirement{} = req) do
    requirement_ids = MapSet.new(Requirement.requirements(req))

    connected_ids =
      req.graph.edges
      |> Enum.flat_map(fn {_edge_id, {from, to, _weight}} -> [from, to] end)
      |> MapSet.new()

    requirement_ids
    |> MapSet.difference(connected_ids)
    |> MapSet.to_list()
    |> Enum.sort()
  end

  @doc """
  Returns requirements with no `satisfies` edge from a component.

  ## Examples

      iex> req = Choreo.Requirement.new()
      ...>   |> Choreo.Requirement.add_requirement(:unsat, id: "R1", text: "Unsatisfied")
      ...>   |> Choreo.Requirement.add_requirement(:sat, id: "R2", text: "Satisfied")
      ...>   |> Choreo.Requirement.add_component(:c)
      ...>   |> Choreo.Requirement.satisfies(:c, :sat)
      iex> Analysis.unsatisfied(req)
      [:unsat]
  """
  @spec unsatisfied(Requirement.t()) :: [Yog.node_id()]
  def unsatisfied(%Requirement{} = req) do
    satisfied =
      req.graph.edges
      |> Enum.flat_map(fn {edge_id, {_from, to, _weight}} ->
        meta = Map.get(req.edge_meta, edge_id, %{})
        if meta[:type] == :satisfies, do: [to], else: []
      end)
      |> MapSet.new()

    Requirement.requirements(req)
    |> Enum.reject(&MapSet.member?(satisfied, &1))
    |> Enum.sort()
  end

  @doc """
  Returns requirements with no `verifies` edge from a test.

  ## Examples

      iex> req = Choreo.Requirement.new()
      ...>   |> Choreo.Requirement.add_requirement(:unver, id: "R1", text: "Unverified")
      ...>   |> Choreo.Requirement.add_requirement(:ver, id: "R2", text: "Verified")
      ...>   |> Choreo.Requirement.add_test(:t)
      ...>   |> Choreo.Requirement.verifies(:t, :ver)
      iex> Analysis.unverified(req)
      [:unver]
  """
  @spec unverified(Requirement.t()) :: [Yog.node_id()]
  def unverified(%Requirement{} = req) do
    verified =
      req.graph.edges
      |> Enum.flat_map(fn {edge_id, {_from, to, _weight}} ->
        meta = Map.get(req.edge_meta, edge_id, %{})
        if meta[:type] == :verifies, do: [to], else: []
      end)
      |> MapSet.new()

    Requirement.requirements(req)
    |> Enum.reject(&MapSet.member?(verified, &1))
    |> Enum.sort()
  end

  @doc """
  Returns coverage statistics for the requirements diagram.

  Returns a map with satisfied, verified, and orphan requirement IDs plus
  ratios.

  ## Examples

      iex> req = Choreo.Requirement.new()
      ...>   |> Choreo.Requirement.add_requirement(:r1, id: "R1", text: "One")
      ...>   |> Choreo.Requirement.add_requirement(:r2, id: "R2", text: "Two")
      ...>   |> Choreo.Requirement.add_component(:c)
      ...>   |> Choreo.Requirement.add_test(:t)
      ...>   |> Choreo.Requirement.satisfies(:c, :r1)
      ...>   |> Choreo.Requirement.verifies(:t, :r2)
      iex> %{satisfied: [:r1], verified: [:r2], orphan: []} = Analysis.coverage(req)
  """
  @spec coverage(Requirement.t()) :: map()
  def coverage(%Requirement{} = req) do
    reqs = Requirement.requirements(req)
    total = length(reqs)

    satisfied =
      unsatisfied(req)
      |> MapSet.new()
      |> then(&MapSet.difference(MapSet.new(reqs), &1))
      |> MapSet.to_list()
      |> Enum.sort()

    verified =
      unverified(req)
      |> MapSet.new()
      |> then(&MapSet.difference(MapSet.new(reqs), &1))
      |> MapSet.to_list()
      |> Enum.sort()

    orphan = orphan_requirements(req)

    %{
      total: total,
      satisfied: satisfied,
      verified: verified,
      orphan: orphan,
      ratios: %{
        satisfied: if(total > 0, do: length(satisfied) / total, else: 1.0),
        verified: if(total > 0, do: length(verified) / total, else: 1.0),
        orphan: if(total > 0, do: length(orphan) / total, else: 0.0)
      }
    }
  end

  @doc """
  Returns a traceability matrix: requirements mapped to their related
  components, tests, and stakeholders.

  ## Examples

      iex> req = Choreo.Requirement.new()
      ...>   |> Choreo.Requirement.add_requirement(:r1, id: "R1", text: "One")
      ...>   |> Choreo.Requirement.add_component(:c)
      ...>   |> Choreo.Requirement.satisfies(:c, :r1)
      iex> matrix = Analysis.traceability_matrix(req)
      iex> matrix[:r1].components
      [:c]
  """
  @spec traceability_matrix(Requirement.t()) :: %{Yog.node_id() => map()}
  def traceability_matrix(%Requirement{} = req) do
    req.graph.edges
    |> Enum.reduce(%{}, fn {edge_id, {from, to, _weight}}, acc ->
      meta = Map.get(req.edge_meta, edge_id, %{})
      type = meta[:type]

      acc
      |> add_matrix_entry(to, from, type, :satisfies, :components)
      |> add_matrix_entry(to, from, type, :verifies, :tests)
      |> add_matrix_entry(to, from, type, :traces, :stakeholders)
      |> add_matrix_entry(from, to, type, :refines, :refined_by)
      |> add_matrix_entry(from, to, type, :depends, :depends_on)
      |> add_matrix_entry(from, to, type, :contains, :children)
      |> add_matrix_entry(from, to, type, :derives, :derived_from)
    end)
  end

  defp add_matrix_entry(acc, key, related, type, expected_type, bucket) do
    if type == expected_type do
      Map.update(acc, key, %{bucket => [related]}, fn existing ->
        Map.update(existing, bucket, [related], fn list -> [related | list] end)
      end)
    else
      acc
    end
  end

  @doc """
  Returns requirements related to a given component, test, or stakeholder.

  ## Examples

      iex> req = Choreo.Requirement.new()
      ...>   |> Choreo.Requirement.add_requirement(:r1, id: "R1", text: "One")
      ...>   |> Choreo.Requirement.add_component(:c)
      ...>   |> Choreo.Requirement.satisfies(:c, :r1)
      iex> Analysis.requirements_for(req, :c)
      [:r1]
  """
  @spec requirements_for(Requirement.t(), Yog.node_id()) :: [Yog.node_id()]
  def requirements_for(%Requirement{} = req, id) do
    req.graph.edges
    |> Enum.flat_map(fn {edge_id, {from, to, _weight}} ->
      meta = Map.get(req.edge_meta, edge_id, %{})

      cond do
        from == id and meta[:type] in [:satisfies, :verifies, :traces] -> [to]
        to == id and meta[:type] in [:traces] -> [from]
        true -> []
      end
    end)
    |> Enum.filter(fn related_id ->
      case Requirement.node(req, related_id) do
        %{node_type: :requirement} -> true
        _ -> false
      end
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Returns components, tests, and stakeholders related to a requirement.

  ## Examples

      iex> req = Choreo.Requirement.new()
      ...>   |> Choreo.Requirement.add_requirement(:r1, id: "R1", text: "One")
      ...>   |> Choreo.Requirement.add_component(:c)
      ...>   |> Choreo.Requirement.satisfies(:c, :r1)
      iex> Analysis.components_for(req, :r1)
      [:c]
  """
  @spec components_for(Requirement.t(), Yog.node_id()) :: [Yog.node_id()]
  def components_for(%Requirement{} = req, id) do
    req.graph.edges
    |> Enum.flat_map(fn {edge_id, {from, to, _weight}} ->
      meta = Map.get(req.edge_meta, edge_id, %{})

      cond do
        to == id and meta[:type] in [:satisfies, :verifies, :traces] -> [from]
        from == id and meta[:type] == :traces -> [to]
        true -> []
      end
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Returns high or critical risk requirements that are neither satisfied nor
  verified.

  ## Examples

      iex> req = Choreo.Requirement.new()
      ...>   |> Choreo.Requirement.add_requirement(:r1,
      ...>     id: "R1",
      ...>     text: "Critical",
      ...>     risk: :critical
      ...>   )
      ...>   |> Choreo.Requirement.add_component(:c)
      ...>   |> Choreo.Requirement.satisfies(:c, :r1)
      iex> Analysis.high_risk_gaps(req)
      [] # satisfied, so not a gap
  """
  @spec high_risk_gaps(Requirement.t()) :: [Yog.node_id()]
  def high_risk_gaps(%Requirement{} = req) do
    high_risk = high_risk_requirements(req)
    unsatisfied_set = MapSet.new(unsatisfied(req))
    unverified_set = MapSet.new(unverified(req))

    high_risk
    |> Enum.filter(fn id ->
      MapSet.member?(unsatisfied_set, id) and MapSet.member?(unverified_set, id)
    end)
    |> Enum.sort()
  end

  @doc """
  Propagates risk from parent requirements down to their children.

  A child requirement inherits the maximum risk of any ancestor through
  `refines`, `contains`, or `derives` relationships.

  Returns a map of requirement ID to propagated risk.
  """
  @spec risk_propagation(Requirement.t()) :: %{Yog.node_id() => atom()}
  def risk_propagation(%Requirement{} = req) do
    reqs = Requirement.requirements(req)

    Enum.reduce(reqs, %{}, fn id, acc ->
      base_risk = req.graph.nodes[id][:risk] || :medium
      ancestor_risks = ancestor_risks(req, id)
      propagated = max_risk([base_risk | ancestor_risks])
      Map.put(acc, id, propagated)
    end)
  end

  defp ancestor_risks(req, id) do
    req.graph.edges
    |> Enum.flat_map(fn {edge_id, {from, to, _weight}} ->
      meta = Map.get(req.edge_meta, edge_id, %{})

      if parent_of?(id, from, to, meta[:type]) do
        parent = parent_id(from, to, meta[:type])
        [parent | ancestor_risks(req, parent)]
      else
        []
      end
    end)
    |> Enum.map(fn ancestor_id -> req.graph.nodes[ancestor_id][:risk] || :medium end)
  end

  @doc """
  Returns high or critical risk requirements that do not have a lower-risk
  child refinement.

  These are risks that have not been decomposed into more manageable pieces.
  """
  @spec unmitigated_risks(Requirement.t()) :: [Yog.node_id()]
  def unmitigated_risks(%Requirement{} = req) do
    high_risk = high_risk_requirements(req)

    Enum.filter(high_risk, fn id ->
      children = children_of(req, id)

      if children == [] do
        true
      else
        Enum.all?(children, fn child_id ->
          risk = req.graph.nodes[child_id][:risk] || :medium
          risk_level(risk) >= risk_level(:high)
        end)
      end
    end)
    |> Enum.sort()
  end

  @doc """
  Returns all nodes upstream and downstream of a given node.

  Useful for impact analysis: "if I change this component, what else is
  affected?"

  ## Examples

      iex> req = Choreo.Requirement.new()
      ...>   |> Choreo.Requirement.add_requirement(:r1, id: "R1", text: "One")
      ...>   |> Choreo.Requirement.add_component(:c)
      ...>   |> Choreo.Requirement.satisfies(:c, :r1)
      iex> Analysis.impact_of(req, :c)
      [:r1]
  """
  @spec impact_of(Requirement.t(), Yog.node_id()) :: [Yog.node_id()]
  def impact_of(%Requirement{} = req, id) do
    forward = bfs_edges(req.graph, id, :out)
    backward = bfs_edges(req.graph, id, :in)

    MapSet.union(forward, backward)
    |> MapSet.delete(id)
    |> MapSet.to_list()
    |> Enum.sort()
  end

  defp bfs_edges(graph, seed, direction) do
    do_bfs_edges(graph, [seed], MapSet.new([seed]), direction)
  end

  defp do_bfs_edges(_graph, [], visited, _direction), do: visited

  defp do_bfs_edges(graph, [current | rest], visited, direction) do
    neighbors =
      if direction == :out do
        graph.edges
        |> Enum.flat_map(fn {_edge_id, {from, to, _weight}} ->
          if from == current, do: [to], else: []
        end)
      else
        graph.edges
        |> Enum.flat_map(fn {_edge_id, {from, to, _weight}} ->
          if to == current, do: [from], else: []
        end)
      end
      |> Enum.uniq()

    new_neighbors = Enum.reject(neighbors, &MapSet.member?(visited, &1))

    do_bfs_edges(
      graph,
      rest ++ new_neighbors,
      MapSet.union(visited, MapSet.new(new_neighbors)),
      direction
    )
  end

  @doc """
  Detects cycles among requirement-to-requirement relationships.

  Only considers `depends`, `refines`, `contains`, and `derives` edges.

  Returns a list of cycles, where each cycle is a list of node IDs.
  """
  @spec circular_dependencies(Requirement.t()) :: [[Yog.node_id()]]
  def circular_dependencies(%Requirement{} = req) do
    requirement_graph = requirement_only_graph(req)

    if Yog.cyclic?(requirement_graph) do
      requirement_graph
      |> strongly_connected_components()
      |> Enum.filter(fn component ->
        length(component) > 1 or self_loop?(requirement_graph, component)
      end)
    else
      []
    end
  end

  defp requirement_only_graph(req) do
    req_ids = MapSet.new(Requirement.requirements(req))

    edges =
      req.graph.edges
      |> Enum.filter(fn {edge_id, {from, to, _weight}} ->
        meta = Map.get(req.edge_meta, edge_id, %{})

        MapSet.member?(req_ids, from) and MapSet.member?(req_ids, to) and
          meta[:type] in [:depends, :refines, :contains, :derives]
      end)
      |> Enum.map(fn {_edge_id, {from, to, _weight}} -> {from, to} end)

    graph = Yog.directed()
    graph = Enum.reduce(req_ids, graph, &Yog.add_node(&2, &1, %{}))

    Enum.reduce(edges, graph, fn {from, to}, g ->
      Yog.add_edge_ensure(g, from, to, 1)
    end)
  end

  defp strongly_connected_components(graph) do
    # Tarjan's algorithm
    {components, _} = tarjan(graph)
    components
  end

  defp tarjan(graph) do
    nodes = Map.keys(graph.nodes)
    state = %{index: 0, stack: [], on_stack: MapSet.new(), indices: %{}, lowlinks: %{}, sccs: []}

    Enum.reduce(nodes, {[], state}, fn node, {sccs, state} ->
      if Map.has_key?(state.indices, node) do
        {sccs, state}
      else
        {new_sccs, new_state} = strongconnect(node, graph, state)
        {sccs ++ new_sccs, new_state}
      end
    end)
  end

  defp strongconnect(node, graph, state) do
    state = %{
      state
      | index: state.index + 1,
        indices: Map.put(state.indices, node, state.index),
        lowlinks: Map.put(state.lowlinks, node, state.index),
        stack: [node | state.stack],
        on_stack: MapSet.put(state.on_stack, node)
    }

    successors =
      Map.get(graph.out_edges, node, %{}) |> Map.keys()

    state =
      Enum.reduce(successors, state, fn successor, acc ->
        cond do
          not Map.has_key?(acc.indices, successor) ->
            {_, new_state} = strongconnect(successor, graph, acc)
            new_lowlink = min(acc.lowlinks[node], new_state.lowlinks[successor])
            put_in_lowlink(new_state, node, new_lowlink)

          MapSet.member?(acc.on_stack, successor) ->
            new_lowlink = min(acc.lowlinks[node], acc.indices[successor])
            put_in_lowlink(acc, node, new_lowlink)

          true ->
            acc
        end
      end)

    if state.lowlinks[node] == state.indices[node] do
      {scc, rest_stack, on_stack} = pop_scc(state.stack, state.on_stack, node)
      {[scc | state.sccs], %{state | stack: rest_stack, on_stack: on_stack}}
    else
      {[], state}
    end
  end

  defp put_in_lowlink(state, node, value) do
    %{state | lowlinks: Map.put(state.lowlinks, node, value)}
  end

  defp pop_scc(stack, on_stack, node, acc \\ []) do
    [current | rest] = stack
    on_stack = MapSet.delete(on_stack, current)
    acc = [current | acc]

    if current == node do
      {acc, rest, on_stack}
    else
      pop_scc(rest, on_stack, node, acc)
    end
  end

  defp self_loop?(graph, [node]) do
    Map.has_key?(Map.get(graph.out_edges, node, %{}), node)
  end

  @doc """
  Evaluates structural integrity and returns a list of human-readable warnings and errors.
  """
  @spec validate(Requirement.t()) :: [{:error | :warning, String.t()}]
  def validate(%Requirement{} = req) do
    req
    |> validate_raw()
    |> Enum.map(&format_message/1)
  end

  defp validate_raw(%Requirement{} = req) do
    []
    |> validate_requirement_fields(req)
    |> validate_allowed_values(req)
    |> validate_components(req)
    |> validate_circular_dependencies(req)
    |> validate_high_risk_gaps(req)
  end

  @doc """
  Returns human-readable validation messages.
  """
  @spec validate_messages(Requirement.t()) :: [{:error | :warning, String.t()}]
  def validate_messages(%Requirement{} = req) do
    validate(req)
  end

  defp validate_requirement_fields(acc, req) do
    Requirement.requirements(req)
    |> Enum.reduce(acc, fn id, acc ->
      data = req.graph.nodes[id]

      acc =
        if blank?(data[:id]) do
          [{:error, :missing_requirement_id, id} | acc]
        else
          acc
        end

      if blank?(data[:text]) do
        [{:error, :missing_requirement_text, id} | acc]
      else
        acc
      end
    end)
  end

  defp validate_allowed_values(acc, req) do
    Requirement.requirements(req)
    |> Enum.reduce(acc, fn id, acc ->
      data = req.graph.nodes[id]

      acc =
        if data[:risk] in [:low, :medium, :high, :critical, nil] do
          acc
        else
          [{:warning, :invalid_risk, id} | acc]
        end

      if data[:verification] in [:analysis, :inspection, :test, :demonstration, nil] do
        acc
      else
        [{:warning, :invalid_verification, id} | acc]
      end
    end)
  end

  defp validate_components(acc, req) do
    (Requirement.components(req) ++ Requirement.tests(req) ++ Requirement.stakeholders(req))
    |> Enum.reduce(acc, fn id, acc ->
      data = req.graph.nodes[id]

      if blank?(data[:label]) do
        [{:warning, :empty_label, id} | acc]
      else
        acc
      end
    end)
  end

  defp validate_circular_dependencies(acc, req) do
    circular_dependencies(req)
    |> Enum.reduce(acc, fn cycle, acc ->
      [{:warning, :circular_dependency, cycle} | acc]
    end)
  end

  defp validate_high_risk_gaps(acc, req) do
    high_risk_gaps(req)
    |> Enum.reduce(acc, fn id, acc ->
      [{:warning, :high_risk_gap, id} | acc]
    end)
  end

  defp format_message({severity, :missing_requirement_id, id}) do
    {severity, "Requirement #{inspect(id)} is missing a required :id"}
  end

  defp format_message({severity, :missing_requirement_text, id}) do
    {severity, "Requirement #{inspect(id)} is missing required :text"}
  end

  defp format_message({severity, :invalid_risk, id}) do
    {severity, "Requirement #{inspect(id)} has an invalid :risk value"}
  end

  defp format_message({severity, :invalid_verification, id}) do
    {severity, "Requirement #{inspect(id)} has an invalid :verification value"}
  end

  defp format_message({severity, :empty_label, id}) do
    {severity, "Node #{inspect(id)} has an empty :label"}
  end

  defp format_message({severity, :circular_dependency, cycle}) do
    {severity, "Circular dependency detected: #{Enum.map_join(cycle, " -> ", &inspect/1)}"}
  end

  defp format_message({severity, :high_risk_gap, id}) do
    {severity, "High-risk requirement #{inspect(id)} is not fully satisfied or verified"}
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp high_risk_requirements(req) do
    req.graph.nodes
    |> Enum.filter(fn {_id, data} ->
      data[:node_type] == :requirement and risk_level(data[:risk]) >= risk_level(:high)
    end)
    |> Enum.map(fn {id, _data} -> id end)
    |> Enum.sort()
  end

  defp risk_level(:low), do: 1
  defp risk_level(:medium), do: 2
  defp risk_level(:high), do: 3
  defp risk_level(:critical), do: 4
  defp risk_level(_), do: 2

  defp max_risk(risks) do
    risks
    |> Enum.max_by(&risk_level/1, fn -> :medium end)
  end

  # Parent/child helpers respect the semantic direction of each edge type:
  #   * refines: child -> parent
  #   * derives: derived -> source
  #   * contains: parent -> child
  defp parent_of?(id, from, _to, :refines), do: from == id
  defp parent_of?(id, from, _to, :derives), do: from == id
  defp parent_of?(id, _from, to, :contains), do: to == id
  defp parent_of?(_id, _from, _to, _type), do: false

  defp parent_id(_from, to, :refines), do: to
  defp parent_id(_from, to, :derives), do: to
  defp parent_id(from, _to, :contains), do: from

  defp children_of(req, id) do
    req.graph.edges
    |> Enum.flat_map(fn {edge_id, {from, to, _weight}} ->
      meta = Map.get(req.edge_meta, edge_id, %{})

      cond do
        meta[:type] == :refines and to == id -> [from]
        meta[:type] == :derives and to == id -> [from]
        meta[:type] == :contains and from == id -> [to]
        true -> []
      end
    end)
    |> Enum.uniq()
  end

  defp blank?(nil), do: true
  defp blank?(s) when is_binary(s), do: String.trim(s) == ""
  defp blank?(_), do: true
end
