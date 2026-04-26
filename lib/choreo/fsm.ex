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

  Use `:default`, `:dark`, or a custom `Choreo.Theme` struct:

      dot = Choreo.FSM.to_dot(fsm, theme: :dark)
  """

  @type t :: %__MODULE__{
          graph: Yog.Multi.Graph.t(),
          edge_meta: %{optional(Yog.Multi.Graph.edge_id()) => map()},
          meta: map()
        }

  defstruct graph: nil, edge_meta: %{}, meta: %{}

  alias Choreo.FSM.Analysis

  # ============================================================================
  # Creation
  # ============================================================================

  @doc """
  Creates a new empty FSM.

  ## Options

    * `:directed` — whether the underlying graph is directed (default: `true`)

  ## Examples

      iex> fsm = Choreo.FSM.new()
      iex> fsm.graph.kind == :directed
      true
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    kind = if Keyword.get(opts, :directed, true), do: :directed, else: :undirected

    %__MODULE__{
      graph: Yog.Multi.new(kind),
      edge_meta: %{},
      meta: %{initial_state: nil, final_states: MapSet.new()}
    }
  end

  # ============================================================================
  # States
  # ============================================================================

  @doc """
  Adds a state to the FSM.

  ## Options

    * `:label` — display label (defaults to the state id)
    * `:type` — `:normal`, `:initial`, or `:final` (default: `:normal`)

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
    data = %{
      type: :state,
      label: Keyword.get(opts, :label, to_string(id))
    }

    fsm = %{fsm | graph: Yog.Multi.add_node(fsm.graph, id, data)}

    case Keyword.get(opts, :type) do
      :initial ->
        if fsm.meta.initial_state != nil do
          raise ArgumentError, "DFAs can only have one initial state"
        end

        put_in(fsm.meta.initial_state, id)

      :final ->
        put_in(fsm.meta.final_states, MapSet.put(fsm.meta.final_states, id))

      :normal ->
        fsm
        |> then(fn acc ->
          if acc.meta.initial_state == id, do: put_in(acc.meta.initial_state, nil), else: acc
        end)
        |> put_in([Access.key!(:meta), :final_states], MapSet.delete(fsm.meta.final_states, id))

      nil ->
        fsm
    end
  end

  @doc """
  Adds an initial state to the FSM.

  Initial states are rendered with a filled entry-point dot and an incoming
  arrow in DOT output.

  ## Options

    * `:label` — display label (defaults to the state id)

  ## Examples

      iex> fsm = Choreo.FSM.new() |> Choreo.FSM.add_initial_state(:idle)
      iex> :idle in Choreo.FSM.initial_states(fsm)
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
    if fsm.meta.initial_state != nil do
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

    * `:label` — display label (defaults to the state id)

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
    fsm
    |> add_state(id, opts)
    |> put_in([Access.key!(:meta), :final_states], MapSet.put(fsm.meta.final_states, id))
  end

  @doc """
  Removes a state from the set of initial states.

  ## Examples

      iex> fsm = Choreo.FSM.new() |> Choreo.FSM.add_initial_state(:idle) |> Choreo.FSM.remove_initial_state(:idle)
      iex> :idle in Choreo.FSM.initial_states(fsm)
      false
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

  # ============================================================================
  # Transitions
  # ============================================================================

  @doc """
  Adds a transition (directed edge) between two states.

  Multiple transitions are allowed per `(from, to)` pair (parallel edges),
  as long as they have unique labels from the source state.

  ## Options

    * `:label` — label shown on the transition arrow
    * `:guard` — guard condition (rendered alongside the label)

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
    label = build_transition_label(opts)

    # DFAs do not support epsilon transitions
    if label == "" do
      raise ArgumentError,
            "epsilon transitions (empty labels) are not supported in DFAs"
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
    parts =
      []
      |> then(&if label = opts[:label], do: [label | &1], else: &1)
      |> then(&if guard = opts[:guard], do: ["[#{guard}]" | &1], else: &1)

    case parts do
      [] -> ""
      list -> Enum.reverse(list) |> Enum.join(" ")
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
  Returns the set of initial state IDs.

  ## Examples

      iex> fsm = Choreo.FSM.new() |> Choreo.FSM.add_initial_state(:idle)
      iex> :idle in Choreo.FSM.initial_states(fsm)
      true
  """
  @spec initial_states(t()) :: MapSet.t(Yog.node_id())
  def initial_states(%__MODULE__{meta: %{initial_state: nil}}), do: MapSet.new()
  def initial_states(%__MODULE__{meta: %{initial_state: state}}), do: MapSet.new([state])
  def initial_states(%__MODULE__{}), do: MapSet.new()

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
  become final. Initial states keep their `:initial` type.

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

    * `:theme` — `:default`, `:dark`, or a `Choreo.Theme` struct

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
end
