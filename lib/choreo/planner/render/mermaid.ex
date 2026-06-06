defmodule Choreo.Planner.Render.Mermaid do
  @moduledoc """
  Mermaid.js rendering for `Choreo.Planner` project diagrams.

  Supports four Mermaid syntaxes:

    * `:kanban` — Native Mermaid Kanban board with status columns (requires Mermaid ≥11.4)
    * `:kanban_compat` — Flowchart-based Kanban board compatible with all Mermaid versions
    * `:gantt` — Mermaid Gantt chart with dependency scheduling
    * `:flowchart` — Standard Mermaid flowchart via `Yog.Multi.Mermaid`

  ## Examples

      iex> project = Choreo.Planner.new()
      ...> |> Choreo.Planner.add_task(:a, title: "Task A", status: :done)
      ...> |> Choreo.Planner.add_task(:b, title: "Task B", status: :backlog)
      iex> Choreo.Planner.Render.Mermaid.to_mermaid(project, syntax: :kanban) =~ "kanban"
      true
  """

  alias Choreo.Planner
  alias Choreo.Theme

  @status_columns [
    backlog: "Backlog",
    todo: "Todo",
    in_progress: "In Progress",
    in_review: "In Review",
    done: "Done",
    cancelled: "Cancelled"
  ]

  @status_colors %{
    done: "#4ade80",
    in_progress: "#60a5fa",
    backlog: "#e5e7eb",
    todo: "#fcd34d",
    in_review: "#c084fc",
    cancelled: "#f87171"
  }

  @doc """
  Renders a planner project to a Mermaid diagram string.

  ## Options

    * `:syntax` — `:kanban` (default), `:kanban_compat`, `:gantt`, or `:flowchart`
    * `:theme` — `:default`, `:dark`, `:warm`, `:forest`, `:ocean` (flowchart only)
    * `:direction` — `:td` (default) or `:lr` (flowchart only)
    * `:milestone` — Only include tasks under this milestone
    * `:assignee` — Only include tasks assigned to this user (kanban only)
    * `:ticket_base_url` — Base URL for ticket links (kanban only)
    * `:title` — Chart title (gantt only, defaults to project name)
    * `:section_by` — `:milestone` or `:assignee` to group tasks (gantt only)
    * `:start_date` — Base date for synthetic scheduling (gantt only)
  """
  @spec to_mermaid(Planner.t(), keyword()) :: String.t()
  def to_mermaid(%Planner{} = planner, opts \\ []) do
    case Keyword.get(opts, :syntax, :kanban) do
      :kanban -> to_kanban(planner, opts)
      :kanban_compat -> to_kanban_compat(planner, opts)
      :gantt -> to_gantt(planner, opts)
      :flowchart -> to_flowchart(planner, opts)
    end
  end

  # ============================================================================
  # Kanban
  # ============================================================================

  defp to_kanban(planner, opts) do
    tasks = filter_tasks(planner, opts)
    ticket_base_url = Keyword.get(opts, :ticket_base_url)

    header =
      if ticket_base_url do
        [
          "---",
          "config:",
          "  kanban:",
          "    ticketBaseUrl: '#{ticket_base_url}'",
          "---",
          "kanban"
        ]
      else
        ["kanban"]
      end

    column_lines =
      Enum.flat_map(@status_columns, fn {status, col_name} ->
        col_tasks = Enum.filter(tasks, fn {_id, data} -> data[:status] == status end)

        if col_tasks == [] do
          []
        else
          col_id = sanitize_id("#{status}_col")

          cards =
            Enum.map(col_tasks, fn {id, data} ->
              render_kanban_card(planner, id, data)
            end)

          ["  #{col_id}[#{col_name}]" | cards]
        end
      end)

    (header ++ column_lines)
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  defp render_kanban_card(planner, id, data) do
    name = escape(data[:title] || inspect(id))
    task_id = sanitize_id(id)
    meta = kanban_meta(planner, id, data)

    if meta == %{} do
      "    #{task_id}[#{name}]"
    else
      meta_str = Enum.map_join(meta, ", ", fn {k, v} -> "#{k}: #{escape_meta(v)}" end)
      "    #{task_id}[#{name}]@{ #{meta_str} }"
    end
  end

  defp kanban_meta(planner, id, data) do
    %{}
    |> maybe_put(:assigned, assignee_name(planner, id))
    |> maybe_put(:priority, kanban_priority(data[:priority]))
    |> maybe_put(:ticket, data[:ticket])
  end

  defp assignee_name(planner, id) do
    case Planner.assignee(planner, id) do
      nil -> nil
      user_id -> planner.graph.nodes[user_id][:name] || inspect(user_id)
    end
  end

  defp kanban_priority(:critical), do: "Very High"
  defp kanban_priority(:high), do: "High"
  defp kanban_priority(:low), do: "Low"
  defp kanban_priority(_), do: nil

  # ============================================================================
  # Kanban Compatibility (flowchart-based)
  # ============================================================================

  @kanban_compat_column_bg %{
    backlog: "#f1f5f9",
    todo: "#fef3c7",
    in_progress: "#dbeafe",
    in_review: "#f3e8ff",
    done: "#dcfce7",
    cancelled: "#fee2e2"
  }

  @kanban_compat_column_stroke %{
    backlog: "#94a3b8",
    todo: "#f59e0b",
    in_progress: "#3b82f6",
    in_review: "#a855f7",
    done: "#22c55e",
    cancelled: "#ef4444"
  }

  defp to_kanban_compat(planner, opts) do
    tasks = filter_tasks(planner, opts)

    {subgraphs, _all_task_ids} =
      Enum.flat_map_reduce(@status_columns, [], fn {status, col_name}, acc_ids ->
        col_tasks = Enum.filter(tasks, fn {_id, data} -> data[:status] == status end)

        if col_tasks == [] do
          {[], acc_ids}
        else
          col_id = sanitize_id("col_#{status}")
          bg = Map.get(@kanban_compat_column_bg, status, "#f1f5f9")
          stroke = Map.get(@kanban_compat_column_stroke, status, "#94a3b8")

          task_results =
            Enum.map(col_tasks, fn {id, data} ->
              task_id = sanitize_id(id)
              name = escape(data[:title] || inspect(id))
              fill = Map.get(@status_colors, status, "#e5e7eb")
              stroke_color = Choreo.Internal.darken(fill)

              decl = "    #{task_id}[\"#{name}\"]"
              style = "style #{task_id} fill:#{fill},stroke:#{stroke_color},stroke-width:2px"
              {id, decl, style}
            end)

          task_ids = Enum.map(task_results, fn {id, _, _} -> id end)
          task_decl_lines = Enum.map(task_results, fn {_, decl, _} -> decl end)
          task_style_lines = Enum.map(task_results, fn {_, _, style} -> style end)

          subgraph_lines =
            [
              "  subgraph #{col_id}[\"#{col_name}\"]",
              "    direction TB" | task_decl_lines
            ] ++ ["  end", ""]

          style_line = "style #{col_id} fill:#{bg},stroke:#{stroke},stroke-width:2px"

          {subgraph_lines ++ [style_line] ++ task_style_lines, acc_ids ++ task_ids}
        end
      end)

    header = [
      "flowchart LR",
      "  classDef default color:#333"
    ]

    (header ++ [""] ++ subgraphs)
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  # ============================================================================
  # Gantt
  # ============================================================================

  defp to_gantt(planner, opts) do
    title = Keyword.get(opts, :title, planner.name || "Project Timeline")
    section_by = Keyword.get(opts, :section_by, :milestone)
    base_date = Keyword.get(opts, :start_date, Date.utc_today())

    tasks =
      case Keyword.get(opts, :milestone) do
        nil -> Planner.tasks(planner)
        m_id -> Planner.tasks(planner) |> filter_by_milestone(planner, m_id)
      end

    if tasks == [] do
      "gantt\n    title #{escape(title)}\n"
    else
      schedule = compute_schedule(planner, tasks, base_date)

      header = [
        "gantt",
        "    title #{escape(title)}",
        "    dateFormat YYYY-MM-DD"
      ]

      sections = group_into_sections(tasks, planner, section_by)

      section_lines =
        Enum.flat_map(sections, fn {section_name, section_tasks} ->
          task_lines =
            Enum.map(section_tasks, fn {id, data} -> render_gantt_task(id, data, schedule) end)

          ["    section #{escape(section_name)}" | task_lines]
        end)

      (header ++ section_lines)
      |> Enum.join("\n")
      |> Kernel.<>("\n")
    end
  end

  defp render_gantt_task(id, data, schedule) do
    name = escape(data[:title] || inspect(id))
    {start_date, duration_days} = Map.fetch!(schedule, id)
    tags = gantt_tags(data)
    task_id = sanitize_id(id)

    start_str = Date.to_iso8601(start_date)
    duration_str = if duration_days == 1, do: "1d", else: "#{duration_days}d"

    meta =
      if tags == [] do
        "#{task_id}, #{start_str}, #{duration_str}"
      else
        "#{Enum.join(tags, ", ")}, #{task_id}, #{start_str}, #{duration_str}"
      end

    "        #{name} : #{meta}"
  end

  defp gantt_tags(data) do
    []
    |> then(fn acc -> if data[:status] == :done, do: ["done" | acc], else: acc end)
    |> then(fn acc -> if data[:status] == :in_progress, do: ["active" | acc], else: acc end)
    |> then(fn acc -> if data[:priority] == :critical, do: ["crit" | acc], else: acc end)
    |> Enum.reverse()
  end

  defp compute_schedule(planner, tasks, base_date) do
    task_ids = Enum.map(tasks, fn {id, _} -> id end) |> MapSet.new()
    dag = build_restricted_dag(planner, task_ids)

    {:ok, sorted} =
      case Yog.Traversal.Sort.topological_sort(dag) do
        {:ok, s} -> {:ok, s}
        _ -> {:ok, Enum.map(tasks, fn {id, _} -> id end)}
      end

    Enum.reduce(sorted, %{}, fn id, acc ->
      data = planner.graph.nodes[id]

      {start, duration} =
        case {data[:start_date], data[:due_date], data[:estimate_hours]} do
          {start_date, due_date, _} when not is_nil(start_date) and not is_nil(due_date) ->
            duration = max(Date.diff(due_date, start_date) + 1, 1)
            {start_date, duration}

          {start_date, nil, hrs} when not is_nil(start_date) ->
            {start_date, estimate_to_days(hrs)}

          {nil, due_date, hrs} when not is_nil(due_date) ->
            duration = estimate_to_days(hrs)
            {Date.add(due_date, -duration), duration}

          {nil, nil, hrs} ->
            duration = estimate_to_days(hrs)
            start = synthetic_start(dag, id, acc, base_date)
            {start, duration}
        end

      Map.put(acc, id, {start, duration})
    end)
  end

  defp synthetic_start(dag, id, schedule, base_date) do
    preds = predecessors(dag, id)

    if preds == [] do
      base_date
    else
      preds
      |> Enum.map(fn p ->
        case Map.fetch(schedule, p) do
          {:ok, {p_start, p_dur}} -> Date.add(p_start, p_dur)
          :error -> base_date
        end
      end)
      |> Enum.max_by(&Date.to_gregorian_days/1)
    end
  end

  defp estimate_to_days(nil), do: 1
  defp estimate_to_days(hrs) when hrs <= 0, do: 1
  defp estimate_to_days(hrs), do: max(trunc(Float.ceil(hrs / 8)), 1)

  defp group_into_sections(tasks, planner, :milestone) do
    tasks
    |> Enum.group_by(fn {id, _} ->
      case Planner.parent(planner, id) do
        nil -> "Backlog"
        m_id -> planner.graph.nodes[m_id][:title] || inspect(m_id)
      end
    end)
    |> Enum.to_list()
  end

  defp group_into_sections(tasks, planner, :assignee) do
    tasks
    |> Enum.group_by(fn {id, _} ->
      case Planner.assignee(planner, id) do
        nil -> "Unassigned"
        u_id -> planner.graph.nodes[u_id][:name] || inspect(u_id)
      end
    end)
    |> Enum.to_list()
  end

  defp group_into_sections(tasks, _, _) do
    [{"Tasks", tasks}]
  end

  # ============================================================================
  # Flowchart
  # ============================================================================

  defp to_flowchart(planner, opts) do
    theme = resolve_theme(Keyword.get(opts, :theme, :default))
    direction = Keyword.get(opts, :direction, :td)

    hl_nodes = MapSet.new(Keyword.get(opts, :highlighted_nodes, []) || [])
    hl_edges = MapSet.new(Keyword.get(opts, :highlighted_edges, []) || [])

    base =
      Yog.Multi.Mermaid.default_options()
      |> Map.put(:direction, direction)
      |> Map.put(:node_shape, &node_shape_fn/2)
      |> Map.put(:node_label, &node_label/2)
      |> Map.put(:edge_label, fn _eid, _w -> "" end)
      |> Map.put(:node_attributes, node_attributes_fn(theme, hl_nodes))
      |> Map.put(:edge_attributes, edge_attributes_fn(planner, theme, hl_edges))
      |> Map.put(:default_font_color, theme.node_fontcolor)
      |> Map.put(:default_link_stroke, theme.edge_color)
      |> Map.merge(Map.new(opts))

    Yog.Multi.Mermaid.to_mermaid(planner.graph, base)
    |> String.replace("stroke_dasharray", "stroke-dasharray")
  end

  # ============================================================================
  # Theme helpers
  # ============================================================================

  @doc false
  def theme(name \\ :default, overrides \\ []) do
    resolve_theme(name) |> Choreo.Theme.override(overrides)
  end

  defp resolve_theme(%Theme{} = theme), do: theme
  defp resolve_theme(:default), do: default_planner_theme()
  defp resolve_theme(:dark), do: dark_planner_theme()
  defp resolve_theme(:warm), do: warm_planner_theme()
  defp resolve_theme(:forest), do: forest_planner_theme()
  defp resolve_theme(:ocean), do: ocean_planner_theme()
  defp resolve_theme(_), do: default_planner_theme()

  defp warm_planner_theme do
    %Theme{
      name: :planner_warm,
      colors: %{
        task: "#f97316",
        milestone: "#f43f5e",
        user: "#db2777",
        label: "#ea580c"
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

  defp forest_planner_theme do
    %Theme{
      name: :planner_forest,
      colors: %{
        task: "#15803d",
        milestone: "#047857",
        user: "#166534",
        label: "#65a30d"
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

  defp ocean_planner_theme do
    %Theme{
      name: :planner_ocean,
      colors: %{
        task: "#0ea5e9",
        milestone: "#0369a1",
        user: "#1d4ed8",
        label: "#0891b2"
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

  defp default_planner_theme do
    %Theme{
      name: :planner_default,
      colors: %{
        task: "#3b82f6",
        milestone: "#8b5cf6",
        user: "#10b981",
        label: "#f59e0b"
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

  defp dark_planner_theme do
    %Theme{
      name: :planner_dark,
      colors: %{
        task: "#2563eb",
        milestone: "#7c3aed",
        user: "#059669",
        label: "#d97706"
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

  defp planner_color(%Theme{colors: colors}, key) do
    Map.get(colors, key, "#64748b")
  end

  # ============================================================================
  # Flowchart node / edge styling
  # ============================================================================

  defp node_shape_fn(_id, data) do
    case Map.get(data, :node_type, :task) do
      :task -> :rounded_rect
      :milestone -> :rhombus
      :user -> :circle
      :label -> :stadium
      _ -> :rounded_rect
    end
  end

  defp node_attributes_fn(theme, hl_nodes) do
    fn id, data ->
      base =
        case Map.get(data, :node_type, :task) do
          :task ->
            status = data[:status] || :backlog
            fill = Map.get(@status_colors, status, "#e5e7eb")
            [{:fill, fill}, {:stroke, Choreo.Internal.darken(fill)}]

          :milestone ->
            [
              {:fill, planner_color(theme, :milestone)},
              {:stroke, Choreo.Internal.darken(planner_color(theme, :milestone))},
              {:stroke_width, "2px"}
            ]

          :user ->
            [
              {:fill, planner_color(theme, :user)},
              {:stroke, Choreo.Internal.darken(planner_color(theme, :user))}
            ]

          :label ->
            [
              {:fill, planner_color(theme, :label)},
              {:stroke, Choreo.Internal.darken(planner_color(theme, :label))}
            ]

          _ ->
            [
              {:fill, planner_color(theme, :task)},
              {:stroke, Choreo.Internal.darken(planner_color(theme, :task))}
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

  defp edge_attributes_fn(planner, theme, hl_edges) do
    fn from, to, edge_id, _weight ->
      meta = Map.get(planner.edge_meta, edge_id, %{})

      base =
        case meta[:type] do
          :depends_on ->
            [{:stroke, theme.edge_color}, {:stroke_width, "2px"}]

          :blocks ->
            [{:stroke, "#ef4444"}, {:stroke_width, "2px"}, {:stroke_dasharray, "5 5"}]

          :contains ->
            [{:stroke, "#94a3b8"}, {:stroke_width, "1px"}, {:stroke_dasharray, "3 3"}]

          :assigned_to ->
            [{:stroke, "#10b981"}, {:stroke_width, "1px"}, {:stroke_dasharray, "2 2"}]

          :tagged_with ->
            [{:stroke, "#f59e0b"}, {:stroke_width, "1px"}, {:stroke_dasharray, "2 2"}]

          :relates_to ->
            [{:stroke, "#cbd5e1"}, {:stroke_width, "1px"}, {:stroke_dasharray, "5 5"}]

          _ ->
            [{:stroke, theme.edge_color}, {:stroke_width, "1px"}]
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

  defp node_label(_id, data) do
    data[:title] || data[:label] || data[:name] || ""
  end

  # ============================================================================
  # Shared helpers
  # ============================================================================

  defp filter_tasks(planner, opts) do
    tasks = Planner.tasks(planner)

    Enum.reduce(opts, tasks, fn
      {:milestone, m_id}, acc ->
        ms_children = Planner.children(planner, m_id) |> MapSet.new()
        Enum.filter(acc, fn {id, _data} -> id in ms_children end)

      {:assignee, user_id}, acc ->
        Enum.filter(acc, fn {id, _data} -> Planner.assignee(planner, id) == user_id end)

      _, acc ->
        acc
    end)
  end

  defp filter_by_milestone(tasks, planner, m_id) do
    ms_children = Planner.children(planner, m_id) |> MapSet.new()
    Enum.filter(tasks, fn {id, _} -> id in ms_children end)
  end

  defp build_restricted_dag(planner, allowed_nodes) do
    g = planner.graph
    simple = Yog.directed()

    simple =
      Enum.reduce(g.nodes, simple, fn {id, _data}, acc ->
        if MapSet.member?(allowed_nodes, id) do
          Yog.Model.add_node(acc, id, nil)
        else
          acc
        end
      end)

    Enum.reduce(g.edges, simple, fn {eid, {from, to, _weight}}, acc ->
      meta = planner.edge_meta[eid] || %{}

      if meta[:type] in [:depends_on, :blocks] and
           MapSet.member?(allowed_nodes, from) and
           MapSet.member?(allowed_nodes, to) do
        case Yog.Model.add_edge(acc, from, to, nil) do
          {:ok, g} -> g
          {:error, _} -> acc
        end
      else
        acc
      end
    end)
  end

  defp predecessors(dag, node) do
    dag
    |> Yog.Model.predecessors(node)
    |> Enum.map(fn {from, _weight} -> from end)
  end

  defp sanitize_id(id) when is_atom(id), do: Atom.to_string(id)
  defp sanitize_id(id) when is_binary(id), do: String.replace(id, ~r/[^a-zA-Z0-9_]/, "_")
  defp sanitize_id(id), do: "node_#{inspect(id)}"

  defp escape(str) do
    str |> to_string() |> String.replace("\"", "\\\"")
  end

  defp escape_meta(str) do
    str = to_string(str)

    if String.contains?(str, ",") or String.contains?(str, ":") do
      "'#{String.replace(str, "'", "\\'")}'"
    else
      str
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
