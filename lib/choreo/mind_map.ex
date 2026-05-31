defmodule Choreo.MindMap do
  @moduledoc """
  Mind-map builder on top of Yog.

  `Choreo.MindMap` models hierarchical concept maps where a central idea
  radiates into topics, sub-topics, and notes. Cross-links (associations)
  between branches are supported for non-hierarchical relationships.

  ## When to use

  Use `Choreo.MindMap` when brainstorming, documenting knowledge domains,
  planning talks, or structuring documentation. It enforces a single-root
  invariant and detects orphaned concepts automatically.

  ## Node types

    * `:root` — the central concept (exactly one per map)
    * `:topic` — main branch radiating from the root
    * `:subtopic` — nested idea under a topic
    * `:note` — annotation or detail node

  ## Edge types

    * `:branch` — hierarchical parent→child relationship
    * `:associates` — cross-link between any two nodes

  ## Further reading

    * [Mind map (Wikipedia)](https://en.wikipedia.org/wiki/Mind_map)
    * [Tony Buzan — Mind Mapping](https://www.tonybuzan.com/about/mind-mapping/)

  ## Quick Start

      map =
        Choreo.MindMap.new()
        |> Choreo.MindMap.set_root(:elixir, label: "Elixir")
        |> Choreo.MindMap.add_topic(:concurrency, label: "Concurrency")
        |> Choreo.MindMap.add_topic(:ecosystem, label: "Ecosystem")
        |> Choreo.MindMap.add_subtopic(:processes, label: "Processes")
        |> Choreo.MindMap.add_note(:beam, label: "BEAM VM")
        |> Choreo.MindMap.branch(:elixir, :concurrency)
        |> Choreo.MindMap.branch(:elixir, :ecosystem)
        |> Choreo.MindMap.branch(:concurrency, :processes)
        |> Choreo.MindMap.branch(:ecosystem, :beam)
        |> Choreo.MindMap.associate(:processes, :beam, label: "runs on")

      dot = Choreo.MindMap.to_dot(map)

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=TB, splines=spline, nodesep=0.6, ranksep=1.2];
      node [shape=ellipse, style=filled, fillcolor="white", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [arrowhead=normal, color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];

      elixir [label="Elixir", fillcolor="#8b5cf6", shape="doublecircle", penwidth="2.0"];
      concurrency [label="Concurrency", fillcolor="#3b82f6", shape="ellipse"];
      ecosystem [label="Ecosystem", fillcolor="#10b981", shape="ellipse"];
      processes [label="Processes", fillcolor="#06b6d4", shape="box"];
      beam [label="BEAM VM", fillcolor="#f59e0b", shape="note"];

      elixir -> concurrency [style="solid", color="#64748b"];
      elixir -> ecosystem [style="solid", color="#64748b"];
      concurrency -> processes [style="solid", color="#64748b"];
      ecosystem -> beam [style="solid", color="#64748b"];
      processes -> beam [style="dashed", color="#94a3b8", label="runs on", dir=none];
    }
  </div>

  ## Analysis

      # Detect orphaned ideas not reachable from the root
      Choreo.MindMap.Analysis.orphan_nodes(map)

      # Measure map complexity
      Choreo.MindMap.Analysis.depth(map)
      Choreo.MindMap.Analysis.breadth(map)

      # Validate structural soundness
      Choreo.MindMap.Analysis.validate(map)
  """

  @type t :: %__MODULE__{
          graph: Yog.graph(),
          root: Yog.node_id() | nil,
          edge_meta: %{optional({Yog.node_id(), Yog.node_id()}) => map()}
        }

  defstruct graph: nil, root: nil, edge_meta: %{}

  @node_schema [
    label: [
      type: :string,
      required: false
    ],
    description: [
      type: :string,
      required: false
    ],
    shape: [
      type: :atom,
      required: false
    ],
    fillcolor: [
      type: :string,
      required: false
    ],
    fontcolor: [
      type: :string,
      required: false
    ],
    style: [
      type: :string,
      required: false
    ],
    penwidth: [
      type: {:or, [:integer, :float]},
      required: false
    ],
    image: [
      type: :string,
      required: false
    ]
  ]

  @set_root_schema @node_schema
  @add_topic_schema @node_schema
  @add_subtopic_schema @node_schema
  @add_note_schema @node_schema

  @connect_schema [
    label: [
      type: :string,
      required: false
    ]
  ]

  # ============================================================================
  # Creation
  # ============================================================================

  @doc """
  Creates a new empty mind map.

  ## Examples

      iex> map = Choreo.MindMap.new()
      iex> Choreo.MindMap.nodes(map)
      []
      iex> Choreo.MindMap.root(map)
      nil
  """
  @spec new() :: t()
  def new do
    %__MODULE__{
      graph: Yog.directed(),
      root: nil,
      edge_meta: %{}
    }
  end

  # ============================================================================
  # Node builders
  # ============================================================================

  @doc """
  Sets the root concept node of the mind map.

  Can only be called once. Raises `ArgumentError` if the map already has a root.

  ## Options

  #{NimbleOptions.docs(@set_root_schema)}

  ## Examples

      iex> map = Choreo.MindMap.new()
      iex> map = Choreo.MindMap.set_root(map, :idea, label: "Big Idea")
      iex> Choreo.MindMap.root(map)
      :idea
      iex> Yog.node(map.graph, :idea).node_type
      :root
      iex> Yog.node(map.graph, :idea).label
      "Big Idea"

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=TB, splines=spline, nodesep=0.6, ranksep=1.2];
      node [shape=ellipse, style=filled, fillcolor="white", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [arrowhead=normal, color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];

      idea [label="Big Idea", fillcolor="#8b5cf6", shape="doublecircle", penwidth="2.0"];
    }
  </div>

      iex> map = Choreo.MindMap.new() |> Choreo.MindMap.set_root(:a, label: "A")
      iex> Choreo.MindMap.set_root(map, :b, label: "B")
      ** (ArgumentError) Mind map already has a root
  """
  @spec set_root(t(), Yog.node_id(), keyword()) :: t()
  def set_root(map, id, opts \\ [])

  def set_root(%__MODULE__{root: nil} = map, id, opts) do
    opts = NimbleOptions.validate!(opts, @set_root_schema)
    data = node_data(:root, opts)

    %{
      map
      | graph: Yog.add_node(map.graph, id, data),
        root: id
    }
  end

  def set_root(%__MODULE__{}, _id, _opts) do
    raise ArgumentError, "Mind map already has a root"
  end

  @doc """
  Adds a topic node (main branch).

  ## Options

  #{NimbleOptions.docs(@add_topic_schema)}

  ## Examples

      iex> map = Choreo.MindMap.new()
      iex> map = Choreo.MindMap.add_topic(map, :design, label: "Design")
      iex> :design in Choreo.MindMap.nodes(map)
      true
      iex> Yog.node(map.graph, :design).node_type
      :topic

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=TB, splines=spline, nodesep=0.6, ranksep=1.2];
      node [shape=ellipse, style=filled, fillcolor="white", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [arrowhead=normal, color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];

      design [label="Design", fillcolor="#3b82f6", shape="ellipse"];
    }
  </div>
  """
  @spec add_topic(t(), Yog.node_id(), keyword()) :: t()
  def add_topic(%__MODULE__{} = map, id, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @add_topic_schema)
    data = node_data(:topic, opts)
    %{map | graph: Yog.add_node(map.graph, id, data)}
  end

  @doc """
  Adds a subtopic node (nested idea under a topic).

  ## Options

  #{NimbleOptions.docs(@add_subtopic_schema)}

  ## Examples

      iex> map = Choreo.MindMap.new()
      iex> map = Choreo.MindMap.add_subtopic(map, :patterns, label: "Patterns")
      iex> :patterns in Choreo.MindMap.nodes(map)
      true
      iex> Yog.node(map.graph, :patterns).node_type
      :subtopic

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=TB, splines=spline, nodesep=0.6, ranksep=1.2];
      node [shape=ellipse, style=filled, fillcolor="white", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [arrowhead=normal, color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];

      patterns [label="Patterns", fillcolor="#06b6d4", shape="box"];
    }
  </div>
  """
  @spec add_subtopic(t(), Yog.node_id(), keyword()) :: t()
  def add_subtopic(%__MODULE__{} = map, id, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @add_subtopic_schema)
    data = node_data(:subtopic, opts)
    %{map | graph: Yog.add_node(map.graph, id, data)}
  end

  @doc """
  Adds a note node (annotation or detail).

  ## Options

  #{NimbleOptions.docs(@add_note_schema)}

  ## Examples

      iex> map = Choreo.MindMap.new()
      iex> map = Choreo.MindMap.add_note(map, :ref, label: "See RFC 7231")
      iex> :ref in Choreo.MindMap.nodes(map)
      true
      iex> Yog.node(map.graph, :ref).node_type
      :note

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=TB, splines=spline, nodesep=0.6, ranksep=1.2];
      node [shape=ellipse, style=filled, fillcolor="white", fontname="Helvetica", fontsize=12, fontcolor="white"];
      edge [arrowhead=normal, color="#64748b", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];

      ref [label="See RFC 7231", fillcolor="#f59e0b", shape="note"];
    }
  </div>
  """
  @spec add_note(t(), Yog.node_id(), keyword()) :: t()
  def add_note(%__MODULE__{} = map, id, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @add_note_schema)
    data = node_data(:note, opts)
    %{map | graph: Yog.add_node(map.graph, id, data)}
  end

  # ============================================================================
  # Edge builders
  # ============================================================================

  @doc """
  Creates a hierarchical branch from parent to child.

  ## Options

  #{NimbleOptions.docs(@connect_schema)}

  ## Examples

      iex> map = Choreo.MindMap.new()
      iex> map = map
      ...>   |> Choreo.MindMap.set_root(:a, label: "A")
      ...>   |> Choreo.MindMap.add_topic(:b, label: "B")
      ...>   |> Choreo.MindMap.branch(:a, :b)
      iex> Yog.has_edge?(map.graph, :a, :b)
      true
      iex> map.edge_meta[{:a, :b}].edge_type
      :branch
  """
  @spec branch(t(), Yog.node_id(), Yog.node_id(), keyword()) :: t()
  def branch(%__MODULE__{} = map, parent, child, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @connect_schema)
    label = opts[:label]

    meta =
      opts
      |> Map.new()
      |> Map.put(:edge_type, :branch)
      |> Map.put(:label, label)

    edge_meta = Map.put(map.edge_meta, {parent, child}, meta)
    graph = Yog.add_edge_ensure(map.graph, parent, child, 1)

    %{map | graph: graph, edge_meta: edge_meta}
  end

  @doc """
  Creates an associative (cross-link) edge between two nodes.

  Associative edges are rendered as dashed lines without arrowheads,
  representing non-hierarchical relationships.

  ## Options

  #{NimbleOptions.docs(@connect_schema)}

  ## Examples

      iex> map = Choreo.MindMap.new()
      iex> map = map
      ...>   |> Choreo.MindMap.set_root(:a, label: "A")
      ...>   |> Choreo.MindMap.add_topic(:b, label: "B")
      ...>   |> Choreo.MindMap.add_topic(:c, label: "C")
      ...>   |> Choreo.MindMap.branch(:a, :b)
      ...>   |> Choreo.MindMap.branch(:a, :c)
      ...>   |> Choreo.MindMap.associate(:b, :c, label: "related")
      iex> map.edge_meta[{:b, :c}].edge_type
      :associates
      iex> map.edge_meta[{:b, :c}].label
      "related"
  """
  @spec associate(t(), Yog.node_id(), Yog.node_id(), keyword()) :: t()
  def associate(%__MODULE__{} = map, from, to, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @connect_schema)
    label = opts[:label]

    meta =
      opts
      |> Map.new()
      |> Map.put(:edge_type, :associates)
      |> Map.put(:label, label)

    edge_meta = Map.put(map.edge_meta, {from, to}, meta)
    graph = Yog.add_edge_ensure(map.graph, from, to, 1)

    %{map | graph: graph, edge_meta: edge_meta}
  end

  # ============================================================================
  # Queries
  # ============================================================================

  @doc """
  Returns the root node id, or `nil` if not set.

  ## Examples

      iex> map = Choreo.MindMap.new()
      iex> Choreo.MindMap.root(map)
      nil
      iex> map = Choreo.MindMap.set_root(map, :idea, label: "Idea")
      iex> Choreo.MindMap.root(map)
      :idea
  """
  @spec root(t()) :: Yog.node_id() | nil
  def root(%__MODULE__{root: root}), do: root

  @doc """
  Returns all node IDs in the mind map.

  ## Examples

      iex> map = Choreo.MindMap.new()
      iex> map = map
      ...>   |> Choreo.MindMap.set_root(:a, label: "A")
      ...>   |> Choreo.MindMap.add_topic(:b, label: "B")
      iex> Enum.sort(Choreo.MindMap.nodes(map))
      [:a, :b]
  """
  @spec nodes(t()) :: [Yog.node_id()]
  def nodes(%__MODULE__{graph: graph}) do
    Map.keys(graph.nodes)
  end

  @doc """
  Returns all edges as `{from, to, weight}` tuples.

  ## Examples

      iex> map = Choreo.MindMap.new()
      iex> map = map
      ...>   |> Choreo.MindMap.set_root(:a, label: "A")
      ...>   |> Choreo.MindMap.add_topic(:b, label: "B")
      ...>   |> Choreo.MindMap.branch(:a, :b)
      iex> Choreo.MindMap.edges(map)
      [{:a, :b, 1}]
  """
  @spec edges(t()) :: [{Yog.node_id(), Yog.node_id(), number()}]
  def edges(%__MODULE__{graph: graph}) do
    Yog.all_edges(graph)
  end

  @doc """
  Returns all topic node IDs.

  ## Examples

      iex> map = Choreo.MindMap.new()
      iex> map = map
      ...>   |> Choreo.MindMap.set_root(:a)
      ...>   |> Choreo.MindMap.add_topic(:b)
      ...>   |> Choreo.MindMap.add_subtopic(:c)
      iex> Choreo.MindMap.topics(map)
      [:b]
  """
  @spec topics(t()) :: [Yog.node_id()]
  def topics(%__MODULE__{graph: graph}) do
    graph.nodes
    |> Enum.filter(fn {_id, data} -> data[:node_type] == :topic end)
    |> Enum.map(fn {id, _data} -> id end)
  end

  @doc """
  Returns all subtopic node IDs.

  ## Examples

      iex> map = Choreo.MindMap.new()
      iex> map = map
      ...>   |> Choreo.MindMap.set_root(:a)
      ...>   |> Choreo.MindMap.add_topic(:b)
      ...>   |> Choreo.MindMap.add_subtopic(:c)
      iex> Choreo.MindMap.subtopics(map)
      [:c]
  """
  @spec subtopics(t()) :: [Yog.node_id()]
  def subtopics(%__MODULE__{graph: graph}) do
    graph.nodes
    |> Enum.filter(fn {_id, data} -> data[:node_type] == :subtopic end)
    |> Enum.map(fn {id, _data} -> id end)
  end

  @doc """
  Returns all note node IDs.

  ## Examples

      iex> map = Choreo.MindMap.new()
      iex> map = map
      ...>   |> Choreo.MindMap.set_root(:a)
      ...>   |> Choreo.MindMap.add_note(:n, label: "Note")
      iex> Choreo.MindMap.notes(map)
      [:n]
  """
  @spec notes(t()) :: [Yog.node_id()]
  def notes(%__MODULE__{graph: graph}) do
    graph.nodes
    |> Enum.filter(fn {_id, data} -> data[:node_type] == :note end)
    |> Enum.map(fn {id, _data} -> id end)
  end

  @doc """
  Returns the raw `Yog.Graph` struct underpinning the mind map.

  ## Examples

      iex> map = Choreo.MindMap.new()
      iex> graph = Choreo.MindMap.to_graph(map)
      iex> graph.kind
      :directed
  """
  @spec to_graph(t()) :: Yog.graph()
  def to_graph(%__MODULE__{graph: graph}), do: graph

  # ============================================================================
  # Rendering
  # ============================================================================

  @doc """
  Renders the mind map to DOT format.

  ## Options

    * `:theme` — `:default`, `:dark`, or a `Choreo.Theme` struct

  ## Examples

      iex> map = Choreo.MindMap.new()
      iex> map = map
      ...>   |> Choreo.MindMap.set_root(:a, label: "A")
      ...>   |> Choreo.MindMap.add_topic(:b, label: "B")
      ...>   |> Choreo.MindMap.branch(:a, :b)
      iex> dot = Choreo.MindMap.to_dot(map)
      iex> String.contains?(dot, "digraph")
      true
      iex> String.contains?(dot, "A")
      true
      iex> String.contains?(dot, "B")
      true
  """
  @spec to_dot(t(), keyword()) :: String.t()
  def to_dot(%__MODULE__{} = map, opts \\ []) do
    Choreo.MindMap.Render.DOT.to_dot(map, opts)
  end

  @doc """
  Renders the mind map to Mermaid.js flowchart or native mindmap syntax.

  ## Options

    * `:syntax` — `:flowchart` (default) or `:mindmap`
    * `:theme` — `:default`, `:dark`, `:warm`, `:forest`, `:ocean`, or a `Choreo.Theme` struct
    * `:direction` — `:td` (default), `:lr`, `:bt`, `:rl`

  ## Examples

      iex> map = Choreo.MindMap.new() |> Choreo.MindMap.set_root(:ideas, label: "Ideas")
      iex> mermaid = Choreo.MindMap.to_mermaid(map)
      iex> String.contains?(mermaid, "graph TD")
      true

      iex> map = Choreo.MindMap.new() |> Choreo.MindMap.set_root(:ideas, label: "Ideas")
      iex> native = Choreo.MindMap.to_mermaid(map, syntax: :mindmap)
      iex> String.contains?(native, "mindmap")
      true
      iex> String.contains?(native, "ideas((Ideas))")
      true
  """
  @spec to_mermaid(t(), keyword()) :: String.t()
  def to_mermaid(%__MODULE__{} = map, opts \\ []) do
    Choreo.MindMap.Render.Mermaid.to_mermaid(map, opts)
  end

  @doc """
  Returns a theme for `Choreo.MindMap`.

  ## Examples

      iex> theme = Choreo.MindMap.theme(:default, graph_rankdir: :lr)
      iex> theme.graph_rankdir
      :lr
  """
  @spec theme(atom(), keyword()) :: Choreo.Theme.t()
  def theme(name \\ :default, overrides \\ []) do
    Choreo.MindMap.Render.DOT.theme(name, overrides)
  end

  # ============================================================================
  # Private helpers
  # ============================================================================

  defp node_data(type, opts) do
    opts
    |> Map.new()
    |> Map.merge(%{
      type: :mind_map_node,
      node_type: type,
      label: Keyword.get(opts, :label, to_string(opts[:feature] || ""))
    })
  end
end

defimpl Choreo.DOT, for: Choreo.MindMap do
  def to_dot(map, opts), do: Choreo.MindMap.Render.DOT.to_dot(map, opts)
end

defimpl Choreo.Mermaid, for: Choreo.MindMap do
  def to_mermaid(map, opts), do: Choreo.MindMap.Render.Mermaid.to_mermaid(map, opts)
end

defimpl Choreo.Viewable, for: Choreo.MindMap do
  def rebuild(diagram, new_graph) do
    new_edge_meta =
      diagram.edge_meta
      |> Enum.filter(fn {{from, to}, _meta} ->
        Map.has_key?(new_graph.nodes, from) and Map.has_key?(new_graph.nodes, to)
      end)
      |> Map.new()

    # Add virtual edge metadata for any graph edges that lack it
    vmeta = virtual_edge_meta(diagram)

    new_edge_meta =
      new_graph
      |> Yog.all_edges()
      |> Enum.reduce(new_edge_meta, fn {from, to, _weight}, acc ->
        if Map.has_key?(acc, {from, to}) do
          acc
        else
          Map.put(acc, {from, to}, vmeta)
        end
      end)

    new_root =
      if Map.has_key?(new_graph.nodes, diagram.root) do
        diagram.root
      else
        new_graph.nodes
        |> Enum.sort_by(fn {id, data} ->
          # Prefer typed hierarchy first, then lowest in-degree (most upstream)
          {root_priority(data[:node_type]), Yog.in_degree(new_graph, id)}
        end)
        |> List.first()
        |> case do
          {id, _data} -> id
          nil -> nil
        end
      end

    %{diagram | graph: new_graph, edge_meta: new_edge_meta, root: new_root}
  end

  def zoom_predicate(_diagram, 0), do: fn data -> data[:node_type] == :root end
  def zoom_predicate(_diagram, 1), do: fn data -> data[:node_type] in [:root, :topic] end

  def zoom_predicate(_diagram, 2),
    do: fn data -> data[:node_type] in [:root, :topic, :subtopic] end

  def zoom_predicate(_diagram, _level), do: fn _data -> true end

  def virtual_edge_meta(_diagram), do: %{edge_type: :virtual, label: nil}

  defp root_priority(:root), do: 0
  defp root_priority(:topic), do: 1
  defp root_priority(:subtopic), do: 2
  defp root_priority(:note), do: 3
  defp root_priority(_), do: 99
end
