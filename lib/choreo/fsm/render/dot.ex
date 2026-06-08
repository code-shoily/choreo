defmodule Choreo.FSM.Render.DOT do
  @moduledoc """
  DOT (Graphviz) rendering for `Choreo.FSM` state-machine diagrams.

  Produces classic state-machine visualisation:

  * **Normal states** — filled circles
  * **Initial states** — filled circles with a black entry-point dot
  * **Final states** — double circles
  * **Transitions** — labeled arrows
  * Layout is left-to-right by default

  ## Themes

    * `:default` — light grey states, dark text, left-to-right
    * `:dark` — dark background, neon accents
    * `Choreo.Theme` struct — full custom control
  """

  alias Choreo.FSM
  alias Choreo.Theme

  @doc """
  Renders an FSM to a DOT string.

  ## Options

    * `:theme` — `:default`, `:dark`, or a `Choreo.Theme` struct

  ## Examples

      iex> fsm = Choreo.FSM.new() |> Choreo.FSM.add_state(:a)
      iex> dot = Choreo.FSM.Render.DOT.to_dot(fsm)
      iex> String.contains?(dot, "digraph")
      true
      iex> String.contains?(dot, "rankdir=LR")
      true
      iex> String.contains?(dot, "a")
      true
  """
  @spec to_dot(Choreo.FSM.t(), keyword()) :: String.t()
  def to_dot(%Choreo.FSM{} = fsm, opts \\ []) do
    theme = resolve_theme(Keyword.get(opts, :theme, :default))

    states_list = FSM.states(fsm)
    id_map = Enum.into(states_list, %{}, fn id -> {id, dot_id(id)} end)
    safe_graph = Choreo.Internal.make_multi_graph_safe(fsm.graph, id_map)

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

    initials_safe =
      case FSM.initial_state(fsm) do
        nil -> MapSet.new()
        state -> MapSet.new([dot_id(state)])
      end

    finals_safe = FSM.final_states(fsm) |> Enum.map(&dot_id/1) |> MapSet.new()

    base_opts =
      Yog.Multi.DOT.default_options()
      |> Map.put(:rankdir, :lr)
      |> Map.put(:splines, :spline)
      |> Map.put(:nodesep, 0.5)
      |> Map.put(:ranksep, 1.0)
      |> Map.put(:node_shape, :circle)
      |> Map.put(:node_style, :filled)
      |> Map.put(:node_color, fsm_color(theme, :normal))
      |> Map.put(:node_fontname, theme.node_fontname)
      |> Map.put(:node_fontsize, theme.node_fontsize)
      |> Map.put(:node_fontcolor, theme.node_fontcolor)
      |> Map.put(:edge_color, theme.edge_color)
      |> Map.put(:edge_fontname, theme.edge_fontname)
      |> Map.put(:edge_fontsize, theme.edge_fontsize)
      |> Map.put(:edge_penwidth, theme.edge_penwidth)
      |> Map.put(:arrowhead, :normal)
      |> Map.put(:node_label, fn _id, data -> data[:label] || "" end)
      |> Map.put(:edge_label, fn _edge_id, weight -> weight || "" end)
      |> Map.put(
        :node_attributes,
        node_attributes_fn(theme, initials_safe, finals_safe, hl_nodes)
      )
      |> Map.put(:edge_attributes, edge_attributes_fn(theme, hl_edges))
      |> Map.merge(theme_graph_overrides(theme))
      |> Map.merge(Map.new(opts))

    dot = Yog.Multi.DOT.to_dot(safe_graph, base_opts)

    # Inject invisible entry-point nodes for initial states
    initial_nodes = build_initial_nodes(fsm)

    if initial_nodes != "" do
      inject_before_closing(dot, initial_nodes)
    else
      dot
    end
  end

  # ============================================================================
  # Theme helpers
  # ============================================================================

  @doc false
  def theme(name \\ :default, overrides \\ []) do
    Choreo.FSM.Themes.resolve(name, overrides)
  end

  defp resolve_theme(name_or_theme), do: Choreo.FSM.Themes.resolve(name_or_theme)

  defp fsm_color(%Theme{colors: colors}, key) do
    Map.get(colors, key, "#e2e8f0")
  end

  defp theme_graph_overrides(%Theme{} = theme) do
    base = if theme.graph_rankdir, do: %{rankdir: theme.graph_rankdir}, else: %{}
    if theme.graph_bgcolor, do: Map.put(base, :bgcolor, theme.graph_bgcolor), else: base
  end

  # ============================================================================
  # Node styling
  # ============================================================================

  defp node_attributes_fn(theme, initials, finals, hl_nodes) do
    fn id, data ->
      is_initial = id in initials
      is_final = id in finals

      base =
        cond do
          is_initial and is_final ->
            [
              {:shape, :doublecircle},
              {:fillcolor, fsm_color(theme, :initial)},
              {:fontcolor, theme.node_fontcolor},
              {:style, "filled"},
              {:penwidth, 2.0}
            ]

          is_initial ->
            [
              {:fillcolor, fsm_color(theme, :initial)},
              {:fontcolor, theme.node_fontcolor},
              {:style, "filled"}
            ]

          is_final ->
            [
              {:shape, :doublecircle},
              {:fillcolor, fsm_color(theme, :final)},
              {:fontcolor, theme.node_fontcolor},
              {:style, "filled"},
              {:penwidth, 2.0}
            ]

          true ->
            [
              {:fillcolor, fsm_color(theme, :normal)},
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

      # Final highlighting override: Omit fillcolor if node is highlighted
      if MapSet.member?(hl_nodes, id) do
        Keyword.drop(base, [:fillcolor])
      else
        base
      end
    end
  end

  # ============================================================================
  # Edge styling
  # ============================================================================

  defp edge_attributes_fn(theme, hl_edges) do
    fn from, to, edge_id, _weight ->
      base = [
        {:color, theme.edge_color},
        {:fontname, theme.edge_fontname},
        {:fontsize, theme.edge_fontsize},
        {:penwidth, theme.edge_penwidth}
      ]

      # Handle highlighting: Omit color/penwidth if edge is highlighted
      if MapSet.member?(hl_edges, edge_id) or MapSet.member?(hl_edges, {from, to}) do
        Keyword.drop(base, [:color, :penwidth])
      else
        base
      end
    end
  end

  # ============================================================================
  # Initial-state entry points
  # ============================================================================

  defp build_initial_nodes(fsm) do
    case FSM.initial_state(fsm) do
      nil ->
        ""

      id ->
        str =
          cond do
            is_atom(id) -> Atom.to_string(id)
            is_binary(id) -> id
            true -> inspect(id)
          end

        start_id =
          if str =~ ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/ do
            "__start_#{str}"
          else
            "\"__start_#{String.replace(str, "\"", "\\\"")}\""
          end

        target = dot_id(id)

        "  #{start_id} [shape=point, width=0.15, height=0.15, style=filled, fillcolor=black];\n" <>
          "  #{start_id} -> #{target};"
    end
  end

  defp inject_before_closing(dot, extra) do
    String.replace(dot, ~r/\n\}\z/, "\n#{extra}\n}")
  end

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
