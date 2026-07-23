defmodule Choreo.Lab.View do
  @moduledoc """
  Pipe-friendly view helpers for exploring Choreo models in Livebook.

  This module is ordinary Elixir, not a macro DSL. It is a thin convenience
  layer over `Choreo.View` that keeps the stable view API intact while making
  common zoom, focus, filter, path, and collapse operations easier to compose in
  pipelines.

  `Choreo.View` remains the primitive graph-lens API. `Choreo.Lab.View` is the
  ergonomic exploration API: a place to try friendlier names, positional forms,
  and common predicates before deciding whether any of them should graduate into
  core `Choreo.View`.

  Prefer alias-qualified usage for better editor autocomplete:

      alias Choreo.Lab.View

      system
      |> View.zoom(1)
      |> View.only_type([:service, :database, :cache])
      |> View.focus(:api, depth: 2)

  The functions return ordinary Choreo structs rebuilt through the
  `Choreo.Viewable` protocol.
  """

  @type viewable :: struct()
  @type node_id :: Yog.node_id()
  @type node_type :: atom()

  @doc """
  Returns the view helper vocabulary for Livebook discovery.

      iex> taxonomy = Choreo.Lab.View.taxonomy()
      iex> :zoom in taxonomy.transforms
      true
      iex> :only_type in taxonomy.filters
      true
      iex> :collapse_type in taxonomy.collapse
      true
  """
  @spec taxonomy() :: %{
          transforms: [atom()],
          filters: [atom()],
          collapse: [atom()],
          options: [atom()],
          renders: [atom()]
        }
  def taxonomy do
    %{
      transforms: [:zoom, :focus, :neighborhood, :between, :path, :trace],
      filters: [:only, :without, :only_nodes, :without_nodes, :only_type, :without_type],
      collapse: [:collapse_nodes, :collapse_type],
      options: [:depth, :radius, :mode, :transitive, :label, :data],
      renders: [:tabs, :to_siren, :to_sketch, :to_mermaid, :to_dot]
    }
  end

  @doc """
  Compatibility alias for `taxonomy/0`.
  """
  @spec verbs() :: %{
          transforms: [atom()],
          filters: [atom()],
          collapse: [atom()],
          options: [atom()],
          renders: [atom()]
        }
  def verbs, do: taxonomy()

  @doc """
  Applies `Choreo.View.zoom/2` with a positional level.

      iex> system = Choreo.new() |> Choreo.add_service(:api) |> Choreo.add_database(:db)
      iex> system |> Choreo.Lab.View.zoom(0) |> Choreo.nodes()
      %{api: %{label: "api", node_type: :service}}
  """
  @spec zoom(viewable(), non_neg_integer(), keyword()) :: viewable()
  def zoom(diagram, level, opts \\ []) when is_struct(diagram) do
    Choreo.View.zoom(diagram, Keyword.put(opts, :level, level))
  end

  @doc """
  Keeps `node` and its surrounding neighbourhood.

  Accepts either `:depth` or `:radius`; both map to `Choreo.View.focus/3`'s
  `:radius` option. `:mode` may be `:neighbors`, `:successors`, or
  `:predecessors`.
  """
  @spec focus(viewable(), node_id(), keyword()) :: viewable()
  def focus(diagram, node, opts \\ []) when is_struct(diagram) do
    Choreo.View.focus(diagram, node, normalize_focus_opts(opts))
  end

  @doc """
  Alias for `focus/3` that reads naturally in exploratory pipelines.
  """
  @spec neighborhood(viewable(), node_id(), keyword()) :: viewable()
  def neighborhood(diagram, node, opts \\ []), do: focus(diagram, node, opts)

  @doc """
  Keeps the shortest path between two nodes, optionally with surrounding radius.
  """
  @spec between(viewable(), node_id(), node_id(), keyword()) :: viewable()
  def between(diagram, from, to, opts \\ []) when is_struct(diagram) do
    Choreo.View.focus_between(diagram, from, to, normalize_focus_opts(opts))
  end

  @doc """
  Alias for `between/4`.
  """
  @spec path(viewable(), node_id(), node_id(), keyword()) :: viewable()
  def path(diagram, from, to, opts \\ []), do: between(diagram, from, to, opts)

  @doc """
  Keeps a trace path between two nodes using `Choreo.View.focus_trace/4`.
  """
  @spec trace(viewable(), node_id(), node_id(), keyword()) :: viewable()
  def trace(diagram, from, to, opts \\ []) when is_struct(diagram) do
    Choreo.View.focus_trace(diagram, from, to, normalize_focus_opts(opts))
  end

  @doc """
  Keeps only the listed node IDs.
  """
  @spec only_nodes(viewable(), node_id() | [node_id()], keyword()) :: viewable()
  def only_nodes(diagram, ids, opts \\ []) when is_struct(diagram) do
    keep = ids |> List.wrap() |> MapSet.new()
    Choreo.View.filter(diagram, fn id, _data -> MapSet.member?(keep, id) end, opts)
  end

  @doc """
  Removes the listed node IDs.
  """
  @spec without_nodes(viewable(), node_id() | [node_id()], keyword()) :: viewable()
  def without_nodes(diagram, ids, opts \\ []) when is_struct(diagram) do
    remove = ids |> List.wrap() |> MapSet.new()
    Choreo.View.filter(diagram, fn id, _data -> not MapSet.member?(remove, id) end, opts)
  end

  @doc """
  Keeps only nodes whose `:node_type` or `:type` matches the given type(s).
  """
  @spec only_type(viewable(), node_type() | [node_type()], keyword()) :: viewable()
  def only_type(diagram, types, opts \\ []) when is_struct(diagram) do
    keep = types |> List.wrap() |> MapSet.new()

    Choreo.View.filter(
      diagram,
      fn _id, data -> MapSet.member?(keep, semantic_type(data)) end,
      opts
    )
  end

  @doc """
  Removes nodes whose `:node_type` or `:type` matches the given type(s).
  """
  @spec without_type(viewable(), node_type() | [node_type()], keyword()) :: viewable()
  def without_type(diagram, types, opts \\ []) when is_struct(diagram) do
    remove = types |> List.wrap() |> MapSet.new()

    Choreo.View.filter(
      diagram,
      fn _id, data -> not MapSet.member?(remove, semantic_type(data)) end,
      opts
    )
  end

  @doc """
  Generic keep filter for small Livebook experiments.

  Supported options:

    * `:nodes` — node ID or IDs to keep
    * `:type` / `:types` — semantic node type or types to keep

  When both are supplied, a node may match either condition.
  """
  @spec only(viewable(), keyword()) :: viewable()
  def only(diagram, opts) when is_struct(diagram) and is_list(opts) do
    node_set = opts |> Keyword.get(:nodes, []) |> List.wrap() |> MapSet.new()

    type_set =
      opts |> Keyword.get(:type, Keyword.get(opts, :types, [])) |> List.wrap() |> MapSet.new()

    Choreo.View.filter(diagram, fn id, data ->
      MapSet.member?(node_set, id) or MapSet.member?(type_set, semantic_type(data))
    end)
  end

  @doc """
  Generic remove filter for small Livebook experiments.

  Supported options mirror `only/2`.
  """
  @spec without(viewable(), keyword()) :: viewable()
  def without(diagram, opts) when is_struct(diagram) and is_list(opts) do
    node_set = opts |> Keyword.get(:nodes, []) |> List.wrap() |> MapSet.new()

    type_set =
      opts |> Keyword.get(:type, Keyword.get(opts, :types, [])) |> List.wrap() |> MapSet.new()

    Choreo.View.filter(diagram, fn id, data ->
      not (MapSet.member?(node_set, id) or MapSet.member?(type_set, semantic_type(data)))
    end)
  end

  @doc """
  Collapses the listed node IDs into `new_id`.
  """
  @spec collapse_nodes(viewable(), node_id() | [node_id()], node_id(), keyword()) :: viewable()
  def collapse_nodes(diagram, ids, new_id, opts \\ []) when is_struct(diagram) do
    collapse_set = ids |> List.wrap() |> MapSet.new()

    Choreo.View.collapse(
      diagram,
      fn id, _data -> MapSet.member?(collapse_set, id) end,
      new_id,
      opts
    )
  end

  @doc """
  Collapses all nodes of the given type(s) into `new_id`.
  """
  @spec collapse_type(viewable(), node_type() | [node_type()], node_id(), keyword()) :: viewable()
  def collapse_type(diagram, types, new_id, opts \\ []) when is_struct(diagram) do
    collapse_set = types |> List.wrap() |> MapSet.new()

    Choreo.View.collapse(
      diagram,
      fn _id, data -> MapSet.member?(collapse_set, semantic_type(data)) end,
      new_id,
      opts
    )
  end

  @doc """
  Renders the diagram as a tabbed layout in Livebook featuring Siren, Graphviz, and Sketch.

  Only active when `Kino` is loaded. Returns the Kino widget tab layout.
  If Kino is not loaded, returns the diagram unmodified.
  """
  @spec tabs(viewable(), keyword()) :: any()
  def tabs(diagram, opts \\ []) when is_struct(diagram) do
    if Code.ensure_loaded?(Kino) do
      mermaid = Choreo.to_mermaid(diagram, opts)
      dot = Choreo.to_dot(diagram, opts)
      height = Keyword.get(opts, :height, 400)

      graphviz =
        if Code.ensure_loaded?(Kino.VizJS) do
          module = Module.concat([Kino, VizJS])
          module.render(dot, height: height)
        else
          dot
        end

      Kino.Layout.tabs(
        Siren: Choreo.Lab.Siren.new(mermaid, opts),
        Graphviz: graphviz,
        Sketch: Choreo.Lab.Sketch.new(mermaid, opts)
      )
    else
      diagram
    end
  end

  @doc """
  Renders the diagram using the Siren Kino widget in Livebook.

  Only active when `Kino` is loaded. Returns the Kino widget.
  If Kino is not loaded, returns the diagram unmodified.
  """
  @spec to_siren(viewable(), keyword()) :: any()
  def to_siren(diagram, opts \\ []) when is_struct(diagram) do
    if Code.ensure_loaded?(Kino) do
      Choreo.Lab.Siren.new(Choreo.to_mermaid(diagram, opts), opts)
    else
      diagram
    end
  end

  @doc """
  Renders the diagram using the Sketch Kino widget in Livebook.

  Only active when `Kino` is loaded. Returns the Kino widget.
  If Kino is not loaded, returns the diagram unmodified.
  """
  @spec to_sketch(viewable(), keyword()) :: any()
  def to_sketch(diagram, opts \\ []) when is_struct(diagram) do
    if Code.ensure_loaded?(Kino) do
      Choreo.Lab.Sketch.new(Choreo.to_mermaid(diagram, opts), opts)
    else
      diagram
    end
  end

  @doc """
  Converts the diagram to a Mermaid string.
  """
  @spec to_mermaid(viewable(), keyword()) :: String.t()
  def to_mermaid(diagram, opts \\ []) when is_struct(diagram) do
    Choreo.to_mermaid(diagram, opts)
  end

  @doc """
  Converts the diagram to a Graphviz DOT string.
  """
  @spec to_dot(viewable(), keyword()) :: String.t()
  def to_dot(diagram, opts \\ []) when is_struct(diagram) do
    Choreo.to_dot(diagram, opts)
  end

  defp normalize_focus_opts(opts) do
    case Keyword.pop(opts, :depth) do
      {nil, opts} -> opts
      {depth, opts} -> Keyword.put_new(opts, :radius, depth)
    end
  end

  defp semantic_type(data), do: data[:node_type] || data[:type]
end
