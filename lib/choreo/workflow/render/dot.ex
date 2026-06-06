defmodule Choreo.Workflow.Render.DOT do
  @moduledoc """
  DOT (Graphviz) rendering for `Choreo.Workflow` orchestration diagrams.

  Produces workflow-oriented visualisation:

    * **Start** — green circle (entry point)
    * **End** — red double-circle (terminal)
    * **Task** — 3D boxes (automated steps)
    * **Decision** — diamond (conditional branch)
    * **Fork** — inverted house (parallel split)
    * **Join** — house (parallel merge)
    * **Compensation** — note shape with red dashed border (rollback)
    * **Event** — cloud (trigger / signal)

  Edge styles:
    * **Sequence** — solid grey
    * **Compensation** — dashed red
    * **Retry** — dotted orange
    * **Failure** — dashed grey
    * **Timeout** — dashdot

  Swimlanes are rendered as subgraph clusters with optional fill colours.

  ## Further reading

    * [BPMN 2.0 Specification](https://www.omg.org/spec/BPMN/2.0/)
    * [Workflow Patterns Initiative](http://www.workflowpatterns.com/)
  """

  alias Choreo.Theme

  @doc """
  Renders a workflow to a DOT string.

  ## Options

    * `:theme` — `:default`, `:dark`, or a `Choreo.Theme` struct

  ## Examples

      iex> workflow = Choreo.Workflow.new()
      iex> workflow = workflow
      ...>   |> Choreo.Workflow.add_start(:start)
      ...>   |> Choreo.Workflow.add_task(:process)
      ...>   |> Choreo.Workflow.add_end(:end)
      ...>   |> Choreo.Workflow.connect(:start, :process)
      ...>   |> Choreo.Workflow.connect(:process, :end)
      iex> dot = Choreo.Workflow.Render.DOT.to_dot(workflow)
      iex> String.contains?(dot, "digraph")
      true
      iex> String.contains?(dot, "process")
      true
  """
  @spec to_dot(Choreo.Workflow.t(), keyword()) :: String.t()
  def to_dot(%Choreo.Workflow{} = workflow, opts \\ []) do
    theme = resolve_theme(Keyword.get(opts, :theme, :default))

    states_list = Choreo.Workflow.nodes(workflow)
    id_map = Enum.into(states_list, %{}, fn id -> {id, dot_id(id)} end)
    safe_graph = Choreo.Internal.make_multi_graph_safe(workflow.graph, id_map)
    safe_workflow = %{workflow | graph: safe_graph}

    subgraphs = Choreo.Internal.build_cluster_subgraphs(safe_workflow, theme)

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
      |> Map.put(:edge_label, fn _edge_id, weight -> edge_label(weight) end)
      |> Map.put(:node_attributes, node_attributes_fn(theme, hl_nodes))
      |> Map.put(:edge_attributes, edge_attributes_fn(safe_workflow, hl_edges))
      |> Map.merge(theme_graph_overrides(theme))
      |> Map.merge(Map.new(opts))

    base_opts = if subgraphs != [], do: Map.put(base_opts, :subgraphs, subgraphs), else: base_opts

    Yog.Multi.DOT.to_dot(safe_graph, base_opts)
  end

  # ============================================================================
  # Theme helpers
  # ============================================================================

  @doc false
  def theme(name \\ :default, overrides \\ []) do
    resolve_theme(name) |> Choreo.Theme.override(overrides)
  end

  defp resolve_theme(%Theme{} = theme), do: theme
  defp resolve_theme(:default), do: default_workflow_theme()
  defp resolve_theme(:dark), do: dark_workflow_theme()
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

  defp theme_graph_overrides(%Theme{} = theme) do
    base = if theme.graph_rankdir != nil, do: %{rankdir: theme.graph_rankdir}, else: %{}
    if theme.graph_bgcolor != nil, do: Map.put(base, :bgcolor, theme.graph_bgcolor), else: base
  end

  # ============================================================================
  # Node styling
  # ============================================================================

  defp node_attributes_fn(theme, hl_nodes) do
    fn id, data ->
      base =
        case Map.get(data, :node_type, :task) do
          :start ->
            [
              {:shape, :circle},
              {:fillcolor, wf_color(theme, :start)},
              {:fontcolor, theme.node_fontcolor},
              {:style, "filled"},
              {:penwidth, 2.0}
            ]

          :end ->
            [
              {:shape, :doublecircle},
              {:fillcolor, wf_color(theme, :end)},
              {:fontcolor, theme.node_fontcolor},
              {:style, "filled"},
              {:penwidth, 2.0}
            ]

          :task ->
            [
              {:shape, :box3d},
              {:fillcolor, wf_color(theme, :task)},
              {:fontcolor, theme.node_fontcolor},
              {:style, "filled"}
            ]

          :decision ->
            [
              {:shape, :diamond},
              {:fillcolor, wf_color(theme, :decision)},
              {:fontcolor, theme.node_fontcolor},
              {:style, "filled"}
            ]

          :fork ->
            [
              {:shape, :invhouse},
              {:fillcolor, wf_color(theme, :fork)},
              {:fontcolor, theme.node_fontcolor},
              {:style, "filled"}
            ]

          :join ->
            [
              {:shape, :house},
              {:fillcolor, wf_color(theme, :join)},
              {:fontcolor, theme.node_fontcolor},
              {:style, "filled"}
            ]

          :compensation ->
            [
              {:shape, :note},
              {:fillcolor, wf_color(theme, :compensation)},
              {:fontcolor, theme.node_fontcolor},
              {:style, "filled,dashed"},
              {:color, "#ef4444"}
            ]

          :event ->
            [
              {:shape, :cloud},
              {:fillcolor, wf_color(theme, :event)},
              {:fontcolor, theme.node_fontcolor},
              {:style, "filled"}
            ]

          _ ->
            [
              {:shape, :box},
              {:fillcolor, wf_color(theme, :task)},
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

    label =
      if timeout = data[:timeout_ms] do
        "#{label}\n(#{timeout}ms)"
      else
        label
      end

    if retry = data[:retry] do
      "#{label}\nretry: #{retry}"
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
          [{:color, "#cbd5e1"}, {:style, "dashed"}, {:penwidth, 0.8}]
        else
          base = edge_type_attrs(meta[:edge_type] || :sequence)
          if label = meta[:label], do: [{:label, label} | base], else: base
        end

      # Handle highlighting: Omit color/penwidth if edge is highlighted
      if MapSet.member?(hl_edges, edge_id) or MapSet.member?(hl_edges, {from, to}) do
        Keyword.drop(base, [:color, :penwidth])
      else
        base
      end
    end
  end

  defp edge_type_attrs(:compensation) do
    [{:color, "#ef4444"}, {:fontcolor, "#ef4444"}, {:penwidth, 1.5}, {:style, "dashed"}]
  end

  defp edge_type_attrs(:retry) do
    [{:color, "#f97316"}, {:fontcolor, "#f97316"}, {:penwidth, 1.5}, {:style, "dotted"}]
  end

  defp edge_type_attrs(:failure) do
    [{:color, "#9ca3af"}, {:fontcolor, "#9ca3af"}, {:penwidth, 1.2}, {:style, "dashed"}]
  end

  defp edge_type_attrs(:timeout) do
    [{:color, "#eab308"}, {:fontcolor, "#eab308"}, {:penwidth, 1.2}, {:style, "dashed"}]
  end

  defp edge_type_attrs(_) do
    [{:color, "#64748b"}, {:fontcolor, "#64748b"}, {:penwidth, 1.0}, {:style, "solid"}]
  end

  defp edge_label(_), do: ""

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
