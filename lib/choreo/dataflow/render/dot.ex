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
    subgraphs = Choreo.Internal.build_cluster_subgraphs(flow, theme)

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
      |> Map.put(:node_attributes, node_attributes_fn(theme))
      |> Map.put(:edge_attributes, edge_attributes_fn(flow))
      |> Map.merge(theme_graph_overrides(theme))
      |> Map.merge(Map.new(opts))

    base_opts = if subgraphs != [], do: Map.put(base_opts, :subgraphs, subgraphs), else: base_opts

    Yog.Render.DOT.to_dot(flow.graph, base_opts)
  end

  # ============================================================================
  # Theme helpers
  # ============================================================================

  defp resolve_theme(%Theme{} = theme), do: theme
  defp resolve_theme(:default), do: default_dataflow_theme()
  defp resolve_theme(:dark), do: dark_dataflow_theme()
  defp resolve_theme(_), do: default_dataflow_theme()

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

  defp theme_graph_overrides(%Theme{graph_bgcolor: nil}), do: %{}
  defp theme_graph_overrides(%Theme{graph_bgcolor: bg}), do: %{bgcolor: bg}

  # ============================================================================
  # Node styling
  # ============================================================================

  defp node_attributes_fn(theme) do
    fn _id, data ->
      base =
        case Map.get(data, :node_type, :transform) do
          :source ->
            [
              {:shape, :house},
              {:fillcolor, df_color(theme, :source)}
            ]

          :sink ->
            [
              {:shape, :invhouse},
              {:fillcolor, df_color(theme, :sink)}
            ]

          :transform ->
            [
              {:shape, :box3d},
              {:fillcolor, df_color(theme, :transform)}
            ]

          :buffer ->
            [
              {:shape, :cylinder},
              {:fillcolor, df_color(theme, :buffer)}
            ]

          :conditional ->
            [
              {:shape, :diamond},
              {:fillcolor, df_color(theme, :conditional)}
            ]

          :merge ->
            [
              {:shape, :trapezium},
              {:fillcolor, df_color(theme, :merge)}
            ]

          _ ->
            [
              {:shape, :box},
              {:fillcolor, df_color(theme, :transform)}
            ]
        end

      if desc = data[:description] do
        [{:tooltip, desc} | base]
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

  defp edge_attributes_fn(flow) do
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

      if display_label do
        [{:label, display_label} | base]
      else
        base
      end
    end
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
end
