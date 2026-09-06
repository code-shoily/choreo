defmodule Choreo.FSM do
  @moduledoc """
  Finite-state machine builder on top of Yog.

  `Choreo.FSM` lets you define states, transitions, and render classic
  state-machine diagrams. It supports normal states, initial states, and
  final (accepting) states.

  ## When to use

  Use `Choreo.FSM` when modelling stateful behaviour — protocol handlers,
  UI flows, game states, or embedded-system controllers. It verifies
  determinism, finds dead states, and checks whether any input sequence
  leads to acceptance.

  ## Further reading

    * [Finite-state machine (Wikipedia)](https://en.wikipedia.org/wiki/Finite-state_machine)
    * [Automata Theory (Sipser)](https://math.mit.edu/~sipser/book.html)
    * [UML State Machine Diagrams](https://www.uml-diagrams.org/state-machine-diagrams.html)

  ## Quick Start

      fsm =
        Choreo.FSM.new()
        |> Choreo.FSM.add_initial_state(:idle, label: "Idle")
        |> Choreo.FSM.add_state(:running, label: "Running")
        |> Choreo.FSM.add_final_state(:done, label: "Done")
        |> Choreo.FSM.add_transition(:idle, :running, label: "start")
        |> Choreo.FSM.add_transition(:running, :done, label: "finish")
        |> Choreo.FSM.add_transition(:running, :idle, label: "pause")

      dot = Choreo.FSM.to_dot(fsm)
      mermaid = Choreo.FSM.to_mermaid(fsm)

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=LR, splines=spline, nodesep=0.5, ranksep=1.0];
      node [shape=circle, style=filled, fillcolor="#e2e8f0", fontname="Helvetica", fontsize=12, fontcolor="#1e293b"];
      edge [arrowhead=normal, color="#475569", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];

      running [label="Running", fillcolor="#e2e8f0"];
      idle [label="Idle", fontcolor="white", fillcolor="#10b981"];
      done [label="Done", penwidth="2.0", fillcolor="#e2e8f0", shape="doublecircle"];

      running -> idle [label="pause"];
      running -> done [label="finish"];
      idle -> running [label="start"];

      __start_idle [shape=point, width=0.15, height=0.15, style=filled, fillcolor=black];
      __start_idle -> idle;
    }
  </div>

  ## Themes

  Use any built-in theme (`:default`, `:dark`, `:minimal`, `:warm`, `:forest`, `:ocean`) or a custom `Choreo.Theme` struct:

      dot = Choreo.FSM.to_dot(fsm, theme: :dark)
      mermaid = Choreo.FSM.to_mermaid(fsm, theme: :dark)
  """

  @type t :: %__MODULE__{
          graph: Yog.Multi.Graph.t(),
          edge_meta: %{optional(Yog.Multi.Graph.edge_id()) => map()},
          meta: %{
            initial_state: Yog.node_id() | nil,
            final_states: MapSet.t(Yog.node_id()),
            strict: boolean()
          }
        }

  defstruct graph: nil, edge_meta: %{}, meta: %{}

  @new_schema [
    directed: [
      type: :boolean,
      required: false,
      default: true
    ],
    strict: [
      type: :boolean,
      required: false,
      default: false
    ]
  ]

  @node_schema [
    label: [
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

  @add_state_schema [
                      type: [
                        type: {:in, [:normal, :initial, :final]},
                        required: false
                      ]
                    ] ++ @node_schema

  @add_initial_state_schema @node_schema
  @add_final_state_schema @node_schema

  @add_transition_schema [
    label: [
      type: :string,
      required: false
    ],
    guard: [
      type: :string,
      required: false
    ]
  ]

  alias Choreo.FSM.Analysis

  # ============================================================================
  # Creation
  # ============================================================================

  @doc """
  Creates a new empty FSM.

  ## Options

    * `:directed` — whether the underlying graph is directed (default: `true`)
    * `:strict` — if true, raises on transition definitions with non-existent states (default: `false`)

  ## Examples

      iex> fsm = Choreo.FSM.new()
      iex> fsm.graph.kind == :directed
      true
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    opts = NimbleOptions.validate!(opts, @new_schema)
    kind = if opts[:directed], do: :directed, else: :undirected

    %__MODULE__{
      graph: Yog.Multi.new(kind),
      edge_meta: %{},
      meta: %{initial_state: nil, final_states: MapSet.new(), strict: opts[:strict]}
    }
  end

  # ============================================================================
  # States
  # ============================================================================

  @doc """
  Adds a state to the FSM.

  ## Options

  #{NimbleOptions.docs(@add_state_schema)}

  ## Examples

      iex> fsm = Choreo.FSM.new() |> Choreo.FSM.add_state(:idle, label: "Idle")
      iex> fsm.graph.nodes[:idle].label
      "Idle"

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=LR, splines=spline, nodesep=0.5, ranksep=1.0];
      node [shape=circle, style=filled, fillcolor="#e2e8f0", fontname="Helvetica", fontsize=12, fontcolor="#1e293b"];
      edge [arrowhead=normal, color="#475569", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];

      idle [label="Idle", fillcolor="#e2e8f0"];
    }
  </div>
  """
  @spec add_state(t(), Yog.node_id(), keyword()) :: t()
  def add_state(%__MODULE__{} = fsm, id, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @add_state_schema)
    type = Keyword.get(opts, :type)

    if type == :initial and fsm.meta.initial_state != nil and fsm.meta.initial_state != id do
      raise ArgumentError, "DFAs can only have one initial state"
    end

    data =
      opts
      |> Map.new()
      |> Map.merge(%{
        type: :state,
        label: Keyword.get(opts, :label, to_string(id))
      })

    fsm = %{fsm | graph: Yog.Multi.add_node(fsm.graph, id, data)}

    case type do
      :initial ->
        put_in(fsm.meta.initial_state, id)

      :final ->
        put_in(fsm.meta.final_states, MapSet.put(fsm.meta.final_states, id))

      :normal ->
        fsm
        |> remove_initial_state(id)
        |> remove_final_state(id)

      nil ->
        fsm
    end
  end

  @doc """
  Adds an initial state to the FSM.

  Initial states are rendered with a filled entry-point dot and an incoming
  arrow in DOT output.

  ## Options

  #{NimbleOptions.docs(@add_initial_state_schema)}

  ## Examples

      iex> fsm = Choreo.FSM.new() |> Choreo.FSM.add_initial_state(:idle)
      iex> Choreo.FSM.initial_state(fsm) == :idle
      true

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=LR, splines=spline, nodesep=0.5, ranksep=1.0];
      node [shape=circle, style=filled, fillcolor="#e2e8f0", fontname="Helvetica", fontsize=12, fontcolor="#1e293b"];
      edge [arrowhead=normal, color="#475569", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];

      idle [label="idle", fontcolor="white", fillcolor="#10b981"];

      __start_idle [shape=point, width=0.15, height=0.15, style=filled, fillcolor=black];
      __start_idle -> idle;
    }
  </div>
  """
  @spec add_initial_state(t(), Yog.node_id(), keyword()) :: t()
  def add_initial_state(%__MODULE__{} = fsm, id, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @add_initial_state_schema)

    if fsm.meta.initial_state != nil and fsm.meta.initial_state != id do
      raise ArgumentError, "DFAs can only have one initial state"
    end

    fsm
    |> add_state(id, opts)
    |> put_in([Access.key!(:meta), :initial_state], id)
  end

  @doc """
  Adds a final (accepting) state to the FSM.

  Final states are rendered as double circles.

  ## Options

  #{NimbleOptions.docs(@add_final_state_schema)}

  ## Examples

      iex> fsm = Choreo.FSM.new() |> Choreo.FSM.add_final_state(:done)
      iex> :done in Choreo.FSM.final_states(fsm)
      true

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=LR, splines=spline, nodesep=0.5, ranksep=1.0];
      node [shape=circle, style=filled, fillcolor="#e2e8f0", fontname="Helvetica", fontsize=12, fontcolor="#1e293b"];
      edge [arrowhead=normal, color="#475569", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];

      done [label="done", penwidth="2.0", fillcolor="#e2e8f0", shape="doublecircle"];
    }
  </div>
  """
  @spec add_final_state(t(), Yog.node_id(), keyword()) :: t()
  def add_final_state(%__MODULE__{} = fsm, id, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @add_final_state_schema)

    fsm
    |> add_state(id, opts)
    |> put_in([Access.key!(:meta), :final_states], MapSet.put(fsm.meta.final_states, id))
  end

  @doc """
  Removes a state from the set of initial states.

  ## Examples

      iex> fsm = Choreo.FSM.new() |> Choreo.FSM.add_initial_state(:idle) |> Choreo.FSM.remove_initial_state(:idle)
      iex> Choreo.FSM.initial_state(fsm)
      nil
  """
  @spec remove_initial_state(t(), Yog.node_id()) :: t()
  def remove_initial_state(%__MODULE__{} = fsm, id) do
    if fsm.meta.initial_state == id do
      put_in(fsm.meta.initial_state, nil)
    else
      fsm
    end
  end

  @doc """
  Removes a state from the set of final states.

  ## Examples

      iex> fsm = Choreo.FSM.new() |> Choreo.FSM.add_final_state(:done) |> Choreo.FSM.remove_final_state(:done)
      iex> :done in Choreo.FSM.final_states(fsm)
      false
  """
  @spec remove_final_state(t(), Yog.node_id()) :: t()
  def remove_final_state(%__MODULE__{} = fsm, id) do
    put_in(fsm.meta.final_states, MapSet.delete(fsm.meta.final_states, id))
  end

  @doc """
  Fully removes a state and all transitions involving it from the FSM.

  If the state was the initial state, the initial state is cleared.
  If the state was a final state, it is removed from the final states set.
  If the state does not exist, the FSM is returned unchanged.

  ## Examples

      iex> fsm =
      ...>   Choreo.FSM.new()
      ...>   |> Choreo.FSM.add_state(:a)
      ...>   |> Choreo.FSM.add_state(:b)
      ...>   |> Choreo.FSM.remove_state(:a)
      iex> :a in Choreo.FSM.states(fsm)
      false
      iex> :b in Choreo.FSM.states(fsm)
      true
  """
  @spec remove_state(t(), Yog.node_id()) :: t()
  def remove_state(%__MODULE__{} = fsm, id) do
    if Map.has_key?(fsm.graph.nodes, id) do
      removed_edge_ids =
        fsm.graph.edges
        |> Enum.filter(fn {_eid, {from, to, _data}} -> from == id or to == id end)
        |> Enum.map(fn {eid, _} -> eid end)

      new_graph = Yog.Multi.remove_node(fsm.graph, id)
      new_edge_meta = Map.drop(fsm.edge_meta, removed_edge_ids)

      new_meta = %{
        fsm.meta
        | initial_state: if(fsm.meta.initial_state == id, do: nil, else: fsm.meta.initial_state),
          final_states: MapSet.delete(fsm.meta.final_states, id)
      }

      %__MODULE__{fsm | graph: new_graph, edge_meta: new_edge_meta, meta: new_meta}
    else
      fsm
    end
  end

  # ============================================================================
  # Transitions
  # ============================================================================

  @doc """
  Adds a transition (directed edge) between two states.

  Multiple transitions are allowed per `(from, to)` pair (parallel edges),
  as long as they have unique labels from the source state.

  Guards are rendered as part of the transition label and therefore participate
  in analysis as transition symbols. Choreo stores guard text for rendering and
  inspection; it does not evaluate guard expressions.

  ## Options

  #{NimbleOptions.docs(@add_transition_schema)}

  ## Examples

      iex> fsm =
      ...>   Choreo.FSM.new()
      ...>   |> Choreo.FSM.add_state(:a)
      ...>   |> Choreo.FSM.add_state(:b)
      ...>   |> Choreo.FSM.add_transition(:a, :b, label: "go")
      iex> Yog.Multi.edges_between(fsm.graph, :a, :b) != []
      true

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=LR, splines=spline, nodesep=0.5, ranksep=1.0];
      node [shape=circle, style=filled, fillcolor="#e2e8f0", fontname="Helvetica", fontsize=12, fontcolor="#1e293b"];
      edge [arrowhead=normal, color="#475569", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];

      b [label="b", fillcolor="#e2e8f0"];
      a [label="a", fillcolor="#e2e8f0"];

      a -> b [label="go"];
    }
  </div>
  """
  @spec add_transition(t(), Yog.node_id(), Yog.node_id(), keyword()) :: t()
  def add_transition(%__MODULE__{} = fsm, from, to, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @add_transition_schema)
    label = build_transition_label(opts)

    validate_transition_label!(opts, label)

    # Check strict mode
    if fsm.meta.strict do
      if not Map.has_key?(fsm.graph.nodes, from) do
        raise ArgumentError, "source state #{inspect(from)} does not exist in strict mode"
      end

      if not Map.has_key?(fsm.graph.nodes, to) do
        raise ArgumentError, "target state #{inspect(to)} does not exist in strict mode"
      end
    end

    fsm =
      if Map.has_key?(fsm.graph.nodes, from) do
        fsm
      else
        add_state(fsm, from, type: :normal)
      end

    fsm =
      if Map.has_key?(fsm.graph.nodes, to) do
        fsm
      else
        add_state(fsm, to, type: :normal)
      end

    existing = Yog.Multi.successors(fsm.graph, from)

    existing_labels = Enum.map(existing, fn {_dest, _eid, lbl} -> lbl end)

    if label in existing_labels do
      raise ArgumentError,
            "duplicate transition label #{inspect(label)} from state #{inspect(from)}"
    end

    {graph, edge_id} = Yog.Multi.add_edge(fsm.graph, from, to, label)
    edge_meta = Map.put(fsm.edge_meta, edge_id, %{label: label, guard: opts[:guard]})

    %{fsm | graph: graph, edge_meta: edge_meta}
  end

  defp build_transition_label(opts) do
    [opts[:label], opts[:guard] && "[#{opts[:guard]}]"]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp validate_transition_label!(opts, label) do
    cond do
      is_nil(opts[:label]) and is_nil(opts[:guard]) ->
        raise ArgumentError, "missing transition :label option"

      label == "" ->
        raise ArgumentError,
              "epsilon transitions (empty labels) are not supported in DFAs"

      true ->
        :ok
    end
  end

  # ============================================================================
  # Queries
  # ============================================================================

  @doc """
  Returns all state IDs in the FSM.

  ## Examples

      iex> fsm = Choreo.FSM.new() |> Choreo.FSM.add_state(:a) |> Choreo.FSM.add_state(:b)
      iex> Enum.sort(Choreo.FSM.states(fsm))
      [:a, :b]
  """
  @spec states(t()) :: [Yog.node_id()]
  def states(%__MODULE__{graph: graph}) do
    Map.keys(graph.nodes)
  end

  @doc """
  Returns all transitions as `{from, to, label}` tuples.

  ## Examples

      iex> fsm =
      ...>   Choreo.FSM.new()
      ...>   |> Choreo.FSM.add_state(:a)
      ...>   |> Choreo.FSM.add_state(:b)
      ...>   |> Choreo.FSM.add_transition(:a, :b, label: "go")
      iex> Choreo.FSM.transitions(fsm)
      [{:a, :b, "go"}]
  """
  @spec transitions(t()) :: [{Yog.node_id(), Yog.node_id(), String.t()}]
  def transitions(%__MODULE__{graph: graph}) do
    Enum.map(graph.edges, fn {_edge_id, {from, to, label}} ->
      {from, to, label}
    end)
  end

  @doc """
  Returns the initial state ID, or `nil` if none is defined.

  ## Examples

      iex> fsm = Choreo.FSM.new() |> Choreo.FSM.add_initial_state(:idle)
      iex> Choreo.FSM.initial_state(fsm)
      :idle
  """
  @spec initial_state(t()) :: Yog.node_id() | nil
  def initial_state(%__MODULE__{meta: %{initial_state: state}}), do: state
  def initial_state(%__MODULE__{}), do: nil

  @doc """
  Returns all final state IDs.

  ## Examples

      iex> fsm = Choreo.FSM.new() |> Choreo.FSM.add_final_state(:done)
      iex> :done in Choreo.FSM.final_states(fsm)
      true
  """
  @spec final_states(t()) :: [Yog.node_id()]
  def final_states(%__MODULE__{meta: %{final_states: set}}), do: MapSet.to_list(set)
  def final_states(%__MODULE__{}), do: []

  # ============================================================================
  # Transforms
  # ============================================================================

  @doc """
  Returns the complement FSM: final states become normal, and normal states
  become final.

  Initial states keep their `:initial` type. Note that if the initial state
  was not previously final, it becomes both initial and final in the
  complement FSM (which is mathematically correct to accept the empty string).

  This operation assumes a complete DFA for strict language-complement semantics.
  If the FSM is incomplete, missing transitions still reject during simulation;
  `complement/1` does not add an implicit sink state.

  ## Examples

      iex> fsm =
      ...>   Choreo.FSM.new()
      ...>   |> Choreo.FSM.add_initial_state(:a)
      ...>   |> Choreo.FSM.add_final_state(:b)
      iex> comp = Choreo.FSM.complement(fsm)
      iex> :a in Choreo.FSM.final_states(comp)
      true
      iex> :b in Choreo.FSM.final_states(comp)
      false

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=LR, splines=spline, nodesep=0.5, ranksep=1.0];
      node [shape=circle, style=filled, fillcolor="#e2e8f0", fontname="Helvetica", fontsize=12, fontcolor="#1e293b"];
      edge [arrowhead=normal, color="#475569", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];

      b [label="b", fillcolor="#e2e8f0"];
      a [label="a", penwidth="2.0", fontcolor="white", fillcolor="#10b981", shape="doublecircle"];

      __start_a [shape=point, width=0.15, height=0.15, style=filled, fillcolor=black];
      __start_a -> a;
    }
  </div>
  """
  @spec complement(t()) :: t()
  def complement(%__MODULE__{} = fsm) do
    all_states = states(fsm) |> MapSet.new()
    old_finals = final_states(fsm) |> MapSet.new()
    new_finals = MapSet.difference(all_states, old_finals)

    put_in(fsm.meta.final_states, new_finals)
  end

  @doc """
  Prunes unreachable and dead states, returning a smaller equivalent FSM.

  * Unreachable states — no path from any initial state
  * Dead states — no path to any final state

  ## Examples

      iex> fsm =
      ...>   Choreo.FSM.new()
      ...>   |> Choreo.FSM.add_initial_state(:a)
      ...>   |> Choreo.FSM.add_state(:b)
      ...>   |> Choreo.FSM.add_state(:trap)
      ...>   |> Choreo.FSM.add_final_state(:c)
      ...>   |> Choreo.FSM.add_transition(:a, :c, label: "go")
      iex> pruned = Choreo.FSM.prune(fsm)
      iex> :a in Choreo.FSM.states(pruned)
      true
      iex> :b in Choreo.FSM.states(pruned)
      false
      iex> :trap in Choreo.FSM.states(pruned)
      false

  ## Diagram

  <div class="graphviz">
    digraph G {
      graph [rankdir=LR, splines=spline, nodesep=0.5, ranksep=1.0];
      node [shape=circle, style=filled, fillcolor="#e2e8f0", fontname="Helvetica", fontsize=12, fontcolor="#1e293b"];
      edge [arrowhead=normal, color="#475569", style=solid, fontname="Helvetica", fontsize=10, penwidth=1.0];

      c [label="c", penwidth="2.0", fillcolor="#e2e8f0", shape="doublecircle"];
      a [label="a", fontcolor="white", fillcolor="#10b981"];

      a -> c [label="go"];

      __start_a [shape=point, width=0.15, height=0.15, style=filled, fillcolor=black];
      __start_a -> a;
    }
  </div>
  """
  @spec prune(t()) :: t()
  def prune(%__MODULE__{} = fsm) do
    reachable = Analysis.reachable_states(fsm) |> MapSet.new()
    dead = Analysis.dead_states(fsm) |> MapSet.new()
    all = states(fsm) |> MapSet.new()

    to_remove = MapSet.union(dead, MapSet.difference(all, reachable))

    removed_edge_ids =
      fsm.graph.edges
      |> Enum.filter(fn {_eid, {from, to, _data}} ->
        from in to_remove or to in to_remove
      end)
      |> Enum.map(fn {eid, _} -> eid end)

    new_graph = Enum.reduce(to_remove, fsm.graph, &Yog.Multi.remove_node(&2, &1))

    new_edge_meta = Map.drop(fsm.edge_meta, removed_edge_ids)

    new_meta = %{
      fsm.meta
      | initial_state:
          if(fsm.meta.initial_state in to_remove, do: nil, else: fsm.meta.initial_state),
        final_states: MapSet.difference(fsm.meta.final_states, to_remove)
    }

    %__MODULE__{fsm | graph: new_graph, edge_meta: new_edge_meta, meta: new_meta}
  end

  # ============================================================================
  # Rendering
  # ============================================================================

  @doc """
  Renders the FSM to DOT format.

  ## Options

    * `:theme` — `:default`, `:dark`, `:minimal`, `:warm`, `:forest`, `:ocean`, or a `Choreo.Theme` struct
    * `:highlighted_nodes` — list of state IDs to highlight
    * `:highlighted_edges` — list of edge IDs or `{from, to}` tuples to highlight
    * Any other option accepted by `Yog.Multi.DOT.to_dot/2`, such as `:rankdir`

  ## Examples

      iex> fsm = Choreo.FSM.new() |> Choreo.FSM.add_state(:a)
      iex> dot = Choreo.FSM.to_dot(fsm)
      iex> String.contains?(dot, "digraph")
      true
      iex> String.contains?(dot, "a")
      true
  """
  @spec to_dot(t(), keyword()) :: String.t()
  def to_dot(%__MODULE__{} = fsm, opts \\ []) do
    Choreo.FSM.Render.DOT.to_dot(fsm, opts)
  end

  @doc """
  Renders the FSM to Mermaid.js syntax.

  The default output is flowchart syntax. Pass `syntax: :state_diagram` to render
  native Mermaid `stateDiagram-v2` syntax.

  ## Options

    * `:syntax` — `:flowchart` (default) or `:state_diagram`
    * `:theme` — `:default`, `:dark`, `:minimal`, `:warm`, `:forest`, `:ocean`, or a `Choreo.Theme` struct (for `:flowchart` syntax)
    * `:direction` — `:lr` (default), `:td`, `:rl`, `:bt` (for `:flowchart` syntax)
    * `:highlighted_nodes` — list of state IDs to highlight (for `:flowchart` syntax)
    * `:highlighted_edges` — list of edge IDs or `{from, to}` tuples to highlight (for `:flowchart` syntax)

  ## Examples

      iex> fsm = Choreo.FSM.new() |> Choreo.FSM.add_state(:a)
      iex> mermaid = Choreo.FSM.to_mermaid(fsm)
      iex> String.contains?(mermaid, "graph LR")
      true
      iex> String.contains?(mermaid, "a")
      true
  """
  @spec to_mermaid(t(), keyword()) :: String.t()
  def to_mermaid(%__MODULE__{} = fsm, opts \\ []) do
    Choreo.FSM.Render.Mermaid.to_mermaid(fsm, opts)
  end

  @doc """
  Returns a theme for `Choreo.FSM`.

  ## Examples

      iex> theme = Choreo.FSM.theme(:default, graph_rankdir: :tb)
      iex> theme.graph_rankdir
      :tb
  """
  @spec theme(atom(), keyword()) :: Choreo.Theme.t()
  def theme(name \\ :default, overrides \\ []) do
    Choreo.FSM.Render.DOT.theme(name, overrides)
  end

  @doc """
  Converts the multigraph to a simple graph.
  """
  @spec to_simple_graph(t(), keyword()) :: Yog.Graph.t()
  def to_simple_graph(%__MODULE__{graph: graph}, opts \\ []) do
    combine = Keyword.get(opts, :combine, fn _k, v1, _v2 -> v1 end)
    Yog.Multi.to_simple_graph(graph, combine)
  end
end

defimpl Choreo.DOT, for: Choreo.FSM do
  def to_dot(fsm, opts), do: Choreo.FSM.Render.DOT.to_dot(fsm, opts)
end

defimpl Choreo.Mermaid, for: Choreo.FSM do
  def to_mermaid(fsm, opts), do: Choreo.FSM.Render.Mermaid.to_mermaid(fsm, opts)
end
