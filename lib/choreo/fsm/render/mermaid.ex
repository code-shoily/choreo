defmodule Choreo.FSM.Render.Mermaid do
  @moduledoc """
  Mermaid.js rendering for `Choreo.FSM` state-machine diagrams.

  Produces classic state-machine visualisation:

  * **Normal states** — filled circles
  * **Initial states** — filled circles with a black entry-point dot
  * **Final states** — circles with thick stroke (double-circle equivalent)
  * **Transitions** — labeled arrows
  * Layout is left-to-right by default

  ## Themes

    * `:default` — light grey states, dark text, left-to-right
    * `:dark` — dark background, neon accents
    * `Choreo.Theme` struct — full custom control

  ## Examples

      iex> fsm = Choreo.FSM.new() |> Choreo.FSM.add_state(:a)
      iex> mermaid = Choreo.FSM.Render.Mermaid.to_mermaid(fsm)
      iex> String.contains?(mermaid, "graph LR")
      true
      iex> String.contains?(mermaid, "a")
      true

      iex> fsm = Choreo.FSM.new() |> Choreo.FSM.add_initial_state(:idle) |> Choreo.FSM.add_final_state(:done)
      iex> mermaid = Choreo.FSM.Render.Mermaid.to_mermaid(fsm, syntax: :state_diagram)
      iex> String.contains?(mermaid, "stateDiagram-v2")
      true
      iex> String.contains?(mermaid, "[*] --> idle")
      true
  """

  alias Choreo.FSM
  alias Choreo.Theme

  @doc """
  Renders an FSM to a Mermaid diagram string.

  ## Options

    * `:syntax` — `:flowchart` (default) or `:state_diagram` (native `stateDiagram-v2` syntax)
    * `:theme` — `:default`, `:dark`, `:warm`, `:forest`, `:ocean`, or a `Choreo.Theme` struct (for `:flowchart` syntax)
    * `:direction` — `:lr` (default), `:td`, `:rl`, `:bt` (for `:flowchart` syntax)
    * `:highlighted_nodes` — list of state IDs to highlight (for `:flowchart` syntax)
    * `:highlighted_edges` — list of edge IDs or `{from, to}` tuples to highlight (for `:flowchart` syntax)
    * Any other option accepted by `Yog.Multi.Mermaid.to_mermaid/2`
  """
  @spec to_mermaid(FSM.t(), keyword()) :: String.t()
  def to_mermaid(%FSM{} = fsm, opts \\ []) do
    case Keyword.get(opts, :syntax, :flowchart) do
      :state_diagram ->
        to_native_state_diagram(fsm)

      :flowchart ->
        theme = resolve_theme(Keyword.get(opts, :theme, :default))
        direction = Keyword.get(opts, :direction, :lr)

        hl_nodes = MapSet.new(Keyword.get(opts, :highlighted_nodes, []) || [])
        hl_edges = MapSet.new(Keyword.get(opts, :highlighted_edges, []) || [])

        graph = build_mermaid_graph(fsm)

        base =
          Yog.Multi.Mermaid.default_options()
          |> Map.put(:node_label, fn _id, data ->
            if data[:label] == "", do: " ", else: data[:label] || ""
          end)
          |> Map.put(:edge_label, fn _edge_id, weight ->
            case weight || "" do
              "" -> ""
              label -> "\"#{String.replace(label, "\"", "\\\"")}\""
            end
          end)
          |> Map.put(:node_shape, :circle)
          |> Map.put(:node_attributes, node_attributes_fn(theme, fsm, hl_nodes))
          |> Map.put(:edge_attributes, edge_attributes_fn(theme, hl_edges))
          |> Map.put(:direction, direction)
          |> Map.put(:default_font_color, theme.node_fontcolor)
          |> Map.put(:default_link_stroke, theme.edge_color)
          |> Map.merge(Map.new(opts))

        Yog.Multi.Mermaid.to_mermaid(graph, base)
    end
  end

  defp to_native_state_diagram(fsm) do
    state_defs =
      fsm.graph.nodes
      |> Enum.sort_by(fn {id, _data} -> id end)
      |> Enum.map(fn {id, data} ->
        label = data[:label] || to_string(id)
        m_id = mermaid_id(id)

        if label != m_id or to_string(id) != m_id do
          "  state \"#{label}\" as #{m_id}"
        else
          nil
        end
      end)
      |> Enum.filter(& &1)
      |> Enum.join("\n")

    state_defs_part = if state_defs == "", do: "", else: state_defs <> "\n"

    initial_transitions =
      case FSM.initial_state(fsm) do
        nil -> ""
        id -> "  [*] --> #{mermaid_id(id)}"
      end

    initial_part = if initial_transitions == "", do: "", else: initial_transitions <> "\n"

    transitions =
      fsm.graph.edges
      |> Map.keys()
      |> Enum.sort()
      |> Enum.map_join("\n", fn edge_id ->
        {from, to, weight} = Map.get(fsm.graph.edges, edge_id)
        label = weight || ""

        m_from = mermaid_id(from)
        m_to = mermaid_id(to)

        if label != "" do
          "  #{m_from} --> #{m_to} : #{label}"
        else
          "  #{m_from} --> #{m_to}"
        end
      end)

    transitions_part = if transitions == "", do: "", else: transitions <> "\n"

    final_transitions =
      FSM.final_states(fsm)
      |> Enum.sort()
      |> Enum.map_join("\n", fn id ->
        "  #{mermaid_id(id)} --> [*]"
      end)

    final_part = if final_transitions == "", do: "", else: final_transitions <> "\n"

    "stateDiagram-v2\n" <>
      state_defs_part <> platform_part(initial_part, transitions_part, final_part)
  end

  defp mermaid_id(id) do
    str =
      cond do
        is_atom(id) -> Atom.to_string(id)
        is_binary(id) -> id
        true -> inspect(id)
      end

    if str =~ ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/ do
      str
    else
      sanitized = String.replace(str, ~r/[^a-zA-Z0-9_]/, "_")

      if sanitized =~ ~r/^[0-9]/ do
        "s_" <> sanitized
      else
        sanitized
      end
    end
  end

  defp platform_part(initial_part, transitions_part, final_part) do
    initial_part <> transitions_part <> final_part
  end

  @doc """
  Returns a theme for `Choreo.FSM` Mermaid diagrams.
  """
  @spec theme(atom(), keyword()) :: Theme.t()
  def theme(name \\ :default, overrides \\ []) do
    Choreo.FSM.Themes.resolve(name, overrides)
  end

  # ============================================================================
  # Theme helpers
  # ============================================================================

  defp resolve_theme(name_or_theme), do: Choreo.FSM.Themes.resolve(name_or_theme)

  defp fsm_color(%Theme{colors: colors}, key) do
    Map.get(colors, key, "#e2e8f0")
  end

  # ============================================================================
  # Graph builder — injects entry-point nodes for initial states
  # ============================================================================

  defp build_mermaid_graph(fsm) do
    case FSM.initial_state(fsm) do
      nil ->
        fsm.graph

      id ->
        entry_id = :"__start_#{id}"
        entry_nodes = %{entry_id => %{label: "", type: :entry_point}}
        entry_edges = %{:__entry_0 => {entry_id, id, nil}}

        nodes = Map.merge(fsm.graph.nodes, entry_nodes)
        edges = Map.merge(fsm.graph.edges, entry_edges)

        %{fsm.graph | nodes: nodes, edges: edges}
    end
  end

  # ============================================================================
  # Node styling
  # ============================================================================

  defp node_attributes_fn(theme, fsm, hl_nodes) do
    fn id, data ->
      if data[:type] == :entry_point do
        [{:fill, "black"}, {:stroke, "black"}, {:stroke_width, "1px"}]
      else
        is_initial = id == FSM.initial_state(fsm)
        is_final = id in FSM.final_states(fsm)

        base =
          cond do
            is_initial and is_final ->
              [
                {:fill, fsm_color(theme, :initial)},
                {:stroke, Choreo.Internal.darken(fsm_color(theme, :initial))},
                {:stroke_width, "3px"}
              ]

            is_initial ->
              [
                {:fill, fsm_color(theme, :initial)},
                {:stroke, Choreo.Internal.darken(fsm_color(theme, :initial))}
              ]

            is_final ->
              [
                {:fill, fsm_color(theme, :final)},
                {:stroke, Choreo.Internal.darken(fsm_color(theme, :final))},
                {:stroke_width, "3px"}
              ]

            true ->
              [
                {:fill, fsm_color(theme, :normal)},
                {:stroke, Choreo.Internal.darken(fsm_color(theme, :normal))}
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
  end

  # ============================================================================
  # Edge styling
  # ============================================================================

  defp edge_attributes_fn(theme, hl_edges) do
    fn from, to, edge_id, _weight ->
      base = [
        {:stroke, theme.edge_color},
        {:stroke_width, "#{theme.edge_penwidth}px"}
      ]

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
end
