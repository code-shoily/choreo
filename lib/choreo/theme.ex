defmodule Choreo.Theme do
  @moduledoc """
  Visual themes for `Choreo` architecture diagrams.

  A theme controls node shapes, colours, fonts, edge styling, graph layout,
  and cluster defaults. Use `custom/1` to build your own, or use the built-in
  atom shortcuts (`:default`, `:dark`, `:minimal`).

  ## Built-in themes

      # Warm, top-down layout with type-coloured nodes (default)
      Choreo.to_dot(system, theme: :default)

      # Dark background with neon accents
      Choreo.to_dot(system, theme: :dark)

      # Wireframe look — monochrome, no fills
      Choreo.to_dot(system, theme: :minimal)

  ## Custom themes

      theme =
        Choreo.Theme.custom(
          name: "brand",
          colors: [database: "#1e3a8a", service: "#047857"],
          graph_bgcolor: "#f8fafc",
          graph_rankdir: :lr
        )

      Choreo.to_dot(system, theme: theme)

  ## Per-type overrides

  The `shapes` and `colors` maps accept any node `:type` as a key. Missing
  types fall back to the built-in defaults (`:box` shape, `"#9ca3af"` colour).

  ## Cluster theming

  You can set default cluster styling so every `add_cluster/3` inherits a
  look unless it provides its own `:fillcolor`, `:style`, or `:color`.

      Choreo.Theme.custom(
        cluster_fillcolor: "#e2e8f0",
        cluster_style: :rounded,
        cluster_color: "#64748b"
      )
  """

  alias __MODULE__

  @type t :: %__MODULE__{
          name: atom() | String.t(),
          shapes: %{atom() => Yog.Render.DOT.node_shape()},
          colors: %{atom() => String.t()},
          node_fontname: String.t(),
          node_fontsize: integer(),
          node_fontcolor: String.t(),
          edge_color: String.t(),
          edge_fontname: String.t(),
          edge_fontsize: integer(),
          edge_penwidth: float(),
          graph_rankdir: Yog.Render.DOT.rank_dir(),
          graph_splines: Yog.Render.DOT.splines(),
          graph_bgcolor: String.t() | nil,
          graph_nodesep: float(),
          graph_ranksep: float(),
          cluster_style: Yog.Render.DOT.style() | nil,
          cluster_fillcolor: String.t() | nil,
          cluster_color: String.t() | nil
        }

  @default_shapes %{
    database: :cylinder,
    cache: :diamond,
    service: :box3d,
    network: :cloud,
    user: :doublecircle,
    load_balancer: :hexagon,
    queue: :folder,
    storage: :folder,
    generic: :box
  }

  @default_colors %{
    database: "#3b82f6",
    cache: "#f59e0b",
    service: "#10b981",
    network: "#6366f1",
    user: "#ef4444",
    load_balancer: "#8b5cf6",
    queue: "#ec4899",
    storage: "#14b8a6",
    generic: "#9ca3af"
  }

  defstruct [
    :name,
    shapes: %{},
    colors: %{},
    node_fontname: "Helvetica",
    node_fontsize: 12,
    node_fontcolor: "white",
    edge_color: "#64748b",
    edge_fontname: "Helvetica",
    edge_fontsize: 10,
    edge_penwidth: 1.0,
    graph_rankdir: :tb,
    graph_splines: :spline,
    graph_bgcolor: nil,
    graph_nodesep: 0.6,
    graph_ranksep: 1.2,
    cluster_style: nil,
    cluster_fillcolor: nil,
    cluster_color: nil
  ]

  @doc """
  Returns the default shape palette.
  """
  @spec default_shapes() :: %{atom() => Yog.Render.DOT.node_shape()}
  def default_shapes, do: @default_shapes

  @doc """
  Returns the default colour palette.
  """
  @spec default_colors() :: %{atom() => String.t()}
  def default_colors, do: @default_colors

  @doc """
  Builds a custom theme from keyword options.

  Only the fields you specify are overridden; everything else falls back to
  the default theme values.

  ## Examples

      iex> theme = Choreo.Theme.custom(name: :brand, graph_rankdir: :lr)
      iex> theme.name
      :brand
      iex> theme.graph_rankdir
      :lr
  """
  @spec custom(keyword()) :: t()
  def custom(opts \\ []) do
    struct!(__MODULE__, [{:name, :custom} | opts])
  end

  @doc """
  The default theme — type-coloured nodes, top-down layout.
  """
  @spec default() :: t()
  def default, do: struct!(__MODULE__, name: :default)

  @doc """
  Dark theme — dark background, neon accents.
  """
  @spec dark() :: t()
  def dark do
    struct!(__MODULE__,
      name: :dark,
      graph_bgcolor: "#0f172a",
      edge_color: "#94a3b8",
      node_fontname: "Helvetica",
      node_fontcolor: "white"
    )
  end

  @doc """
  Minimal theme — monochrome wireframe, thin edges, no fills.
  """
  @spec minimal() :: t()
  def minimal do
    struct!(__MODULE__,
      name: :minimal,
      colors: %{
        database: "#ffffff",
        cache: "#ffffff",
        service: "#ffffff",
        network: "#ffffff",
        user: "#ffffff",
        load_balancer: "#ffffff",
        queue: "#ffffff",
        storage: "#ffffff",
        generic: "#ffffff"
      },
      shapes: %{
        database: :box,
        cache: :box,
        service: :box,
        network: :box,
        user: :box,
        load_balancer: :box,
        queue: :box,
        storage: :box,
        generic: :box
      },
      node_fontcolor: "black",
      edge_color: "#334155",
      edge_penwidth: 0.8
    )
  end

  @doc """
  Resolves the effective shape for a node type, falling back to defaults.
  """
  @spec shape(t(), atom()) :: Yog.Render.DOT.node_shape()
  def shape(%Theme{shapes: shapes}, type) do
    Map.get(shapes, type) || Map.get(@default_shapes, type, :box)
  end

  @doc """
  Resolves the effective colour for a node type, falling back to defaults.
  """
  @spec color(t(), atom()) :: String.t()
  def color(%Theme{colors: colors}, type) do
    Map.get(colors, type) || Map.get(@default_colors, type, "#9ca3af")
  end
end
