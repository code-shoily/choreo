defmodule Choreo.DecisionTree.Render.DOT do
  @moduledoc """
  DOT (Graphviz) rendering for `Choreo.DecisionTree`.

  Produces tree-oriented visualisation:

    * **Root** — diamond with double border
    * **Decisions** — diamonds
    * **Outcomes** — rounded rectangles with class colour coding

  Layout is top-down so decisions flow downward to outcomes.
  Edge labels show the branch condition.
  """

  alias Choreo.Theme

  @doc """
  Renders a decision tree to a DOT string.

  ## Options

    * `:theme` — `:default`, `:dark`, or a `Choreo.Theme` struct

  ## Examples

      iex> tree = Choreo.DecisionTree.new()
      iex> tree = tree
      ...>   |> Choreo.DecisionTree.set_root(:color, feature: "color")
      ...>   |> Choreo.DecisionTree.add_outcome(:stop, label: "Stop")
      ...>   |> Choreo.DecisionTree.add_outcome(:go, label: "Go")
      ...>   |> Choreo.DecisionTree.branch(:color, :stop, "red")
      ...>   |> Choreo.DecisionTree.branch(:color, :go, "green")
      iex> dot = Choreo.DecisionTree.Render.DOT.to_dot(tree)
      iex> String.contains?(dot, "digraph")
      true
      iex> String.contains?(dot, "red")
      true
      iex> String.contains?(dot, "green")
      true
  """
  @spec to_dot(Choreo.DecisionTree.t(), keyword()) :: String.t()
  def to_dot(%Choreo.DecisionTree{} = tree, opts \\ []) do
    theme = resolve_theme(Keyword.get(opts, :theme, :default))

    hl_nodes = MapSet.new(Keyword.get(opts, :highlighted_nodes, []) || [])
    hl_edges = MapSet.new(Keyword.get(opts, :highlighted_edges, []) || [])

    base_opts =
      Yog.Render.DOT.default_options()
      |> Map.put(:rankdir, :tb)
      |> Map.put(:splines, :spline)
      |> Map.put(:nodesep, 0.7)
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
      |> Map.put(:edge_attributes, edge_attributes_fn(tree, theme, hl_edges))
      |> Map.merge(theme_graph_overrides(theme))
      |> Map.merge(Map.new(opts))

    dot = Yog.Render.DOT.to_dot(tree.graph, base_opts)

    # Force same-rank alignment for siblings at each depth level
    rank_groups = build_rank_groups(tree)

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
  defp resolve_theme(:default), do: default_tree_theme()
  defp resolve_theme(:dark), do: dark_tree_theme()
  defp resolve_theme(:warm), do: warm_tree_theme()
  defp resolve_theme(:forest), do: forest_tree_theme()
  defp resolve_theme(:ocean), do: ocean_tree_theme()
  defp resolve_theme(_), do: default_tree_theme()

  defp warm_tree_theme do
    %Theme{
      name: :tree_warm,
      colors: %{
        root: "#ec4899",
        decision: "#f97316",
        outcome: "#10b981"
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

  defp forest_tree_theme do
    %Theme{
      name: :tree_forest,
      colors: %{
        root: "#15803d",
        decision: "#166534",
        outcome: "#84cc16"
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

  defp ocean_tree_theme do
    %Theme{
      name: :tree_ocean,
      colors: %{
        root: "#1d4ed8",
        decision: "#0284c7",
        outcome: "#0ea5e9"
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

  defp default_tree_theme do
    %Theme{
      name: :tree_default,
      colors: %{
        root: "#8b5cf6",
        decision: "#3b82f6",
        outcome: "#10b981"
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

  defp dark_tree_theme do
    %Theme{
      name: :tree_dark,
      colors: %{
        root: "#7c3aed",
        decision: "#2563eb",
        outcome: "#059669"
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

  defp tree_color(%Theme{colors: colors}, key) do
    Map.get(colors, key, "#64748b")
  end

  defp theme_graph_overrides(%Theme{} = theme) do
    base = if theme.graph_rankdir, do: %{rankdir: theme.graph_rankdir}, else: %{}
    if theme.graph_bgcolor, do: Map.put(base, :bgcolor, theme.graph_bgcolor), else: base
  end

  # ============================================================================
  # Rank groups (same-level alignment)
  # ============================================================================

  defp build_rank_groups(tree) do
    tree
    |> nodes_by_depth()
    |> Enum.reject(fn {_depth, nodes} -> length(nodes) <= 1 end)
    |> Enum.map_join("\n", fn {_depth, nodes} ->
      node_list = Enum.map_join(nodes, "; ", &safe_id/1)
      "  { rank=same; #{node_list}; }"
    end)
  end

  defp nodes_by_depth(tree) do
    do_nodes_by_depth(tree, tree.root, 0, %{})
  end

  defp do_nodes_by_depth(_tree, nil, _depth, acc), do: acc

  defp do_nodes_by_depth(tree, id, depth, acc) do
    acc = Map.update(acc, depth, [id], &[id | &1])

    children = Yog.successor_ids(tree.graph, id)

    Enum.reduce(children, acc, fn child, acc ->
      do_nodes_by_depth(tree, child, depth + 1, acc)
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
        case Map.get(data, :node_type, :decision) do
          :root ->
            [
              {:shape, :diamond},
              {:fillcolor, tree_color(theme, :root)},
              {:fontcolor, theme.node_fontcolor},
              {:style, "filled"},
              {:penwidth, 2.0}
            ]

          :decision ->
            [
              {:shape, :diamond},
              {:fillcolor, tree_color(theme, :decision)},
              {:fontcolor, theme.node_fontcolor},
              {:style, "filled"}
            ]

          :outcome ->
            [
              {:shape, :box},
              {:style, "rounded,filled"},
              {:fontcolor, theme.node_fontcolor},
              {:fillcolor, tree_color(theme, :outcome)}
            ]

          _ ->
            [
              {:shape, :ellipse},
              {:fillcolor, tree_color(theme, :decision)},
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

    if prob = data[:probability] do
      "#{label}\n(#{:erlang.float_to_binary(prob, decimals: 2)})"
    else
      label
    end
  end

  # ============================================================================
  # Edge styling
  # ============================================================================

  defp edge_attributes_fn(tree, theme, hl_edges) do
    fn from, to, _weight ->
      meta = Map.get(tree.edge_meta, {from, to}, %{})

      base =
        case meta[:edge_type] do
          :virtual ->
            [{:color, "#cbd5e1"}, {:style, "dashed"}, {:penwidth, 0.8}]

          _ ->
            base = [{:color, theme.edge_color}, {:fontcolor, theme.edge_color}]
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
end
