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

  @doc """
    Checks if the state machine is deterministic.

    An FSM is deterministic if it has at most one initial state (always true by construction),
    no duplicate transition labels from any single state (always true by construction),
    and no epsilon transitions (empty/nil labels).

    ## Examples

        iex> fsm =
        ...>   Choreo.FSM.new()
        ...>   |> Choreo.FSM.add_initial_state(:a)
        ...>   |> Choreo.FSM.add_transition(:a, :b, label: "go")
        iex> Choreo.FSM.Analysis.deterministic?(fsm)
        true
  """
  @spec deterministic?(FSM.t()) :: boolean()
  def deterministic?(%FSM{} = fsm) do
    # Verify no epsilon/empty transitions exist
    has_epsilon? =
      fsm.graph.edges
      |> Enum.any?(fn {_eid, {_from, _to, label}} -> is_nil(label) or label == "" end)

    # Verify no state has duplicate outgoing labels
    has_duplicates? =
      FSM.states(fsm)
      |> Enum.any?(fn state ->
        successors = Yog.Multi.successors(fsm.graph, state)
        labels = Enum.map(successors, fn {_to, _eid, label} -> label end)
        length(labels) != length(Enum.uniq(labels))
      end)

    not has_epsilon? and not has_duplicates?
  end

  @doc """
    Generates a set of transition label sequences (test cases) to achieve
    the specified coverage metric.

    Supported strategies:
      * `:state` - guarantees every reachable state is visited at least once.
      * `:transition` - guarantees every reachable transition is traversed at least once.

    ## Examples

        iex> fsm =
        ...>   Choreo.FSM.new()
        ...>   |> Choreo.FSM.add_initial_state(:a)
        ...>   |> Choreo.FSM.add_state(:b)
        ...>   |> Choreo.FSM.add_final_state(:c)
        ...>   |> Choreo.FSM.add_transition(:a, :b, label: "x")
        ...>   |> Choreo.FSM.add_transition(:b, :c, label: "y")
        iex> Choreo.FSM.Analysis.generate_test_cases(fsm, :state) |> Enum.sort()
        [[], ["x"], ["x", "y"]]
        iex> Choreo.FSM.Analysis.generate_test_cases(fsm, :transition) |> Enum.sort()
        [["x"], ["x", "y"]]
  """
  @spec generate_test_cases(FSM.t(), :state | :transition) :: [[String.t()]]
  def generate_test_cases(%FSM{} = fsm, strategy \\ :state) do
    case FSM.initial_state(fsm) do
      nil ->
        []

      initial ->
        # Find shortest path to every reachable state (paths are in reverse order)
        shortest_paths = find_shortest_paths_to_all(fsm, initial)

        case strategy do
          :state ->
            shortest_paths
            |> Map.values()
            |> Enum.map(&Enum.reverse/1)
            |> Enum.uniq()

          :transition ->
            fsm.graph.edges
            |> Map.values()
            |> Enum.flat_map(fn {from, _to, label} ->
              case Map.fetch(shortest_paths, from) do
                {:ok, path} -> [Enum.reverse([label | path])]
                :error -> []
              end
            end)
            |> Enum.uniq()
        end
    end
  end

  defp find_shortest_paths_to_all(fsm, initial) do
    queue = :queue.from_list([{initial, []}])
    do_shortest_paths_bfs(fsm.graph, queue, %{initial => []})
  end

  defp do_shortest_paths_bfs(graph, queue, visited_paths) do
    case :queue.out(queue) do
      {{:value, {state, path}}, rest_queue} ->
        successors = Yog.Multi.successors(graph, state)

        {new_queue, new_visited} =
          Enum.reduce(successors, {rest_queue, visited_paths}, fn {to, _eid, label},
                                                                  {q_acc, v_acc} ->
            if Map.has_key?(v_acc, to) do
              {q_acc, v_acc}
            else
              new_path = [label | path]
              {:queue.in({to, new_path}, q_acc), Map.put(v_acc, to, new_path)}
            end
          end)

        do_shortest_paths_bfs(graph, new_queue, new_visited)

      {:empty, _} ->
        visited_paths
    end
  end

  @doc """
    Checks if two FSMs accept the exact same language (are equivalent).

    Uses a product automaton BFS traversal to check if there is any reachable pair of states
    where one is accepting (final) and the other is not.

    ## Examples

        iex> fsm1 =
        ...>   Choreo.FSM.new()
        ...>   |> Choreo.FSM.add_initial_state(:a)
        ...>   |> Choreo.FSM.add_final_state(:b)
        ...>   |> Choreo.FSM.add_transition(:a, :b, label: "x")
        iex> fsm2 =
        ...>   Choreo.FSM.new()
        ...>   |> Choreo.FSM.add_initial_state(:a)
        ...>   |> Choreo.FSM.add_final_state(:c)
        ...>   |> Choreo.FSM.add_transition(:a, :c, label: "x")
        iex> Choreo.FSM.Analysis.equivalent?(fsm1, fsm2)
        true
  """
  @spec equivalent?(FSM.t(), FSM.t()) :: boolean()
  def equivalent?(%FSM{} = fsm1, %FSM{} = fsm2) do
    init1 = FSM.initial_state(fsm1)
    init2 = FSM.initial_state(fsm2)

    cond do
      is_nil(init1) and is_nil(init2) ->
        true

      is_nil(init1) or is_nil(init2) ->
        # One is nil, the other isn't. They are equivalent only if the non-nil one accepts nothing
        non_nil_fsm = init1 || init2
        shortest_accepting_path(non_nil_fsm) == :error

      true ->
        # Both are non-nil, run product automaton reachability check
        alphabet = MapSet.union(alphabet(fsm1), alphabet(fsm2))
        queue = :queue.from_list([{init1, init2}])
        visited = MapSet.new([{init1, init2}])
        check_equivalence_bfs(fsm1, fsm2, queue, visited, alphabet)
    end
  end

  defp check_equivalence_bfs(fsm1, fsm2, queue, visited, alphabet) do
    case :queue.out(queue) do
      {{:value, {s1, s2}}, rest_queue} ->
        # Mismatch check: is one final and the other not?
        accept1 = accepting?(fsm1, s1)
        accept2 = accepting?(fsm2, s2)

        if accept1 != accept2 do
          false
        else
          # Push transition targets for all symbols in the alphabet
          {new_queue, new_visited} =
            Enum.reduce(alphabet, {rest_queue, visited}, fn sym, {q_acc, v_acc} ->
              t1 = get_next_state(fsm1.graph, s1, sym)
              t2 = get_next_state(fsm2.graph, s2, sym)
              pair = {t1, t2}

              if MapSet.member?(v_acc, pair) do
                {q_acc, v_acc}
              else
                {:queue.in(pair, q_acc), MapSet.put(v_acc, pair)}
              end
            end)

          check_equivalence_bfs(fsm1, fsm2, new_queue, new_visited, alphabet)
        end

      {:empty, _} ->
        true
    end
  end

  defp get_next_state(_graph, :sink_state, _sym), do: :sink_state

  defp get_next_state(graph, state, sym) do
    find_next(graph, state, sym) || :sink_state
  end

  defp accepting?(_fsm, :sink_state), do: false
  defp accepting?(fsm, state), do: state in FSM.final_states(fsm)

  @doc """
    Minimizes a DFA using Partition Refinement (Moore's algorithm).

    Returns a new minimized FSM.

    ## Examples

        iex> fsm =
        ...>   Choreo.FSM.new()
        ...>   |> Choreo.FSM.add_initial_state(:a)
        ...>   |> Choreo.FSM.add_state(:b)
        ...>   |> Choreo.FSM.add_final_state(:c)
        ...>   |> Choreo.FSM.add_transition(:a, :b, label: "x")
        ...>   |> Choreo.FSM.add_transition(:b, :c, label: "y")
        ...>   |> Choreo.FSM.add_transition(:a, :c, label: "z")
        iex> minimized = Choreo.FSM.Analysis.minimize(fsm)
        iex> minimized.meta.initial_state != nil
        true
  """
  @spec minimize(FSM.t()) :: FSM.t()
  def minimize(%FSM{} = fsm) do
    initial = FSM.initial_state(fsm)
    reachable = reachable_states(fsm)

    if is_nil(initial) or reachable == [] do
      fsm
    else
      # Check if sink state is needed for completeness during partition refinement
      sigma = alphabet(fsm) |> MapSet.to_list() |> Enum.sort()
      is_complete = complete?(fsm)
      sink_needed? = not is_complete

      # Partition states into final and non-final
      finals = FSM.final_states(fsm) |> Enum.filter(&(&1 in reachable)) |> MapSet.new()
      non_finals = Enum.filter(reachable, &(&1 not in finals)) |> MapSet.new()

      non_finals =
        if sink_needed? do
          MapSet.put(non_finals, :sink_state)
        else
          non_finals
        end

      initial_partition =
        [finals, non_finals]
        |> Enum.reject(&(MapSet.size(&1) == 0))

      final_partition = refine_partitions(initial_partition, fsm, sigma, sink_needed?)

      # Construct the minimized FSM
      min_fsm = FSM.new(strict: fsm.meta.strict)

      # Determine groups and name them
      group_mapping =
        final_partition
        |> Enum.with_index()
        |> Enum.flat_map(fn {group, _idx} ->
          rep = Enum.min(group)
          Enum.map(group, fn state -> {state, rep} end)
        end)
        |> Map.new()

      # Add states
      min_fsm =
        final_partition
        |> Enum.reduce(min_fsm, fn group, acc ->
          rep = Map.fetch!(group_mapping, Enum.min(group))

          if rep == :sink_state do
            acc
          else
            is_initial = initial in group
            is_final = Enum.any?(group, &(&1 in FSM.final_states(fsm)))

            cond do
              is_initial -> FSM.add_initial_state(acc, rep)
              is_final -> FSM.add_final_state(acc, rep)
              true -> FSM.add_state(acc, rep)
            end
          end
        end)

      # Add transitions
      final_partition
      |> Enum.reduce(min_fsm, fn group, acc ->
        add_group_transitions(acc, group, group_mapping, sigma, fsm)
      end)
    end
  end

  defp add_group_transitions(acc, group, group_mapping, sigma, fsm) do
    rep_from = Map.fetch!(group_mapping, Enum.min(group))

    if rep_from == :sink_state do
      acc
    else
      some_state = Enum.min(group)

      Enum.reduce(sigma, acc, fn sym, inner_acc ->
        add_symbol_transition(inner_acc, some_state, sym, rep_from, group_mapping, fsm)
      end)
    end
  end

  defp add_symbol_transition(inner_acc, some_state, sym, rep_from, group_mapping, fsm) do
    case get_next_state(fsm.graph, some_state, sym) do
      :sink_state ->
        inner_acc

      next_state ->
        rep_to = Map.fetch!(group_mapping, next_state)
        add_valid_transition(inner_acc, rep_from, rep_to, sym)
    end
  end

  defp add_valid_transition(inner_acc, _rep_from, :sink_state, _sym), do: inner_acc

  defp add_valid_transition(inner_acc, rep_from, rep_to, sym) do
    existing_successors = Yog.Multi.successors(inner_acc.graph, rep_from)

    already_exists =
      Enum.any?(existing_successors, fn {dest, _eid, label} ->
        dest == rep_to and label == sym
      end)

    if already_exists do
      inner_acc
    else
      FSM.add_transition(inner_acc, rep_from, rep_to, label: sym)
    end
  end

  defp refine_partitions(partition, fsm, sigma, sink_needed?) do
    new_partition =
      partition
      |> Enum.flat_map(fn group ->
        group
        |> Enum.group_by(fn state ->
          Enum.map(sigma, fn sym ->
            target = get_next_state(fsm.graph, state, sym)
            Enum.find_index(partition, &MapSet.member?(&1, target))
          end)
        end)
        |> Map.values()
        |> Enum.map(&MapSet.new/1)
      end)

    if length(new_partition) == length(partition) do
      new_partition
    else
      refine_partitions(new_partition, fsm, sigma, sink_needed?)
    end
  end

  @doc """
    Validates that a path of states satisfies the given temporal constraint.

    Supported options:
      * `:forbid_path` - a list of state IDs that must not be traversed consecutively in this sequence.

    ## Examples

        iex> fsm =
        ...>   Choreo.FSM.new()
        ...>   |> Choreo.FSM.add_initial_state(:a)
        ...>   |> Choreo.FSM.add_state(:b)
        ...>   |> Choreo.FSM.add_transition(:a, :b, label: "x")
        iex> Choreo.FSM.Analysis.violates_invariant?(fsm, forbid_path: [:a, :b])
        true
  """
  @spec violates_invariant?(FSM.t(), keyword()) :: boolean()
  def violates_invariant?(%FSM{} = fsm, opts) do
    forbid = opts[:forbid_path]

    if is_list(forbid) and length(forbid) > 1 do
      forbid
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.all?(fn [from, to] ->
        Map.has_key?(fsm.graph.nodes, from) and
          Map.has_key?(fsm.graph.nodes, to) and
          Yog.Multi.edges_between(fsm.graph, from, to) != []
      end)
    else
      false
    end
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
