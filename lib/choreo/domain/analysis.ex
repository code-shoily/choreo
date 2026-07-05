defmodule Choreo.Domain.Analysis do
  @moduledoc """
  Audit and analysis rules for `Choreo.Domain` diagrams.

  Validates Event Storming graphs against logical rules:
  1. Commands must target an Aggregate or Workflow.
  2. Events must be emitted by an Aggregate, Workflow, or External System.
  3. Events must not be dead-ends (they should trigger a Policy, Read Model, or Actor).
  4. Policies must trigger a Command.
  """

  alias Choreo.Domain

  @doc """
  Runs semantic validation rules against a domain model.

  Returns a list of `{severity, message}` tuples for cross-module composability.

  Severity levels:
    * `:error` — structural issues (missing targets, missing causes)
    * `:warning` — soft semantic checks (dead-ends, passive actors)

  This is the cross-module validation entry point. It is equivalent to
  `warnings/1`, which is kept as a domain-specific alias.
  """
  @spec validate(Domain.t()) :: [{:error | :warning, String.t()}]
  def validate(%Domain{} = domain), do: warnings(domain)

  @doc """
  Runs semantic audit rules against a domain model.
  """
  @spec warnings(Domain.t()) :: [{:error | :warning, String.t()}]
  def warnings(%Domain{} = domain) do
    nodes = Domain.nodes(domain)
    edges = Domain.edges(domain)

    # Pre-calculate incoming/outgoing index maps for speed
    {incoming_map, outgoing_map} = build_adjacency_maps(edges)

    []
    # Rule 1: Command must target an Aggregate or Workflow
    |> check_command_targets(nodes, outgoing_map)
    # Rule 2: Event must have a cause (aggregate, workflow, external_system)
    |> check_event_causes(nodes, incoming_map)
    # Rule 3: Event must not be a dead end
    |> check_event_effects(nodes, outgoing_map)
    # Rule 4: Policy must trigger a Command
    |> check_policy_commands(nodes, outgoing_map)
    # Rule 5: Aggregate with no incoming Command (orphan aggregate)
    |> check_orphan_aggregates(nodes, incoming_map)
    # Rule 6: Actor with no outgoing Command (passive actor)
    |> check_passive_actors(nodes, outgoing_map)
    # Rule 7: Type with no :fields (empty type)
    |> check_empty_types(nodes)
    # Rule 8: Context boundary with zero member nodes
    |> check_empty_contexts(domain)
    # Rule 9: Semantic helper relationship endpoint validation
    |> check_semantic_relationships(domain)
    # Rule 10: Named scenario path validation
    |> check_scenarios(domain)
    # Rule 11: DDD strategic/tactical metadata quality hints
    |> check_domain_design_metadata(nodes)
  end

  @doc """
  Generates a Markdown-formatted table representing the Ubiquitous Language (glossary)
  extracted from all nodes, aggregates, events, and types defined in the domain.
  """
  @spec ubiquitous_language(Domain.t()) :: String.t()
  def ubiquitous_language(%Domain{} = domain) do
    nodes = Domain.nodes(domain)

    rows =
      nodes
      |> Enum.sort_by(fn {id, data} -> data[:name] || to_string(id) end)
      |> Enum.map_join("\n", fn {id, data} ->
        term = data[:name] || to_string(id)

        stereotype =
          (data[:type] || :generic)
          |> to_string()
          |> String.split("_")
          |> Enum.map_join(" ", &String.capitalize/1)

        context_lbl =
          if cluster = data[:cluster] do
            case Map.get(domain.clusters, cluster) do
              %{label: lbl} -> lbl
              _ -> String.replace_prefix(cluster, "cluster_", "")
            end
          else
            "Global"
          end

        description = data[:description] || "No description provided."
        desc_escaped = String.replace(description, "|", "\\|")

        "| **#{term}** | `#{stereotype}` | *#{context_lbl}* | #{desc_escaped} |"
      end)

    """
    | Term | Stereotype | Bounded Context | Description / Definition |
    |---|---|---|---|
    """ <> rows
  end

  # ============================================================================
  # Internal Rules
  # ============================================================================

  defp check_command_targets(acc, nodes, outgoing) do
    Enum.reduce(nodes, acc, fn {id, data}, list ->
      if data[:type] == :command do
        targets = Map.get(outgoing, id, [])

        has_valid_target =
          Enum.any?(targets, fn target_id ->
            target_data = Map.get(nodes, target_id, %{})
            target_data[:type] in [:aggregate, :workflow]
          end)

        if has_valid_target do
          list
        else
          [
            {:error,
             "Command '#{data[:name]}' is orphaned (it does not target any aggregate or workflow)."}
            | list
          ]
        end
      else
        list
      end
    end)
  end

  defp check_event_causes(acc, nodes, incoming) do
    Enum.reduce(nodes, acc, fn {id, data}, list ->
      if data[:type] == :event do
        causes = Map.get(incoming, id, [])

        has_valid_cause =
          Enum.any?(causes, fn cause_id ->
            cause_data = Map.get(nodes, cause_id, %{})
            cause_data[:type] in [:aggregate, :workflow, :external_system]
          end)

        if has_valid_cause do
          list
        else
          [
            {:error,
             "Domain Event '#{data[:name]}' is missing a cause (it is not emitted by any aggregate, workflow, or external system)."}
            | list
          ]
        end
      else
        list
      end
    end)
  end

  defp check_event_effects(acc, nodes, outgoing) do
    Enum.reduce(nodes, acc, fn {id, data}, list ->
      if data[:type] == :event do
        effects = Map.get(outgoing, id, [])

        has_valid_effect =
          Enum.any?(effects, fn effect_id ->
            effect_data = Map.get(nodes, effect_id, %{})
            effect_data[:type] in [:policy, :read_model, :actor]
          end)

        if has_valid_effect do
          list
        else
          [
            {:warning,
             "Domain Event '#{data[:name]}' is a dead-end (it does not trigger any policies, read models, or notify actors)."}
            | list
          ]
        end
      else
        list
      end
    end)
  end

  defp check_policy_commands(acc, nodes, outgoing) do
    Enum.reduce(nodes, acc, fn {id, data}, list ->
      if data[:type] == :policy do
        effects = Map.get(outgoing, id, [])

        has_valid_effect =
          Enum.any?(effects, fn effect_id ->
            effect_data = Map.get(nodes, effect_id, %{})
            effect_data[:type] == :command
          end)

        if has_valid_effect do
          list
        else
          [{:error, "Policy '#{data[:name]}' does not trigger any commands."} | list]
        end
      else
        list
      end
    end)
  end

  defp check_orphan_aggregates(acc, nodes, incoming) do
    Enum.reduce(nodes, acc, fn {id, data}, list ->
      if data[:type] == :aggregate do
        causes = Map.get(incoming, id, [])

        has_command =
          Enum.any?(causes, fn cause_id ->
            cause_data = Map.get(nodes, cause_id, %{})
            cause_data[:type] == :command
          end)

        if has_command do
          list
        else
          [
            {:warning, "Aggregate '#{data[:name]}' has no incoming commands."}
            | list
          ]
        end
      else
        list
      end
    end)
  end

  defp check_passive_actors(acc, nodes, outgoing) do
    Enum.reduce(nodes, acc, fn {id, data}, list ->
      if data[:type] == :actor do
        effects = Map.get(outgoing, id, [])

        has_command =
          Enum.any?(effects, fn effect_id ->
            effect_data = Map.get(nodes, effect_id, %{})
            effect_data[:type] == :command
          end)

        if has_command do
          list
        else
          [
            {:warning, "Actor '#{data[:name]}' has no outgoing commands."}
            | list
          ]
        end
      else
        list
      end
    end)
  end

  defp check_empty_types(acc, nodes) do
    Enum.reduce(nodes, acc, fn {_id, data}, list ->
      if data[:type] == :type do
        fields = data[:fields] || []

        if fields == [] do
          [{:warning, "Type '#{data[:name]}' has no fields."} | list]
        else
          list
        end
      else
        list
      end
    end)
  end

  defp check_semantic_relationships(acc, %Domain{} = domain) do
    Enum.reduce(domain.edge_meta, acc, fn {edge_id, meta}, list ->
      relationship = meta[:relationship]

      if meta[:type] == :domain_relationship and relationship do
        {from, to, _weight} = Map.fetch!(domain.graph.edges, edge_id)
        from_type = domain.graph.nodes |> Map.fetch!(from) |> Map.get(:type)
        to_type = domain.graph.nodes |> Map.fetch!(to) |> Map.get(:type)

        if valid_semantic_relationship?(relationship, from_type, to_type) do
          list
        else
          [
            {:warning,
             "Relationship #{inspect(relationship)} from #{inspect(from)} (#{inspect(from_type)}) to #{inspect(to)} (#{inspect(to_type)}) has unusual endpoint types."}
            | list
          ]
        end
      else
        list
      end
    end)
  end

  defp valid_semantic_relationship?(:initiates, from_type, :command),
    do: from_type in [:actor, :external_system, :workflow, :policy]

  defp valid_semantic_relationship?(:handles, :command, to_type),
    do: to_type in [:aggregate, :workflow]

  defp valid_semantic_relationship?(:emits, from_type, :event),
    do: from_type in [:aggregate, :workflow, :external_system]

  defp valid_semantic_relationship?(:triggers, from_type, to_type),
    do: from_type in [:event, :policy, :workflow] and to_type in [:command, :policy, :workflow]

  defp valid_semantic_relationship?(:projects_to, :event, :read_model), do: true
  defp valid_semantic_relationship?(:notifies, :event, :actor), do: true

  defp valid_semantic_relationship?(:translates_via, _from_type, to_type),
    do: to_type in [:acl, :external_system, :context]

  defp valid_semantic_relationship?(_relationship, _from_type, _to_type), do: false

  defp check_scenarios(acc, %Domain{} = domain) do
    Enum.reduce(domain.scenarios, acc, fn {name, scenario}, list ->
      path = scenario[:path] || []
      missing = Enum.reject(path, &Map.has_key?(domain.graph.nodes, &1))

      disconnected =
        path
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.reject(fn [from, to] -> connected?(domain.graph.edges, from, to) end)

      list =
        if missing == [] do
          list
        else
          [
            {:error, "Scenario #{inspect(name)} references missing nodes: #{inspect(missing)}"}
            | list
          ]
        end

      if disconnected == [] do
        list
      else
        pairs = Enum.map(disconnected, fn [from, to] -> {from, to} end)

        [
          {:warning, "Scenario #{inspect(name)} contains disconnected steps: #{inspect(pairs)}"}
          | list
        ]
      end
    end)
  end

  defp check_domain_design_metadata(acc, nodes) do
    Enum.reduce(nodes, acc, fn {_id, data}, list ->
      cond do
        data[:type] == :aggregate and (data[:invariants] || []) == [] ->
          [{:warning, "Aggregate '#{data[:name]}' has no documented invariants."} | list]

        data[:type] == :context and is_nil(data[:subdomain]) ->
          [{:warning, "Bounded Context '#{data[:name]}' has no subdomain classification."} | list]

        true ->
          list
      end
    end)
  end

  defp connected?(edges, from, to) do
    Enum.any?(edges, fn {_edge_id, {edge_from, edge_to, _weight}} ->
      edge_from == from and edge_to == to
    end)
  end

  defp check_empty_contexts(acc, %Domain{graph: graph, clusters: clusters}) do
    context_clusters =
      clusters
      |> Enum.filter(fn {_name, meta} -> meta[:cluster_type] == :context_boundary end)
      |> Enum.map(fn {name, _meta} -> name end)

    populated =
      graph.nodes
      |> Enum.flat_map(fn {_id, data} ->
        if data[:cluster], do: [data[:cluster]], else: []
      end)
      |> MapSet.new()

    empty =
      Enum.reject(context_clusters, &MapSet.member?(populated, &1))

    if empty == [] do
      acc
    else
      labels = Enum.map(empty, &String.replace_prefix(&1, "cluster_", ""))
      [{:warning, "Empty context boundaries: #{inspect(labels)}"} | acc]
    end
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp build_adjacency_maps(edges) do
    Enum.reduce(edges, {%{}, %{}}, fn {from, to, _weight}, {inc, out} ->
      new_inc = Map.update(inc, to, [from], &[from | &1])
      new_out = Map.update(out, from, [to], &[to | &1])
      {new_inc, new_out}
    end)
  end
end
