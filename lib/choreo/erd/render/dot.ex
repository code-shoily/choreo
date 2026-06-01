defmodule Choreo.ERD.Render.DOT do
  @moduledoc """
  DOT (Graphviz) rendering for `Choreo.ERD` diagrams using HTML-like table nodes.
  """

  alias Choreo.Theme

  @doc """
  Renders an ERD diagram to a DOT string.
  """
  @spec to_dot(Choreo.ERD.t(), keyword()) :: String.t()
  def to_dot(%Choreo.ERD{} = erd, opts \\ []) do
    theme = resolve_theme(Keyword.get(opts, :theme, :default))

    hl_nodes = MapSet.new(Keyword.get(opts, :highlighted_nodes, []) || [])
    hl_edges = MapSet.new(Keyword.get(opts, :highlighted_edges, []) || [])

    direction =
      Keyword.get(opts, :direction, :lr)
      |> to_string()
      |> String.downcase()
      |> String.to_existing_atom()

    base_opts =
      Yog.Render.DOT.default_options()
      |> Map.put(:rankdir, direction)
      |> Map.put(:splines, :ortho)
      |> Map.put(:nodesep, 1.2)
      |> Map.put(:ranksep, 1.2)
      # HTML tables render best on plain/transparent nodes
      |> Map.put(:node_shape, :plain)
      |> Map.put(:node_style, :filled)
      |> Map.put(:node_color, "transparent")
      |> Map.put(:node_fontname, theme.node_fontname)
      |> Map.put(:node_fontsize, theme.node_fontsize)
      |> Map.put(:node_fontcolor, theme.node_fontcolor)
      |> Map.put(:edge_color, theme.edge_color)
      |> Map.put(:edge_fontname, theme.edge_fontname)
      |> Map.put(:edge_fontsize, theme.edge_fontsize)
      |> Map.put(:edge_penwidth, theme.edge_penwidth)
      |> Map.put(:node_label, fn id, data -> node_label(id, data, theme) end)
      |> Map.put(:edge_label, fn _edge_id, _weight -> "" end)
      |> Map.put(:node_attributes, node_attributes_fn(theme, hl_nodes))
      |> Map.put(:edge_attributes, edge_attributes_fn(erd, theme, hl_edges))
      |> Map.merge(theme_graph_overrides(theme))
      |> Map.merge(Map.new(Keyword.drop(opts, [:theme, :direction])))

    # Render multigraph
    dot = Yog.Multi.DOT.to_dot(erd.graph, base_opts)

    # Post-process generated DOT to unwrap HTML-like labels from quotes
    String.replace(dot, ~r/label="<TABLE.*?<\/TABLE>"/is, fn match ->
      html =
        match
        |> String.slice(7..-2//1)
        |> String.replace(~r/\\"/, "\"")

      "label=<#{html}>"
    end)
  end

  @doc false
  def theme(name \\ :default, overrides \\ []) do
    resolve_theme(name) |> Choreo.Theme.override(overrides)
  end

  defp resolve_theme(%Theme{} = theme), do: theme
  defp resolve_theme(:default), do: default_erd_theme()
  defp resolve_theme(:dark), do: dark_erd_theme()
  defp resolve_theme(:warm), do: warm_erd_theme()
  defp resolve_theme(:forest), do: forest_erd_theme()
  defp resolve_theme(:ocean), do: ocean_erd_theme()
  defp resolve_theme(_), do: default_erd_theme()

  defp default_erd_theme do
    %Theme{
      name: :erd_default,
      colors: %{
        header_bg: "#3b82f6",
        header_fg: "#ffffff",
        border: "#cbd5e1"
      },
      node_fontname: "Helvetica",
      node_fontsize: 12,
      node_fontcolor: "#1e293b",
      edge_color: "#64748b",
      edge_fontname: "Helvetica",
      edge_fontsize: 10,
      edge_penwidth: 1.0,
      graph_bgcolor: nil,
      graph_splines: :spline,
      graph_nodesep: 1.2,
      graph_ranksep: 1.2
    }
  end

  defp dark_erd_theme do
    %Theme{
      name: :erd_dark,
      colors: %{
        header_bg: "#1e293b",
        header_fg: "#f8fafc",
        border: "#475569"
      },
      node_fontname: "Helvetica",
      node_fontsize: 12,
      node_fontcolor: "#e2e8f0",
      edge_color: "#94a3b8",
      edge_fontname: "Helvetica",
      edge_fontsize: 10,
      edge_penwidth: 1.0,
      graph_bgcolor: "#0f172a",
      graph_splines: :spline,
      graph_nodesep: 1.2,
      graph_ranksep: 1.2
    }
  end

  defp warm_erd_theme do
    %Theme{
      name: :erd_warm,
      colors: %{
        header_bg: "#f97316",
        header_fg: "#ffffff",
        border: "#fed7aa"
      },
      node_fontname: "Helvetica",
      node_fontsize: 12,
      node_fontcolor: "#78350f",
      edge_color: "#78716c",
      edge_fontname: "Helvetica",
      edge_fontsize: 10,
      edge_penwidth: 1.0,
      graph_bgcolor: "#fffbeb",
      graph_splines: :spline,
      graph_nodesep: 1.2,
      graph_ranksep: 1.2
    }
  end

  defp forest_erd_theme do
    %Theme{
      name: :erd_forest,
      colors: %{
        header_bg: "#15803d",
        header_fg: "#ffffff",
        border: "#bbf7d0"
      },
      node_fontname: "Helvetica",
      node_fontsize: 12,
      node_fontcolor: "#14532d",
      edge_color: "#4b5563",
      edge_fontname: "Helvetica",
      edge_fontsize: 10,
      edge_penwidth: 1.0,
      graph_bgcolor: "#f0fdf4",
      graph_splines: :spline,
      graph_nodesep: 1.2,
      graph_ranksep: 1.2
    }
  end

  defp ocean_erd_theme do
    %Theme{
      name: :erd_ocean,
      colors: %{
        header_bg: "#0369a1",
        header_fg: "#ffffff",
        border: "#bae6fd"
      },
      node_fontname: "Helvetica",
      node_fontsize: 12,
      node_fontcolor: "#0c4a6e",
      edge_color: "#64748b",
      edge_fontname: "Helvetica",
      edge_fontsize: 10,
      edge_penwidth: 1.0,
      graph_bgcolor: "#f0f9ff",
      graph_splines: :spline,
      graph_nodesep: 1.2,
      graph_ranksep: 1.2
    }
  end

  defp theme_graph_overrides(%Theme{} = theme) do
    %{
      rankdir: theme.graph_rankdir,
      bgcolor: theme.graph_bgcolor,
      splines: theme.graph_splines,
      nodesep: theme.graph_nodesep,
      ranksep: theme.graph_ranksep
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  # ============================================================================
  # Node label & attributes
  # ============================================================================

  defp node_attributes_fn(_theme, hl_nodes) do
    fn id, _data ->
      if MapSet.member?(hl_nodes, id) do
        [color: "#ef4444"]
      else
        []
      end
    end
  end

  defp node_label(id, data, theme) do
    columns = data[:columns] || []
    table_name = data[:label] || to_string(id)

    header_bg = theme.colors[:header_bg] || "#3b82f6"
    header_fg = theme.colors[:header_fg] || "#ffffff"
    border = theme.colors[:border] || "#cbd5e1"

    # Build the HTML Table markup
    rows =
      Enum.map_join(columns, "", fn col ->
        key_marker =
          case col[:key] do
            :pk -> "<b>[PK]</b>"
            :fk -> "<i>[FK]</i>"
            _ -> ""
          end

        comment_suffix =
          if col[:comment], do: " &lt;#{col[:comment]}&gt;", else: ""

        "<TR>" <>
          "<TD ALIGN='LEFT' BORDER='1' COLOR='#{border}'>#{col[:name]}</TD>" <>
          "<TD ALIGN='LEFT' BORDER='1' COLOR='#{border}'><i>#{col[:type]}</i></TD>" <>
          "<TD ALIGN='CENTER' BORDER='1' COLOR='#{border}'>#{key_marker}#{comment_suffix}</TD>" <>
          "</TR>"
      end)

    # Full HTML table label
    "<TABLE BORDER='0' CELLBORDER='1' CELLSPACING='0' CELLPADDING='6' COLOR='#{border}'>" <>
      "<TR><TD COLSPAN='3' BGCOLOR='#{header_bg}' ALIGN='CENTER' BORDER='1' COLOR='#{border}'>" <>
      "<FONT COLOR='#{header_fg}'><B>#{table_name}</B></FONT>" <>
      "</TD></TR>" <>
      rows <>
      "</TABLE>"
  end

  # ============================================================================
  # Edge styling
  # ============================================================================

  defp edge_attributes_fn(erd, theme, hl_edges) do
    fn from, to, edge_id, _weight ->
      meta = Map.get(erd.edge_meta, edge_id, %{})

      # Map cardinality to dual-end arrow decorations
      {tail, head} =
        case meta[:cardinality] do
          :one_to_one -> {:teetee, :teetee}
          :one_to_many -> {:teetee, :crowodot}
          :zero_or_one_to_many -> {:odot, :crowodot}
          :exactly_one_to_many -> {:teetee, :crowtee}
          :many_to_many -> {:crowodot, :crowodot}
          _ -> {:none, :normal}
        end

      base = [
        {:arrowtail, tail},
        {:arrowhead, head},
        {:dir, :both},
        {:color, theme.edge_color},
        {:penwidth, theme.edge_penwidth}
      ]

      base = if label = meta[:label], do: [{:label, label} | base], else: base

      # Highlight override
      if MapSet.member?(hl_edges, edge_id) or MapSet.member?(hl_edges, {from, to}) do
        Keyword.merge(base, color: "#ef4444", penwidth: 2.0)
      else
        base
      end
    end
  end
end
