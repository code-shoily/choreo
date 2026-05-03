defmodule Choreo.Dataflow.Analysis do
  @moduledoc """
  Analysis functions for `Choreo.Dataflow` pipelines.

  Provides algorithms that answer practical questions about a dataflow:

    * Is there a cycle? (feedback loop detection)
    * What is the execution order? (topological sort)
    * Which stages have no upstream source? (orphans)
    * Which stages never reach a sink? (dead ends)
    * Where are the bottlenecks? (high fan-in / fan-out)
    * What is the critical path? (longest source→sink chain)
    * Where does back-pressure build up? (throughput simulation)

  ## Further reading

    * [Dataflow Programming (Wikipedia)](https://en.wikipedia.org/wiki/Dataflow_programming)
    * [Streaming Systems (O'Reilly)](https://www.oreilly.com/library/view/streaming-systems/9781491983867/)
    * [Enterprise Integration Patterns](https://www.enterpriseintegrationpatterns.com/)
  """

  alias Choreo.Dataflow

  @doc """
  Returns all source node IDs in the dataflow.

  ## Examples

      iex> flow = Choreo.Dataflow.new()
      iex> flow = flow
      ...>   |> Choreo.Dataflow.add_source(:a)
      ...>   |> Choreo.Dataflow.add_source(:b)
      ...>   |> Choreo.Dataflow.add_transform(:c)
      iex> Enum.sort(Choreo.Dataflow.Analysis.sources(flow))
      [:a, :b]

  This analysis answers the question: "Where does data enter the pipeline?"
  """
  @spec sources(Dataflow.t()) :: [Yog.node_id()]
  def sources(%Dataflow{} = flow) do
    Dataflow.nodes_of_type(flow, :source)
  end

  @doc """
  Returns all sink node IDs in the dataflow.

  ## Examples

      iex> flow = Choreo.Dataflow.new()
      iex> flow = flow
      ...>   |> Choreo.Dataflow.add_transform(:a)
      ...>   |> Choreo.Dataflow.add_sink(:b)
      iex> Choreo.Dataflow.Analysis.sinks(flow)
      [:b]

  This analysis answers the question: "Where does data leave the pipeline?"
  """
  @spec sinks(Dataflow.t()) :: [Yog.node_id()]
  def sinks(%Dataflow{} = flow) do
    Dataflow.nodes_of_type(flow, :sink)
  end

  @doc """
  Checks whether the dataflow contains a directed cycle.

  ## Examples

      iex> flow = Choreo.Dataflow.new()
      iex> flow = flow
      ...>   |> Choreo.Dataflow.add_source(:a)
      ...>   |> Choreo.Dataflow.add_transform(:b)
      ...>   |> Choreo.Dataflow.add_transform(:c)
      ...>   |> Choreo.Dataflow.connect(:a, :b)
      ...>   |> Choreo.Dataflow.connect(:b, :c)
      ...>   |> Choreo.Dataflow.connect(:c, :b)
      iex> Choreo.Dataflow.Analysis.cyclic?(flow)
      true

      iex> flow = Choreo.Dataflow.new()
      iex> flow = flow
      ...>   |> Choreo.Dataflow.add_source(:a)
      ...>   |> Choreo.Dataflow.add_transform(:b)
      ...>   |> Choreo.Dataflow.add_sink(:c)
      ...>   |> Choreo.Dataflow.connect(:a, :b)
      ...>   |> Choreo.Dataflow.connect(:b, :c)
      iex> Choreo.Dataflow.Analysis.cyclic?(flow)
      false

  This analysis answers the question: "Is there a feedback loop in the data pipeline?"
  """
  @spec cyclic?(Dataflow.t()) :: boolean()
  def cyclic?(%Dataflow{graph: graph}) do
    Yog.cyclic?(graph)
  end

  @doc """
  Returns a topological ordering of all stages.

  ## Examples

      iex> flow = Choreo.Dataflow.new()
      iex> flow = flow
      ...>   |> Choreo.Dataflow.add_source(:a)
      ...>   |> Choreo.Dataflow.add_transform(:b)
      ...>   |> Choreo.Dataflow.add_sink(:c)
      ...>   |> Choreo.Dataflow.connect(:a, :b)
      ...>   |> Choreo.Dataflow.connect(:b, :c)
      iex> {:ok, order} = Choreo.Dataflow.Analysis.topological_sort(flow)
      iex> Enum.find_index(order, & &1 == :a) < Enum.find_index(order, & &1 == :b)
      true
      iex> Enum.find_index(order, & &1 == :b) < Enum.find_index(order, & &1 == :c)
      true

  This analysis answers the question: "In what order should stages execute?"
  """
  @spec topological_sort(Dataflow.t()) :: {:ok, [Yog.node_id()]} | {:error, :contains_cycle}
  def topological_sort(%Dataflow{graph: graph}) do
    Yog.Traversal.Sort.topological_sort(graph)
  end

  @doc """
  Returns nodes that are not reachable from any source.

  ## Examples

      iex> flow = Choreo.Dataflow.new()
      iex> flow = flow
      ...>   |> Choreo.Dataflow.add_source(:a)
      ...>   |> Choreo.Dataflow.add_transform(:b)
      ...>   |> Choreo.Dataflow.add_transform(:c)
      ...>   |> Choreo.Dataflow.connect(:a, :b)
      iex> Choreo.Dataflow.Analysis.orphan_nodes(flow)
      [:c]

  This analysis answers the question: "Which stages are unreachable from any source?"
  """
  @spec orphan_nodes(Dataflow.t()) :: [Yog.node_id()]
  def orphan_nodes(%Dataflow{} = flow) do
    source_ids = sources(flow)

    if source_ids == [] do
      []
    else
      reachable = Choreo.Internal.bfs_reachable(flow.graph, source_ids)
      all = Dataflow.nodes(flow) |> MapSet.new()
      MapSet.difference(all, reachable) |> MapSet.to_list()
    end
  end

  @doc """
  Returns nodes that cannot reach any sink.

  ## Examples

      iex> flow = Choreo.Dataflow.new()
      iex> flow = flow
      ...>   |> Choreo.Dataflow.add_source(:a)
      ...>   |> Choreo.Dataflow.add_transform(:b)
      ...>   |> Choreo.Dataflow.add_sink(:c)
      ...>   |> Choreo.Dataflow.add_transform(:d)
      ...>   |> Choreo.Dataflow.connect(:a, :b)
      ...>   |> Choreo.Dataflow.connect(:b, :c)
      iex> Choreo.Dataflow.Analysis.dead_ends(flow)
      [:d]

  This analysis answers the question: "Which stages can never reach a sink?"
  """
  @spec dead_ends(Dataflow.t()) :: [Yog.node_id()]
  def dead_ends(%Dataflow{} = flow) do
    sink_ids = sinks(flow)

    if sink_ids == [] do
      Dataflow.nodes(flow)
    else
      transposed = Yog.transpose(flow.graph)
      can_reach_sink = Choreo.Internal.bfs_reachable(transposed, sink_ids)
      all = Dataflow.nodes(flow) |> MapSet.new()
      MapSet.difference(all, can_reach_sink) |> MapSet.to_list()
    end
  end

  @doc """
  Returns nodes with high combined fan-in and fan-out.

  ## Options

    * `:threshold` — minimum `in_degree + out_degree` to qualify (default: `3`)

  ## Examples

      iex> flow = Choreo.Dataflow.new()
      iex> flow = flow
      ...>   |> Choreo.Dataflow.add_source(:a)
      ...>   |> Choreo.Dataflow.add_source(:b)
      ...>   |> Choreo.Dataflow.add_transform(:hub)
      ...>   |> Choreo.Dataflow.add_sink(:c)
      ...>   |> Choreo.Dataflow.add_sink(:d)
      ...>   |> Choreo.Dataflow.connect(:a, :hub)
      ...>   |> Choreo.Dataflow.connect(:b, :hub)
      ...>   |> Choreo.Dataflow.connect(:hub, :c)
      ...>   |> Choreo.Dataflow.connect(:hub, :d)
      iex> Choreo.Dataflow.Analysis.bottlenecks(flow)
      [:hub]

  This analysis answers the question: "Which stages have the highest fan-in and fan-out?"
  """
  @spec bottlenecks(Dataflow.t(), keyword()) :: [Yog.node_id()]
  def bottlenecks(%Dataflow{graph: graph}, opts \\ []) do
    threshold = Keyword.get(opts, :threshold, 3)

    graph.nodes
    |> Enum.filter(fn {id, _data} ->
      in_deg = Yog.in_degree(graph, id)
      out_deg = Yog.out_degree(graph, id)
      in_deg + out_deg >= threshold
    end)
    |> Enum.map(fn {id, _data} -> id end)
  end

  @doc """
  Finds the longest weighted path from any source to any sink.

  This is the **critical path** for latency: the chain of stages that
  determines the minimum end-to-end latency of the pipeline.

  Returns `{:ok, [id], total_weight}` or `:error` if the graph is cyclic
  or has no source→sink path.

  Edge weights default to `1` unless overridden with `connect/4` option
  `:weight`. You can also encode per-node latency by setting `:weight`
  on outgoing edges.

  ## Examples

      iex> flow = Choreo.Dataflow.new()
      iex> flow = flow
      ...>   |> Choreo.Dataflow.add_source(:a)
      ...>   |> Choreo.Dataflow.add_transform(:b)
      ...>   |> Choreo.Dataflow.add_transform(:c)
      ...>   |> Choreo.Dataflow.add_sink(:d)
      ...>   |> Choreo.Dataflow.connect(:a, :b, weight: 10)
      ...>   |> Choreo.Dataflow.connect(:b, :c, weight: 5)
      ...>   |> Choreo.Dataflow.connect(:c, :d, weight: 2)
      iex> Choreo.Dataflow.Analysis.longest_path(flow)
      {:ok, [:a, :b, :c, :d], 17}

  This analysis answers the question: "What is the critical path that determines end-to-end latency?"
  """
  @spec longest_path(Dataflow.t()) :: {:ok, [Yog.node_id()], number()} | :error
  def longest_path(%Dataflow{graph: graph} = flow) do
    case topological_sort(flow) do
      {:ok, order} ->
        source_set = sources(flow) |> MapSet.new()
        sink_set = sinks(flow) |> MapSet.new()
        dp = Choreo.Internal.compute_dp(graph, order, source_set)

        case Choreo.Internal.find_best_end_path(dp, sink_set) do
          nil ->
            :error

          {_dist, sink_id} ->
            path = Choreo.Internal.reconstruct_path(dp, sink_id)
            total = elem(Map.fetch!(dp, sink_id), 0)
            {:ok, path, total}
        end

      {:error, :contains_cycle} ->
        :error
    end
  end

  @doc """
  Identifies nodes that lack explicit error handling paths.

  Checks all `:transform` and `:sink` nodes. Returns a list of node IDs that do
  not have any outgoing edge configured with `path_type: :error` or
  `path_type: :dead_letter`.

  ## Examples

      iex> flow = Choreo.Dataflow.new()
      iex> flow = flow
      ...>   |> Choreo.Dataflow.add_source(:a)
      ...>   |> Choreo.Dataflow.add_transform(:b)
      ...>   |> Choreo.Dataflow.add_transform(:c)
      ...>   |> Choreo.Dataflow.add_sink(:d)
      ...>   |> Choreo.Dataflow.connect(:a, :b)
      ...>   |> Choreo.Dataflow.connect(:b, :c)
      ...>   |> Choreo.Dataflow.connect(:c, :d)
      ...>   |> Choreo.Dataflow.add_error_path(:b, :d)
      iex> Enum.sort(Choreo.Dataflow.Analysis.unhandled_errors(flow))
      [:c, :d]

  This analysis answers the question: "Which stages lack explicit error handling?"
  """
  @spec unhandled_errors(Dataflow.t()) :: [Yog.node_id()]
  def unhandled_errors(%Dataflow{} = flow) do
    flow.graph.nodes
    |> Enum.filter(fn {id, data} ->
      is_target = data[:node_type] in [:transform, :sink]

      has_handler =
        Enum.any?(Yog.successor_ids(flow.graph, id), fn to ->
          meta = Map.get(flow.edge_meta, {id, to}, %{})
          meta[:path_type] in [:error, :dead_letter]
        end)

      is_target and not has_handler
    end)
    |> Enum.map(fn {id, _data} -> id end)
  end

  @doc """
  Identifies nodes where the simulated incoming data rate exceeds capacity.

  Reuses the `simulate/2` logic to calculate steady-state incoming rates,
  and compares them against the `:capacity` attribute of each node.

  Returns a list of node IDs where `in_rate > capacity`.

  ## Examples

      iex> flow = Choreo.Dataflow.new()
      iex> flow = flow
      ...>   |> Choreo.Dataflow.add_source(:a, rate: 100)
      ...>   |> Choreo.Dataflow.add_transform(:b, capacity: 50)
      ...>   |> Choreo.Dataflow.add_transform(:c, capacity: 150)
      ...>   |> Choreo.Dataflow.add_sink(:d)
      ...>   |> Choreo.Dataflow.connect(:a, :b)
      ...>   |> Choreo.Dataflow.connect(:b, :c)
      ...>   |> Choreo.Dataflow.connect(:c, :d)
      iex> Choreo.Dataflow.Analysis.capacity_bottlenecks(flow)
      [:b]

  This analysis answers the question: "Which stages will be overwhelmed by incoming data?"
  """
  @spec capacity_bottlenecks(Dataflow.t()) :: [Yog.node_id()]
  def capacity_bottlenecks(%Dataflow{} = flow) do
    simulated = simulate(flow)

    flow.graph.nodes
    |> Enum.filter(fn {id, data} ->
      capacity = data[:capacity]
      stats = Map.get(simulated, id, %{in_rate: 0})

      capacity != nil and stats.in_rate > capacity
    end)
    |> Enum.map(fn {id, _data} -> id end)
  end

  @doc """
  Simulates throughput propagation through the pipeline.

  Each source is assigned a `:rate` (events/sec). Each non-source stage
  receives the **sum** of all incoming rates. The result is a map of
  `node_id => %{in_rate: float, out_rate: float, latency_ms: number}`.

  Sources use their own `:rate`; transforms/buffers/merges sum inputs;
  sinks consume without producing.

  ## Examples

      iex> flow = Choreo.Dataflow.new()
      iex> flow = flow
      ...>   |> Choreo.Dataflow.add_source(:a, rate: 100)
      ...>   |> Choreo.Dataflow.add_source(:b, rate: 200)
      ...>   |> Choreo.Dataflow.add_merge(:m)
      ...>   |> Choreo.Dataflow.add_sink(:c)
      ...>   |> Choreo.Dataflow.connect(:a, :m)
      ...>   |> Choreo.Dataflow.connect(:b, :m)
      ...>   |> Choreo.Dataflow.connect(:m, :c)
      iex> result = Choreo.Dataflow.Analysis.simulate(flow)
      iex> result[:a].out_rate
      100
      iex> result[:b].out_rate
      200
      iex> result[:m].in_rate
      300
      iex> result[:c].in_rate
      300
      iex> result[:c].out_rate
      0

  This analysis answers the question: "What is the throughput at each stage?"
  """
  @spec simulate(Dataflow.t()) :: %{
          optional(Yog.node_id()) => %{in_rate: number, out_rate: number, latency_ms: number}
        }
  def simulate(%Dataflow{graph: graph} = flow) do
    case topological_sort(flow) do
      {:ok, order} ->
        do_simulate(graph, order, %{})

      {:error, :contains_cycle} ->
        %{}
    end
  end

  @doc """
  Returns nodes where simulated input rate exceeds a threshold.

  In practice these are the stages that will experience back-pressure
  first if they cannot process fast enough.

  ## Options

    * `:threshold` — minimum in_rate to be considered a backpressure point
      (default: `0`, meaning any node with inbound flow)

  ## Examples

      iex> flow = Choreo.Dataflow.new()
      iex> flow = flow
      ...>   |> Choreo.Dataflow.add_source(:a, rate: 100)
      ...>   |> Choreo.Dataflow.add_transform(:b)
      ...>   |> Choreo.Dataflow.add_sink(:c)
      ...>   |> Choreo.Dataflow.connect(:a, :b)
      ...>   |> Choreo.Dataflow.connect(:b, :c)
      iex> Enum.sort(Choreo.Dataflow.Analysis.backpressure_points(flow))
      [:b, :c]

  This analysis answers the question: "Where will back-pressure build up?"
  """
  @spec backpressure_points(Dataflow.t(), keyword()) :: [Yog.node_id()]
  def backpressure_points(%Dataflow{} = flow, opts \\ []) do
    threshold = Keyword.get(opts, :threshold, 0)
    results = simulate(flow)

    results
    |> Enum.filter(fn {_id, stats} -> stats.in_rate > threshold end)
    |> Enum.map(fn {id, _stats} -> id end)
  end

  @doc """
  Returns edges filtered by path type.

  ## Examples

      iex> flow = Choreo.Dataflow.new()
      iex> flow = flow
      ...>   |> Choreo.Dataflow.add_transform(:a)
      ...>   |> Choreo.Dataflow.add_sink(:b)
      ...>   |> Choreo.Dataflow.add_sink(:c)
      ...>   |> Choreo.Dataflow.connect(:a, :b)
      ...>   |> Choreo.Dataflow.add_error_path(:a, :c)
      iex> Choreo.Dataflow.Analysis.edges_of_type(flow, :normal)
      [{:a, :b, 1}]
      iex> Choreo.Dataflow.Analysis.edges_of_type(flow, :error)
      [{:a, :c, 1}]

  This analysis answers the question: "Which edges have a specific path type?"
  """
  @spec edges_of_type(Dataflow.t(), atom()) :: [{Yog.node_id(), Yog.node_id(), String.t()}]
  def edges_of_type(%Dataflow{graph: graph, edge_meta: edge_meta}, path_type) do
    graph
    |> Yog.all_edges()
    |> Enum.filter(fn {from, to, _weight} ->
      meta = Map.get(edge_meta, {from, to}, %{})
      meta[:path_type] == path_type
    end)
  end

  @doc """
  Validates a dataflow pipeline and returns a list of issues.

  Checks for cycles, orphan nodes, dead ends, missing sources, and missing sinks.

  ## Examples

      iex> flow = Choreo.Dataflow.new()
      iex> flow = flow
      ...>   |> Choreo.Dataflow.add_source(:a)
      ...>   |> Choreo.Dataflow.add_transform(:b)
      ...>   |> Choreo.Dataflow.add_sink(:c)
      ...>   |> Choreo.Dataflow.connect(:a, :b)
      ...>   |> Choreo.Dataflow.connect(:b, :c)
      iex> Choreo.Dataflow.Analysis.validate(flow)
      []

      iex> flow = Choreo.Dataflow.new()
      iex> flow = flow
      ...>   |> Choreo.Dataflow.add_transform(:a)
      ...>   |> Choreo.Dataflow.add_transform(:b)
      ...>   |> Choreo.Dataflow.connect(:a, :b)
      iex> issues = Choreo.Dataflow.Analysis.validate(flow)
      iex> {:error, "No source nodes"} in issues
      true
      iex> {:error, "No sink nodes"} in issues
      true

  This analysis answers the question: "Is the pipeline structurally sound?"
  """
  @spec validate(Dataflow.t()) :: [{:error | :warning, String.t()}]
  def validate(%Dataflow{} = flow) do
    []
    |> check_sources(flow)
    |> check_sinks(flow)
    |> check_cycles(flow)
    |> check_orphans(flow)
    |> check_dead_ends(flow)
  end

  # ============================================================================
  # Private helpers
  # ============================================================================

  defp do_simulate(_graph, [], acc), do: acc

  defp do_simulate(graph, [id | rest], acc) do
    data = Yog.node(graph, id) || %{}
    node_type = data[:node_type]

    in_rate =
      if node_type == :source do
        0
      else
        graph
        |> Yog.predecessors(id)
        |> Enum.reduce(0, fn {pred, _weight}, sum ->
          pred_stats = Map.get(acc, pred, %{out_rate: 0})
          sum + pred_stats.out_rate
        end)
      end

    out_rate =
      cond do
        node_type == :source -> data[:rate] || 0
        node_type == :sink -> 0
        true -> in_rate
      end

    latency_ms = data[:latency_ms] || 0

    do_simulate(
      graph,
      rest,
      Map.put(acc, id, %{in_rate: in_rate, out_rate: out_rate, latency_ms: latency_ms})
    )
  end

  defp check_sources(acc, flow) do
    if sources(flow) == [] do
      [{:error, "No source nodes"} | acc]
    else
      acc
    end
  end

  defp check_sinks(acc, flow) do
    if sinks(flow) == [] do
      [{:error, "No sink nodes"} | acc]
    else
      acc
    end
  end

  defp check_cycles(acc, flow) do
    if cyclic?(flow) do
      [{:error, "Cycle detected in dataflow"} | acc]
    else
      acc
    end
  end

  @doc """
  Generates a heatmap of the dataflow based on throughput (inbound rate).

  Nodes with higher incoming data rates will be colored with "hotter" colors.

  ## Options
    * `:palette` — Color palette (`:heat`, `:cool`, `:spectral`)
  """
  @spec heatmap(Dataflow.t(), keyword()) :: Dataflow.t()
  def heatmap(%Dataflow{} = flow, opts \\ []) do
    simulation = simulate(flow)

    scores =
      simulation
      |> Enum.map(fn {id, stats} -> {id, stats.in_rate} end)

    Choreo.Analysis.heatmap(flow, Keyword.put(opts, :scores, scores))
  end

  defp check_orphans(acc, flow) do
    case orphan_nodes(flow) do
      [] -> acc
      nodes -> [{:warning, "Orphan nodes: #{inspect(nodes)}"} | acc]
    end
  end

  defp check_dead_ends(acc, flow) do
    case dead_ends(flow) do
      [] -> acc
      nodes -> [{:warning, "Dead-end nodes: #{inspect(nodes)}"} | acc]
    end
  end
end
