defmodule Choreo.Render.DOT do
  @moduledoc """
  DOT (Graphviz) rendering for `Choreo` architecture diagrams.

  This module translates a `Choreo` struct into the DOT language with
  sensible defaults for infrastructure diagrams:

  * Databases are rendered as **cylinders**
  * Caches as **octagons**
  * Services as **3D boxes**
  * Networks as **clouds**
  * Users as **double circles**
  * Load balancers as **hexagons**
  * Queues as **components**
  * Storage as **tabs**

  Edges are styled according to their semantic type (`:connection` or
  `:dataflow`).

  Themes (built-in or custom) control colours, shapes, fonts, and layout.
  See `Choreo.Theme` for details.
  """

  alias Choreo.Theme

  @doc """
  Renders a `Choreo` to a DOT string.

  ## Options

    * `:theme` - `:default`, `:dark`, `:minimal`, or a `Choreo.Theme` struct
    * `:subgraphs` - list of subgraph / cluster definitions (manual override)
    * `:ranks` - rank constraints
    * Any other option accepted by `Yog.Render.DOT.to_dot/2`

  ## Examples

      dot = Choreo.Render.DOT.to_dot(system)
      dot = Choreo.Render.DOT.to_dot(system, theme: :dark)

      theme = Choreo.Theme.custom(colors: [database: "#ff0000"])
      dot = Choreo.Render.DOT.to_dot(system, theme: theme)
  """
  @spec to_dot(Choreo.t(), keyword()) :: String.t()
  def to_dot(system, opts \\ []) do
    theme = resolve_theme(Keyword.get(opts, :theme, :default))

    subgraphs = Choreo.Internal.build_cluster_subgraphs(system, theme)

    base =
      Yog.Multi.DOT.default_options()
      |> Map.put(:node_label, &node_label/2)
      |> Map.put(:edge_label, fn _edge_id, weight -> edge_label(weight) end)
      |> Map.put(:node_attributes, node_attributes_fn(system, theme))
      |> Map.put(:edge_attributes, edge_attributes_fn(system))
      |> Map.merge(theme_graph_attrs(theme))
      |> Map.merge(Map.new(opts))

    base = if subgraphs != [], do: Map.put(base, :subgraphs, subgraphs), else: base

    Yog.Multi.DOT.to_dot(system.graph, base)
  end

  # ============================================================================
  # Theme resolution
  # ============================================================================

  defp resolve_theme(%Theme{} = theme), do: theme
  defp resolve_theme(:default), do: Theme.default()
  defp resolve_theme(:dark), do: Theme.dark()
  defp resolve_theme(:minimal), do: Theme.minimal()
  defp resolve_theme(:warm), do: Theme.warm()
  defp resolve_theme(:forest), do: Theme.forest()
  defp resolve_theme(:ocean), do: Theme.ocean()
  defp resolve_theme(_), do: Theme.default()

  defp theme_graph_attrs(%Theme{} = theme) do
    %{
      rankdir: theme.graph_rankdir,
      splines: theme.graph_splines,
      nodesep: theme.graph_nodesep,
      ranksep: theme.graph_ranksep,
      bgcolor: theme.graph_bgcolor,
      edge_color: theme.edge_color,
      edge_fontcolor: theme.edge_color,
      edge_fontname: theme.edge_fontname,
      edge_fontsize: theme.edge_fontsize,
      edge_penwidth: theme.edge_penwidth,
      node_fontname: theme.node_fontname,
      node_fontsize: theme.node_fontsize,
      node_fontcolor: theme.node_fontcolor
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  # ============================================================================
  # Node styling
  # ============================================================================

  defp node_attributes_fn(_system, theme) do
    fn _id, data ->
      type = Map.get(data, :type, :generic)

      shape = Map.get(data, :shape) || Theme.shape(theme, type)
      color = Map.get(data, :fillcolor) || Theme.color(theme, type)
      fontcolor = Map.get(data, :fontcolor) || theme.node_fontcolor
      style = Map.get(data, :style, "filled")

      attrs = [
        {:shape, shape},
        {:fillcolor, color},
        {:fontcolor, fontcolor},
        {:style, style}
      ]

      attrs =
        if penwidth = data[:penwidth] do
          [{:penwidth, penwidth} | attrs]
        else
          attrs
        end

      if desc = data[:description] do
        [{:tooltip, desc} | attrs]
      else
        attrs
      end
    end
  end

  defp node_label(_id, data) do
    Map.get(data, :name, "")
  end

  # ============================================================================
  # Edge styling
  # ============================================================================

  defp edge_attributes_fn(system) do
    fn _from, to, edge_id, _weight ->
      meta = Map.get(system.edge_meta, edge_id, %{})

      base =
        case meta[:type] do
          :dataflow ->
            [{:color, "#6366f1"}, {:penwidth, 1.5}, {:style, "dashed"}]

          _ ->
            [{:color, "#64748b"}, {:penwidth, 1.0}]
        end

      base = if protocol = meta[:protocol], do: [{:label, to_string(protocol)} | base], else: base

      # Smart headport: databases look best when entered from the top.
      target_data = Map.get(system.graph.nodes, to, %{})

      base =
        if target_data[:type] == :database and is_nil(meta[:headport]) do
          [{:headport, "n"} | base]
        else
          base
        end

      # Allow user overrides
      base = if port = meta[:headport], do: [{:headport, port} | base], else: base
      base = if port = meta[:tailport], do: [{:tailport, port} | base], else: base

      base
    end
  end

  defp edge_label(weight) when is_number(weight) do
    to_string(weight)
  end

  defp edge_label(_) do
    ""
  end
end
