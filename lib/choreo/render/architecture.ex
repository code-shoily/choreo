defmodule Choreo.Render.Architecture do
  @moduledoc """
  Renders a `Choreo` struct to Mermaid.js `architecture-beta` syntax.

  `architecture-beta` is Mermaid's dedicated diagram type for cloud and
  service topologies. It uses built-in icons (cloud, database, disk, internet,
  server) and `group` boundaries instead of arbitrary shapes and colours.

  ## Mapping from Choreo

  | Choreo node type | Architecture icon |
  | ---------------- | ----------------- |
  | `:internet`      | `internet`        |
  | `:database`      | `database`        |
  | `:managed_db`    | `database`        |
  | `:cache`         | `database`        |
  | `:storage`       | `disk`            |
  | `:network`       | `cloud`           |
  | `:service`       | `server`          |
  | `:compute`       | `server`          |
  | `:load_balancer` | `server`          |
  | `:queue`         | `server`          |
  | `:user`          | `server`          |
  | `:generic`       | `server`          |

  Choreo clusters become `group` declarations. Nested clusters are emitted
  with the `in` keyword.

  ## Limitations

  The `architecture-beta` syntax does not support edge labels, protocols, or
  per-node styling. Those attributes are intentionally omitted from the
  rendered output.

  Labels are sanitized to the character set supported by Mermaid
  (`[a-zA-Z0-9_ ]`); hyphens and slashes become spaces and other punctuation
  is removed.

  ## Examples

      system =
        Choreo.new()
        |> Choreo.add_service(:api, label: "API")
        |> Choreo.add_database(:db, label: "Postgres")
        |> Choreo.connect(:api, :db)

      Choreo.Render.Architecture.to_mermaid(system)
      # => "architecture-beta\\n  service api(server)[API]\\n  ..."
  """

  alias Choreo.Internal

  defp clean_cluster_name(name), do: String.replace_prefix(to_string(name), "cluster_", "")

  @doc """
  Renders a `Choreo` system diagram to Mermaid.js `architecture-beta` syntax.

  ## Options

    * `:direction` — accepted for API compatibility but ignored; architecture
      diagrams use a force-directed layout.
    * `:theme` — accepted for API compatibility but ignored; architecture
      diagrams rely on global Mermaid themes.
  """
  @spec to_mermaid(Choreo.t(), keyword()) :: String.t()
  def to_mermaid(%Choreo{} = system, _opts \\ []) do
    id_map = build_id_map(system)

    lines =
      ["architecture-beta"]
      |> Kernel.++(render_groups(system, id_map))
      |> Kernel.++(render_services(system, id_map))
      |> Kernel.++(render_edges(system, id_map))

    Enum.join(lines, "\n") <> "\n"
  end

  # ============================================================================
  # ID sanitization
  # ============================================================================

  defp build_id_map(system) do
    node_ids = Map.keys(system.graph.nodes)
    cluster_ids = Map.keys(system.clusters)

    acc =
      Enum.reduce(node_ids, %{}, fn id, acc ->
        Map.put(acc, id, unique_safe_id(id, acc))
      end)

    # Cluster IDs are stored with a "cluster_" prefix; use the cleaned name for
    # the Mermaid identifier so group references match the user's intent.
    Enum.reduce(cluster_ids, acc, fn name, acc ->
      safe = unique_safe_id(clean_cluster_name(name), acc)
      Map.put(acc, name, safe)
    end)
  end

  defp unique_safe_id(id, used_map) do
    base = sanitize_base_id(id)

    if base in Map.values(used_map) do
      Stream.iterate(1, &(&1 + 1))
      |> Enum.find_value(fn i ->
        candidate = "#{base}_#{i}"
        if candidate in Map.values(used_map), do: nil, else: candidate
      end)
    else
      base
    end
  end

  defp sanitize_base_id(id) do
    id
    |> to_string()
    |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
    |> then(fn s ->
      if s =~ ~r/^[0-9]/ do
        "_" <> s
      else
        s
      end
    end)
    |> then(fn s ->
      if s == "", do: "_", else: s
    end)
  end

  # ============================================================================
  # Groups (clusters)
  # ============================================================================

  defp render_groups(system, id_map) do
    clusters = system.clusters

    if map_size(clusters) == 0 do
      []
    else
      clusters
      |> sorted_cluster_names()
      |> Enum.map(&render_group(&1, clusters, id_map))
    end
  end

  defp sorted_cluster_names(clusters) do
    # Topological sort: parents must be declared before children.
    graph =
      Enum.reduce(clusters, %{}, fn {name, meta}, acc ->
        parent = meta[:parent] && Internal.ensure_cluster_prefix(meta[:parent])
        Map.put(acc, name, if(parent, do: [parent], else: []))
      end)

    {sorted, _} =
      Enum.reduce(clusters, {[], MapSet.new()}, fn _iteration, {acc, visited} ->
        Enum.reduce(clusters, {acc, visited}, fn {name, _meta}, {acc, visited} = state ->
          if MapSet.member?(visited, name) do
            state
          else
            parents = Map.get(graph, name, [])

            if Enum.all?(parents, &MapSet.member?(visited, &1)) do
              {[name | acc], MapSet.put(visited, name)}
            else
              state
            end
          end
        end)
      end)

    Enum.reverse(sorted)
  end

  defp render_group(name, clusters, id_map) do
    cluster = Map.get(clusters, name, %{})
    label = cluster[:label] || clean_cluster_name(name)
    safe_name = Map.fetch!(id_map, name)
    parent = cluster[:parent]

    parent_clause =
      if parent do
        parent_safe = Map.fetch!(id_map, Internal.ensure_cluster_prefix(parent))
        " in #{parent_safe}"
      else
        ""
      end

    "  group #{safe_name}(cloud)[#{sanitize_label(label)}]#{parent_clause}"
  end

  # ============================================================================
  # Services (nodes)
  # ============================================================================

  defp render_services(system, id_map) do
    system.graph.nodes
    |> Enum.sort_by(fn {id, _data} -> to_string(id) end)
    |> Enum.map(fn {id, data} ->
      safe_id = Map.fetch!(id_map, id)
      icon = node_icon(data)
      label = data[:label] || to_string(id)
      cluster = data[:cluster]

      cluster_clause =
        if cluster do
          " in #{Map.fetch!(id_map, cluster)}"
        else
          ""
        end

      "  service #{safe_id}(#{icon})[#{sanitize_label(label)}]#{cluster_clause}"
    end)
  end

  defp node_icon(data) do
    case Map.get(data, :node_type, :generic) do
      :internet -> "internet"
      type when type in [:database, :managed_db, :cache] -> "database"
      :storage -> "disk"
      :network -> "cloud"
      _ -> "server"
    end
  end

  # ============================================================================
  # Edges
  # ============================================================================

  defp render_edges(system, id_map) do
    directed? = system.graph.kind == :directed

    system.graph.edges
    |> Enum.sort_by(fn {edge_id, _} -> edge_id end)
    |> Enum.map(fn {_edge_id, {from, to, _weight}} ->
      from_safe = Map.fetch!(id_map, from)
      to_safe = Map.fetch!(id_map, to)

      if directed? do
        "  #{from_safe}:R --> L:#{to_safe}"
      else
        "  #{from_safe}:R -- L:#{to_safe}"
      end
    end)
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  # Mermaid architecture-beta labels only tolerate [a-zA-Z0-9_ ].
  # Replace common punctuation with spaces and drop any remaining unsafe chars.
  defp sanitize_label(label) do
    label
    |> to_string()
    |> String.replace(~r/[-\/]/, " ")
    |> String.replace(~r/[^a-zA-Z0-9_ ]/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> then(fn s -> if s == "", do: "_", else: s end)
  end
end
