defmodule Choreo.Infrastructure.Analysis do
  @moduledoc """
  Architectural analysis and security warning scans for `Choreo.Infrastructure`.

  Provides automated audits for common cloud infrastructure configurations:
  * Flagging direct internet connections to resources inside private subnets.
  * Ensuring managed databases (`:managed_db`) are isolated inside private subnets.
  * Ensuring load balancers (`:load_balancer`) are placed within public subnets.
  """

  alias Choreo.Infrastructure

  @doc """
  Runs analysis checks on the topology and returns a list of architectural warnings.

  ## Examples

      iex> infra = Choreo.Infrastructure.new()
      iex> infra = infra
      ...>   |> Choreo.Infrastructure.add_internet(:gateway)
      ...>   |> Choreo.Infrastructure.add_subnet_private("subnet_app")
      ...>   |> Choreo.Infrastructure.add_compute(:api, cluster: "subnet_app")
      ...>   |> Choreo.Infrastructure.connect(:gateway, :api)
      iex> Choreo.Infrastructure.Analysis.warnings(infra)
      ["Private resource 'api' is connected directly to public internet boundary 'gateway'."]
  """
  @spec warnings(Infrastructure.t()) :: [String.t()]
  def warnings(%Infrastructure{} = infra) do
    []
    |> check_direct_internet_connections(infra)
    |> check_database_placement(infra)
    |> check_load_balancer_placement(infra)
  end

  defp check_direct_internet_connections(acc, infra) do
    # Find all nodes in a private subnet
    private_nodes =
      infra.graph.nodes
      |> Enum.filter(fn {_id, data} ->
        in_private_subnet?(data[:cluster], infra.clusters)
      end)
      |> Enum.map(fn {id, _data} -> id end)
      |> MapSet.new()

    # Find all nodes of type :internet
    internet_nodes =
      infra.graph.nodes
      |> Enum.filter(fn {_id, data} -> data[:node_type] == :internet end)
      |> Enum.map(fn {id, _data} -> id end)
      |> MapSet.new()

    # Scan edges for direct links between internet and private nodes
    edges_warnings =
      infra.graph.edges
      |> Map.values()
      |> Enum.reduce(MapSet.new(), fn {from, to, _weight}, warnings_acc ->
        cond do
          MapSet.member?(private_nodes, from) and MapSet.member?(internet_nodes, to) ->
            MapSet.put(
              warnings_acc,
              "Private resource '#{from}' is connected directly to public internet boundary '#{to}'."
            )

          MapSet.member?(internet_nodes, from) and MapSet.member?(private_nodes, to) ->
            MapSet.put(
              warnings_acc,
              "Private resource '#{to}' is connected directly to public internet boundary '#{from}'."
            )

          true ->
            warnings_acc
        end
      end)

    acc ++ MapSet.to_list(edges_warnings)
  end

  defp check_database_placement(acc, infra) do
    db_warnings =
      infra.graph.nodes
      |> Enum.filter(fn {_id, data} -> data[:node_type] == :managed_db end)
      |> Enum.reduce([], fn {id, data}, warnings_acc ->
        cluster = data[:cluster]

        cond do
          is_nil(cluster) ->
            [
              "Managed database '#{id}' should be located in a private subnet, but it is outside of any subnet."
              | warnings_acc
            ]

          not in_private_subnet?(cluster, infra.clusters) ->
            # Get display label or name of the subnet
            subnet_name =
              case Map.get(infra.clusters, cluster) do
                %{label: label} -> label
                _ -> String.replace(cluster, "cluster_", "")
              end

            [
              "Managed database '#{id}' should be located in a private subnet, but it is in '#{subnet_name}'."
              | warnings_acc
            ]

          true ->
            warnings_acc
        end
      end)

    acc ++ Enum.reverse(db_warnings)
  end

  defp check_load_balancer_placement(acc, infra) do
    lb_warnings =
      infra.graph.nodes
      |> Enum.filter(fn {_id, data} -> data[:node_type] == :load_balancer end)
      |> Enum.reduce([], fn {id, data}, warnings_acc ->
        cluster = data[:cluster]

        cond do
          is_nil(cluster) ->
            # Outside of any subnet is okay sometimes for global LBs, but let's check if inside VPC.
            # Usually we want it in a public subnet.
            [
              "Load balancer '#{id}' should be located in a public subnet, but it is outside of any subnet."
              | warnings_acc
            ]

          not in_public_subnet?(cluster, infra.clusters) ->
            subnet_name =
              case Map.get(infra.clusters, cluster) do
                %{label: label} -> label
                _ -> String.replace(cluster, "cluster_", "")
              end

            [
              "Load balancer '#{id}' should be located in a public subnet, but it is in '#{subnet_name}'."
              | warnings_acc
            ]

          true ->
            warnings_acc
        end
      end)

    acc ++ Enum.reverse(lb_warnings)
  end

  # Helpers

  defp in_private_subnet?(nil, _clusters), do: false

  defp in_private_subnet?(cluster_name, clusters) do
    case Map.get(clusters, cluster_name) do
      %{cluster_type: :subnet_private} -> true
      _ -> false
    end
  end

  defp in_public_subnet?(cluster_name, clusters) do
    if is_nil(cluster_name) do
      false
    else
      case Map.get(clusters, cluster_name) do
        %{cluster_type: :subnet_public} -> true
        _ -> false
      end
    end
  end
end
