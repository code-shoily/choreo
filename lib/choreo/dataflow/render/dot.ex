defmodule Choreo.Dataflow.Render.DOT do
  @moduledoc """
  DOT (Graphviz) rendering for `Choreo.Dataflow` pipeline diagrams.

  Produces dataflow-oriented visualisation:

    * **Sources** — house shape (data enters)
    * **Sinks** — inverted house (data exits)
    * **Transforms** — 3D boxes (processing)
    * **Buffers** — cylinders (queues / topics)
    * **Conditionals** — diamonds (branching decisions)
    * **Merges** — trapezium (joining streams)

  Edge styles:
    * **Normal** — solid grey
    * **Error** — dashed red
    * **Retry** — dotted orange
    * **Dead letter** — dashed grey

  Layout is left-to-right by default so data flows from left to right.
  Clusters are rendered as bounded rectangles with optional fill colours.

  ## Further reading

    * [Dataflow Programming (Wikipedia)](https://en.wikipedia.org/wiki/Dataflow_programming)
    * [Enterprise Integration Patterns](https://www.enterpriseintegrationpatterns.com/)
  """

  alias Choreo.Theme

  @doc """
  Renders a dataflow to a DOT string.

  ## Options

    * `:theme` — `:default`, `:dark`, or a `Choreo.Theme` struct

  ## Examples

      iex> flow = Choreo.Dataflow.new()
      iex> flow = flow
      ...>   |> Choreo.Dataflow.add_source(:in, label: "Input")
      ...>   |> Choreo.Dataflow.add_transform(:proc, label: "Process")
      ...>   |> Choreo.Dataflow.add_sink(:out, label: "Output")
      ...>   |> Choreo.Dataflow.connect(:in, :proc, data_type: "raw")
      ...>   |> Choreo.Dataflow.connect(:proc, :out, data_type: "result")
      iex> dot = Choreo.Dataflow.Render.DOT.to_dot(flow)
      iex> String.contains?(dot, "digraph")
      true
      iex> String.contains?(dot, "Input")
      true
      iex> String.contains?(dot, "Output")
      true
  """
  @spec to_dot(Choreo.Dataflow.t(), keyword()) :: String.t()
  def to_dot(%Choreo.Dataflow{} = flow, opts \\ []) do
    theme = resolve_theme(Keyword.get(opts, :theme, :default))

    states_list = Choreo.Dataflow.nodes(flow)
    id_map = Enum.into(states_list, %{}, fn id -> {id, dot_id(id)} end)
    safe_graph = Choreo.Internal.make_simple_graph_safe(flow.graph, id_map)

    safe_edge_meta =
      Map.new(flow.edge_meta, fn {{from, to}, meta} ->
        {{Map.fetch!(id_map, from), Map.fetch!(id_map, to)}, meta}
      end)

    safe_flow = %{flow | graph: safe_graph, edge_meta: safe_edge_meta}

    subgraphs = Choreo.Internal.build_cluster_subgraphs(safe_flow, theme)

    hl_nodes =
      Keyword.get(opts, :highlighted_nodes, [])
      |> Kernel.||([])
      |> Enum.map(&dot_id/1)
      |> MapSet.new()

    hl_edges =
      Keyword.get(opts, :highlighted_edges, [])
      |> Kernel.||([])
      |> Enum.map(fn
        {from, to} -> {dot_id(from), dot_id(to)}
        other -> other
      end)
      |> MapSet.new()

    base_opts =
      Yog.Render.DOT.default_options()
      |> Map.put(:rankdir, :lr)
      |> Map.put(:splines, :spline)
      |> Map.put(:nodesep, 0.6)
      |> Map.put(:ranksep, 1.2)
      |> Map.put(:node_shape, :box)
      |> Map.put(:node_style, :filled)
      |> Map.put(:node_color, "white")
      |> Map.put(:node_fontname, theme.node_fontname)
      |> Map.put(:node_fontsize, theme.node_fontsize)
      |> Map.put(:node_fontcolor, theme.node_fontcolor)
      |> Map.put(:edge_color, theme.edge_color)
      |> Map.put(:edge_fontname, theme.edge_fontname)
      |> Map.put(:edge_fontsize, theme.edge_fontsize)
      |> Map.put(:edge_penwidth, theme.edge_penwidth)
      |> Map.put(:arrowhead, :normal)
      |> Map.put(:node_label, &node_label/2)
      |> Map.put(:edge_label, &edge_label/1)
      |> Map.put(:node_attributes, node_attributes_fn(theme, hl_nodes))
      |> Map.put(:edge_attributes, edge_attributes_fn(safe_flow, hl_edges))
      |> Map.merge(theme_graph_overrides(theme))
      |> Map.merge(Map.new(opts))

    base_opts = if subgraphs != [], do: Map.put(base_opts, :subgraphs, subgraphs), else: base_opts

    Yog.Render.DOT.to_dot(safe_graph, base_opts)
  end

  # ============================================================================
  # Theme helpers
  # ============================================================================

  @doc false
  def theme(name \\ :default, overrides \\ []) do
    resolve_theme(name) |> Choreo.Theme.override(overrides)
  end

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

  defp theme_graph_overrides(%Theme{} = theme) do
    base = if theme.graph_rankdir != nil, do: %{rankdir: theme.graph_rankdir}, else: %{}
    if theme.graph_bgcolor != nil, do: Map.put(base, :bgcolor, theme.graph_bgcolor), else: base
  end

  # ============================================================================
  # Node styling
  # ============================================================================

  defp node_attributes_fn(theme, hl_nodes) do
    fn id, data ->
      base =
        case Map.get(data, :node_type, :transform) do
          :source ->
            [
              {:shape, :house},
              {:fillcolor, df_color(theme, :source)},
              {:fontcolor, theme.node_fontcolor},
              {:style, "filled"}
            ]

          :sink ->
            [
              {:shape, :invhouse},
              {:fillcolor, df_color(theme, :sink)},
              {:fontcolor, theme.node_fontcolor},
              {:style, "filled"}
            ]

          :transform ->
            [
              {:shape, :box3d},
              {:fillcolor, df_color(theme, :transform)},
              {:fontcolor, theme.node_fontcolor},
              {:style, "filled"}
            ]

          :buffer ->
            [
              {:shape, :cylinder},
              {:fillcolor, df_color(theme, :buffer)},
              {:fontcolor, theme.node_fontcolor},
              {:style, "filled"}
            ]

          :conditional ->
            [
              {:shape, :diamond},
              {:fillcolor, df_color(theme, :conditional)},
              {:fontcolor, theme.node_fontcolor},
              {:style, "filled"}
            ]

          :merge ->
            [
              {:shape, :trapezium},
              {:fillcolor, df_color(theme, :merge)},
              {:fontcolor, theme.node_fontcolor},
              {:style, "filled"}
            ]

          _ ->
            [
              {:shape, :box},
              {:fillcolor, df_color(theme, :transform)},
              {:fontcolor, theme.node_fontcolor},
              {:style, "filled"}
            ]
        end

      base =
        if shape = data[:shape], do: [{:shape, shape} | Keyword.delete(base, :shape)], else: base

      base =
        if color = data[:fillcolor],
          do: [{:fillcolor, color} | Keyword.delete(base, :fillcolor)],
          else: base

      base =
        if fontcolor = data[:fontcolor],
          do: [{:fontcolor, fontcolor} | Keyword.delete(base, :fontcolor)],
          else: base

      base =
        if style = data[:style], do: [{:style, style} | Keyword.delete(base, :style)], else: base

      base =
        if penwidth = data[:penwidth],
          do: [{:penwidth, penwidth} | Keyword.delete(base, :penwidth)],
          else: base

      base =
        if image = data[:image],
          do: [{:image, image} | Keyword.delete(base, :image)],
          else: base

      base =
        if desc = data[:description] do
          [{:tooltip, desc} | base]
        else
          base
        end

      # Final highlighting override: Omit fillcolor if node is highlighted
      if MapSet.member?(hl_nodes, id) do
        Keyword.drop(base, [:fillcolor])
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

  defp edge_attributes_fn(flow, hl_edges) do
    fn from, to, _weight ->
      meta = Map.get(flow.edge_meta, {from, to}, %{})

      base = path_type_attrs(meta[:path_type] || :normal)

      label = meta[:label]
      rate = meta[:rate]

      display_label =
        case {label, rate} do
          {nil, nil} -> nil
          {label, nil} -> label
          {nil, rate} -> "#{rate} evt/s"
          {label, rate} -> "#{label}\\n#{rate} evt/s"
        end

      base =
        if display_label do
          [{:label, display_label} | base]
        else
          base
        end

      # Handle highlighting: Omit color/penwidth if edge is highlighted
      if MapSet.member?(hl_edges, {from, to}) do
        Keyword.drop(base, [:color, :penwidth])
      else
        base
      end
    end
  end

  defp path_type_attrs(:virtual) do
    [{:color, "#cbd5e1"}, {:penwidth, 0.8}, {:style, "dashed"}]
  end

  defp path_type_attrs(:error) do
    [{:color, "#ef4444"}, {:penwidth, 1.5}, {:style, "dashed"}]
  end

  defp path_type_attrs(:retry) do
    [{:color, "#f97316"}, {:penwidth, 1.5}, {:style, "dotted"}]
  end

  defp path_type_attrs(:dead_letter) do
    [{:color, "#9ca3af"}, {:penwidth, 1.2}, {:style, "dashed"}]
  end

  defp path_type_attrs(_) do
    [{:color, "#64748b"}, {:penwidth, 1.0}, {:style, "solid"}]
  end

  defp edge_label(_), do: ""

  defp dot_id(id) do
    str =
      cond do
        is_atom(id) -> Atom.to_string(id)
        is_binary(id) -> id
        true -> inspect(id)
      end

    if str =~ ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/ do
      str
    else
      "\"" <> String.replace(str, "\"", "\\\"") <> "\""
    end
  end
end
