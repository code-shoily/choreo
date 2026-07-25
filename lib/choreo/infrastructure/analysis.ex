defmodule Choreo.Infrastructure.Analysis do
  @moduledoc """
  Architectural analysis and security audits for `Choreo.Infrastructure`.

  Provides automated audits for common cloud infrastructure configurations:
  * Flagging direct internet connections to resources inside private subnets.
  * Ensuring managed databases (`:managed_db`) and storage are isolated inside private subnets.
  * Ensuring load balancers (`:load_balancer`) are placed within public subnets.
  * Detecting compute nodes without subnet assignments.
  """

  alias Choreo.Infrastructure

  @doc """
  Runs analysis checks on the topology and returns a list of `{severity, message}` tuples.

  ## Examples

      iex> infra = Choreo.Infrastructure.new()
      iex> infra = infra
      ...>   |> Choreo.Infrastructure.add_internet(:gateway)
      ...>   |> Choreo.Infrastructure.add_subnet_private("subnet_app")
      ...>   |> Choreo.Infrastructure.add_compute(:api, cluster: "subnet_app")
      ...>   |> Choreo.Infrastructure.connect(:gateway, :api)
      iex> Choreo.Infrastructure.Analysis.validate(infra)
      [{:error, "Private resource 'api' is connected directly to public internet boundary 'gateway'."}]
  """
  @spec validate(Infrastructure.t() | Choreo.t()) :: [{:error | :warning, String.t()}]
  def validate(%Choreo{} = system) do
    system |> Choreo.Infrastructure.from_choreo() |> validate()
  end

  def validate(%Infrastructure{} = infra) do
    []
    |> check_direct_internet_connections(infra)
    |> check_database_placement(infra)
    |> check_storage_placement(infra)
    |> check_load_balancer_placement(infra)
    |> check_compute_assignment(infra)
  end

  @doc false
  @deprecated "Use validate/1 instead"
  def warnings(infra) do
    infra |> validate() |> Enum.map(&elem(&1, 1))
  end

  # ============================================================================
  # Rule 1 — direct internet to private subnet
  # ============================================================================

  defp check_direct_internet_connections(acc, infra) do
    private_nodes =
      infra.graph.nodes
      |> Enum.filter(fn {_id, data} ->
        cluster = data[:cluster]
        not is_nil(cluster) and in_private_subnet?(cluster, infra.clusters)
      end)
      |> Enum.map(fn {id, _data} -> id end)
      |> MapSet.new()

    internet_nodes =
      infra.graph.nodes
      |> Enum.filter(fn {_id, data} -> data[:node_type] == :internet end)
      |> Enum.map(fn {id, _data} -> id end)
      |> MapSet.new()

    edges_warnings =
      infra.graph.edges
      |> Map.values()
      |> Enum.reduce(MapSet.new(), fn {from, to, _weight}, warnings_acc ->
        cond do
          MapSet.member?(private_nodes, from) and MapSet.member?(internet_nodes, to) ->
            MapSet.put(
              warnings_acc,
              {:error,
               "Private resource '#{from}' is connected directly to public internet boundary '#{to}'."}
            )

          MapSet.member?(internet_nodes, from) and MapSet.member?(private_nodes, to) ->
            MapSet.put(
              warnings_acc,
              {:error,
               "Private resource '#{to}' is connected directly to public internet boundary '#{from}'."}
            )

          true ->
            warnings_acc
        end
      end)

    acc ++ MapSet.to_list(edges_warnings)
  end

  # ============================================================================
  # Rule 2 — managed databases in private subnets
  # ============================================================================

  defp check_database_placement(acc, infra) do
    db_warnings =
      infra.graph.nodes
      |> Enum.filter(fn {_id, data} -> data[:node_type] == :managed_db end)
      |> Enum.reduce([], fn {id, data}, warnings_acc ->
        cluster = data[:cluster]

        cond do
          is_nil(cluster) ->
            [
              {:error,
               "Managed database '#{id}' should be located in a private subnet, but it is outside of any subnet."}
              | warnings_acc
            ]

          not in_private_subnet?(cluster, infra.clusters) ->
            subnet_name = subnet_label(infra.clusters, cluster)

            [
              {:error,
               "Managed database '#{id}' should be located in a private subnet, but it is in '#{subnet_name}'."}
              | warnings_acc
            ]

          true ->
            warnings_acc
        end
      end)

    acc ++ Enum.reverse(db_warnings)
  end

  # ============================================================================
  # Rule 3 — storage in private subnets
  # ============================================================================

  defp check_storage_placement(acc, infra) do
    storage_warnings =
      infra.graph.nodes
      |> Enum.filter(fn {_id, data} -> data[:node_type] == :storage end)
      |> Enum.reduce([], fn {id, data}, warnings_acc ->
        cluster = data[:cluster]

        cond do
          is_nil(cluster) ->
            warnings_acc

          in_public_subnet?(cluster, infra.clusters) ->
            subnet_name = subnet_label(infra.clusters, cluster)

            [
              {:error,
               "Storage '#{id}' should not be in a public subnet, but it is in '#{subnet_name}'."}
              | warnings_acc
            ]

          true ->
            warnings_acc
        end
      end)

    acc ++ Enum.reverse(storage_warnings)
  end

  # ============================================================================
  # Rule 4 — load balancers in public subnets
  # ============================================================================

  defp check_load_balancer_placement(acc, infra) do
    lb_warnings =
      infra.graph.nodes
      |> Enum.filter(fn {_id, data} -> data[:node_type] == :load_balancer end)
      |> Enum.reduce([], fn {id, data}, warnings_acc ->
        cluster = data[:cluster]

        cond do
          is_nil(cluster) ->
            [
              {:warning,
               "Load balancer '#{id}' should be located in a public subnet, but it is outside of any subnet."}
              | warnings_acc
            ]

          not in_public_subnet?(cluster, infra.clusters) ->
            subnet_name = subnet_label(infra.clusters, cluster)

            [
              {:warning,
               "Load balancer '#{id}' should be located in a public subnet, but it is in '#{subnet_name}'."}
              | warnings_acc
            ]

          true ->
            warnings_acc
        end
      end)

    acc ++ Enum.reverse(lb_warnings)
  end

  # ============================================================================
  # Rule 5 — compute nodes should have a subnet assignment
  # ============================================================================

  defp check_compute_assignment(acc, infra) do
    compute_warnings =
      infra.graph.nodes
      |> Enum.filter(fn {_id, data} -> data[:node_type] == :compute end)
      |> Enum.reduce([], fn {id, data}, warnings_acc ->
        cluster = data[:cluster]

        if is_nil(cluster) do
          [
            {:warning,
             "Compute node '#{id}' is not assigned to any subnet. This may indicate incomplete modeling."}
            | warnings_acc
          ]
        else
          warnings_acc
        end
      end)

    acc ++ Enum.reverse(compute_warnings)
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp in_private_subnet?(cluster_name, clusters) do
    case Map.get(clusters, cluster_name) do
      %{cluster_type: :subnet_private} -> true
      _ -> false
    end
  end

  defp in_public_subnet?(cluster_name, clusters) do
    case Map.get(clusters, cluster_name) do
      %{cluster_type: :subnet_public} -> true
      _ -> false
    end
  end

  defp subnet_label(clusters, cluster_name) do
    case Map.get(clusters, cluster_name) do
      %{label: label} -> label
      _ -> String.replace(cluster_name, "cluster_", "")
    end
  end
end
