defmodule Choreo.Analysis.Tracing do
  @moduledoc """
  Analysis functions for cross-diagram semantic tracing in Choreo.
  """

  alias Choreo

  @doc """
  Returns a list of all nodes that are transitively impacted by `target_id`
  along trace edges.
  """
  @spec impact_analysis(Choreo.t(), Yog.node_id()) :: [Yog.node_id()]
  def impact_analysis(%Choreo{} = system, target_id) do
    trace_graph = build_trace_only_graph(system)
    transposed = Yog.transpose(trace_graph)

    if Yog.has_node?(transposed, target_id) do
      transposed
      |> Yog.Traversal.walk(target_id, :breadth_first)
      |> List.delete(target_id)
    else
      []
    end
  end

  @doc """
  Finds the tracing path (sequence of nodes) from `from` to `to` using trace edges.
  """
  @spec trace_path(Choreo.t(), Yog.node_id(), Yog.node_id()) :: {:ok, [Yog.node_id()]} | :error
  def trace_path(%Choreo{} = system, from, to) do
    trace_graph = build_trace_only_graph(system)

    case Yog.Pathfinding.Dijkstra.shortest_path(trace_graph, from, to) do
      {:ok, path} -> {:ok, path.nodes}
      :error -> :error
    end
  end

  @doc """
  Performs nested, cross-domain analysis on a trace path starting from `from`
  down to `to`. Threads through domain-specific metadata for each node.
  """
  @spec analyze(Choreo.t(), Yog.node_id(), Yog.node_id()) :: {:ok, map()} | :error
  def analyze(%Choreo{} = system, from, to) do
    case trace_path(system, from, to) do
      {:ok, path} ->
        findings =
          Enum.map(path, fn node_id ->
            node_data = Map.get(system.graph.nodes, node_id, %{})

            base = %{
              node: node_id,
              label: node_data[:label] || node_data[:name] || to_string(node_id)
            }

            domain_info =
              cond do
                # Workflow node
                node_data[:node_type] in [:task, :decision, :start, :end] ->
                  %{
                    domain: :workflow,
                    type: node_data[:node_type],
                    timeout_ms: node_data[:timeout_ms],
                    retry: node_data[:retry]
                  }

                # ThreatModel element (e.g. data_store or process)
                node_data[:element_type] != nil ->
                  %{
                    domain: :threat_model,
                    type: node_data[:element_type],
                    sensitivity: node_data[:sensitivity],
                    boundary: node_data[:boundary]
                  }

                # ERD Table node
                node_data[:type] == :table ->
                  %{
                    domain: :erd,
                    type: :table,
                    columns: node_data[:columns]
                  }

                # Dataflow node
                node_data[:type] == :dataflow_node ->
                  %{
                    domain: :dataflow,
                    type: node_data[:node_type],
                    capacity: node_data[:capacity],
                    rate: node_data[:rate]
                  }

                # Dependency node
                node_data[:type] == :dependency_node ->
                  %{
                    domain: :dependency,
                    type: node_data[:node_type]
                  }

                # C4 container/component node
                node_data[:technology] != nil or
                    node_data[:node_type] in [:person, :software_system, :container, :component] ->
                  %{
                    domain: :c4,
                    type: node_data[:node_type],
                    technology: node_data[:technology]
                  }

                # Generic / Fallback
                true ->
                  %{
                    domain: :generic
                  }
              end

            Map.merge(base, domain_info)
          end)

        has_bottleneck =
          Enum.any?(findings, fn f ->
            f[:domain] == :workflow and is_number(f[:timeout_ms]) and f[:timeout_ms] >= 5000
          end)

        has_high_risk =
          Enum.any?(findings, fn f ->
            (f[:domain] == :threat_model and
               f[:sensitivity] in [:confidential, :restricted, :high_risk]) or
              (f[:domain] == :erd and
                 Enum.any?(f[:columns] || [], fn col ->
                   col[:sensitivity] in [:confidential, :restricted, :high_risk]
                 end))
          end)

        summary = %{
          path: path,
          findings: findings,
          has_bottleneck?: has_bottleneck,
          has_high_risk?: has_high_risk
        }

        {:ok, summary}

      :error ->
        :error
    end
  end

  defp build_trace_only_graph(system) do
    simple = Yog.new(:directed)

    simple =
      Enum.reduce(system.graph.nodes, simple, fn {id, data}, g ->
        Yog.add_node(g, id, data)
      end)

    Enum.reduce(system.graph.edges, simple, fn {edge_id, {src, dst, _weight}}, g ->
      meta = Map.get(system.edge_meta, edge_id, %{})

      if meta[:edge_type] == :trace do
        Yog.add_edge_ensure(g, src, dst, 1)
      else
        g
      end
    end)
  end
end
