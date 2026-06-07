defmodule Choreo.Render.DOT do
  @moduledoc """
  DOT (Graphviz) rendering for `Choreo` architecture diagrams.

  This module translates a `Choreo` struct into the DOT language with
  sensible defaults for infrastructure diagrams:

  * Databases are rendered as **cylinders**
  * Caches as **octagons**
  * Services as **3D boxes**
  * Networks as **clouds**
  * Users as **double circles**
  * Load balancers as **hexagons**
  * Queues as **components**
  * Storage as **tabs**

  Edges are styled according to their semantic type (`:connection` or
  `:dataflow`).

  Themes (built-in or custom) control colours, shapes, fonts, and layout.
  See `Choreo.Theme` for details.
  """

  alias Choreo.Theme

  @doc """
  Renders a `Choreo` to a DOT string.

  ## Options

    * `:theme` - `:default`, `:dark`, `:minimal`, or a `Choreo.Theme` struct
    * `:subgraphs` - list of subgraph / cluster definitions (manual override)
    * `:ranks` - rank constraints
    * Any other option accepted by `Yog.Render.DOT.to_dot/2`

  ## Examples

      dot = Choreo.Render.DOT.to_dot(system)
      dot = Choreo.Render.DOT.to_dot(system, theme: :dark)

      theme = Choreo.Theme.custom(colors: [database: "#ff0000"])
      dot = Choreo.Render.DOT.to_dot(system, theme: theme)
  """
  @spec to_dot(Choreo.t(), keyword()) :: String.t()
  def to_dot(system, opts \\ []) do
    theme = resolve_theme(Keyword.get(opts, :theme, :default))
    show_traces = Keyword.get(opts, :show_traces, false)

    system =
      if show_traces do
        system
      else
        remove_trace_edges(system)
      end

    states_list = Map.keys(system.graph.nodes)
    id_map = Enum.into(states_list, %{}, fn id -> {id, dot_id(id)} end)
    safe_graph = Choreo.Internal.make_multi_graph_safe(system.graph, id_map)
    safe_system = %{system | graph: safe_graph}

    subgraphs = Choreo.Internal.build_cluster_subgraphs(safe_system, theme)

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

    base =
      Yog.Multi.DOT.default_options()
      |> Map.put(:node_label, &node_label/2)
      |> Map.put(:edge_label, fn edge_id, weight ->
        meta = Map.get(system.edge_meta, edge_id, %{})

        if meta[:edge_type] == :trace do
          to_string(meta[:type] || "trace")
        else
          edge_label(weight)
        end
      end)
      |> Map.put(:node_attributes, node_attributes_fn(safe_system, theme, hl_nodes))
      |> Map.put(:edge_attributes, edge_attributes_fn(safe_system, hl_edges))
      |> Map.merge(theme_graph_attrs(theme))
      |> Map.merge(Map.new(opts))

    base = if subgraphs != [], do: Map.put(base, :subgraphs, subgraphs), else: base

    Yog.Multi.DOT.to_dot(safe_graph, base)
  end

  # ============================================================================
  # Theme resolution
  # ============================================================================

  @doc false
  def theme(name \\ :default, overrides \\ []) do
    resolve_theme(name) |> Choreo.Theme.override(overrides)
  end

  defp resolve_theme(%Theme{} = theme), do: theme
  defp resolve_theme(:default), do: Theme.default()
  defp resolve_theme(:dark), do: Theme.dark()
  defp resolve_theme(:minimal), do: Theme.minimal()
  defp resolve_theme(:warm), do: Theme.warm()
  defp resolve_theme(:forest), do: Theme.forest()
  defp resolve_theme(:ocean), do: Theme.ocean()
  defp resolve_theme(_), do: Theme.default()

  defp theme_graph_attrs(%Theme{} = theme) do
    %{
      rankdir: theme.graph_rankdir,
      splines: theme.graph_splines,
      nodesep: theme.graph_nodesep,
      ranksep: theme.graph_ranksep,
      bgcolor: theme.graph_bgcolor,
      edge_color: theme.edge_color,
      edge_fontcolor: theme.edge_color,
      edge_fontname: theme.edge_fontname,
      edge_fontsize: theme.edge_fontsize,
      edge_penwidth: theme.edge_penwidth,
      node_fontname: theme.node_fontname,
      node_fontsize: theme.node_fontsize,
      node_fontcolor: theme.node_fontcolor
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  # ============================================================================
  # Node styling
  # ============================================================================

  defp node_attributes_fn(_system, theme, hl_nodes) do
    fn id, data ->
      type = Map.get(data, :type, :generic)

      shape = Map.get(data, :shape) || Theme.shape(theme, type)
      color = Map.get(data, :fillcolor) || Theme.color(theme, type)
      fontcolor = Map.get(data, :fontcolor) || theme.node_fontcolor
      style = Map.get(data, :style, "filled")

      attrs = [
        {:shape, shape},
        {:fontcolor, fontcolor},
        {:style, style}
      ]

      # Only add fillcolor if node is NOT highlighted.
      # This allows Yog's highlight_color to take precedence.
      attrs =
        if MapSet.member?(hl_nodes, id) do
          attrs
        else
          [{:fillcolor, color} | attrs]
        end

      attrs =
        if penwidth = data[:penwidth] do
          [{:penwidth, penwidth} | attrs]
        else
          attrs
        end

      attrs =
        if image = data[:image] do
          [{:image, image} | attrs]
        else
          attrs
        end

      if desc = data[:description] do
        [{:tooltip, desc} | attrs]
      else
        attrs
      end
    end
  end

  defp node_label(_id, data) do
    Map.get(data, :name, "")
  end

  # ============================================================================
  # Edge styling
  # ============================================================================

  defp edge_attributes_fn(system, hl_edges) do
    fn from, to, edge_id, _weight ->
      meta = Map.get(system.edge_meta, edge_id, %{})

      cond do
        meta[:edge_type] == :virtual ->
          [{:color, "#cbd5e1"}, {:style, "dashed"}, {:penwidth, 0.8}]

        meta[:edge_type] == :trace ->
          [{:color, "#ef4444"}, {:style, "dashed"}, {:penwidth, 1.0}, {:constraint, "false"}]

        true ->
          base =
            case meta[:type] do
              :dataflow ->
                [{:color, "#6366f1"}, {:penwidth, 1.5}, {:style, "dashed"}]

              _ ->
                [{:color, "#64748b"}, {:penwidth, 1.0}]
            end

          base =
            cond do
              label = meta[:label] -> [{:label, to_string(label)} | base]
              protocol = meta[:protocol] -> [{:label, to_string(protocol)} | base]
              true -> base
            end

          # Smart headport: databases look best when entered from the top.
          target_data = Map.get(system.graph.nodes, to, %{})

          base =
            if target_data[:type] == :database and is_nil(meta[:headport]) do
              [{:headport, "n"} | base]
            else
              base
            end

          # Allow user overrides
          base = if port = meta[:headport], do: [{:headport, port} | base], else: base
          base = if port = meta[:tailport], do: [{:tailport, port} | base], else: base

          # Final highlighting override
          if MapSet.member?(hl_edges, edge_id) or MapSet.member?(hl_edges, {from, to}) do
            Keyword.drop(base, [:color, :penwidth])
          else
            base
          end
      end
    end
  end

  defp edge_label(weight) when is_number(weight) do
    to_string(weight)
  end

  defp edge_label(_) do
    ""
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

  defp remove_trace_edges(system) do
    trace_edge_ids =
      system.edge_meta
      |> Enum.filter(fn {_eid, meta} -> meta[:edge_type] == :trace end)
      |> Enum.map(&elem(&1, 0))
      |> MapSet.new()

    new_graph =
      Enum.reduce(trace_edge_ids, system.graph, fn eid, g ->
        Yog.Multi.remove_edge(g, eid)
      end)

    new_edge_meta = Map.drop(system.edge_meta, MapSet.to_list(trace_edge_ids))

    %{system | graph: new_graph, edge_meta: new_edge_meta}
  end
end
