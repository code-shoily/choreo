defmodule Choreo.Infrastructure.Render.DOT do
  @moduledoc """
  DOT (Graphviz) rendering for `Choreo.Infrastructure` topology diagrams.
  """

  alias Choreo.Theme

  @doc """
  Renders a `Choreo.Infrastructure` struct to a DOT string.
  """
  @spec to_dot(Choreo.Infrastructure.t(), keyword()) :: String.t()
  def to_dot(%Choreo.Infrastructure{} = infra, opts \\ []) do
    theme = Theme.resolve(Keyword.get(opts, :theme, :default))

    states_list = Choreo.Infrastructure.nodes(infra)
    id_map = Enum.into(states_list, %{}, fn id -> {id, Choreo.Internal.dot_id(id)} end)
    safe_graph = Choreo.Internal.make_multi_graph_safe(infra.graph, id_map)

    # Style clusters dynamically depending on theme
    styled_clusters =
      infra.clusters
      |> Enum.into(%{}, fn {name, cluster} ->
        {name, apply_cluster_theme_defaults(cluster, theme)}
      end)

    safe_infra = %{infra | graph: safe_graph, clusters: styled_clusters}
    subgraphs = Choreo.Internal.build_cluster_subgraphs(safe_infra, theme)

    hl_nodes =
      Keyword.get(opts, :highlighted_nodes, [])
      |> Kernel.||([])
      |> Enum.map(&Choreo.Internal.dot_id/1)
      |> MapSet.new()

    hl_edges =
      Keyword.get(opts, :highlighted_edges, [])
      |> Kernel.||([])
      |> Enum.map(fn
        {from, to} -> {Choreo.Internal.dot_id(from), Choreo.Internal.dot_id(to)}
        other -> other
      end)
      |> MapSet.new()

    base_opts =
      Yog.Render.DOT.default_options()
      |> Map.put(:rankdir, :tb)
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
      |> Map.put(:edge_label, fn _edge_id, _weight -> "" end)
      |> Map.put(:node_attributes, node_attributes_fn(theme, hl_nodes))
      |> Map.put(:edge_attributes, edge_attributes_fn(infra, hl_edges))
      |> Map.merge(theme_graph_overrides(theme))
      |> Map.merge(Map.new(opts))

    base_opts = if subgraphs != [], do: Map.put(base_opts, :subgraphs, subgraphs), else: base_opts

    Yog.Multi.DOT.to_dot(safe_graph, base_opts)
  end

  # ============================================================================
  # Theme helpers
  # ============================================================================

  defp theme_graph_overrides(%Theme{} = theme) do
    base = if theme.graph_rankdir != nil, do: %{rankdir: theme.graph_rankdir}, else: %{}
    if theme.graph_bgcolor != nil, do: Map.put(base, :bgcolor, theme.graph_bgcolor), else: base
  end

  defp apply_cluster_theme_defaults(cluster, theme) do
    is_dark = Theme.dark?(theme)

    defaults =
      case cluster[:cluster_type] do
        :vpc ->
          # Use :dashed only — Yog's style_to_string does not accept compound strings
          [
            style: :dashed,
            fillcolor: if(is_dark, do: "#1e293b", else: "#f8fafc"),
            color: if(is_dark, do: "#475569", else: "#64748b")
          ]

        :subnet_public ->
          [
            style: :rounded,
            fillcolor: if(is_dark, do: "#064e3b", else: "#f0fdf4"),
            color: if(is_dark, do: "#10b981", else: "#22c55e")
          ]

        :subnet_private ->
          [
            style: :rounded,
            fillcolor: if(is_dark, do: "#7f1d1d", else: "#fef2f2"),
            color: if(is_dark, do: "#ef4444", else: "#ef4444")
          ]

        _ ->
          []
      end
      |> Map.new()

    Map.merge(defaults, cluster)
  end

  # (node colors and shapes are resolved via Theme.color/2 and Theme.shape/2)

  # ============================================================================
  # Node styling
  # ============================================================================

  defp node_attributes_fn(theme, hl_nodes) do
    fn id, data ->
      node_type = Map.get(data, :node_type, :compute)

      base =
        [
          {:shape, Theme.shape(theme, node_type)},
          {:fillcolor, Theme.color(theme, node_type)},
          {:fontcolor, "white"},
          {:style, "filled"}
        ]

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
        if image = data[:image] do
          [{:image, image} | Keyword.delete(base, :image)]
        else
          base
        end

      base =
        if desc = data[:description] do
          [{:tooltip, desc} | base]
        else
          base
        end

      # Highlight override: drop fillcolor
      if MapSet.member?(hl_nodes, id) do
        Keyword.drop(base, [:fillcolor])
      else
        base
      end
    end
  end

  defp node_label(_id, data) do
    data[:label] || ""
  end

  # ============================================================================
  # Edge styling
  # ============================================================================

  defp edge_attributes_fn(infra, hl_edges) do
    fn from, to, edge_id, _weight ->
      meta = Map.get(infra.edge_meta, edge_id, %{})

      base =
        case meta[:protocol] do
          p when p in [:https, :ssl] ->
            [{:color, "#10b981"}, {:penwidth, 1.5}]

          _ ->
            [{:color, "#64748b"}, {:penwidth, 1.0}]
        end

      base =
        if label = meta[:label] do
          [{:label, label} | base]
        else
          base
        end

      # Highlight override
      if MapSet.member?(hl_edges, edge_id) or MapSet.member?(hl_edges, {from, to}) do
        [{:color, "#ef4444"}, {:penwidth, 2.0} | Keyword.drop(base, [:color, :penwidth])]
      else
        base
      end
    end
  end
end
