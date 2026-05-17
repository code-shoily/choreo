defmodule Choreo.Render.Mermaid do
  @moduledoc """
  Mermaid.js rendering for `Choreo` architecture diagrams.

  This module translates a `Choreo` struct into Mermaid flowchart syntax,
  suitable for embedding in Markdown, GitHub, GitLab, Notion, and other
  platforms that support Mermaid natively.

  ## Node shapes

  Infrastructure types map to Mermaid flowchart shapes:

  | Type            | Mermaid shape   | Syntax                    |
  | --------------- | --------------- | ------------------------- |
  | `database`      | `:cylinder`     | `[(label)]`               |
  | `cache`         | `:hexagon`      | `{{label}}`               |
  | `service`       | `:subroutine`   | `[[label]]`               |
  | `network`       | `:rounded_rect` | `[label]`                 |
  | `user`          | `:circle`       | `((label))`               |
  | `load_balancer` | `:hexagon`      | `{{label}}`               |
  | `queue`         | `:stadium`      | `([label])`               |
  | `storage`       | `:rounded_rect` | `[label]`                 |
  | `generic`       | `:rounded_rect` | `[label]`                 |

  Edges are styled according to their semantic type (`:connection` or
  `:dataflow`). Dataflow edges use a dashed purple stroke; virtual
  edges (from transitive filtering) use a light-grey stroke.

  ## Themes

  All built-in themes (`:default`, `:dark`, `:minimal`, `:warm`, `:forest`,
  `:ocean`) are supported. Per-type colours and shapes are resolved from
  `Choreo.Theme` and translated into Mermaid `style` declarations.

  ## Examples

      mermaid = Choreo.Render.Mermaid.to_mermaid(system)
      mermaid = Choreo.Render.Mermaid.to_mermaid(system, theme: :dark)

      theme = Choreo.Theme.custom(colors: [database: "#ff0000"])
      mermaid = Choreo.Render.Mermaid.to_mermaid(system, theme: theme)

  The output can be wrapped in a Markdown code block:

  ````markdown
  ```mermaid
  <%= mermaid %>
  ```
  ````
  """

  alias Choreo.Theme

  @doc """
  Renders a `Choreo` struct to a Mermaid flowchart string.

  ## Options

    * `:theme` - `:default`, `:dark`, `:minimal`, `:warm`, `:forest`, `:ocean`
      or a `Choreo.Theme` struct
    * `:direction` - `:td` (default), `:lr`, `:bt`, `:rl`
    * `:highlighted_nodes` - list of node IDs to highlight
    * `:highlighted_edges` - list of edge IDs or `{from, to}` tuples to highlight
    * Any other option accepted by `Yog.Multi.Mermaid.to_mermaid/2`

  ## Examples

      iex> system = Choreo.new() |> Choreo.add_service(:api)
      iex> mermaid = Choreo.Render.Mermaid.to_mermaid(system)
      iex> String.contains?(mermaid, "graph TD")
      true
      iex> String.contains?(mermaid, "api")
      true
  """
  @spec to_mermaid(Choreo.t(), keyword()) :: String.t()
  def to_mermaid(system, opts \\ []) do
    theme = resolve_theme(Keyword.get(opts, :theme, :default))
    direction = Keyword.get(opts, :direction, theme_direction(theme))

    subgraphs = build_mermaid_subgraphs(system)

    hl_nodes = MapSet.new(Keyword.get(opts, :highlighted_nodes, []) || [])
    hl_edges = MapSet.new(Keyword.get(opts, :highlighted_edges, []) || [])

    base =
      Yog.Multi.Mermaid.default_options()
      |> Map.put(:node_label, &node_label/2)
      |> Map.put(:edge_label, fn edge_id, _weight -> edge_label(system, edge_id) end)
      |> Map.put(:node_shape, node_shape_fn(theme))
      |> Map.put(:node_attributes, node_attributes_fn(system, theme, hl_nodes))
      |> Map.put(:edge_attributes, edge_attributes_fn(system, theme, hl_edges))
      |> Map.put(:direction, direction)
      |> Map.put(:default_font_color, theme.node_fontcolor)
      |> Map.merge(Map.new(opts))

    base = if subgraphs != [], do: Map.put(base, :subgraphs, subgraphs), else: base

    # Workaround: Yog.Multi.Mermaid filters undirected edges with from_id <= to_id,
    # but Yog.Multi.Graph stores undirected edges exactly as added (no duplication).
    # Normalizing edge direction ensures no edges are dropped.
    graph = normalize_undirected_graph(system.graph)

    Yog.Multi.Mermaid.to_mermaid(graph, base)
    |> String.replace("stroke_dasharray", "stroke-dasharray")
  end

  @doc """
  Returns a theme for `Choreo` infrastructure Mermaid diagrams.

  See also `Choreo.theme/2`.
  """
  @spec theme(atom(), keyword()) :: map()
  def theme(name \\ :default, overrides \\ []) do
    resolve_theme(name) |> Choreo.Theme.override(overrides)
  end

  # ============================================================================
  # Theme resolution
  # ============================================================================

  defp resolve_theme(%Theme{} = theme), do: theme
  defp resolve_theme(:default), do: Theme.default()
  defp resolve_theme(:dark), do: Theme.dark()
  defp resolve_theme(:minimal), do: Theme.minimal()
  defp resolve_theme(:warm), do: Theme.warm()
  defp resolve_theme(:forest), do: Theme.forest()
  defp resolve_theme(:ocean), do: Theme.ocean()
  defp resolve_theme(_), do: Theme.default()

  defp theme_direction(%Theme{graph_rankdir: nil}), do: :td
  defp theme_direction(%Theme{graph_rankdir: :tb}), do: :td
  defp theme_direction(%Theme{graph_rankdir: dir}), do: dir

  # ============================================================================
  # Node styling
  # ============================================================================

  defp node_shape_fn(theme) do
    fn _id, data ->
      type = Map.get(data, :type, :generic)
      Map.get(data, :shape) || Theme.shape(theme, type) |> to_mermaid_shape()
    end
  end

  defp node_attributes_fn(_system, theme, hl_nodes) do
    fn id, data ->
      type = Map.get(data, :type, :generic)

      fill = Map.get(data, :fillcolor) || Theme.color(theme, type)
      stroke = darken(fill)

      attrs = [
        {:fill, fill},
        {:stroke, stroke}
      ]

      # Only add fill/stroke if node is NOT highlighted.
      attrs =
        if MapSet.member?(hl_nodes, id) do
          []
        else
          attrs
        end

      attrs =
        if penwidth = data[:penwidth] do
          [{:stroke_width, "#{penwidth}px"} | attrs]
        else
          attrs
        end

      if desc = data[:description] do
        [{:title, desc} | attrs]
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

  defp edge_attributes_fn(system, theme, hl_edges) do
    fn from, to, edge_id, _weight ->
      meta = Map.get(system.edge_meta, edge_id, %{})

      if meta[:edge_type] == :virtual do
        [{:stroke, "#cbd5e1"}, {:stroke_width, "1px"}]
      else
        base =
          case meta[:type] do
            :dataflow ->
              [
                {:stroke, "#6366f1"},
                {:stroke_width, "2px"},
                {:stroke_dasharray, "5 5"}
              ]

            _ ->
              [{:stroke, theme.edge_color}, {:stroke_width, "2px"}]
          end

        # Final highlighting override
        is_highlighted =
          MapSet.member?(hl_edges, edge_id) or
            MapSet.member?(hl_edges, {from, to}) or
            (system.graph.kind == :undirected and
               MapSet.member?(hl_edges, {to, from}))

        if is_highlighted do
          Keyword.drop(base, [:stroke, :stroke_width])
        else
          base
        end
      end
    end
  end

  defp edge_label(system, edge_id) do
    meta = Map.get(system.edge_meta, edge_id, %{})

    cond do
      label = meta[:label] -> to_string(label)
      protocol = meta[:protocol] -> to_string(protocol)
      true -> ""
    end
  end

  # ============================================================================
  # Subgraphs
  # ============================================================================

  defp build_mermaid_subgraphs(system) do
    clusters = system.clusters || %{}

    if map_size(clusters) == 0 do
      []
    else
      nodes_by_cluster =
        system.graph.nodes
        |> Enum.group_by(fn {_id, data} -> data[:cluster] end)
        |> Map.delete(nil)

      Enum.flat_map(nodes_by_cluster, fn {cluster_name, nodes} ->
        cluster = Map.get(clusters, cluster_name, %{})
        label = cluster[:label] || cluster_name

        node_ids = Enum.map(nodes, fn {id, _data} -> id end)

        if node_ids == [] do
          []
        else
          [
            %{
              name: clean_cluster_name(cluster_name),
              label: label,
              node_ids: node_ids
            }
          ]
        end
      end)
    end
  end

  defp clean_cluster_name(name) do
    name = to_string(name)
    String.replace_prefix(name, "cluster_", "")
  end

  # Normalize undirected graph edges so from_id <= to_id.
  # This works around Yog.Multi.Mermaid's deduplication filter.
  defp normalize_undirected_graph(%{kind: :undirected} = graph) do
    normalized =
      Map.new(graph.edges, fn {edge_id, {from, to, weight}} ->
        if from <= to do
          {edge_id, {from, to, weight}}
        else
          {edge_id, {to, from, weight}}
        end
      end)

    %{graph | edges: normalized}
  end

  defp normalize_undirected_graph(graph), do: graph

  # ============================================================================
  # Helpers
  # ============================================================================

  @doc false
  @spec to_mermaid_shape(atom()) :: Yog.Render.Mermaid.node_shape()
  def to_mermaid_shape(:cylinder), do: :cylinder
  def to_mermaid_shape(:octagon), do: :hexagon
  def to_mermaid_shape(:box3d), do: :subroutine
  def to_mermaid_shape(:cloud), do: :rounded_rect
  def to_mermaid_shape(:doublecircle), do: :circle
  def to_mermaid_shape(:hexagon), do: :hexagon
  def to_mermaid_shape(:component), do: :stadium
  def to_mermaid_shape(:tab), do: :rounded_rect
  def to_mermaid_shape(:box), do: :rounded_rect
  def to_mermaid_shape(:ellipse), do: :rounded_rect
  def to_mermaid_shape(:circle), do: :circle
  def to_mermaid_shape(:diamond), do: :rhombus
  def to_mermaid_shape(_), do: :rounded_rect

  # Darken a hex colour slightly for use as a stroke colour.
  defp darken("#" <> hex) when byte_size(hex) == 6 do
    hex
    |> String.to_integer(16)
    |> then(fn n ->
      r = max(0, div(n, 0x10000) - 30)
      g = max(0, div(rem(n, 0x10000), 0x100) - 30)
      b = max(0, rem(n, 0x100) - 30)
      <<r::8, g::8, b::8>>
    end)
    |> Base.encode16(case: :lower)
    |> then(&("#" <> &1))
  end

  defp darken(other), do: other
end
