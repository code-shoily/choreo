defmodule Choreo.DecisionTree.Render.Mermaid do
  @moduledoc """
  Mermaid.js rendering for `Choreo.DecisionTree`.

  Produces tree-oriented visualisation:

    * **Root** — rhombus with thick stroke
    * **Decisions** — rhombus shapes
    * **Outcomes** — rounded rectangles with class colour coding

  Layout is top-down so decisions flow downward to outcomes.
  Edge labels show the branch condition.

  ## Themes

    * `:default` — purple root, blue decisions, green outcomes
    * `:dark` — dark background, neon accents
    * `Choreo.Theme` struct — full custom control
  """

  alias Choreo.Theme

  @doc """
  Renders a decision tree to a Mermaid flowchart string.

  ## Options

    * `:theme` — `:default`, `:dark`, `:warm`, `:forest`, `:ocean`, or a `Choreo.Theme` struct
    * `:direction` — `:td` (default), `:lr`, `:bt`, `:rl`
    * `:highlighted_nodes` — list of node IDs to highlight
    * `:highlighted_edges` — list of `{from, to}` tuples to highlight
    * Any other option accepted by `Yog.Multi.Mermaid.to_mermaid/2`

  ## Examples

      iex> tree = Choreo.DecisionTree.new()
      iex> tree = tree
      ...>   |> Choreo.DecisionTree.set_root(:color, feature: "color")
      ...>   |> Choreo.DecisionTree.add_outcome(:stop, label: "Stop")
      ...>   |> Choreo.DecisionTree.add_outcome(:go, label: "Go")
      ...>   |> Choreo.DecisionTree.branch(:color, :stop, "red")
      ...>   |> Choreo.DecisionTree.branch(:color, :go, "green")
      iex> mermaid = Choreo.DecisionTree.Render.Mermaid.to_mermaid(tree)
      iex> String.contains?(mermaid, "graph TD")
      true
      iex> String.contains?(mermaid, "red")
      true
      iex> String.contains?(mermaid, "green")
      true
  """
  @spec to_mermaid(Choreo.DecisionTree.t(), keyword()) :: String.t()
  def to_mermaid(%Choreo.DecisionTree{} = tree, opts \\ []) do
    theme = resolve_theme(Keyword.get(opts, :theme, :default))
    direction = Keyword.get(opts, :direction, :td)

    hl_nodes = MapSet.new(Keyword.get(opts, :highlighted_nodes, []) || [])
    hl_edges = MapSet.new(Keyword.get(opts, :highlighted_edges, []) || [])

    # Decision tree's underlying graph is Yog.directed() (a simple graph).
    # Yog.Multi.Mermaid lives in the Multi namespace only, so we convert
    # to a multi-graph before rendering. This is an intentional round-trip.
    {multi_graph, edge_id_map} = Choreo.Internal.to_multi_graph(tree.graph)

    # Build edge_meta keyed by edge_id for the multigraph renderer
    multi_edge_meta =
      Map.new(edge_id_map, fn {edge_id, {from, to}} ->
        meta = Map.get(tree.edge_meta, {from, to}, %{})
        {edge_id, meta}
      end)

    virtual_tree = %{graph: multi_graph, edge_meta: multi_edge_meta}

    base =
      Yog.Multi.Mermaid.default_options()
      |> Map.put(:node_label, &node_label/2)
      |> Map.put(:edge_label, fn edge_id, _weight -> edge_label(virtual_tree, edge_id) end)
      |> Map.put(:node_shape, &node_shape_fn/2)
      |> Map.put(:node_attributes, node_attributes_fn(theme, hl_nodes))
      |> Map.put(:edge_attributes, edge_attributes_fn(virtual_tree, theme, hl_edges))
      |> Map.put(:direction, direction)
      |> Map.put(:default_font_color, theme.node_fontcolor)
      |> Map.put(:default_link_stroke, theme.edge_color)
      |> Map.merge(Map.new(opts))

    Yog.Multi.Mermaid.to_mermaid(multi_graph, base)
    |> String.replace("stroke_dasharray", "stroke-dasharray")
  end

  @doc """
  Returns a theme for `Choreo.DecisionTree` Mermaid diagrams.
  """
  @spec theme(atom(), keyword()) :: Theme.t()
  def theme(name \\ :default, overrides \\ []) do
    resolve_theme(name) |> Choreo.Theme.override(overrides)
  end

  # ============================================================================
  # Theme helpers
  # ============================================================================

  defp resolve_theme(%Theme{} = theme), do: theme
  defp resolve_theme(:default), do: default_tree_theme()
  defp resolve_theme(:dark), do: dark_tree_theme()
  defp resolve_theme(:warm), do: warm_tree_theme()
  defp resolve_theme(:forest), do: forest_tree_theme()
  defp resolve_theme(:ocean), do: ocean_tree_theme()
  defp resolve_theme(_), do: default_tree_theme()

  defp warm_tree_theme do
    %Theme{
      name: :tree_warm,
      colors: %{root: "#ec4899", decision: "#f97316", outcome: "#10b981"},
      node_fontname: "Helvetica",
      node_fontsize: 12,
      node_fontcolor: "white",
      edge_color: "#78716c",
      edge_fontname: "Helvetica",
      edge_fontsize: 10,
      edge_penwidth: 1.0,
      graph_bgcolor: "#fef2f2"
    }
  end

  defp forest_tree_theme do
    %Theme{
      name: :tree_forest,
      colors: %{root: "#15803d", decision: "#166534", outcome: "#84cc16"},
      node_fontname: "Helvetica",
      node_fontsize: 12,
      node_fontcolor: "white",
      edge_color: "#4b5563",
      edge_fontname: "Helvetica",
      edge_fontsize: 10,
      edge_penwidth: 1.0,
      graph_bgcolor: "#f0fdf4"
    }
  end

  defp ocean_tree_theme do
    %Theme{
      name: :tree_ocean,
      colors: %{root: "#1d4ed8", decision: "#0284c7", outcome: "#0ea5e9"},
      node_fontname: "Helvetica",
      node_fontsize: 12,
      node_fontcolor: "white",
      edge_color: "#64748b",
      edge_fontname: "Helvetica",
      edge_fontsize: 10,
      edge_penwidth: 1.0,
      graph_bgcolor: "#f0f9ff"
    }
  end

  defp default_tree_theme do
    %Theme{
      name: :tree_default,
      colors: %{root: "#8b5cf6", decision: "#3b82f6", outcome: "#10b981"},
      node_fontname: "Helvetica",
      node_fontsize: 12,
      node_fontcolor: "white",
      edge_color: "#64748b",
      edge_fontname: "Helvetica",
      edge_fontsize: 10,
      edge_penwidth: 1.0,
      graph_bgcolor: nil
    }
  end

  defp dark_tree_theme do
    %Theme{
      name: :tree_dark,
      colors: %{root: "#7c3aed", decision: "#2563eb", outcome: "#059669"},
      node_fontname: "Helvetica",
      node_fontsize: 12,
      node_fontcolor: "#e2e8f0",
      edge_color: "#94a3b8",
      edge_fontname: "Helvetica",
      edge_fontsize: 10,
      edge_penwidth: 1.0,
      graph_bgcolor: "#0f172a"
    }
  end

  defp tree_color(%Theme{colors: colors}, key) do
    Map.get(colors, key, "#64748b")
  end

  # ============================================================================
  # Node styling
  # ============================================================================

  defp node_shape_fn(_id, data) do
    case Map.get(data, :node_type, :decision) do
      :root -> :rhombus
      :decision -> :rhombus
      :outcome -> :rounded_rect
      _ -> :rounded_rect
    end
  end

  defp node_attributes_fn(theme, hl_nodes) do
    fn id, data ->
      base =
        case Map.get(data, :node_type, :decision) do
          :root ->
            [
              {:fill, tree_color(theme, :root)},
              {:stroke, Choreo.Internal.darken(tree_color(theme, :root))},
              {:stroke_width, "3px"}
            ]

          :decision ->
            [
              {:fill, tree_color(theme, :decision)},
              {:stroke, Choreo.Internal.darken(tree_color(theme, :decision))}
            ]

          :outcome ->
            [
              {:fill, tree_color(theme, :outcome)},
              {:stroke, Choreo.Internal.darken(tree_color(theme, :outcome))}
            ]

          _ ->
            [
              {:fill, tree_color(theme, :decision)},
              {:stroke, Choreo.Internal.darken(tree_color(theme, :decision))}
            ]
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

    if prob = data[:probability] do
      "#{label} (#{:erlang.float_to_binary(prob, decimals: 2)})"
    else
      label
    end
  end

  # ============================================================================
  # Edge styling
  # ============================================================================

  defp edge_attributes_fn(tree, theme, hl_edges) do
    fn from, to, edge_id, _weight ->
      meta = Map.get(tree.edge_meta, edge_id, %{})

      base =
        if meta[:edge_type] == :virtual do
          [{:stroke, "#cbd5e1"}, {:stroke_width, "1px"}]
        else
          [{:stroke, theme.edge_color}, {:stroke_width, "2px"}]
        end

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

  defp edge_label(tree, edge_id) do
    meta = Map.get(tree.edge_meta, edge_id, %{})
    meta[:label] || meta[:condition] || ""
  end
end
