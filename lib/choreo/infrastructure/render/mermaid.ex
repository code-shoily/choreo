defmodule Choreo.Infrastructure.Render.Mermaid do
  @moduledoc """
  Mermaid.js rendering for `Choreo.Infrastructure` topology diagrams.
  """

  alias Choreo.Theme

  @doc """
  Renders a `Choreo.Infrastructure` struct to a Mermaid diagram string.
  """
  @spec to_mermaid(Choreo.Infrastructure.t(), keyword()) :: String.t()
  def to_mermaid(%Choreo.Infrastructure{} = infra, opts \\ []) do
    theme = Theme.resolve(Keyword.get(opts, :theme, :default))
    direction = Keyword.get(opts, :direction, :td)
    subgraphs = Choreo.Internal.build_mermaid_subgraphs(infra)

    hl_nodes = MapSet.new(Keyword.get(opts, :highlighted_nodes, []) || [])
    hl_edges = MapSet.new(Keyword.get(opts, :highlighted_edges, []) || [])

    base_opts =
      Yog.Multi.Mermaid.default_options()
      |> Map.put(:direction, direction)
      |> Map.put(:node_shape, &node_shape_fn/2)
      |> Map.put(:node_label, &node_label/2)
      |> Map.put(:edge_label, fn edge_id, _weight -> edge_label(infra, edge_id) end)
      |> Map.put(:node_attributes, node_attributes_fn(theme, hl_nodes))
      |> Map.put(:edge_attributes, edge_attributes_fn(infra, theme, hl_edges))
      |> Map.put(:default_font_color, theme.node_fontcolor)
      |> Map.put(:default_link_stroke, theme.edge_color)
      |> Map.merge(Map.new(opts))

    base_opts =
      if subgraphs != [], do: Map.put(base_opts, :subgraphs, subgraphs), else: base_opts

    Yog.Multi.Mermaid.to_mermaid(infra.graph, base_opts)
    |> String.replace("stroke_dasharray", "stroke-dasharray")
  end

  # ============================================================================
  # Theme helpers
  # ============================================================================

  # (node colors resolved via Theme.color/2)

  # ============================================================================
  # Node styling
  # ============================================================================

  defp node_shape_fn(_id, data) do
    # Shapes are now resolved via Theme; this provides Mermaid-compatible shape mapping
    case Map.get(data, :node_type, :compute) do
      :internet -> :circle
      :load_balancer -> :hexagon
      :compute -> :subroutine
      :managed_db -> :cylinder
      :storage -> :rounded_rect
      _ -> :rounded_rect
    end
  end

  defp node_attributes_fn(theme, hl_nodes) do
    fn id, data ->
      node_type = Map.get(data, :node_type, :compute)

      base = [
        {:fill, Theme.color(theme, node_type)},
        {:stroke, Choreo.Internal.darken(Theme.color(theme, node_type))}
      ]

      base =
        if color = data[:fillcolor],
          do: [{:fill, color} | Keyword.delete(base, :fill)],
          else: base

      base =
        if penwidth = data[:penwidth],
          do: [{:stroke_width, "#{penwidth}px"} | base],
          else: base

      # Icon support intentionally omitted in this build (Choreo.Icons module not loaded)

      if MapSet.member?(hl_nodes, id) do
        Keyword.drop(base, [:fill])
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

  defp edge_attributes_fn(infra, theme, hl_edges) do
    fn from, to, edge_id, _weight ->
      meta = Map.get(infra.edge_meta, edge_id, %{})

      base =
        case meta[:protocol] do
          p when p in [:https, :ssl] ->
            [{:stroke, "#10b981"}, {:stroke_width, "2.5px"}]

          _ ->
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

  defp edge_label(infra, edge_id) do
    meta = Map.get(infra.edge_meta, edge_id, %{})
    meta[:label] || ""
  end
end
