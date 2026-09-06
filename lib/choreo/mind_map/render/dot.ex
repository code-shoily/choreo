defmodule Choreo.MindMap.Render.DOT do
  @moduledoc """
  DOT (Graphviz) rendering for `Choreo.MindMap`.

  Produces mind-map oriented visualisation:

    * **Root** — double circle, bold border, prominent colour
    * **Topics** — ellipses, medium size
    * **Subtopics** — boxes, compact
    * **Notes** — note shape, pale background

  Edge styles:
    * **Branch** — solid grey with arrowhead
    * **Associates** — dashed grey without arrowhead

  Layout is top-down so the root sits at the top and branches flow
  downward. Siblings at the same depth are aligned on the same rank.
  """

  alias Choreo.Theme

  @doc """
  Renders a mind map to a DOT string.

  ## Options

    * `:theme` — `:default`, `:dark`, `:minimal`, `:warm`, `:forest`, `:ocean`, or a `Choreo.Theme` struct
    * `:highlighted_nodes` — list of node IDs to highlight
    * `:highlighted_edges` — list of `{from, to}` tuples to highlight
    * Any other option accepted by `Yog.Render.DOT.to_dot/2`, such as `:rankdir`

  ## Examples

      iex> map = Choreo.MindMap.new()
      iex> map = map
      ...>   |> Choreo.MindMap.set_root(:a, label: "A")
      ...>   |> Choreo.MindMap.add_topic(:b, label: "B")
      ...>   |> Choreo.MindMap.branch(:a, :b)
      iex> dot = Choreo.MindMap.Render.DOT.to_dot(map)
      iex> String.contains?(dot, "digraph")
      true
      iex> String.contains?(dot, "A")
      true
      iex> String.contains?(dot, "B")
      true
  """
  @spec to_dot(Choreo.MindMap.t(), keyword()) :: String.t()
  def to_dot(%Choreo.MindMap{} = map, opts \\ []) do
    theme = resolve_theme(Keyword.get(opts, :theme, :default))

    states_list = Choreo.MindMap.nodes(map)
    id_map = Enum.into(states_list, %{}, fn id -> {id, dot_id(id)} end)
    safe_graph = Choreo.Internal.make_simple_graph_safe(map.graph, id_map)
    safe_root = if map.root, do: Map.fetch!(id_map, map.root), else: nil

    safe_edge_meta =
      Map.new(map.edge_meta, fn {{from, to}, meta} ->
        {{Map.fetch!(id_map, from), Map.fetch!(id_map, to)}, meta}
      end)

    safe_map = %{map | graph: safe_graph, root: safe_root, edge_meta: safe_edge_meta}

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
      |> Map.put(:rankdir, :tb)
      |> Map.put(:splines, :spline)
      |> Map.put(:nodesep, 0.6)
      |> Map.put(:ranksep, 1.2)
      |> Map.put(:node_shape, :ellipse)
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
      |> Map.put(:edge_attributes, edge_attributes_fn(safe_map, hl_edges))
      |> Map.merge(theme_graph_overrides(theme))
      |> Map.merge(Map.new(opts))

    dot = Yog.Render.DOT.to_dot(safe_graph, base_opts)

    # Force same-rank alignment for siblings at each depth level
    rank_groups = build_rank_groups(safe_map)

    if rank_groups != "" do
      inject_before_closing(dot, rank_groups)
    else
      dot
    end
  end

  # ============================================================================
  # Theme helpers
  # ============================================================================

  @doc false
  def theme(name \\ :default, overrides \\ []) do
    resolve_theme(name) |> Choreo.Theme.override(overrides)
  end

  defp resolve_theme(%Theme{} = theme), do: theme
  defp resolve_theme(:default), do: default_mind_map_theme()
  defp resolve_theme(:dark), do: dark_mind_map_theme()
  defp resolve_theme(:minimal), do: minimal_mind_map_theme()
  defp resolve_theme(:warm), do: warm_mind_map_theme()
  defp resolve_theme(:forest), do: forest_mind_map_theme()
  defp resolve_theme(:ocean), do: ocean_mind_map_theme()
  defp resolve_theme(_), do: default_mind_map_theme()

  defp warm_mind_map_theme do
    %Theme{
      name: :mind_map_warm,
      colors: %{
        root: "#ec4899",
        topic: "#f97316",
        subtopic: "#fbbf24",
        note: "#fdba74"
      },
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

  defp forest_mind_map_theme do
    %Theme{
      name: :mind_map_forest,
      colors: %{
        root: "#15803d",
        topic: "#166534",
        subtopic: "#65a30d",
        note: "#86efac"
      },
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

  defp ocean_mind_map_theme do
    %Theme{
      name: :mind_map_ocean,
      colors: %{
        root: "#1d4ed8",
        topic: "#0284c7",
        subtopic: "#0ea5e9",
        note: "#7dd3fc"
      },
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

  defp minimal_mind_map_theme do
    %Theme{default_mind_map_theme() | name: :mind_map_minimal}
  end

  defp default_mind_map_theme do
    %Theme{
      name: :mind_map_default,
      colors: %{
        root: "#8b5cf6",
        topic: "#3b82f6",
        subtopic: "#06b6d4",
        note: "#f59e0b"
      },
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

  defp dark_mind_map_theme do
    %Theme{
      name: :mind_map_dark,
      colors: %{
        root: "#7c3aed",
        topic: "#2563eb",
        subtopic: "#0891b2",
        note: "#d97706"
      },
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

  defp mm_color(%Theme{colors: colors}, key) do
    Map.get(colors, key, "#64748b")
  end

  defp theme_graph_overrides(%Theme{} = theme) do
    base = if theme.graph_rankdir, do: %{rankdir: theme.graph_rankdir}, else: %{}
    if theme.graph_bgcolor, do: Map.put(base, :bgcolor, theme.graph_bgcolor), else: base
  end

  # ============================================================================
  # Rank groups (same-level alignment)
  # ============================================================================

  defp build_rank_groups(map) do
    map
    |> nodes_by_depth()
    |> Enum.reject(fn {_depth, nodes} -> length(nodes) <= 1 end)
    |> Enum.map_join("\n", fn {_depth, nodes} ->
      node_list = Enum.map_join(nodes, "; ", &safe_id/1)
      "  { rank=same; #{node_list}; }"
    end)
  end

  defp nodes_by_depth(map) do
    do_nodes_by_depth(map, map.root, 0, %{})
  end

  defp do_nodes_by_depth(_map, nil, _depth, acc), do: acc

  defp do_nodes_by_depth(map, id, depth, acc) do
    acc = Map.update(acc, depth, [id], &[id | &1])

    children = branch_successors(map, id)

    Enum.reduce(children, acc, fn child, acc ->
      do_nodes_by_depth(map, child, depth + 1, acc)
    end)
  end

  defp branch_successors(map, id) do
    map.graph
    |> Yog.successor_ids(id)
    |> Enum.filter(fn succ ->
      meta = Map.get(map.edge_meta, {id, succ}, %{})
      meta[:edge_type] == :branch
    end)
  end

  defp inject_before_closing(dot, extra) do
    String.replace(dot, ~r/\n\}\z/, "\n#{extra}\n}")
  end

  # ============================================================================
  # Node styling
  # ============================================================================

  defp node_attributes_fn(theme, hl_nodes) do
    fn id, data ->
      base =
        case Map.get(data, :node_type, :topic) do
          :root ->
            [
              {:shape, :doublecircle},
              {:fillcolor, mm_color(theme, :root)},
              {:fontcolor, theme.node_fontcolor},
              {:style, "filled"},
              {:penwidth, 2.0}
            ]

          :topic ->
            [
              {:shape, :ellipse},
              {:fillcolor, mm_color(theme, :topic)},
              {:fontcolor, theme.node_fontcolor},
              {:style, "filled"}
            ]

          :subtopic ->
            [
              {:shape, :box},
              {:fillcolor, mm_color(theme, :subtopic)},
              {:fontcolor, theme.node_fontcolor},
              {:style, "rounded,filled"}
            ]

          :note ->
            [
              {:shape, :note},
              {:fillcolor, mm_color(theme, :note)},
              {:fontcolor, theme.node_fontcolor},
              {:style, "filled"}
            ]

          _ ->
            [
              {:shape, :ellipse},
              {:fillcolor, mm_color(theme, :topic)},
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
    data[:label] || ""
  end

  # ============================================================================
  # Edge styling
  # ============================================================================

  defp edge_attributes_fn(map, hl_edges) do
    fn from, to, _weight ->
      meta = Map.get(map.edge_meta, {from, to}, %{})

      base =
        case meta[:edge_type] do
          :associates ->
            base = [{:color, "#94a3b8"}, {:style, "dashed"}, {:dir, "none"}]
            if label = meta[:label], do: [{:label, label} | base], else: base

          :virtual ->
            [{:color, "#cbd5e1"}, {:style, "dashed"}, {:penwidth, 0.8}]

          _ ->
            base = [{:color, "#64748b"}]
            if label = meta[:label], do: [{:label, label} | base], else: base
        end

      # Handle highlighting: Omit color/penwidth if edge is highlighted
      if MapSet.member?(hl_edges, {from, to}) do
        Keyword.drop(base, [:color, :penwidth])
      else
        base
      end
    end
  end

  defp edge_label(_), do: ""

  defp safe_id(id) when is_atom(id), do: Atom.to_string(id)
  defp safe_id(id) when is_binary(id), do: id
  defp safe_id(id), do: inspect(id)

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
