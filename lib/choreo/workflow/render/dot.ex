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
  """
  @spec to_dot(Choreo.Workflow.t(), keyword()) :: String.t()
  def to_dot(%Choreo.Workflow{} = workflow, opts \\ []) do
    theme = resolve_theme(Keyword.get(opts, :theme, :default))
    subgraphs = Choreo.Internal.build_cluster_subgraphs(workflow, theme)

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
      |> Map.put(:edge_label, &edge_label/1)
      |> Map.put(:node_attributes, node_attributes_fn(theme))
      |> Map.put(:edge_attributes, edge_attributes_fn(workflow))
      |> Map.merge(theme_graph_overrides(theme))
      |> Map.merge(Map.new(opts))

    base_opts = if subgraphs != [], do: Map.put(base_opts, :subgraphs, subgraphs), else: base_opts

    Yog.Render.DOT.to_dot(workflow.graph, base_opts)
  end

  # ============================================================================
  # Theme helpers
  # ============================================================================

  defp resolve_theme(%Theme{} = theme), do: theme
  defp resolve_theme(:default), do: default_workflow_theme()
  defp resolve_theme(:dark), do: dark_workflow_theme()
  defp resolve_theme(_), do: default_workflow_theme()

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

  defp theme_graph_overrides(%Theme{graph_bgcolor: nil}), do: %{}
  defp theme_graph_overrides(%Theme{graph_bgcolor: bg}), do: %{bgcolor: bg}

  # ============================================================================
  # Node styling
  # ============================================================================

  defp node_attributes_fn(theme) do
    fn _id, data ->
      base =
        case Map.get(data, :node_type, :task) do
          :start ->
            [
              {:shape, :circle},
              {:fillcolor, wf_color(theme, :start)},
              {:penwidth, 2.0}
            ]

          :end ->
            [
              {:shape, :doublecircle},
              {:fillcolor, wf_color(theme, :end)},
              {:penwidth, 2.0}
            ]

          :task ->
            [
              {:shape, :box3d},
              {:fillcolor, wf_color(theme, :task)}
            ]

          :decision ->
            [
              {:shape, :diamond},
              {:fillcolor, wf_color(theme, :decision)}
            ]

          :fork ->
            [
              {:shape, :invhouse},
              {:fillcolor, wf_color(theme, :fork)}
            ]

          :join ->
            [
              {:shape, :house},
              {:fillcolor, wf_color(theme, :join)}
            ]

          :compensation ->
            [
              {:shape, :note},
              {:fillcolor, wf_color(theme, :compensation)},
              {:style, "filled,dashed"},
              {:color, "#ef4444"}
            ]

          :event ->
            [
              {:shape, :cloud},
              {:fillcolor, wf_color(theme, :event)}
            ]

          _ ->
            [
              {:shape, :box},
              {:fillcolor, wf_color(theme, :task)}
            ]
        end

      if desc = data[:description] do
        [{:tooltip, desc} | base]
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

  defp edge_attributes_fn(workflow) do
    fn from, to, _weight ->
      meta = Map.get(workflow.edge_meta, {from, to}, %{})

      base = edge_type_attrs(meta[:edge_type] || :sequence)

      base = if label = meta[:label], do: [{:label, label} | base], else: base

      base
    end
  end

  defp edge_type_attrs(:compensation) do
    [{:color, "#ef4444"}, {:penwidth, 1.5}, {:style, "dashed"}]
  end

  defp edge_type_attrs(:retry) do
    [{:color, "#f97316"}, {:penwidth, 1.5}, {:style, "dotted"}]
  end

  defp edge_type_attrs(:failure) do
    [{:color, "#9ca3af"}, {:penwidth, 1.2}, {:style, "dashed"}]
  end

  defp edge_type_attrs(:timeout) do
    [{:color, "#eab308"}, {:penwidth, 1.2}, {:style, "dashed"}]
  end

  defp edge_type_attrs(_) do
    [{:color, "#64748b"}, {:penwidth, 1.0}, {:style, "solid"}]
  end

  defp edge_label(_), do: ""
end
