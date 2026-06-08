defmodule Choreo.FSM.Analysis do
  @moduledoc """
  Analysis functions for `Choreo.FSM` state machines.

  Provides reachability, dead-state detection, determinism checks,
  completeness verification, and input-string acceptance simulation.

  ## Function overview

  | Function | Question |
  |----------|----------|
  | `reachable_states/1` | Which states can I reach from the start? |
  | `dead_states/1` | Which states are traps (can never accept)? |
  | `livelock_states/1` | Which reachable states can get stuck in a loop forever? |
  | `alphabet/1` | What are the distinct input symbols? |
  | `complete?/1` | Does every state handle every input? |
  | `accepts?/2` | Does input X lead to acceptance? |
  | `shortest_accepting_path/1` | What’s the minimum input to accept? |
  | `accepted_strings/2` | What inputs are accepted up to length N? |
  | `validate/1` | Are there structural issues? |

  ## Further reading

    * [Finite-state machine (Wikipedia)](https://en.wikipedia.org/wiki/Finite-state_machine)
    * [DFA vs NFA (Sipser, Ch. 1)](https://math.mit.edu/~sipser/book.html)
    * [Hopcroft’s Algorithm for DFA Minimization](https://en.wikipedia.org/wiki/DFA_minimization)
  """

  alias Choreo.FSM

  @doc """
    Returns all states reachable from any initial state.

    ## Examples

        iex> fsm =
        ...>   Choreo.FSM.new()
        ...>   |> Choreo.FSM.add_initial_state(:a)
        ...>   |> Choreo.FSM.add_state(:b)
        ...>   |> Choreo.FSM.add_state(:c)
        ...>   |> Choreo.FSM.add_transition(:a, :b, label: "go")
        iex> Enum.sort(Choreo.FSM.Analysis.reachable_states(fsm))
        [:a, :b]

    This analysis answers the question: "Which states can I reach from the start?"
  """
  @spec reachable_states(FSM.t()) :: [Yog.node_id()]
  def reachable_states(%FSM{} = fsm) do
    case FSM.initial_state(fsm) do
      nil ->
        []

      initial ->
        bfs_reachable_multi(fsm.graph, [initial])
        |> MapSet.to_list()
    end
  end

  @doc """
    Returns states that have no path to any final state.

    A "dead state" (or trap state) is one from which an accepting state
    can never be reached. If the FSM has no final states, every state is
    considered dead.

    ## Examples

        iex> fsm =
        ...>   Choreo.FSM.new()
        ...>   |> Choreo.FSM.add_initial_state(:a)
        ...>   |> Choreo.FSM.add_state(:b)
        ...>   |> Choreo.FSM.add_final_state(:c)
        ...>   |> Choreo.FSM.add_transition(:a, :b, label: "go")
        ...>   |> Choreo.FSM.add_transition(:a, :c, label: "ok")
        iex> Choreo.FSM.Analysis.dead_states(fsm)
        [:b]

    This analysis answers the question: "Which states are traps that can never accept?"
  """
  @spec dead_states(FSM.t()) :: [Yog.node_id()]
  def dead_states(%FSM{} = fsm) do
    finals = FSM.final_states(fsm)
    all = FSM.states(fsm) |> MapSet.new()

    if finals == [] do
      MapSet.to_list(all)
    else
      predecessors = build_predecessors(fsm.graph)
      can_reach_final = bfs_reachable_reverse(predecessors, finals)
      MapSet.difference(all, can_reach_final) |> MapSet.to_list()
    end
  end

  @doc """
    Returns all reachable states that are part of a cycle of dead states (livelock).

    A state is in a livelock when it is reachable from the start, has no path
    to any final/accepting state, and is part of a cycle (can reach itself).

    ## Examples

        iex> fsm =
        ...>   Choreo.FSM.new()
        ...>   |> Choreo.FSM.add_initial_state(:start)
        ...>   |> Choreo.FSM.add_final_state(:ok)
        ...>   |> Choreo.FSM.add_state(:l1)
        ...>   |> Choreo.FSM.add_state(:l2)
        ...>   |> Choreo.FSM.add_transition(:start, :ok, label: "yes")
        ...>   |> Choreo.FSM.add_transition(:start, :l1, label: "fail")
        ...>   |> Choreo.FSM.add_transition(:l1, :l2, label: "loop")
        ...>   |> Choreo.FSM.add_transition(:l2, :l1, label: "back")
        ...>   |> Choreo.FSM.add_state(:dead_end)
        ...>   |> Choreo.FSM.add_transition(:start, :dead_end, label: "trap")
        iex> Enum.sort(Choreo.FSM.Analysis.livelock_states(fsm))
        [:l1, :l2]

    This analysis answers the question: "Which states can get trapped in infinite non-accepting loops?"
  """
  @spec livelock_states(FSM.t()) :: [Yog.node_id()]
  def livelock_states(%FSM{} = fsm) do
    reachable = MapSet.new(reachable_states(fsm))
    dead = MapSet.new(dead_states(fsm))
    livelock_states(fsm, reachable, dead)
  end

  @doc false
  @spec livelock_states(FSM.t(), MapSet.t(Yog.node_id()), MapSet.t(Yog.node_id())) :: [
          Yog.node_id()
        ]
  def livelock_states(%FSM{} = fsm, reachable, dead) do
    reachable_dead = MapSet.intersection(reachable, dead)

    reachable_dead
    |> Enum.filter(fn state ->
      successors = Yog.Multi.successors(fsm.graph, state) |> Enum.map(fn {to, _, _} -> to end)
      bfs_reaches_self?(fsm.graph, successors, state, MapSet.new(successors))
    end)
    |> Enum.sort()
  end

  defp bfs_reaches_self?(_graph, [], _target, _visited), do: false

  defp bfs_reaches_self?(graph, [h | t], target, visited) do
    if h == target do
      true
    else
      neighbors =
        graph
        |> Yog.Multi.successors(h)
        |> Enum.map(fn {to, _, _} -> to end)
        |> Enum.reject(&MapSet.member?(visited, &1))

      bfs_reaches_self?(
        graph,
        t ++ neighbors,
        target,
        MapSet.union(visited, MapSet.new(neighbors))
      )
    end
  end

  @doc """
    Simulates the FSM on a sequence of input symbols.

    Returns `true` if the unique path from the initial state leads to a
    final state after consuming all inputs.

    ## Examples

        iex> fsm =
        ...>   Choreo.FSM.new()
        ...>   |> Choreo.FSM.add_initial_state(:idle)
        ...>   |> Choreo.FSM.add_state(:running)
        ...>   |> Choreo.FSM.add_final_state(:done)
        ...>   |> Choreo.FSM.add_transition(:idle, :running, label: "start")
        ...>   |> Choreo.FSM.add_transition(:running, :done, label: "finish")
        iex> Choreo.FSM.Analysis.accepts?(fsm, ["start", "finish"])
        true
        iex> Choreo.FSM.Analysis.accepts?(fsm, ["start"])
        false

    This analysis answers the question: "Does this input sequence lead to acceptance?"
  """
  @spec accepts?(FSM.t(), [String.t()]) :: boolean()
  def accepts?(%FSM{} = fsm, inputs) do
    case FSM.initial_state(fsm) do
      nil ->
        false

      initial ->
        result =
          Enum.reduce_while(inputs, initial, fn input, current ->
            case find_next(fsm.graph, current, input) do
              nil -> {:halt, :dead}
              next -> {:cont, next}
            end
          end)

        case result do
          :dead -> false
          state -> state in FSM.final_states(fsm)
        end
    end
  end

  defp find_next(graph, state, input) do
    graph
    |> Yog.Multi.successors(state)
    |> Enum.find(fn {_to, _edge_id, label} -> label == input end)
    |> case do
      nil -> nil
      {to, _edge_id, _label} -> to
    end
  end

  @doc """
    Finds the shortest sequence of transition labels that leads from an
    initial state to a final state.

    Returns `{:ok, [String.t()]}` or `:error` if no accepting path exists.

    ## Examples

        iex> fsm =
        ...>   Choreo.FSM.new()
        ...>   |> Choreo.FSM.add_initial_state(:a)
        ...>   |> Choreo.FSM.add_state(:b)
        ...>   |> Choreo.FSM.add_final_state(:c)
        ...>   |> Choreo.FSM.add_transition(:a, :b, label: "x")
        ...>   |> Choreo.FSM.add_transition(:b, :c, label: "y")
        iex> Choreo.FSM.Analysis.shortest_accepting_path(fsm)
        {:ok, ["x", "y"]}

    This analysis answers the question: "What is the minimum input to reach an accepting state?"
  """
  @spec shortest_accepting_path(FSM.t()) :: {:ok, [String.t()]} | :error
  def shortest_accepting_path(%FSM{} = fsm) do
    case FSM.initial_state(fsm) do
      nil ->
        :error

      initial ->
        queue = [{initial, []}]
        visited = MapSet.new([initial])
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

        iex> fsm =
        ...>   Choreo.FSM.new()
        ...>   |> Choreo.FSM.add_initial_state(:a)
        ...>   |> Choreo.FSM.add_final_state(:b)
        ...>   |> Choreo.FSM.add_transition(:a, :b, label: "x")
        ...>   |> Choreo.FSM.add_transition(:b, :b, label: "y")
        iex> Enum.sort(Choreo.FSM.Analysis.accepted_strings(fsm, 2))
        [["x"], ["x", "y"]]

    This analysis answers the question: "What inputs are accepted up to length N?"
  """
  @spec accepted_strings(FSM.t(), non_neg_integer()) :: [[String.t()]]
  def accepted_strings(%FSM{} = fsm, max_length) when max_length >= 0 do
    case FSM.initial_state(fsm) do
      nil ->
        []

      initial ->
        queue = [{initial, []}]

        do_accepted_strings(fsm, queue, max_length, 0, [])
        |> Enum.reverse()
    end
  end

  # ============================================================================
  # Alphabet and completeness
  # ============================================================================

  @doc """
    Returns the set of distinct input symbols (the alphabet) of the FSM.

    The alphabet is derived from all transition labels. Empty-string labels
    are excluded.

    ## Examples

        iex> fsm =
        ...>   Choreo.FSM.new()
        ...>   |> Choreo.FSM.add_state(:a)
        ...>   |> Choreo.FSM.add_state(:b)
        ...>   |> Choreo.FSM.add_state(:c)
        ...>   |> Choreo.FSM.add_transition(:a, :b, label: "x")
        ...>   |> Choreo.FSM.add_transition(:b, :c, label: "y")
        ...>   |> Choreo.FSM.add_transition(:c, :a, label: "x")
        iex> Choreo.FSM.Analysis.alphabet(fsm) |> MapSet.to_list() |> Enum.sort()
        ["x", "y"]

    This analysis answers the question: "What are the distinct input symbols?"
  """
  @spec alphabet(FSM.t()) :: MapSet.t(String.t())
  def alphabet(%FSM{graph: graph}) do
    graph.edges
    |> Enum.map(fn {_eid, {_from, _to, label}} -> label end)
    |> Enum.reject(&(&1 == "" or is_nil(&1)))
    |> MapSet.new()
  end

  @doc """
    Checks whether the FSM is complete (total).

    A complete FSM has a transition from every state for every symbol in
    the alphabet. Incomplete FSMs implicitly reject inputs that have no
    matching transition.

    ## Examples

        iex> fsm =
        ...>   Choreo.FSM.new()
        ...>   |> Choreo.FSM.add_state(:a)
        ...>   |> Choreo.FSM.add_state(:b)
        ...>   |> Choreo.FSM.add_transition(:a, :b, label: "x")
        ...>   |> Choreo.FSM.add_transition(:a, :a, label: "y")
        ...>   |> Choreo.FSM.add_transition(:b, :a, label: "x")
        ...>   |> Choreo.FSM.add_transition(:b, :b, label: "y")
        iex> Choreo.FSM.Analysis.complete?(fsm)
        true

    This analysis answers the question: "Does every state handle every input symbol?"
  """
  @spec complete?(FSM.t()) :: boolean()
  def complete?(%FSM{graph: graph} = fsm) do
    sigma = alphabet(fsm)

    if MapSet.size(sigma) == 0 do
      true
    else
      graph.nodes
      |> Map.keys()
      |> Enum.all?(fn id ->
        labels =
          Yog.Multi.successors(graph, id)
          |> Enum.map(fn {_to, _edge_id, label} -> label end)
          |> MapSet.new()

        MapSet.subset?(sigma, labels)
      end)
    end
  end

  # ============================================================================
  # Validation
  # ============================================================================

  @doc """
    Validates the FSM and returns a list of issues.

    Checks for:

      * no initial state defined
      * no final states defined
      * unreachable states
      * dead (trap) states
      * incomplete alphabet coverage

    Returns a list of `{severity, message}` tuples.

    ## Examples

        iex> fsm =
        ...>   Choreo.FSM.new()
        ...>   |> Choreo.FSM.add_initial_state(:idle)
        ...>   |> Choreo.FSM.add_final_state(:done)
        ...>   |> Choreo.FSM.add_transition(:idle, :done, label: "go")
        ...>   |> Choreo.FSM.add_transition(:done, :idle, label: "go")
        iex> Choreo.FSM.Analysis.validate(fsm)
        []

    This analysis answers the question: "Is the state machine structurally sound?"
  """
  @spec validate(FSM.t()) :: [{:error | :warning, String.t()}]
  def validate(%FSM{} = fsm) do
    reachable = reachable_states(fsm) |> MapSet.new()
    dead = dead_states(fsm) |> MapSet.new()
    livelock = livelock_states(fsm, reachable, dead)

    []
    |> check_no_initial(fsm)
    |> check_no_final(fsm)
    |> check_unreachable(fsm, reachable)
    |> check_dead(fsm, reachable, dead)
    |> check_livelock(fsm, livelock)
    |> check_completeness(fsm)
    # Each check prepends, so reverse to restore declaration order.
    |> Enum.reverse()
  end

  # ============================================================================
  # Private helpers — validation
  # ============================================================================

  defp check_no_initial(acc, fsm) do
    if is_nil(FSM.initial_state(fsm)) and FSM.states(fsm) != [] do
      [{:error, "No initial state defined"} | acc]
    else
      acc
    end
  end

  defp check_no_final(acc, fsm) do
    if FSM.final_states(fsm) == [] and FSM.states(fsm) != [] do
      [{:warning, "No final states defined"} | acc]
    else
      acc
    end
  end

  defp check_unreachable(acc, fsm, reachable) do
    all = FSM.states(fsm) |> MapSet.new()
    unreachable = MapSet.difference(all, reachable)

    if MapSet.size(unreachable) > 0 do
      [{:warning, "Unreachable states: #{inspect(MapSet.to_list(unreachable))}"} | acc]
    else
      acc
    end
  end

  defp check_dead(acc, _fsm, reachable, dead) do
    reachable_dead = MapSet.intersection(reachable, dead)

    if MapSet.size(reachable_dead) > 0 do
      [{:warning, "Dead states: #{inspect(MapSet.to_list(reachable_dead))}"} | acc]
    else
      acc
    end
  end

  defp check_livelock(acc, _fsm, livelock) do
    case livelock do
      [] -> acc
      states -> [{:warning, "Livelock states: #{inspect(states)}"} | acc]
    end
  end

  defp check_completeness(acc, fsm) do
    if not complete?(fsm) and MapSet.size(alphabet(fsm)) > 0 do
      [{:warning, "FSM is incomplete — not all states handle every input symbol"} | acc]
    else
      acc
    end
  end

  # ============================================================================
  # Private helpers — BFS
  # ============================================================================

  defp bfs_path(_fsm, [], _visited), do: :error

  defp bfs_path(fsm, [{state, path} | rest], visited) do
    if state in FSM.final_states(fsm) do
      {:ok, Enum.reverse(path)}
    else
      new_items =
        Yog.Multi.successors(fsm.graph, state)
        |> Enum.reject(fn {to, _edge_id, _label} -> MapSet.member?(visited, to) end)
        |> Enum.map(fn {to, _edge_id, label} -> {to, [label | path]} end)

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
          Yog.Multi.successors(fsm.graph, state)
          |> Enum.map(fn {to, _edge_id, label} -> {to, [label | path]} end)
        end)

      do_accepted_strings(fsm, next_queue, max_length, current_length + 1, new_acc)
    end
  end

  # ============================================================================
  # Multigraph helpers
  # ============================================================================

  defp bfs_reachable_multi(graph, seeds) do
    do_bfs_multi(graph, seeds, MapSet.new(seeds))
  end

  defp do_bfs_multi(_graph, [], visited), do: visited

  defp do_bfs_multi(graph, [h | t], visited) do
    neighbors =
      graph
      |> Yog.Multi.successors(h)
      |> Enum.map(fn {to, _edge_id, _data} -> to end)
      |> Enum.reject(&MapSet.member?(visited, &1))

    do_bfs_multi(graph, t ++ neighbors, MapSet.union(visited, MapSet.new(neighbors)))
  end

  defp build_predecessors(graph) do
    Enum.reduce(graph.edges, %{}, fn {_eid, {from, to, _data}}, acc ->
      Map.update(acc, to, [from], &[from | &1])
    end)
  end

  defp bfs_reachable_reverse(predecessors, seeds) do
    do_bfs_reverse(predecessors, seeds, MapSet.new(seeds))
  end

  defp do_bfs_reverse(_preds, [], visited), do: visited

  defp do_bfs_reverse(preds, [h | t], visited) do
    neighbors =
      Map.get(preds, h, [])
      |> Enum.reject(&MapSet.member?(visited, &1))

    do_bfs_reverse(preds, t ++ neighbors, MapSet.union(visited, MapSet.new(neighbors)))
  end
end
