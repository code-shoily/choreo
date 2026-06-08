defmodule Choreo.C4.Analysis do
  @moduledoc """
  Analysis functions for `Choreo.C4` architecture models.

  Provides validation and insight functions that answer practical questions
  about your C4 model:

    * Are there orphaned nodes with no relationships?
    * Are there containers or components without parents?
    * Which elements are missing descriptions or technology labels?
    * Is the model structurally consistent?

  ## Further reading

    * [C4 Model](https://c4model.com/)
    * [Software Architecture for Developers (Simon Brown)](https://softwarearchitecturefordevelopers.com/)
  """

  alias Choreo.C4

  @doc """
  Returns nodes with no connections (zero in-degree and out-degree).

  Isolated elements in a C4 diagram are usually a mistake — either a
  missing relationship or an element that should be removed.

  ## Examples

      iex> c4 = Choreo.C4.new()
      ...>   |> Choreo.C4.add_person(:a)
      ...>   |> Choreo.C4.add_software_system(:b)
      iex> Choreo.C4.Analysis.isolated_nodes(c4)
      [:a, :b]

      iex> c4 = Choreo.C4.new()
      ...>   |> Choreo.C4.add_person(:a)
      ...>   |> Choreo.C4.add_software_system(:b)
      ...>   |> Choreo.C4.add_relationship(:a, :b)
      iex> Choreo.C4.Analysis.isolated_nodes(c4)
      []

  This analysis answers the question: "Which elements have no relationships?"
  """
  @spec isolated_nodes(C4.t()) :: [Yog.node_id()]
  def isolated_nodes(%C4{} = c4) do
    simple_graph = C4.to_graph(c4) |> Yog.Multi.to_simple_graph()

    simple_graph.nodes
    |> Map.keys()
    |> Enum.filter(fn id ->
      Yog.in_degree(simple_graph, id) == 0 and Yog.out_degree(simple_graph, id) == 0
    end)
    |> Enum.sort()
  end

  @doc """
  Returns containers or components that have no parent.

  In the C4 model every container should belong to a software system,
  and every component should belong to a container.

  ## Examples

      iex> c4 = Choreo.C4.new()
      ...>   |> Choreo.C4.add_container(:api, label: "API")
      iex> Choreo.C4.Analysis.missing_parents(c4)
      [:api]

      iex> c4 = Choreo.C4.new()
      ...>   |> Choreo.C4.add_software_system(:banking)
      ...>   |> Choreo.C4.add_container(:api, parent: :banking)
      iex> Choreo.C4.Analysis.missing_parents(c4)
      []

  This analysis answers the question: "Which containers or components are missing a parent?"
  """
  @spec missing_parents(C4.t()) :: [Yog.node_id()]
  def missing_parents(%C4{} = c4) do
    c4.graph.nodes
    |> Enum.filter(fn {_id, data} ->
      data[:node_type] in [:container, :component] and is_nil(data[:parent])
    end)
    |> Enum.map(fn {id, _data} -> id end)
  end

  @doc """
  Returns nodes that are missing a description.

  In C4, every element should have a meaningful description.

  ## Examples

      iex> c4 = Choreo.C4.new()
      ...>   |> Choreo.C4.add_person(:a, label: "A", description: "User A")
      ...>   |> Choreo.C4.add_software_system(:b, label: "B")
      iex> Choreo.C4.Analysis.missing_descriptions(c4)
      [:b]

  This analysis answers the question: "Which elements lack descriptions?"
  """
  @spec missing_descriptions(C4.t()) :: [Yog.node_id()]
  def missing_descriptions(%C4{} = c4) do
    c4.graph.nodes
    |> Enum.filter(fn {_id, data} ->
      is_nil(data[:description]) or data[:description] == ""
    end)
    |> Enum.map(fn {id, _data} -> id end)
  end

  @doc """
  Returns containers and components that are missing a technology label.

  In C4, containers and components should indicate the technology used.

  ## Examples

      iex> c4 = Choreo.C4.new()
      ...>   |> Choreo.C4.add_software_system(:banking)
      ...>   |> Choreo.C4.add_container(:api, technology: "Phoenix", parent: :banking)
      ...>   |> Choreo.C4.add_container(:db, parent: :banking)
      iex> Choreo.C4.Analysis.missing_technology(c4)
      [:db]

  This analysis answers the question: "Which containers or components lack technology labels?"
  """
  @spec missing_technology(C4.t()) :: [Yog.node_id()]
  def missing_technology(%C4{} = c4) do
    c4.graph.nodes
    |> Enum.filter(fn {_id, data} ->
      data[:node_type] in [:container, :component] and
        (is_nil(data[:technology]) or data[:technology] == "")
    end)
    |> Enum.map(fn {id, _data} -> id end)
  end

  @doc """
  Returns relationships that are missing a description label.

  In C4, every relationship should describe *how* or *what* one element
  does with another.

  ## Examples

      iex> c4 = Choreo.C4.new()
      ...>   |> Choreo.C4.add_person(:a)
      ...>   |> Choreo.C4.add_software_system(:b)
      ...>   |> Choreo.C4.add_relationship(:a, :b, label: "Uses")
      iex> Choreo.C4.Analysis.missing_relationship_labels(c4)
      []

  This analysis answers the question: "Which relationships lack descriptions?"
  """
  @spec missing_relationship_labels(C4.t()) :: [Yog.Multi.Graph.edge_id()]
  def missing_relationship_labels(%C4{} = c4) do
    c4.edge_meta
    |> Enum.filter(fn {_edge_id, meta} ->
      is_nil(meta[:label]) or meta[:label] == ""
    end)
    |> Enum.map(fn {edge_id, _meta} -> edge_id end)
  end

  @doc """
  Returns nodes that have children but no explicit relationships to/from them.

  A parent node (e.g. a software system) that has containers but no
  relationships to those containers may indicate an incomplete model.

  ## Examples

      iex> c4 = Choreo.C4.new()
      ...>   |> Choreo.C4.add_software_system(:banking)
      ...>   |> Choreo.C4.add_container(:api, parent: :banking)
      iex> Choreo.C4.Analysis.parents_without_relationships(c4)
      [:banking]

  This analysis answers the question: "Which parent nodes have no relationships?"
  """
  @spec parents_without_relationships(C4.t()) :: [Yog.node_id()]
  def parents_without_relationships(%C4{} = c4) do
    simple_graph = C4.to_graph(c4) |> Yog.Multi.to_simple_graph()

    c4.graph.nodes
    |> Enum.filter(fn {id, _data} ->
      has_children =
        Enum.any?(c4.graph.nodes, fn {_, child_data} -> child_data[:parent] == id end)

      has_children and
        Yog.in_degree(simple_graph, id) == 0 and
        Yog.out_degree(simple_graph, id) == 0
    end)
    |> Enum.map(fn {id, _data} -> id end)
  end

  @doc """
  Validates a C4 model and returns a list of issues.

  Checks for:
    * isolated nodes (no relationships)
    * containers or components without parents
    * missing descriptions on any node
    * missing technology labels on containers and components
    * relationships without labels
    * orphaned parent nodes

  Returns a list of `{severity, message}` tuples.

  ## Examples

      iex> c4 = Choreo.C4.new()
      ...>   |> Choreo.C4.add_person(:a, description: "User")
      ...>   |> Choreo.C4.add_software_system(:b, description: "System")
      ...>   |> Choreo.C4.add_relationship(:a, :b, label: "Uses")
      iex> Choreo.C4.Analysis.validate(c4)
      []

      iex> c4 = Choreo.C4.new()
      ...>   |> Choreo.C4.add_container(:api)
      iex> issues = Choreo.C4.Analysis.validate(c4)
      iex> Enum.any?(issues, fn {_sev, msg} -> String.contains?(msg, "parent") end)
      true
  """
  @spec validate(C4.t()) :: [{:error | :warning, String.t()}]
  def validate(%C4{} = c4) do
    []
    |> check_multiple_in_scopes(c4)
    |> check_unknown_parents(c4)
    |> check_parent_type_mismatch(c4)
    |> check_isolated(c4)
    |> check_missing_parents(c4)
    |> check_missing_descriptions(c4)
    |> check_missing_technology(c4)
    |> check_missing_relationship_labels(c4)
    |> check_parents_without_relationships(c4)
  end

  # ============================================================================
  # Private helpers
  # ============================================================================

  defp check_isolated(acc, c4) do
    case isolated_nodes(c4) do
      [] -> acc
      nodes -> [{:warning, "Isolated nodes: #{inspect(nodes)}"} | acc]
    end
  end

  defp check_missing_parents(acc, c4) do
    case missing_parents(c4) do
      [] -> acc
      nodes -> [{:error, "Containers or components without parent: #{inspect(nodes)}"} | acc]
    end
  end

  defp check_missing_descriptions(acc, c4) do
    case missing_descriptions(c4) do
      [] -> acc
      nodes -> [{:warning, "Nodes missing descriptions: #{inspect(nodes)}"} | acc]
    end
  end

  defp check_missing_technology(acc, c4) do
    case missing_technology(c4) do
      [] ->
        acc

      nodes ->
        [{:warning, "Containers or components missing technology: #{inspect(nodes)}"} | acc]
    end
  end

  defp check_missing_relationship_labels(acc, c4) do
    case missing_relationship_labels(c4) do
      [] -> acc
      edge_ids -> [{:warning, "Relationships missing labels: #{inspect(edge_ids)}"} | acc]
    end
  end

  defp check_parents_without_relationships(acc, c4) do
    case parents_without_relationships(c4) do
      [] -> acc
      nodes -> [{:warning, "Parent nodes with no relationships: #{inspect(nodes)}"} | acc]
    end
  end

  defp check_multiple_in_scopes(acc, %C4{graph: graph}) do
    in_scope_systems =
      graph.nodes
      |> Enum.filter(fn {_id, data} ->
        data[:node_type] == :software_system and data[:scope] == :in
      end)
      |> Enum.map(fn {id, _data} -> id end)

    if length(in_scope_systems) > 1 do
      [
        {:error, "Multiple in-scope systems: #{inspect(in_scope_systems)}; only one allowed"}
        | acc
      ]
    else
      acc
    end
  end

  defp check_unknown_parents(acc, %C4{graph: graph}) do
    unknown =
      graph.nodes
      |> Enum.filter(fn {_id, data} ->
        data[:parent] != nil and not Map.has_key?(graph.nodes, data[:parent])
      end)
      |> Enum.map(fn {id, _data} -> id end)

    if unknown == [] do
      acc
    else
      [{:error, "Nodes with unknown parents: #{inspect(unknown)}"} | acc]
    end
  end

  defp check_parent_type_mismatch(acc, %C4{graph: graph}) do
    mismatches =
      graph.nodes
      |> Enum.filter(fn {_id, data} ->
        parent_id = data[:parent]

        if parent_id != nil and Map.has_key?(graph.nodes, parent_id) do
          parent_type = graph.nodes[parent_id][:node_type]

          case data[:node_type] do
            :container -> parent_type != :software_system
            :component -> parent_type != :container
            _ -> false
          end
        else
          false
        end
      end)
      |> Enum.map(fn {id, data} ->
        parent_id = data[:parent]
        parent_type = graph.nodes[parent_id][:node_type]
        {id, data[:node_type], parent_id, parent_type}
      end)

    if mismatches == [] do
      acc
    else
      messages =
        Enum.map(mismatches, fn {id, type, parent_id, parent_type} ->
          "#{inspect(id)} (#{type}) has parent #{inspect(parent_id)} (#{parent_type})"
        end)

      [{:error, "Parent type mismatches: #{Enum.join(messages, ", ")}"} | acc]
    end
  end
end
