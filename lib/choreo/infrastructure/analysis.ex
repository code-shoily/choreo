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
  # Programmatic Queries
  # ============================================================================

  @doc """
  Returns a list of direct connection edge tuples `{from, to}` between public internet nodes
  and private subnet resources.

  ## Examples

      iex> infra = Choreo.Infrastructure.new()
      iex> infra = infra
      ...>   |> Choreo.Infrastructure.add_internet(:gw)
      ...>   |> Choreo.Infrastructure.add_subnet_private("priv")
      ...>   |> Choreo.Infrastructure.add_compute(:app, cluster: "priv")
      ...>   |> Choreo.Infrastructure.connect(:gw, :app)
      iex> Choreo.Infrastructure.Analysis.direct_internet_violations(infra)
      [{:gw, :app}]
  """
  @spec direct_internet_violations(Infrastructure.t() | Choreo.t()) :: [
          {Yog.node_id(), Yog.node_id()}
        ]
  def direct_internet_violations(%Choreo{} = system) do
    system |> Infrastructure.from_choreo() |> direct_internet_violations()
  end

  def direct_internet_violations(%Infrastructure{} = infra) do
    private_nodes = private_node_set(infra)

    internet_nodes =
      infra.graph.nodes
      |> Enum.filter(fn {_id, data} -> data[:node_type] == :internet end)
      |> Enum.map(fn {id, _data} -> id end)
      |> MapSet.new()

    infra.graph.edges
    |> Map.values()
    |> Enum.filter(fn {from, to, _weight} ->
      (MapSet.member?(private_nodes, from) and MapSet.member?(internet_nodes, to)) or
        (MapSet.member?(internet_nodes, from) and MapSet.member?(private_nodes, to))
    end)
    |> Enum.map(fn {from, to, _weight} -> {from, to} end)
    |> Enum.uniq()
  end

  @doc """
  Returns a list of managed database node IDs located outside private subnets.

  ## Examples

      iex> infra = Choreo.Infrastructure.new() |> Choreo.Infrastructure.add_managed_db(:db)
      iex> Choreo.Infrastructure.Analysis.misplaced_databases(infra)
      [:db]
  """
  @spec misplaced_databases(Infrastructure.t() | Choreo.t()) :: [Yog.node_id()]
  def misplaced_databases(%Choreo{} = system) do
    system |> Infrastructure.from_choreo() |> misplaced_databases()
  end

  def misplaced_databases(%Infrastructure{} = infra) do
    infra.graph.nodes
    |> Enum.filter(fn {_id, data} ->
      data[:node_type] == :managed_db and
        (is_nil(data[:cluster]) or not in_private_subnet?(data[:cluster], infra.clusters))
    end)
    |> Enum.map(fn {id, _data} -> id end)
  end

  @doc """
  Returns a list of storage node IDs placed inside public subnets.

  ## Examples

      iex> infra = Choreo.Infrastructure.new()
      ...>   |> Choreo.Infrastructure.add_subnet_public("pub")
      ...>   |> Choreo.Infrastructure.add_storage(:s3, cluster: "pub")
      iex> Choreo.Infrastructure.Analysis.misplaced_storage(infra)
      [:s3]
  """
  @spec misplaced_storage(Infrastructure.t() | Choreo.t()) :: [Yog.node_id()]
  def misplaced_storage(%Choreo{} = system) do
    system |> Infrastructure.from_choreo() |> misplaced_storage()
  end

  def misplaced_storage(%Infrastructure{} = infra) do
    infra.graph.nodes
    |> Enum.filter(fn {_id, data} ->
      data[:node_type] == :storage and
        not is_nil(data[:cluster]) and in_public_subnet?(data[:cluster], infra.clusters)
    end)
    |> Enum.map(fn {id, _data} -> id end)
  end

  @doc """
  Returns a list of load balancer node IDs located outside public subnets.

  ## Examples

      iex> infra = Choreo.Infrastructure.new() |> Choreo.Infrastructure.add_load_balancer(:alb)
      iex> Choreo.Infrastructure.Analysis.misplaced_load_balancers(infra)
      [:alb]
  """
  @spec misplaced_load_balancers(Infrastructure.t() | Choreo.t()) :: [Yog.node_id()]
  def misplaced_load_balancers(%Choreo{} = system) do
    system |> Infrastructure.from_choreo() |> misplaced_load_balancers()
  end

  def misplaced_load_balancers(%Infrastructure{} = infra) do
    infra.graph.nodes
    |> Enum.filter(fn {_id, data} ->
      data[:node_type] == :load_balancer and
        (is_nil(data[:cluster]) or not in_public_subnet?(data[:cluster], infra.clusters))
    end)
    |> Enum.map(fn {id, _data} -> id end)
  end

  @doc """
  Returns a list of compute node IDs not assigned to any subnet.

  ## Examples

      iex> infra = Choreo.Infrastructure.new() |> Choreo.Infrastructure.add_compute(:app)
      iex> Choreo.Infrastructure.Analysis.unassigned_compute(infra)
      [:app]
  """
  @spec unassigned_compute(Infrastructure.t() | Choreo.t()) :: [Yog.node_id()]
  def unassigned_compute(%Choreo{} = system) do
    system |> Infrastructure.from_choreo() |> unassigned_compute()
  end

  def unassigned_compute(%Infrastructure{} = infra) do
    infra.graph.nodes
    |> Enum.filter(fn {_id, data} ->
      data[:node_type] == :compute and is_nil(data[:cluster])
    end)
    |> Enum.map(fn {id, _data} -> id end)
  end

  @doc """
  Returns nodes with no connections (zero in-degree and out-degree).

  ## Examples

      iex> infra = Choreo.Infrastructure.new() |> Choreo.Infrastructure.add_compute(:orphan)
      iex> Choreo.Infrastructure.Analysis.isolated_nodes(infra)
      [:orphan]
  """
  @spec isolated_nodes(Infrastructure.t() | Choreo.t()) :: [Yog.node_id()]
  def isolated_nodes(%Choreo{} = system) do
    Choreo.Analysis.isolated_nodes(system)
  end

  def isolated_nodes(%Infrastructure{} = infra) do
    infra |> Infrastructure.to_choreo() |> Choreo.Analysis.isolated_nodes()
  end

  # ============================================================================
  # Rule 1 — direct internet to private subnet
  # ============================================================================

  defp check_direct_internet_connections(acc, infra) do
    private_nodes = private_node_set(infra)

    edges_warnings =
      infra
      |> direct_internet_violations()
      |> Enum.map(fn {from, to} ->
        if MapSet.member?(private_nodes, from) do
          {:error,
           "Private resource '#{from}' is connected directly to public internet boundary '#{to}'."}
        else
          {:error,
           "Private resource '#{to}' is connected directly to public internet boundary '#{from}'."}
        end
      end)

    acc ++ edges_warnings
  end

  # ============================================================================
  # Rule 2 — managed databases in private subnets
  # ============================================================================

  defp check_database_placement(acc, infra) do
    db_warnings =
      infra
      |> misplaced_databases()
      |> Enum.map(fn id ->
        cluster = infra.graph.nodes[id][:cluster]

        if is_nil(cluster) do
          {:error,
           "Managed database '#{id}' should be located in a private subnet, but it is outside of any subnet."}
        else
          subnet_name = subnet_label(infra.clusters, cluster)

          {:error,
           "Managed database '#{id}' should be located in a private subnet, but it is in '#{subnet_name}'."}
        end
      end)

    acc ++ db_warnings
  end

  # ============================================================================
  # Rule 3 — storage in private subnets
  # ============================================================================

  defp check_storage_placement(acc, infra) do
    storage_warnings =
      infra
      |> misplaced_storage()
      |> Enum.map(fn id ->
        cluster = infra.graph.nodes[id][:cluster]
        subnet_name = subnet_label(infra.clusters, cluster)

        {:error,
         "Storage '#{id}' should not be in a public subnet, but it is in '#{subnet_name}'."}
      end)

    acc ++ storage_warnings
  end

  # ============================================================================
  # Rule 4 — load balancers in public subnets
  # ============================================================================

  defp check_load_balancer_placement(acc, infra) do
    lb_warnings =
      infra
      |> misplaced_load_balancers()
      |> Enum.map(fn id ->
        cluster = infra.graph.nodes[id][:cluster]

        if is_nil(cluster) do
          {:warning,
           "Load balancer '#{id}' should be located in a public subnet, but it is outside of any subnet."}
        else
          subnet_name = subnet_label(infra.clusters, cluster)

          {:warning,
           "Load balancer '#{id}' should be located in a public subnet, but it is in '#{subnet_name}'."}
        end
      end)

    acc ++ lb_warnings
  end

  # ============================================================================
  # Rule 5 — compute nodes should have a subnet assignment
  # ============================================================================

  defp check_compute_assignment(acc, infra) do
    compute_warnings =
      infra
      |> unassigned_compute()
      |> Enum.map(fn id ->
        {:warning,
         "Compute node '#{id}' is not assigned to any subnet. This may indicate incomplete modeling."}
      end)

    acc ++ compute_warnings
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp private_node_set(infra) do
    infra.graph.nodes
    |> Enum.filter(fn {_id, data} ->
      cluster = data[:cluster]
      not is_nil(cluster) and in_private_subnet?(cluster, infra.clusters)
    end)
    |> Enum.map(fn {id, _data} -> id end)
    |> MapSet.new()
  end

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
