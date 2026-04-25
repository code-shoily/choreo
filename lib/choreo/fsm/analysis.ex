defmodule Choreo.FSM.Analysis do
  @moduledoc """
  Analysis functions for `Choreo.FSM` state machines.

  Provides reachability, dead-state detection, determinism checks,
  and input-string acceptance simulation.
  """

  alias Choreo.FSM

  @doc """
  Returns all states reachable from any initial state.

  ## Examples

      fsm =
        Choreo.FSM.new()
        |> Choreo.FSM.add_initial_state(:a)
        |> Choreo.FSM.add_state(:b)
        |> Choreo.FSM.add_state(:c)
        |> Choreo.FSM.add_transition(:a, :b, label: "go")

      Choreo.FSM.Analysis.reachable_states(fsm)
      #=> [:a, :b]
  """
  @spec reachable_states(FSM.t()) :: [Yog.node_id()]
  def reachable_states(%FSM{} = fsm) do
    initials = FSM.initial_states(fsm) |> MapSet.to_list()

    if initials == [] do
      []
    else
      Choreo.Internal.bfs_reachable(fsm.graph, initials)
      |> MapSet.to_list()
    end
  end

  @doc """
  Returns states that have no path to any final state.

  A "dead state" (or trap state) is one from which an accepting state
  can never be reached. If the FSM has no final states, every state is
  considered dead.

  ## Examples

      fsm =
        Choreo.FSM.new()
        |> Choreo.FSM.add_initial_state(:a)
        |> Choreo.FSM.add_state(:b)
        |> Choreo.FSM.add_final_state(:c)
        |> Choreo.FSM.add_transition(:a, :b, label: "go")

      Choreo.FSM.Analysis.dead_states(fsm)
      #=> [:b]
  """
  @spec dead_states(FSM.t()) :: [Yog.node_id()]
  def dead_states(%FSM{} = fsm) do
    finals = FSM.final_states(fsm)
    all = FSM.states(fsm) |> MapSet.new()

    if finals == [] do
      MapSet.to_list(all)
    else
      transposed = Yog.transpose(fsm.graph)
      can_reach_final = Choreo.Internal.bfs_reachable(transposed, finals)
      MapSet.difference(all, can_reach_final) |> MapSet.to_list()
    end
  end

  @doc """
  Checks whether the FSM is deterministic.

  An FSM is deterministic when no state has two outgoing transitions
  with the same label. (Epsilon transitions are not supported.)

  ## Examples

      fsm =
        Choreo.FSM.new()
        |> Choreo.FSM.add_state(:a)
        |> Choreo.FSM.add_state(:b)
        |> Choreo.FSM.add_state(:c)
        |> Choreo.FSM.add_transition(:a, :b, label: "x")
        |> Choreo.FSM.add_transition(:a, :c, label: "x")

      Choreo.FSM.Analysis.deterministic?(fsm)
      #=> false
  """
  @spec deterministic?(FSM.t()) :: boolean()
  def deterministic?(%FSM{graph: graph}) do
    graph.nodes
    |> Map.keys()
    |> Enum.all?(fn id ->
      labels =
        Yog.successors(graph, id)
        |> Enum.map(fn {_to, label} -> label end)

      length(labels) == length(Enum.uniq(labels))
    end)
  end

  @doc """
  Simulates the FSM on a sequence of input symbols.

  Returns `true` if at least one path from an initial state leads to a
  final state after consuming all inputs. This works for both DFAs and
  NFAs.

  ## Examples

      fsm =
        Choreo.FSM.new()
        |> Choreo.FSM.add_initial_state(:idle)
        |> Choreo.FSM.add_state(:running)
        |> Choreo.FSM.add_final_state(:done)
        |> Choreo.FSM.add_transition(:idle, :running, label: "start")
        |> Choreo.FSM.add_transition(:running, :done, label: "finish")

      Choreo.FSM.Analysis.accepts?(fsm, ["start", "finish"])
      #=> true

      Choreo.FSM.Analysis.accepts?(fsm, ["start"])
      #=> false
  """
  @spec accepts?(FSM.t(), [String.t()]) :: boolean()
  def accepts?(%FSM{} = fsm, inputs) do
    initial = FSM.initial_states(fsm) |> MapSet.new()

    if MapSet.size(initial) == 0 do
      false
    else
      result =
        Enum.reduce_while(inputs, initial, fn input, current ->
          next =
            current
            |> Enum.flat_map(fn state ->
              fsm.graph
              |> Yog.successors(state)
              |> Enum.filter(fn {_to, label} -> label == input end)
              |> Enum.map(fn {to, _label} -> to end)
            end)
            |> MapSet.new()

          if MapSet.size(next) == 0 do
            {:halt, :dead}
          else
            {:cont, next}
          end
        end)

      case result do
        :dead ->
          false

        states ->
          final_set = FSM.final_states(fsm) |> MapSet.new()
          not MapSet.disjoint?(states, final_set)
      end
    end
  end

  @doc """
  Finds the shortest sequence of transition labels that leads from an
  initial state to a final state.

  Returns `{:ok, [String.t()]}` or `:error` if no accepting path exists.

  ## Examples

      fsm =
        Choreo.FSM.new()
        |> Choreo.FSM.add_initial_state(:a)
        |> Choreo.FSM.add_state(:b)
        |> Choreo.FSM.add_final_state(:c)
        |> Choreo.FSM.add_transition(:a, :b, label: "x")
        |> Choreo.FSM.add_transition(:b, :c, label: "y")

      Choreo.FSM.Analysis.shortest_accepting_path(fsm)
      #=> {:ok, ["x", "y"]}
  """
  @spec shortest_accepting_path(FSM.t()) :: {:ok, [String.t()]} | :error
  def shortest_accepting_path(%FSM{} = fsm) do
    initials = FSM.initial_states(fsm) |> MapSet.to_list()

    if initials == [] do
      :error
    else
      queue = Enum.map(initials, fn id -> {id, []} end)
      visited = MapSet.new(initials)
      bfs_path(fsm, queue, visited)
    end
  end

  @doc """
  Enumerates all accepted input strings up to a maximum length.

  This performs a breadth-first expansion of the state space and collects
  every path that ends in a final state. The result is deduplicated.

  **Warning:** Cyclic FSMs can produce exponentially many paths; keep
  `max_length` small.

  ## Examples

      fsm =
        Choreo.FSM.new()
        |> Choreo.FSM.add_initial_state(:a)
        |> Choreo.FSM.add_final_state(:b)
        |> Choreo.FSM.add_transition(:a, :b, label: "x")
        |> Choreo.FSM.add_transition(:b, :b, label: "y")

      Choreo.FSM.Analysis.accepted_strings(fsm, 2)
      #=> [["x"], ["x", "y"]]
  """
  @spec accepted_strings(FSM.t(), non_neg_integer()) :: [[String.t()]]
  def accepted_strings(%FSM{} = fsm, max_length) when max_length >= 0 do
    initials = FSM.initial_states(fsm) |> MapSet.to_list()

    if initials == [] do
      []
    else
      queue = Enum.map(initials, fn id -> {id, []} end)

      do_accepted_strings(fsm, queue, max_length, 0, [])
      |> Enum.reverse()
      |> Enum.uniq()
    end
  end

  # ============================================================================
  # Private helpers
  # ============================================================================

  defp bfs_path(_fsm, [], _visited), do: :error

  defp bfs_path(fsm, [{state, path} | rest], visited) do
    if state in FSM.final_states(fsm) do
      {:ok, Enum.reverse(path)}
    else
      new_items =
        Yog.successors(fsm.graph, state)
        |> Enum.reject(fn {to, _label} -> MapSet.member?(visited, to) end)
        |> Enum.map(fn {to, label} -> {to, [label | path]} end)

      new_visited = Enum.reduce(new_items, visited, fn {to, _}, acc -> MapSet.put(acc, to) end)
      bfs_path(fsm, rest ++ new_items, new_visited)
    end
  end

  defp do_accepted_strings(_fsm, _queue, max_length, current_length, acc)
       when current_length > max_length do
    acc
  end

  defp do_accepted_strings(fsm, queue, max_length, current_length, acc) do
    accepted =
      queue
      |> Enum.filter(fn {state, _path} -> state in FSM.final_states(fsm) end)
      |> Enum.map(fn {_state, path} -> Enum.reverse(path) end)

    new_acc = Enum.reduce(accepted, acc, &[&1 | &2])

    if current_length == max_length do
      new_acc
    else
      next_queue =
        queue
        |> Enum.flat_map(fn {state, path} ->
          Yog.successors(fsm.graph, state)
          |> Enum.map(fn {to, label} -> {to, [label | path]} end)
        end)

      do_accepted_strings(fsm, next_queue, max_length, current_length + 1, new_acc)
    end
  end
end
