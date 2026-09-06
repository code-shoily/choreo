defmodule Choreo.UML.Render.Mermaid do
  @moduledoc """
  Mermaid.js rendering for `Choreo.UML` diagrams, supporting flowchart & classDiagram syntaxes.
  """

  alias Choreo.Render.Mermaid, as: MermaidRender
  alias Choreo.Theme

  @doc false
  def theme(name \\ :default, overrides \\ []) do
    Choreo.UML.Render.DOT.theme(name, overrides)
  end

  @doc """
  Renders a UML diagram to a Mermaid string.
  """
  @spec to_mermaid(Choreo.UML.t(), keyword()) :: String.t()
  def to_mermaid(%Choreo.UML{} = uml, opts \\ []) do
    case Keyword.get(opts, :syntax, :flowchart) do
      :class_diagram ->
        to_native_class_diagram(uml, opts)

      :flowchart ->
        theme = resolve_theme(Keyword.get(opts, :theme, :default))
        direction = Keyword.get(opts, :direction, :td)

        hl_nodes = MapSet.new(Keyword.get(opts, :highlighted_nodes, []) || [])
        hl_edges = MapSet.new(Keyword.get(opts, :highlighted_edges, []) || [])

        base_opts =
          Yog.Multi.Mermaid.default_options()
          |> Map.put(:direction, direction)
          |> Map.put(:node_shape, :rounded_rect)
          |> Map.put(:node_label, &node_label/2)
          |> Map.put(:edge_label, fn edge_id, _weight -> edge_label(uml, edge_id) end)
          |> Map.put(:node_attributes, node_attributes_fn(theme, hl_nodes))
          |> Map.put(:edge_attributes, edge_attributes_fn(uml, theme, hl_edges))
          |> Map.put(:default_font_color, theme.node_fontcolor)
          |> Map.put(:default_link_stroke, theme.edge_color)
          |> Map.merge(Map.new(opts))

        Yog.Multi.Mermaid.to_mermaid(uml.graph, base_opts)
        |> String.replace("stroke_dasharray", "stroke-dasharray")
    end
  end

  # ============================================================================
  # Native classDiagram generator
  # ============================================================================

  defp to_native_class_diagram(uml, opts) do
    direction = Keyword.get(opts, :direction, :td)
    direction_part = "  direction #{String.upcase(to_string(direction))}\n"

    id_map = MermaidRender.native_id_map(Map.keys(uml.graph.nodes), "class")

    class_defs =
      uml.graph.nodes
      |> Enum.sort_by(fn {id, _data} -> to_string(id) end)
      |> Enum.map_join("\n", fn {id, data} ->
        safe_id = Map.fetch!(id_map, id)

        stereotype =
          if data[:type] != :class do
            "    <<#{data[:type]}>>"
          else
            ""
          end

        fields =
          data[:fields]
          |> Enum.map_join("\n", fn f ->
            vis = visibility_symbol(f[:visibility])
            type = if f[:type], do: " #{native_member(f[:type])}", else: ""
            "    #{vis}#{native_member(f[:name])}#{type}"
          end)

        functions =
          data[:functions]
          |> Enum.map_join("\n", fn func ->
            vis = visibility_symbol(func[:visibility])
            arity = if func[:arity], do: "(#{func[:arity]})", else: "()"
            ret = if func[:return], do: " #{native_member(func[:return])}", else: ""
            "    #{vis}#{native_member(func[:name])}#{arity}#{ret}"
          end)

        body =
          [stereotype, fields, functions]
          |> Enum.filter(&(&1 != ""))
          |> Enum.join("\n")

        "  class #{safe_id} {\n#{body}\n  }"
      end)

    relations =
      uml.graph.edges
      |> Map.keys()
      |> Enum.sort()
      |> Enum.map_join("\n", fn edge_id ->
        {from, to, _weight} = Map.get(uml.graph.edges, edge_id)
        meta = Map.get(uml.edge_meta, edge_id, %{})
        type = meta[:type] || :depends

        arrow =
          case type do
            :inherits -> "--|>"
            :realizes -> "..|>"
            :associates -> "-->"
            :depends -> "..>"
            _ -> "-->"
          end

        label =
          if l = meta[:label],
            do: " : #{MermaidRender.native_label(l)}",
            else: " : #{type}"

        "  #{Map.fetch!(id_map, from)} #{arrow} #{Map.fetch!(id_map, to)}#{label}"
      end)

    "classDiagram\n" <> direction_part <> class_defs <> "\n" <> relations <> "\n"
  end

  defp native_member(value) do
    value
    |> MermaidRender.native_label()
    |> String.replace(~r/[{}<>\[\]]+/, " ")
    |> String.replace(~r/\s+/, "_")
    |> String.trim("_")
    |> case do
      "" -> "value"
      text -> text
    end
  end

  # ============================================================================
  # Flowchart support & HTML elements
  # ============================================================================

  defp node_label(id, data) do
    type = data[:type] || :class
    label = data[:label] || to_string(id)

    stereotype_part =
      if type != :class do
        "«#{type}»<br/>"
      else
        ""
      end

    fields = data[:fields] || []

    fields_part =
      if fields == [] do
        ""
      else
        "<br/>---<br/>" <>
          (fields
           |> Enum.map_join("<br/>", fn f ->
             vis = visibility_symbol(f[:visibility])
             type_str = if f[:type], do: " : #{f[:type]}", else: ""
             "#{vis} #{f[:name]}#{type_str}"
           end))
      end

    functions = data[:functions] || []

    functions_part =
      if functions == [] do
        ""
      else
        "<br/>---<br/>" <>
          (functions
           |> Enum.map_join("<br/>", fn func ->
             vis = visibility_symbol(func[:visibility])
             arity = if func[:arity], do: "(#{func[:arity]})", else: "()"
             ret_str = if func[:return], do: " : #{func[:return]}", else: ""
             "#{vis} #{func[:name]}#{arity}#{ret_str}"
           end))
      end

    "\"#{stereotype_part}<b>#{label}</b>#{fields_part}#{functions_part}\""
  end

  defp edge_label(uml, edge_id) do
    meta = Map.get(uml.edge_meta, edge_id, %{})
    meta[:label] || ""
  end

  # ============================================================================
  # Node & Edge Styling
  # ============================================================================

  defp node_attributes_fn(theme, hl_nodes) do
    fn id, data ->
      type = data[:type] || :class
      fill = Map.get(theme.colors, type, "#3b82f6")
      stroke = Choreo.Internal.darken(fill)

      base = [
        {:fill, fill},
        {:stroke, stroke},
        {:stroke_width, "1px"}
      ]

      if MapSet.member?(hl_nodes, id) do
        [
          {:stroke, "#ef4444"},
          {:stroke_width, "3px"} | Keyword.drop(base, [:stroke, :stroke_width])
        ]
      else
        base
      end
    end
  end

  defp edge_attributes_fn(uml, theme, hl_edges) do
    fn from, to, edge_id, _weight ->
      meta = Map.get(uml.edge_meta, edge_id, %{})
      type = meta[:type] || :depends

      base = [
        {:stroke, theme.edge_color},
        {:stroke_width, "#{theme.edge_penwidth}px"}
      ]

      base =
        case type do
          :realizes ->
            [{:stroke_dasharray, "5 5"} | base]

          :depends ->
            [{:stroke_dasharray, "5 5"} | base]

          _ ->
            base
        end

      is_highlighted =
        MapSet.member?(hl_edges, edge_id) or
          MapSet.member?(hl_edges, {from, to})

      if is_highlighted do
        [
          {:stroke, "#ef4444"},
          {:stroke_width, "2px"} | Keyword.drop(base, [:stroke, :stroke_width])
        ]
      else
        base
      end
    end
  end

  # ============================================================================
  # Theme support
  # ============================================================================

  defp resolve_theme(%Theme{} = theme), do: theme
  defp resolve_theme(name), do: Choreo.UML.Render.DOT.theme(name)

  defp visibility_symbol(:public), do: "+"
  defp visibility_symbol(:private), do: "-"
  defp visibility_symbol(:protected), do: "#"
  defp visibility_symbol(_), do: ""
end
