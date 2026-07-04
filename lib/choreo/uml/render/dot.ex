defmodule Choreo.UML.Render.DOT do
  @moduledoc """
  DOT (Graphviz) rendering for `Choreo.UML` diagrams using 3-compartment HTML record table nodes.
  """

  alias Choreo.Theme

  @doc """
  Renders a UML diagram to a DOT string.
  """
  @spec to_dot(Choreo.UML.t(), keyword()) :: String.t()
  def to_dot(%Choreo.UML{} = uml, opts \\ []) do
    theme = resolve_theme(Keyword.get(opts, :theme, :default))

    states_list = Map.keys(uml.graph.nodes)
    id_map = Enum.into(states_list, %{}, fn id -> {id, dot_id(id)} end)
    safe_graph = Choreo.Internal.make_multi_graph_safe(uml.graph, id_map)
    safe_uml = %{uml | graph: safe_graph}

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

    direction =
      case Keyword.get(opts, :direction, :tb) do
        :td ->
          :tb

        other ->
          other
          |> to_string()
          |> String.downcase()
          |> String.to_existing_atom()
      end

    base_opts =
      Yog.Render.DOT.default_options()
      |> Map.put(:rankdir, direction)
      |> Map.put(:splines, :ortho)
      |> Map.put(:nodesep, 1.2)
      |> Map.put(:ranksep, 1.2)
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
      |> Map.put(:edge_attributes, edge_attributes_fn(safe_uml, theme, hl_edges))
      |> Map.merge(theme_graph_overrides(theme))
      |> Map.merge(Map.new(Keyword.drop(opts, [:theme, :direction])))

    dot = Yog.Multi.DOT.to_dot(safe_graph, base_opts)

    # Post-process generated DOT to convert HTML-like labels to Graphviz-compatible
    # double-angle-bracket syntax (required by Viz.js and older Graphviz versions).
    String.replace(dot, ~r/label=<(TABLE.*?)<\/TABLE>/s, "label=<<\\1</TABLE>>")
  end

  @doc false
  def theme(name \\ :default, overrides \\ []) do
    resolve_theme(name) |> Choreo.Theme.override(overrides)
  end

  defp resolve_theme(%Theme{} = theme), do: theme
  defp resolve_theme(:default), do: default_uml_theme()
  defp resolve_theme(:dark), do: dark_uml_theme()
  defp resolve_theme(:minimal), do: minimal_uml_theme()
  defp resolve_theme(:warm), do: warm_uml_theme()
  defp resolve_theme(:forest), do: forest_uml_theme()
  defp resolve_theme(:ocean), do: ocean_uml_theme()
  defp resolve_theme(_), do: default_uml_theme()

  defp minimal_uml_theme do
    %Theme{default_uml_theme() | name: :uml_minimal}
  end

  defp default_uml_theme do
    %Theme{
      name: :uml_default,
      colors: %{
        class: "#3b82f6",
        struct: "#10b981",
        behavior: "#f59e0b",
        protocol: "#8b5cf6",
        interface: "#ec4899",
        header_fg: "#ffffff",
        text_color: "#1e293b",
        border_color: "#cbd5e1",
        bg_color: "#f8fafc"
      },
      node_fontname: "Helvetica",
      node_fontsize: 11,
      node_fontcolor: "#1e293b",
      edge_color: "#475569",
      edge_fontname: "Helvetica",
      edge_fontsize: 9,
      edge_penwidth: 1.0,
      graph_bgcolor: "#ffffff",
      graph_splines: :spline,
      graph_nodesep: 1.2,
      graph_ranksep: 1.2
    }
  end

  defp dark_uml_theme do
    %Theme{
      name: :uml_dark,
      colors: %{
        class: "#60a5fa",
        struct: "#34d399",
        behavior: "#fbbf24",
        protocol: "#a78bfa",
        interface: "#f472b6",
        header_fg: "#ffffff",
        text_color: "#e2e8f0",
        border_color: "#475569",
        bg_color: "#1e293b"
      },
      node_fontname: "Helvetica",
      node_fontsize: 11,
      node_fontcolor: "#e2e8f0",
      edge_color: "#94a3b8",
      edge_fontname: "Helvetica",
      edge_fontsize: 9,
      edge_penwidth: 1.0,
      graph_bgcolor: "#0f172a",
      graph_splines: :spline,
      graph_nodesep: 1.2,
      graph_ranksep: 1.2
    }
  end

  defp warm_uml_theme do
    %Theme{
      name: :uml_warm,
      colors: %{
        class: "#ea580c",
        struct: "#ca8a04",
        behavior: "#b45309",
        protocol: "#c026d3",
        interface: "#db2777",
        header_fg: "#ffffff",
        text_color: "#44403c",
        border_color: "#e7e5e4",
        bg_color: "#fafaf9"
      },
      node_fontname: "Helvetica",
      node_fontsize: 11,
      node_fontcolor: "#44403c",
      edge_color: "#78716c",
      edge_fontname: "Helvetica",
      edge_fontsize: 9,
      edge_penwidth: 1.0,
      graph_bgcolor: "#fffbeb",
      graph_splines: :spline,
      graph_nodesep: 1.2,
      graph_ranksep: 1.2
    }
  end

  defp forest_uml_theme do
    %Theme{
      name: :uml_forest,
      colors: %{
        class: "#047857",
        struct: "#15803d",
        behavior: "#b45309",
        protocol: "#0f766e",
        interface: "#0369a1",
        header_fg: "#ffffff",
        text_color: "#1f2937",
        border_color: "#d1d5db",
        bg_color: "#f9fafb"
      },
      node_fontname: "Helvetica",
      node_fontsize: 11,
      node_fontcolor: "#1f2937",
      edge_color: "#4b5563",
      edge_fontname: "Helvetica",
      edge_fontsize: 9,
      edge_penwidth: 1.0,
      graph_bgcolor: "#f0fdf4",
      graph_splines: :spline,
      graph_nodesep: 1.2,
      graph_ranksep: 1.2
    }
  end

  defp ocean_uml_theme do
    %Theme{
      name: :uml_ocean,
      colors: %{
        class: "#0369a1",
        struct: "#0f766e",
        behavior: "#7c3aed",
        protocol: "#4338ca",
        interface: "#be185d",
        header_fg: "#ffffff",
        text_color: "#0f172a",
        border_color: "#e2e8f0",
        bg_color: "#f8fafc"
      },
      node_fontname: "Helvetica",
      node_fontsize: 11,
      node_fontcolor: "#0f172a",
      edge_color: "#475569",
      edge_fontname: "Helvetica",
      edge_fontsize: 9,
      edge_penwidth: 1.0,
      graph_bgcolor: "#f0f9ff",
      graph_splines: :spline,
      graph_nodesep: 1.2,
      graph_ranksep: 1.2
    }
  end

  defp theme_graph_overrides(%Theme{} = theme), do: Choreo.Theme.graph_overrides(theme)

  # ============================================================================
  # Node styling & unquoting
  # ============================================================================

  defp node_attributes_fn(_theme, hl_nodes) do
    fn id, _data ->
      if MapSet.member?(hl_nodes, id) do
        [{:color, "#ef4444"}, {:penwidth, "2.0"}]
      else
        []
      end
    end
  end

  # ============================================================================
  # Edge styling
  # ============================================================================

  defp edge_attributes_fn(uml, theme, hl_edges) do
    fn from, to, edge_id, _weight ->
      meta = Map.get(uml.edge_meta, edge_id, %{})
      type = meta[:type] || :depends

      base = [
        {:color, theme.edge_color},
        {:penwidth, theme.edge_penwidth}
      ]

      base =
        case type do
          :inherits ->
            [{:style, "solid"}, {:arrowhead, "empty"} | base]

          :realizes ->
            [{:style, "dashed"}, {:arrowhead, "empty"} | base]

          :associates ->
            [{:style, "solid"}, {:arrowhead, "normal"} | base]

          :depends ->
            [{:style, "dashed"}, {:arrowhead, "normal"} | base]

          _ ->
            [{:style, "solid"}, {:arrowhead, "normal"} | base]
        end

      base =
        if label = meta[:label],
          do: [
            {:label, label},
            {:fontname, theme.edge_fontname},
            {:fontsize, theme.edge_fontsize} | base
          ],
          else: base

      is_highlighted =
        MapSet.member?(hl_edges, edge_id) or
          MapSet.member?(hl_edges, {from, to})

      if is_highlighted do
        [{:color, "#ef4444"}, {:penwidth, 2.0} | Keyword.drop(base, [:color, :penwidth])]
      else
        base
      end
    end
  end

  # ============================================================================
  # HTML Table Builder (Standard 3-Compartment UML Table)
  # ============================================================================

  defp node_label(id, data, theme) do
    type = data[:type] || :class
    header_bg = Map.get(theme.colors, type, "#3b82f6")
    header_fg = theme.colors.header_fg
    border_color = theme.colors.border_color
    bg_color = theme.colors.bg_color
    text_color = theme.colors.text_color
    label = data[:label] || to_string(id)

    # 1. Header Compartment
    stereotype_part =
      if type != :class do
        "«#{type}»<BR/>"
      else
        ""
      end

    header_html =
      "<TR><TD BGCOLOR=\"#{header_bg}\"><FONT COLOR=\"#{header_fg}\"><B>#{stereotype_part}#{label}</B></FONT></TD></TR>"

    # 2. Fields Compartment
    fields = data[:fields] || []

    fields_html =
      if fields == [] do
        ~s(<TR><TD BGCOLOR="#{bg_color}" HEIGHT="10"></TD></TR>)
      else
        rows =
          fields
          |> Enum.map_join("<BR/>", fn f ->
            vis = visibility_symbol(f[:visibility])
            type_part = if f[:type], do: " : #{f[:type]}", else: ""
            "#{vis} #{f[:name]}#{type_part}"
          end)

        ~s(<TR><TD BGCOLOR="#{bg_color}" ALIGN="LEFT"><FONT COLOR="#{text_color}">#{rows}</FONT></TD></TR>)
      end

    # 3. Functions Compartment
    functions = data[:functions] || []

    functions_html =
      if functions == [] do
        ~s(<TR><TD BGCOLOR="#{bg_color}" HEIGHT="10"></TD></TR>)
      else
        rows =
          functions
          |> Enum.map_join("<BR/>", fn func ->
            vis = visibility_symbol(func[:visibility])
            arity = if func[:arity], do: "(#{func[:arity]})", else: "()"
            ret_part = if func[:return], do: " : #{func[:return]}", else: ""
            "#{vis} #{func[:name]}#{arity}#{ret_part}"
          end)

        ~s(<TR><TD BGCOLOR="#{bg_color}" ALIGN="LEFT"><FONT COLOR="#{text_color}">#{rows}</FONT></TD></TR>)
      end

    ~s(<TABLE BORDER="0" CELLBORDER="1" CELLSPACING="0" CELLPADDING="4" PORT="f0" COLOR="#{border_color}">) <>
      header_html <> fields_html <> functions_html <> "</TABLE>"
  end

  defp visibility_symbol(:public), do: "+"
  defp visibility_symbol(:private), do: "-"
  defp visibility_symbol(:protected), do: "#"
  defp visibility_symbol(_), do: ""

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
