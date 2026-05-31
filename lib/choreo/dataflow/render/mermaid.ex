defmodule Choreo.Dataflow.Render.Mermaid do
  @moduledoc """
  Mermaid.js rendering for `Choreo.Dataflow` pipeline diagrams.

  Produces dataflow-oriented visualisation:

    * **Sources** — stadium shape (data enters)
    * **Sinks** — rounded rectangles (data exits)
    * **Transforms** — subroutine rectangles (processing)
    * **Buffers** — cylinders (queues / topics)
    * **Conditionals** — rhombus (branching decisions)
    * **Merges** — trapezoid (joining streams)

  Edge styles:
    * **Normal** — solid grey
    * **Error** — dashed red
    * **Retry** — dashed orange
    * **Dead letter** — dashed grey
    * **Virtual** — dashed light grey

  Clusters are rendered as Mermaid subgraphs with optional fill colours.

  ## Further reading

    * [Dataflow Programming (Wikipedia)](https://en.wikipedia.org/wiki/Dataflow_programming)
    * [Enterprise Integration Patterns](https://www.enterpriseintegrationpatterns.com/)
  """

  alias Choreo.Theme

  @doc """
  Renders a dataflow pipeline to a Mermaid flowchart string.

  ## Options

    * `:theme` — `:default`, `:dark`, `:warm`, `:forest`, `:ocean`, or a `Choreo.Theme` struct
    * `:direction` — `:td` (default), `:lr`, `:bt`, `:rl`
    * `:highlighted_nodes` — list of node IDs to highlight
    * `:highlighted_edges` — list of `{from, to}` tuples to highlight
    * Any other option accepted by `Yog.Multi.Mermaid.to_mermaid/2`

  ## Examples

      iex> flow = Choreo.Dataflow.new()
      iex> flow = flow
      ...>   |> Choreo.Dataflow.add_source(:in, label: "Input")
      ...>   |> Choreo.Dataflow.add_transform(:proc, label: "Process")
      ...>   |> Choreo.Dataflow.add_sink(:out, label: "Output")
      ...>   |> Choreo.Dataflow.connect(:in, :proc, data_type: "raw")
      ...>   |> Choreo.Dataflow.connect(:proc, :out, data_type: "result")
      iex> mermaid = Choreo.Dataflow.Render.Mermaid.to_mermaid(flow)
      iex> String.contains?(mermaid, "graph TD")
      true
      iex> String.contains?(mermaid, "Input")
      true
      iex> String.contains?(mermaid, "Output")
      true
  """
  @spec to_mermaid(Choreo.Dataflow.t(), keyword()) :: String.t()
  def to_mermaid(%Choreo.Dataflow{} = flow, opts \\ []) do
    theme = resolve_theme(Keyword.get(opts, :theme, :default))
    direction = Keyword.get(opts, :direction, :td)

    {multi_graph, edge_id_map} = Choreo.Internal.to_multi_graph(flow.graph)

    # Build edge_meta keyed by edge_id for the multigraph renderer
    multi_edge_meta =
      Map.new(edge_id_map, fn {edge_id, {from, to}} ->
        meta = Map.get(flow.edge_meta, {from, to}, %{})
        {edge_id, meta}
      end)

    virtual_flow = %{graph: multi_graph, edge_meta: multi_edge_meta}

    subgraphs = build_mermaid_subgraphs(flow)

    hl_nodes = MapSet.new(Keyword.get(opts, :highlighted_nodes, []) || [])
    hl_edges = MapSet.new(Keyword.get(opts, :highlighted_edges, []) || [])

    base =
      Yog.Multi.Mermaid.default_options()
      |> Map.put(:node_label, &node_label/2)
      |> Map.put(:edge_label, fn edge_id, _weight -> edge_label(virtual_flow, edge_id) end)
      |> Map.put(:node_shape, &node_shape_fn/2)
      |> Map.put(:node_attributes, node_attributes_fn(theme, hl_nodes))
      |> Map.put(:edge_attributes, edge_attributes_fn(virtual_flow, theme, hl_edges))
      |> Map.put(:direction, direction)
      |> Map.put(:default_font_color, theme.node_fontcolor)
      |> Map.merge(Map.new(opts))

    base = if subgraphs != [], do: Map.put(base, :subgraphs, subgraphs), else: base

    Yog.Multi.Mermaid.to_mermaid(multi_graph, base)
    |> String.replace("stroke_dasharray", "stroke-dasharray")
  end

  @doc """
  Returns a theme for `Choreo.Dataflow` Mermaid diagrams.
  """
  @spec theme(atom(), keyword()) :: Theme.t()
  def theme(name \\ :default, overrides \\ []) do
    resolve_theme(name) |> Choreo.Theme.override(overrides)
  end

  # ============================================================================
  # Subgraphs (clusters)
  # ============================================================================

  # ============================================================================
  # Subgraphs (clusters)
  # ============================================================================

  defp build_mermaid_subgraphs(flow) do
    clusters = flow.clusters || %{}

    if map_size(clusters) == 0 do
      []
    else
      nodes_by_cluster =
        flow.graph.nodes
        |> Enum.group_by(fn {_id, data} -> data[:cluster] end)
        |> Map.delete(nil)

      Enum.flat_map(nodes_by_cluster, fn {cluster_name, nodes} ->
        cluster = Map.get(clusters, cluster_name, %{name: cluster_name, label: cluster_name})
        label = cluster[:label] || cluster_name
        node_ids = Enum.map(nodes, fn {id, _data} -> id end)

        if node_ids == [] do
          []
        else
          [
            %{
              name: Yog.Utils.safe_string(cluster_name),
              label: label,
              node_ids: node_ids
            }
          ]
        end
      end)
    end
  end

  # ============================================================================
  # Theme helpers
  # ============================================================================

  defp resolve_theme(%Theme{} = theme), do: theme
  defp resolve_theme(:default), do: default_dataflow_theme()
  defp resolve_theme(:dark), do: dark_dataflow_theme()
  defp resolve_theme(:warm), do: warm_dataflow_theme()
  defp resolve_theme(:forest), do: forest_dataflow_theme()
  defp resolve_theme(:ocean), do: ocean_dataflow_theme()
  defp resolve_theme(_), do: default_dataflow_theme()

  defp warm_dataflow_theme do
    %Theme{
      name: :dataflow_warm,
      colors: %{
        source: "#fbbf24",
        sink: "#f43f5e",
        transform: "#f97316",
        buffer: "#ea580c",
        conditional: "#ec4899",
        merge: "#db2777"
      },
      node_fontname: "Helvetica",
      node_fontsize: 12,
      node_fontcolor: "white",
      edge_color: "#78716c",
      edge_fontname: "Helvetica",
      edge_fontsize: 10,
      edge_penwidth: 1.0,
      graph_bgcolor: "#fef2f2",
      cluster_fillcolor: "#fee2e2",
      cluster_style: :rounded,
      cluster_color: "#fca5a5"
    }
  end

  defp forest_dataflow_theme do
    %Theme{
      name: :dataflow_forest,
      colors: %{
        source: "#84cc16",
        sink: "#15803d",
        transform: "#14b8a6",
        buffer: "#047857",
        conditional: "#65a30d",
        merge: "#0f766e"
      },
      node_fontname: "Helvetica",
      node_fontsize: 12,
      node_fontcolor: "white",
      edge_color: "#4b5563",
      edge_fontname: "Helvetica",
      edge_fontsize: 10,
      edge_penwidth: 1.0,
      graph_bgcolor: "#f0fdf4",
      cluster_fillcolor: "#dcfce7",
      cluster_style: :rounded,
      cluster_color: "#86efac"
    }
  end

  defp ocean_dataflow_theme do
    %Theme{
      name: :dataflow_ocean,
      colors: %{
        source: "#0ea5e9",
        sink: "#1d4ed8",
        transform: "#0891b2",
        buffer: "#0369a1",
        conditional: "#2563eb",
        merge: "#0e7490"
      },
      node_fontname: "Helvetica",
      node_fontsize: 12,
      node_fontcolor: "white",
      edge_color: "#64748b",
      edge_fontname: "Helvetica",
      edge_fontsize: 10,
      edge_penwidth: 1.0,
      graph_bgcolor: "#f0f9ff",
      cluster_fillcolor: "#e0f2fe",
      cluster_style: :rounded,
      cluster_color: "#7dd3fc"
    }
  end

  defp default_dataflow_theme do
    %Theme{
      name: :dataflow_default,
      colors: %{
        source: "#10b981",
        sink: "#f43f5e",
        transform: "#3b82f6",
        buffer: "#f59e0b",
        conditional: "#8b5cf6",
        merge: "#06b6d4"
      },
      node_fontname: "Helvetica",
      node_fontsize: 12,
      node_fontcolor: "white",
      edge_color: "#64748b",
      edge_fontname: "Helvetica",
      edge_fontsize: 10,
      edge_penwidth: 1.0,
      graph_bgcolor: nil,
      cluster_fillcolor: "#f8fafc",
      cluster_style: :rounded,
      cluster_color: "#cbd5e1"
    }
  end

  defp dark_dataflow_theme do
    %Theme{
      name: :dataflow_dark,
      colors: %{
        source: "#059669",
        sink: "#e11d48",
        transform: "#2563eb",
        buffer: "#d97706",
        conditional: "#7c3aed",
        merge: "#0891b2"
      },
      node_fontname: "Helvetica",
      node_fontsize: 12,
      node_fontcolor: "#e2e8f0",
      edge_color: "#94a3b8",
      edge_fontname: "Helvetica",
      edge_fontsize: 10,
      edge_penwidth: 1.0,
      graph_bgcolor: "#0f172a",
      cluster_fillcolor: "#1e293b",
      cluster_style: :rounded,
      cluster_color: "#475569"
    }
  end

  defp df_color(%Theme{colors: colors}, key) do
    Map.get(colors, key, "#64748b")
  end

  # ============================================================================
  # Node styling
  # ============================================================================

  defp node_shape_fn(_id, data) do
    case Map.get(data, :node_type, :transform) do
      :source -> :stadium
      :sink -> :rounded_rect
      :transform -> :subroutine
      :buffer -> :cylinder
      :conditional -> :rhombus
      :merge -> :trapezoid
      _ -> :subroutine
    end
  end

  defp node_attributes_fn(theme, hl_nodes) do
    fn id, data ->
      base =
        case Map.get(data, :node_type, :transform) do
          :source -> [{:fill, df_color(theme, :source)}]
          :sink -> [{:fill, df_color(theme, :sink)}]
          :transform -> [{:fill, df_color(theme, :transform)}]
          :buffer -> [{:fill, df_color(theme, :buffer)}]
          :conditional -> [{:fill, df_color(theme, :conditional)}]
          :merge -> [{:fill, df_color(theme, :merge)}]
          _ -> [{:fill, df_color(theme, :transform)}]
        end

      base =
        if color = data[:fillcolor],
          do: [{:fill, color} | Keyword.delete(base, :fill)],
          else: base

      base =
        if penwidth = data[:penwidth],
          do: [{:stroke_width, "#{penwidth}px"} | base],
          else: base

      if MapSet.member?(hl_nodes, id) do
        Keyword.drop(base, [:fill])
      else
        base
      end
    end
  end

  defp node_label(_id, data) do
    label = data[:label] || ""

    label =
      if rate = data[:rate] do
        "#{label}\n#{rate} evt/s"
      else
        label
      end

    if capacity = data[:capacity] do
      "#{label}\n(cap: #{capacity})"
    else
      label
    end
  end

  # ============================================================================
  # Edge styling
  # ============================================================================

  defp edge_attributes_fn(flow, theme, hl_edges) do
    fn from, to, edge_id, _weight ->
      meta = Map.get(flow.edge_meta, edge_id, %{})

      base = path_type_attrs(meta[:path_type] || :normal, theme)

      is_highlighted =
        MapSet.member?(hl_edges, edge_id) or
          MapSet.member?(hl_edges, {from, to})

      if is_highlighted do
        Keyword.drop(base, [:stroke, :stroke_width])
      else
        base
      end
    end
  end

  defp path_type_attrs(:virtual, _theme) do
    [{:stroke, "#cbd5e1"}, {:stroke_width, "1px"}, {:stroke_dasharray, "5 5"}]
  end

  defp path_type_attrs(:error, _theme) do
    [{:stroke, "#ef4444"}, {:stroke_width, "2px"}, {:stroke_dasharray, "5 5"}]
  end

  defp path_type_attrs(:retry, _theme) do
    [{:stroke, "#f97316"}, {:stroke_width, "2px"}, {:stroke_dasharray, "2 2"}]
  end

  defp path_type_attrs(:dead_letter, _theme) do
    [{:stroke, "#9ca3af"}, {:stroke_width, "2px"}, {:stroke_dasharray, "5 5"}]
  end

  defp path_type_attrs(_, theme) do
    [{:stroke, theme.edge_color}, {:stroke_width, "1px"}]
  end

  defp edge_label(flow, edge_id) do
    meta = Map.get(flow.edge_meta, edge_id, %{})
    label = meta[:label]
    rate = meta[:rate]

    case {label, rate} do
      {nil, nil} -> ""
      {label, nil} -> label
      {nil, rate} -> "#{rate} evt/s"
      {label, rate} -> "#{label}\n#{rate} evt/s"
    end
  end
end
