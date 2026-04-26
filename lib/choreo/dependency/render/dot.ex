defmodule Choreo.Dependency.Render.DOT do
  @moduledoc """
  DOT (Graphviz) rendering for `Choreo.Dependency` graphs.

  Produces dependency-oriented visualisation:

    * **Applications** — 3D boxes
    * **Libraries** — cylinders
    * **Modules** — boxes
    * **Interfaces** — diamonds
    * **Tests** — note shapes

  Edge styles:
    * **uses** — solid grey
    * **imports** — dashed
    * **calls** — dotted
    * **inherits** — solid bold
    * **dev** — dashed grey

  Layout is top-to-bottom by default so dependencies point downward.
  """

  alias Choreo.Theme

  @doc """
  Renders a dependency graph to a DOT string.

  ## Options

    * `:theme` — `:default`, `:dark`, or a `Choreo.Theme` struct

  ## Examples

      iex> deps = Choreo.Dependency.new()
      iex> deps = deps
      ...>   |> Choreo.Dependency.add_application(:api, label: "API")
      ...>   |> Choreo.Dependency.add_module(:auth, label: "Auth")
      ...>   |> Choreo.Dependency.depends_on(:api, :auth)
      iex> dot = Choreo.Dependency.Render.DOT.to_dot(deps)
      iex> String.contains?(dot, "digraph")
      true
      iex> String.contains?(dot, "API")
      true
      iex> String.contains?(dot, "Auth")
      true
  """
  @spec to_dot(Choreo.Dependency.t(), keyword()) :: String.t()
  def to_dot(%Choreo.Dependency{} = deps, opts \\ []) do
    theme = resolve_theme(Keyword.get(opts, :theme, :default))
    subgraphs = Choreo.Internal.build_cluster_subgraphs(deps, theme)
    cycle_edges = cycle_edge_set(deps)

    base_opts =
      Yog.Render.DOT.default_options()
      |> Map.put(:rankdir, :tb)
      |> Map.put(:splines, :spline)
      |> Map.put(:nodesep, 0.5)
      |> Map.put(:ranksep, 1.0)
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
      |> Map.put(:edge_attributes, edge_attributes_fn(deps, cycle_edges))
      |> Map.merge(theme_graph_overrides(theme))
      |> Map.merge(Map.new(opts))

    base_opts = if subgraphs != [], do: Map.put(base_opts, :subgraphs, subgraphs), else: base_opts

    Yog.Render.DOT.to_dot(deps.graph, base_opts)
  end

  # ============================================================================
  # Cycle highlighting
  # ============================================================================

  defp cycle_edge_set(deps) do
    cycles = Choreo.Dependency.Analysis.cyclic_dependencies(deps)

    cycles
    |> Enum.flat_map(fn path ->
      # path is [a, b, c, a]
      path
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [from, to] -> {from, to} end)
    end)
    |> MapSet.new()
  end

  # ============================================================================
  # Theme helpers
  # ============================================================================

  defp resolve_theme(%Theme{} = theme), do: theme
  defp resolve_theme(:default), do: default_dependency_theme()
  defp resolve_theme(:dark), do: dark_dependency_theme()
  defp resolve_theme(_), do: default_dependency_theme()

  defp default_dependency_theme do
    %Theme{
      name: :dependency_default,
      colors: %{
        application: "#3b82f6",
        library: "#f59e0b",
        module: "#10b981",
        interface: "#8b5cf6",
        test: "#64748b"
      },
      node_fontname: "Helvetica",
      node_fontsize: 12,
      node_fontcolor: "white",
      edge_color: "#64748b",
      edge_fontname: "Helvetica",
      edge_fontsize: 9,
      edge_penwidth: 1.0,
      graph_bgcolor: nil,
      cluster_fillcolor: "#f8fafc",
      cluster_style: :rounded,
      cluster_color: "#cbd5e1"
    }
  end

  defp dark_dependency_theme do
    %Theme{
      name: :dependency_dark,
      colors: %{
        application: "#2563eb",
        library: "#d97706",
        module: "#059669",
        interface: "#7c3aed",
        test: "#475569"
      },
      node_fontname: "Helvetica",
      node_fontsize: 12,
      node_fontcolor: "#e2e8f0",
      edge_color: "#94a3b8",
      edge_fontname: "Helvetica",
      edge_fontsize: 9,
      edge_penwidth: 1.0,
      graph_bgcolor: "#0f172a",
      cluster_fillcolor: "#1e293b",
      cluster_style: :rounded,
      cluster_color: "#475569"
    }
  end

  defp dep_color(%Theme{colors: colors}, key) do
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
        case Map.get(data, :node_type, :module) do
          :application ->
            [
              {:shape, :box3d},
              {:fillcolor, dep_color(theme, :application)}
            ]

          :library ->
            [
              {:shape, :cylinder},
              {:fillcolor, dep_color(theme, :library)}
            ]

          :module ->
            [
              {:shape, :box},
              {:fillcolor, dep_color(theme, :module)}
            ]

          :interface ->
            [
              {:shape, :diamond},
              {:fillcolor, dep_color(theme, :interface)}
            ]

          :test ->
            [
              {:shape, :note},
              {:fillcolor, dep_color(theme, :test)}
            ]

          _ ->
            [
              {:shape, :box},
              {:fillcolor, dep_color(theme, :module)}
            ]
        end

      base =
        if desc = data[:description] do
          [{:tooltip, desc} | base]
        else
          base
        end

      base
    end
  end

  defp node_label(_id, data) do
    data[:label] || ""
  end

  # ============================================================================
  # Edge styling
  # ============================================================================

  defp edge_attributes_fn(deps, cycle_edges) do
    fn from, to, _weight ->
      meta = Map.get(deps.edge_meta, {from, to}, %{})

      base = dep_type_attrs(meta[:type] || :uses)

      # Highlight cycle edges in red
      base =
        if MapSet.member?(cycle_edges, {from, to}) do
          [{:color, "#ef4444"}, {:penwidth, 2.0} | Keyword.drop(base, [:color, :penwidth])]
        else
          base
        end

      if label = meta[:label] do
        if label != "" do
          [{:label, label} | base]
        else
          base
        end
      else
        base
      end
    end
  end

  defp dep_type_attrs(:imports), do: [{:style, :dashed}]
  defp dep_type_attrs(:calls), do: [{:style, :dotted}]
  defp dep_type_attrs(:inherits), do: [{:penwidth, 2.0}]
  defp dep_type_attrs(:dev), do: [{:style, :dashed}, {:color, "#9ca3af"}]
  defp dep_type_attrs(_), do: []

  defp edge_label(_), do: ""
end
