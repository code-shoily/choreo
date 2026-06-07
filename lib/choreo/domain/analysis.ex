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
  Runs semantic audit rules against a domain model and returns a list of warning strings.
  """
  @spec warnings(Domain.t()) :: [String.t()]
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
        stereotype = String.capitalize(to_string(data[:type] || :generic))

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
            "Command '#{data[:name]}' is orphaned (it does not target any aggregate or workflow)."
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
            "Domain Event '#{data[:name]}' is missing a cause (it is not emitted by any aggregate, workflow, or external system)."
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
            "Domain Event '#{data[:name]}' is a dead-end (it does not trigger any policies, read models, or notify actors)."
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
          ["Policy '#{data[:name]}' does not trigger any commands." | list]
        end
      else
        list
      end
    end)
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
