defmodule Choreo.Workflow.Render.Mermaid do
  @moduledoc """
  Mermaid.js rendering for `Choreo.Workflow` orchestration diagrams.

  Produces workflow-oriented visualisation:

    * **Start** — green circle (entry point)
    * **End** — red circle with thick stroke (terminal)
    * **Task** — subroutine rectangles (automated steps)
    * **Decision** — rhombus (conditional branch)
    * **Fork** — trapezoid (parallel split)
    * **Join** — trapezoid alt (parallel merge)
    * **Compensation** — rounded rectangle with red dashed border (rollback)
    * **Event** — rounded rectangle (trigger / signal)

  Edge styles:
    * **Sequence** — solid grey
    * **Compensation** — dashed red
    * **Retry** — dashed orange
    * **Failure** — dashed grey
    * **Timeout** — dashed yellow

  Swimlanes are rendered as Mermaid subgraphs with optional fill colours.

  ## Further reading

    * [BPMN 2.0 Specification](https://www.omg.org/spec/BPMN/2.0/)
    * [Workflow Patterns Initiative](http://www.workflowpatterns.com/)
  """

  alias Choreo.Theme

  @doc """
  Renders a workflow to a Mermaid.js string.

  ## Syntax

    * `:flowchart` (default) — classic `graph TD` flowchart, including swimlanes as subgraphs.
    * `:swimlane` — native Mermaid 11.16+ `swimlane-beta` output.

  ## Options

    * `:syntax` — `:flowchart` (default) or `:swimlane`
    * `:theme` — `:default`, `:dark`, `:warm`, `:forest`, `:ocean`, or a `Choreo.Theme` struct
    * `:direction` — `:td` (default for flowchart), `:lr` (default for swimlane), `:bt`, `:rl`
    * `:highlighted_nodes` — list of node IDs to highlight
    * `:highlighted_edges` — list of edge IDs or `{from, to}` tuples to highlight
    * Any other option accepted by `Yog.Multi.Mermaid.to_mermaid/2` (flowchart syntax only)

  ## Examples

      iex> workflow = Choreo.Workflow.new()
      iex> workflow = workflow
      ...>   |> Choreo.Workflow.add_start(:start)
      ...>   |> Choreo.Workflow.add_task(:process)
      ...>   |> Choreo.Workflow.add_end(:end)
      ...>   |> Choreo.Workflow.connect(:start, :process)
      ...>   |> Choreo.Workflow.connect(:process, :end)
      iex> mermaid = Choreo.Workflow.Render.Mermaid.to_mermaid(workflow)
      iex> String.contains?(mermaid, "graph TD")
      true
      iex> String.contains?(mermaid, "process")
      true
  """
  @spec to_mermaid(Choreo.Workflow.t(), keyword()) :: String.t()
  def to_mermaid(%Choreo.Workflow{} = workflow, opts \\ []) do
    case Keyword.get(opts, :syntax, :flowchart) do
      :swimlane -> to_swimlane(workflow, opts)
      _ -> to_flowchart(workflow, opts)
    end
  end

  defp to_flowchart(%Choreo.Workflow{} = workflow, opts) do
    theme = resolve_theme(Keyword.get(opts, :theme, :default))
    direction = Keyword.get(opts, :direction, :td)

    subgraphs = Choreo.Internal.build_mermaid_subgraphs(workflow)

    hl_nodes = MapSet.new(Keyword.get(opts, :highlighted_nodes, []) || [])
    hl_edges = MapSet.new(Keyword.get(opts, :highlighted_edges, []) || [])

    base =
      Yog.Multi.Mermaid.default_options()
      |> Map.put(:node_label, &node_label/2)
      |> Map.put(:edge_label, fn edge_id, _weight -> edge_label(workflow, edge_id) end)
      |> Map.put(:node_shape, &node_shape_fn/2)
      |> Map.put(:node_attributes, node_attributes_fn(theme, hl_nodes))
      |> Map.put(:edge_attributes, edge_attributes_fn(workflow, hl_edges))
      |> Map.put(:direction, direction)
      |> Map.put(:default_font_color, theme.node_fontcolor)
      |> Map.put(:default_link_stroke, theme.edge_color)
      |> Map.merge(Map.new(opts))

    base = if subgraphs != [], do: Map.put(base, :subgraphs, subgraphs), else: base

    Yog.Multi.Mermaid.to_mermaid(workflow.graph, base)
    |> String.replace("stroke_dasharray", "stroke-dasharray")
  end

  @doc """
  Returns a theme for `Choreo.Workflow` Mermaid diagrams.
  """
  @spec theme(atom(), keyword()) :: Theme.t()
  def theme(name \\ :default, overrides \\ []) do
    resolve_theme(name) |> Choreo.Theme.override(overrides)
  end

  # ============================================================================
  # Theme helpers
  # ============================================================================

  defp resolve_theme(%Theme{} = theme), do: theme
  defp resolve_theme(:default), do: default_workflow_theme()
  defp resolve_theme(:dark), do: dark_workflow_theme()
  defp resolve_theme(:minimal), do: minimal_workflow_theme()
  defp resolve_theme(:warm), do: warm_workflow_theme()
  defp resolve_theme(:forest), do: forest_workflow_theme()
  defp resolve_theme(:ocean), do: ocean_workflow_theme()
  defp resolve_theme(_), do: default_workflow_theme()

  defp warm_workflow_theme do
    %Theme{
      name: :workflow_warm,
      colors: %{
        start: "#10b981",
        end: "#ef4444",
        task: "#f97316",
        decision: "#fbbf24",
        fork: "#ea580c",
        join: "#ea580c",
        compensation: "#f43f5e",
        event: "#db2777"
      },
      node_fontname: "Helvetica",
      node_fontsize: 12,
      node_fontcolor: "white",
      edge_color: "#78716c",
      edge_fontname: "Helvetica",
      edge_fontsize: 10,
      edge_penwidth: 1.0,
      graph_bgcolor: "#fef2f2",
      cluster_fillcolor: "#fee2e2",
      cluster_style: :rounded,
      cluster_color: "#fca5a5"
    }
  end

  defp forest_workflow_theme do
    %Theme{
      name: :workflow_forest,
      colors: %{
        start: "#84cc16",
        end: "#ef4444",
        task: "#15803d",
        decision: "#65a30d",
        fork: "#166534",
        join: "#166534",
        compensation: "#047857",
        event: "#14b8a6"
      },
      node_fontname: "Helvetica",
      node_fontsize: 12,
      node_fontcolor: "white",
      edge_color: "#4b5563",
      edge_fontname: "Helvetica",
      edge_fontsize: 10,
      edge_penwidth: 1.0,
      graph_bgcolor: "#f0fdf4",
      cluster_fillcolor: "#dcfce7",
      cluster_style: :rounded,
      cluster_color: "#86efac"
    }
  end

  defp ocean_workflow_theme do
    %Theme{
      name: :workflow_ocean,
      colors: %{
        start: "#0ea5e9",
        end: "#ef4444",
        task: "#1d4ed8",
        decision: "#0891b2",
        fork: "#0369a1",
        join: "#0369a1",
        compensation: "#0e7490",
        event: "#2563eb"
      },
      node_fontname: "Helvetica",
      node_fontsize: 12,
      node_fontcolor: "white",
      edge_color: "#64748b",
      edge_fontname: "Helvetica",
      edge_fontsize: 10,
      edge_penwidth: 1.0,
      graph_bgcolor: "#f0f9ff",
      cluster_fillcolor: "#e0f2fe",
      cluster_style: :rounded,
      cluster_color: "#7dd3fc"
    }
  end

  defp minimal_workflow_theme do
    %Theme{default_workflow_theme() | name: :workflow_minimal}
  end

  defp default_workflow_theme do
    %Theme{
      name: :workflow_default,
      colors: %{
        start: "#10b981",
        end: "#ef4444",
        task: "#3b82f6",
        decision: "#8b5cf6",
        fork: "#f59e0b",
        join: "#f59e0b",
        compensation: "#f87171",
        event: "#64748b"
      },
      node_fontname: "Helvetica",
      node_fontsize: 12,
      node_fontcolor: "white",
      edge_color: "#64748b",
      edge_fontname: "Helvetica",
      edge_fontsize: 10,
      edge_penwidth: 1.0,
      graph_bgcolor: nil,
      cluster_fillcolor: "#f8fafc",
      cluster_style: :rounded,
      cluster_color: "#cbd5e1"
    }
  end

  defp dark_workflow_theme do
    %Theme{
      name: :workflow_dark,
      colors: %{
        start: "#059669",
        end: "#dc2626",
        task: "#2563eb",
        decision: "#7c3aed",
        fork: "#d97706",
        join: "#d97706",
        compensation: "#ef4444",
        event: "#475569"
      },
      node_fontname: "Helvetica",
      node_fontsize: 12,
      node_fontcolor: "#e2e8f0",
      edge_color: "#94a3b8",
      edge_fontname: "Helvetica",
      edge_fontsize: 10,
      edge_penwidth: 1.0,
      graph_bgcolor: "#0f172a",
      cluster_fillcolor: "#1e293b",
      cluster_style: :rounded,
      cluster_color: "#475569"
    }
  end

  defp wf_color(%Theme{colors: colors}, key) do
    Map.get(colors, key, "#64748b")
  end

  # ============================================================================
  # Node styling
  # ============================================================================

  defp node_shape_fn(_id, data) do
    type = Map.get(data, :node_type, :task)

    case type do
      :start -> :circle
      :end -> :circle
      :task -> :subroutine
      :decision -> :rhombus
      :fork -> :trapezoid
      :join -> :trapezoid_alt
      :compensation -> :rounded_rect
      :event -> :rounded_rect
      _ -> :rounded_rect
    end
  end

  defp node_attributes_fn(theme, hl_nodes) do
    fn id, data ->
      base =
        case Map.get(data, :node_type, :task) do
          :start ->
            [
              {:fill, wf_color(theme, :start)},
              {:stroke, Choreo.Internal.darken(wf_color(theme, :start))},
              {:stroke_width, "2px"}
            ]

          :end ->
            [
              {:fill, wf_color(theme, :end)},
              {:stroke, Choreo.Internal.darken(wf_color(theme, :end))},
              {:stroke_width, "3px"}
            ]

          :task ->
            [
              {:fill, wf_color(theme, :task)},
              {:stroke, Choreo.Internal.darken(wf_color(theme, :task))}
            ]

          :decision ->
            [
              {:fill, wf_color(theme, :decision)},
              {:stroke, Choreo.Internal.darken(wf_color(theme, :decision))}
            ]

          :fork ->
            [
              {:fill, wf_color(theme, :fork)},
              {:stroke, Choreo.Internal.darken(wf_color(theme, :fork))}
            ]

          :join ->
            [
              {:fill, wf_color(theme, :join)},
              {:stroke, Choreo.Internal.darken(wf_color(theme, :join))}
            ]

          :compensation ->
            [
              {:fill, wf_color(theme, :compensation)},
              {:stroke, "#ef4444"},
              {:stroke_width, "2px"},
              {:stroke_dasharray, "3 3"}
            ]

          :event ->
            [
              {:fill, wf_color(theme, :event)},
              {:stroke, Choreo.Internal.darken(wf_color(theme, :event))}
            ]

          _ ->
            [
              {:fill, wf_color(theme, :task)},
              {:stroke, Choreo.Internal.darken(wf_color(theme, :task))}
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

    label =
      if timeout = data[:timeout_ms] do
        "#{label} (#{timeout}ms)"
      else
        label
      end

    if retry = data[:retry] do
      "#{label} retry: #{retry}"
    else
      label
    end
  end

  # ============================================================================
  # Edge styling
  # ============================================================================

  defp edge_attributes_fn(workflow, hl_edges) do
    fn from, to, edge_id, _weight ->
      meta = Map.get(workflow.edge_meta, edge_id, %{})

      base =
        if meta[:edge_type] == :virtual do
          [{:stroke, "#cbd5e1"}, {:stroke_width, "1px"}]
        else
          edge_type_attrs(meta[:edge_type] || :sequence)
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

  defp edge_type_attrs(:compensation) do
    [
      {:stroke, "#ef4444"},
      {:stroke_width, "2px"},
      {:stroke_dasharray, "5 5"}
    ]
  end

  defp edge_type_attrs(:retry) do
    [
      {:stroke, "#f97316"},
      {:stroke_width, "2px"},
      {:stroke_dasharray, "5 5"}
    ]
  end

  defp edge_type_attrs(:failure) do
    [
      {:stroke, "#9ca3af"},
      {:stroke_width, "2px"},
      {:stroke_dasharray, "5 5"}
    ]
  end

  defp edge_type_attrs(:timeout) do
    [
      {:stroke, "#eab308"},
      {:stroke_width, "2px"},
      {:stroke_dasharray, "5 5"}
    ]
  end

  defp edge_type_attrs(_) do
    [{:stroke, "#64748b"}, {:stroke_width, "2px"}]
  end

  defp edge_label(workflow, edge_id) do
    meta = Map.get(workflow.edge_meta, edge_id, %{})

    if label = meta[:label], do: to_string(label), else: ""
  end

  # ============================================================================
  # Swimlane (swimlane-beta) rendering
  # ============================================================================

  defp to_swimlane(%Choreo.Workflow{} = workflow, opts) do
    theme = resolve_theme(Keyword.get(opts, :theme, :default))
    direction = Keyword.get(opts, :direction, :lr)

    hl_nodes = MapSet.new(Keyword.get(opts, :highlighted_nodes, []) || [])
    hl_edges = MapSet.new(Keyword.get(opts, :highlighted_edges, []) || [])

    id_map = build_id_map(workflow)
    lanes = build_lanes(workflow, id_map)
    node_attr_fn = node_attributes_fn(theme, hl_nodes)
    edge_attr_fn = edge_attributes_fn(workflow, hl_edges)

    lane_lines = Enum.flat_map(lanes, &render_lane(&1, workflow, id_map, node_attr_fn))
    {edge_lines, link_styles} = render_edges(workflow, id_map, edge_attr_fn)

    (["swimlane-beta #{direction_to_string(direction)}"] ++
       lane_lines ++ edge_lines ++ link_styles)
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  defp direction_to_string(:td), do: "TD"
  defp direction_to_string(:tb), do: "TB"
  defp direction_to_string(:lr), do: "LR"
  defp direction_to_string(:rl), do: "RL"
  defp direction_to_string(:bt), do: "BT"
  defp direction_to_string(_), do: "LR"

  defp build_id_map(workflow) do
    workflow.graph.nodes
    |> Map.keys()
    |> Map.new(fn id -> {id, sanitize_mermaid_id(id)} end)
  end

  defp sanitize_mermaid_id(id) do
    id
    |> to_string()
    |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
    |> then(fn s ->
      if s =~ ~r/^[0-9]/, do: "_" <> s, else: s
    end)
  end

  defp build_lanes(workflow, id_map) do
    subgraphs = Choreo.Internal.build_mermaid_subgraphs(workflow)
    clustered_ids = Enum.flat_map(subgraphs, & &1.node_ids) |> MapSet.new()

    all_node_ids = Map.keys(workflow.graph.nodes)
    unclustered = Enum.reject(all_node_ids, &MapSet.member?(clustered_ids, &1))

    subgraphs =
      Enum.map(subgraphs, fn lane ->
        %{
          id: sanitize_mermaid_id(lane.name),
          label: lane.label,
          node_ids: Enum.map(lane.node_ids, &Map.fetch!(id_map, &1))
        }
      end)

    if unclustered == [] do
      subgraphs
    else
      unassigned_lane = %{
        id: "unassigned",
        label: "Unassigned",
        node_ids: Enum.map(unclustered, &Map.fetch!(id_map, &1))
      }

      List.insert_at(subgraphs, -1, unassigned_lane)
    end
  end

  defp render_lane(lane, workflow, id_map, node_attr_fn) do
    nodes_rendered =
      Enum.flat_map(lane.node_ids, fn safe_id ->
        original_id =
          Enum.find_value(id_map, fn {orig, safe} ->
            if safe == safe_id, do: orig
          end)

        render_node(safe_id, original_id, workflow, node_attr_fn)
      end)

    [
      "subgraph #{lane.id}[\"#{escape_swimlane_label(lane.label)}\"]"
      | List.insert_at(nodes_rendered, -1, "end")
    ]
  end

  defp render_node(safe_id, original_id, workflow, node_attr_fn) do
    data = Map.fetch!(workflow.graph.nodes, original_id)
    shape = node_shape_fn(original_id, data)
    label = node_label(original_id, data)
    brackets = Yog.Render.Mermaid.node_shape_brackets(shape, label)

    attrs = node_attr_fn.(original_id, data)
    style = style_from_attrs(attrs)

    node_line = "  #{safe_id}#{brackets}"

    if style == "" do
      [node_line]
    else
      [node_line, "  style #{safe_id} #{style}"]
    end
  end

  defp style_from_attrs(attrs) do
    attrs
    |> Enum.map(fn
      {:fill, color} -> "fill:#{color}"
      {:stroke, color} -> "stroke:#{color}"
      {:stroke_width, width} -> "stroke-width:#{width}"
      {:stroke_dasharray, dash} -> "stroke-dasharray:#{dash}"
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.join(",")
  end

  defp escape_swimlane_label(label) do
    label
    |> to_string()
    |> String.replace("\"", "\\\"")
  end

  defp render_edges(workflow, id_map, edge_attr_fn) do
    edges =
      workflow.graph.edges
      |> Enum.sort_by(fn {edge_id, _} -> edge_id end)

    edge_lines =
      Enum.map(edges, fn {edge_id, {from, to, _weight}} ->
        from_safe = Map.fetch!(id_map, from)
        to_safe = Map.fetch!(id_map, to)
        meta = Map.get(workflow.edge_meta, edge_id, %{})
        arrow = arrow_for(meta[:edge_type])
        label = edge_label(workflow, edge_id)

        if label == "" do
          "  #{from_safe} #{arrow} #{to_safe}"
        else
          "  #{from_safe} #{arrow}|\"#{escape_swimlane_label(label)}\"| #{to_safe}"
        end
      end)

    link_styles =
      edges
      |> Enum.with_index()
      |> Enum.map(fn {{edge_id, {from, to, weight}}, index} ->
        attrs = edge_attr_fn.(from, to, edge_id, weight)
        css = css_from_attrs(attrs)
        if css == "", do: nil, else: "  linkStyle #{index} #{css}"
      end)
      |> Enum.reject(&is_nil/1)

    {edge_lines, link_styles}
  end

  defp arrow_for(:sequence), do: "-->"
  defp arrow_for(:retry), do: "-.->"
  defp arrow_for(:compensation), do: "-.->"
  defp arrow_for(:failure), do: "-.->"
  defp arrow_for(:timeout), do: "-.->"
  defp arrow_for(_), do: "-->"

  defp css_from_attrs(attrs) do
    attrs
    |> Enum.map(fn
      {:stroke, color} -> "stroke:#{color}"
      {:stroke_width, width} -> "stroke-width:#{width}"
      {:stroke_dasharray, dash} -> "stroke-dasharray:#{dash}"
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.join(",")
  end
end
