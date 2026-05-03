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

  @heat_scale [
    "#ffffcc",
    "#ffeda0",
    "#fed976",
    "#feb24c",
    "#fd8d3c",
    "#fc4e2a",
    "#e31a1c",
    "#bd0026",
    "#800026"
  ]
  @cool_scale [
    "#f7fbff",
    "#deebf7",
    "#c6dbef",
    "#9ecae1",
    "#6baed6",
    "#4292c6",
    "#2171b5",
    "#08519c",
    "#08306b"
  ]
  @spectral_scale ["#2b83ba", "#abdda4", "#ffffbf", "#fdae61", "#d7191c"]

  @default_shapes %{
    database: :cylinder,
    cache: :octagon,
    service: :box3d,
    network: :cloud,
    user: :doublecircle,
    load_balancer: :hexagon,
    queue: :component,
    storage: :tab,
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
    graph_rankdir: nil,
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

  ## Examples

      iex> shapes = Choreo.Theme.default_shapes()
      iex> shapes[:database]
      :cylinder
      iex> shapes[:service]
      :box3d
  """
  @spec default_shapes() :: %{atom() => Yog.Render.DOT.node_shape()}
  def default_shapes, do: @default_shapes

  @doc """
  Returns the default colour palette.

  ## Examples

      iex> colors = Choreo.Theme.default_colors()
      iex> colors[:database]
      "#3b82f6"
      iex> colors[:service]
      "#10b981"
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
  Overrides specific fields in a theme, including deep-merging colors and shapes.

  ## Examples

      iex> theme = Choreo.Theme.default() |> Choreo.Theme.override(graph_rankdir: :lr)
      iex> theme.graph_rankdir
      :lr
  """
  @spec override(t(), keyword()) :: t()
  def override(%Theme{} = theme, opts) do
    colors = Keyword.get(opts, :colors, %{})
    shapes = Keyword.get(opts, :shapes, %{})

    new_colors = Map.merge(theme.colors, Map.new(colors))
    new_shapes = Map.merge(theme.shapes, Map.new(shapes))

    opts_without_maps = Keyword.drop(opts, [:colors, :shapes])

    struct!(theme, opts_without_maps)
    |> Map.put(:colors, new_colors)
    |> Map.put(:shapes, new_shapes)
  end

  @doc """
  Returns a hex color from a predefined scale based on a normalized value (0.0 to 1.0).

  ## Palettes
  - `:heat` — Yellow to Red (9 steps)
  - `:cool` — Light Blue to Dark Blue (9 steps)
  - `:spectral` — Blue-Yellow-Red (5 steps)
  """
  @spec color_from_scale(float(), atom() | [String.t()]) :: String.t()
  def color_from_scale(normalized, palette) when is_atom(palette) do
    scale =
      case palette do
        :heat -> @heat_scale
        :cool -> @cool_scale
        :spectral -> @spectral_scale
        _ -> @heat_scale
      end

    color_from_scale(normalized, scale)
  end

  def color_from_scale(normalized, scale) when is_list(scale) do
    # Clamp to [0, 1]
    n = max(0.0, min(1.0, normalized))
    index = round(n * (length(scale) - 1))
    Enum.at(scale, index)
  end

  @doc """
  The default theme — type-coloured nodes, top-down layout.

  ## Examples

      iex> theme = Choreo.Theme.default()
      iex> theme.name
      :default
      iex> theme.graph_rankdir
      nil
  """
  @spec default() :: t()
  def default, do: struct!(__MODULE__, name: :default)

  @doc """
  Dark theme — dark background, neon accents.

  ## Examples

      iex> theme = Choreo.Theme.dark()
      iex> theme.name
      :dark
      iex> theme.graph_bgcolor
      "#0f172a"
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

  ## Examples

      iex> theme = Choreo.Theme.minimal()
      iex> theme.name
      :minimal
      iex> theme.colors[:database]
      "#ffffff"
      iex> theme.shapes[:service]
      :box
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
  Warm theme — sunset palette, warm background.
  """
  @spec warm() :: t()
  def warm do
    struct!(__MODULE__,
      name: :warm,
      colors: %{
        database: "#f43f5e",
        cache: "#f97316",
        service: "#fbbf24",
        network: "#ec4899",
        user: "#ef4444",
        load_balancer: "#ea580c",
        queue: "#dc2626",
        storage: "#db2777",
        generic: "#78716c"
      },
      graph_bgcolor: "#fef2f2",
      edge_color: "#78716c",
      node_fontname: "Helvetica",
      node_fontcolor: "white"
    )
  end

  @doc """
  Forest theme — lush green palette, earth tones.
  """
  @spec forest() :: t()
  def forest do
    struct!(__MODULE__,
      name: :forest,
      colors: %{
        database: "#15803d",
        cache: "#166534",
        service: "#65a30d",
        network: "#14b8a6",
        user: "#84cc16",
        load_balancer: "#047857",
        queue: "#4d7c0f",
        storage: "#0f766e",
        generic: "#4b5563"
      },
      graph_bgcolor: "#f0fdf4",
      edge_color: "#4b5563",
      node_fontname: "Helvetica",
      node_fontcolor: "white"
    )
  end

  @doc """
  Ocean theme — deep blue palette, cool background.
  """
  @spec ocean() :: t()
  def ocean do
    struct!(__MODULE__,
      name: :ocean,
      colors: %{
        database: "#1d4ed8",
        cache: "#0369a1",
        service: "#0891b2",
        network: "#2563eb",
        user: "#0284c7",
        load_balancer: "#0e7490",
        queue: "#1e3a8a",
        storage: "#008080",
        generic: "#64748b"
      },
      graph_bgcolor: "#f0f9ff",
      edge_color: "#64748b",
      node_fontname: "Helvetica",
      node_fontcolor: "white"
    )
  end

  @doc """
  Resolves the effective shape for a node type, falling back to defaults.

  ## Examples

      iex> theme = Choreo.Theme.custom(shapes: %{database: :box})
      iex> Choreo.Theme.shape(theme, :database)
      :box
      iex> Choreo.Theme.shape(theme, :service)
      :box3d
  """
  @spec shape(t(), atom()) :: Yog.Render.DOT.node_shape()
  def shape(%Theme{shapes: shapes}, type) do
    Map.get(shapes, type) || Map.get(@default_shapes, type, :box)
  end

  @doc """
  Resolves the effective colour for a node type, falling back to defaults.

  ## Examples

      iex> theme = Choreo.Theme.custom(colors: %{database: "#ff0000"})
      iex> Choreo.Theme.color(theme, :database)
      "#ff0000"
      iex> Choreo.Theme.color(theme, :service)
      "#10b981"
  """
  @spec color(t(), atom()) :: String.t()
  def color(%Theme{colors: colors}, type) do
    Map.get(colors, type) || Map.get(@default_colors, type, "#9ca3af")
  end
end
