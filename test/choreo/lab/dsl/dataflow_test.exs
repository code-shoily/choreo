defmodule Choreo.Lab.DataflowDSLTest do
  use ExUnit.Case, async: true

  import Choreo.Lab.DSL.Dataflow

  doctest Choreo.Lab.DSL.Dataflow

  test "taxonomy returns the Livebook discovery vocabulary" do
    taxonomy = Choreo.Lab.DSL.Dataflow.taxonomy()

    assert :cluster in taxonomy.clusters
    assert :source in taxonomy.nodes
    assert :transform in taxonomy.nodes
    assert :sink in taxonomy.nodes
    assert :emits in taxonomy.edges
    assert :dead_letter in taxonomy.edges
    assert :data in taxonomy.modifiers
    assert :path_type in taxonomy.options
    assert Choreo.Lab.DSL.Dataflow.verbs() == taxonomy
  end

  test "builds a dataflow pipeline with variable-bound nodes" do
    pipeline =
      dataflow do
        ingest = source("Kafka Ingest", rate: "10k/s")
        parser = transform("JSON Parser", latency_ms: 5)
        valid = conditional("Valid?")
        postgres = sink("Postgres")
        dlq = sink("Dead Letter Queue")

        ingest ~> parser |> emits("raw events")
        parser ~> valid |> emits("parsed events")
        valid ~> postgres |> writes("valid records")
        dead_letter valid ~> dlq, "invalid records"
      end

    assert pipeline.graph.nodes[:ingest].node_type == :source
    assert pipeline.graph.nodes[:ingest].rate == "10k/s"
    assert pipeline.graph.nodes[:parser].node_type == :transform
    assert pipeline.graph.nodes[:parser].latency_ms == 5
    assert pipeline.graph.nodes[:valid].node_type == :conditional
    assert pipeline.graph.nodes[:postgres].node_type == :sink

    assert pipeline.edge_meta[{:ingest, :parser}].data_type == "raw events"
    assert pipeline.edge_meta[{:ingest, :parser}].label == "raw events"
    assert pipeline.edge_meta[{:valid, :dlq}].path_type == :dead_letter
    assert pipeline.edge_meta[{:valid, :dlq}].label == "invalid records"
  end

  test "supports clusters and cluster variables" do
    pipeline =
      dataflow do
        ingest_stage = stage("Ingestion")
        process_stage = cluster("Processing")

        kafka = source("Kafka", cluster: ingest_stage)
        parser = transform("Parser", cluster: process_stage)
        sink = sink("Warehouse", cluster: process_stage)

        kafka ~> parser |> emits("events")
        parser ~> sink |> writes("rows")
      end

    assert pipeline.clusters["cluster_ingest_stage"].label == "Ingestion"
    assert pipeline.clusters["cluster_process_stage"].label == "Processing"
    assert pipeline.graph.nodes[:kafka].cluster == "cluster_ingest_stage"
    assert pipeline.graph.nodes[:parser].cluster == "cluster_process_stage"
  end

  test "supports inline constructors for one-off sketches" do
    pipeline =
      dataflow do
        source("Kafka") ~> transform("Parser") |> emits("events")
      end

    assert pipeline.graph.nodes[:kafka].label == "Kafka"
    assert pipeline.graph.nodes[:parser].node_type == :transform
    assert [{:kafka, :parser, 1}] = Choreo.Dataflow.edges(pipeline)
  end

  test "supports id option while keeping display label" do
    pipeline =
      dataflow do
        src = source("Kafka Ingest", id: :kafka)
        out = sink("Warehouse")

        edge src ~> out, "events"
      end

    assert pipeline.graph.nodes[:kafka].label == "Kafka Ingest"
    assert pipeline.edge_meta[{:kafka, :out}].label == "events"
  end

  test "supports typed keyword edges and path types" do
    pipeline =
      dataflow do
        parser = transform("Parser")
        sink = sink("Warehouse")
        retry_q = queue("Retry Queue")
        errors = sink("Errors")

        edge parser ~> sink, writes: "valid rows"
        retry parser ~> retry_q, "temporary failure"
        error parser ~> errors, "invalid input"
      end

    assert pipeline.edge_meta[{:parser, :sink}].data_type == "valid rows"
    assert pipeline.edge_meta[{:parser, :sink}].path_type == :normal
    assert pipeline.edge_meta[{:parser, :retry_q}].path_type == :retry
    assert pipeline.edge_meta[{:parser, :errors}].path_type == :error
  end

  test "supports explicit data and rate modifiers" do
    pipeline =
      dataflow do
        in_stream = source("Input")
        out_stream = sink("Output")

        in_stream ~> out_stream |> data("json") |> rate("100/s")
      end

    assert pipeline.edge_meta[{:in_stream, :out_stream}].data_type == "json"
    assert pipeline.edge_meta[{:in_stream, :out_stream}].rate == "100/s"
    assert pipeline.edge_meta[{:in_stream, :out_stream}].label == "json"
  end

  test "supports edge/3 with label and keyword options" do
    pipeline =
      dataflow do
        src = source("Ingest")
        dst = sink("Storage")

        edge(src ~> dst, "raw stream", rate: "500/s", path_type: :normal)
      end

    assert pipeline.edge_meta[{:src, :dst}].label == "raw stream"
    assert pipeline.edge_meta[{:src, :dst}].rate == "500/s"
    assert pipeline.edge_meta[{:src, :dst}].path_type == :normal
  end

  test "supports cluster blocks and inherited scoping" do
    pipeline =
      dataflow do
        ingest = source("Ingest")

        cluster "order_service", label: "Order Service" do
          handler = transform("Handler")
          queue = buffer("Queue")

          handler ~> queue |> emits("events")
        end

        out = sink("Out")

        ingest ~> handler
        queue ~> out
      end

    assert pipeline.clusters["cluster_order_service"].label == "Order Service"
    assert pipeline.graph.nodes[:handler].cluster == "cluster_order_service"
    assert pipeline.graph.nodes[:queue].cluster == "cluster_order_service"
    assert pipeline.edge_meta[{:ingest, :handler}].path_type == :normal
    assert pipeline.edge_meta[{:queue, :out}].path_type == :normal
  end

  test "supports standalone node declarations updating variable scope" do
    pipeline =
      dataflow do
        source("Ingest Stream")
        sink("Data Sink")

        ingest_stream ~> data_sink |> emits("records")
      end

    assert pipeline.graph.nodes[:ingest_stream].label == "Ingest Stream"
    assert pipeline.graph.nodes[:data_sink].label == "Data Sink"
    assert pipeline.edge_meta[{:ingest_stream, :data_sink}].data_type == "records"
  end

  test "supports type modifier and combined options" do
    pipeline =
      dataflow do
        src = source("In")
        retry_q = buffer("Retry")
        dlq = sink("DLQ")
        dst = sink("Out")

        src ~> dst |> on("main", rate: "100/s")
        src ~> retry_q |> type(:retry, "retrying", rate: "10/s")
        src ~> dlq |> type(:dead_letter, "poison")
      end

    assert pipeline.edge_meta[{:src, :dst}].label == "main"
    assert pipeline.edge_meta[{:src, :dst}].rate == "100/s"
    assert pipeline.edge_meta[{:src, :retry_q}].path_type == :retry
    assert pipeline.edge_meta[{:src, :retry_q}].label == "retrying"
    assert pipeline.edge_meta[{:src, :retry_q}].rate == "10/s"
    assert pipeline.edge_meta[{:src, :dlq}].path_type == :dead_letter
    assert pipeline.edge_meta[{:src, :dlq}].label == "poison"
  end

  test "autocomplete helper stubs raise outside DSL block" do
    assert_raise RuntimeError, ~r/DSL constructor `on` must be called inside a DSL block/, fn ->
      on("payload")
    end

    assert_raise RuntimeError, ~r/DSL constructor `type` must be called inside a DSL block/, fn ->
      type(:retry)
    end

    assert_raise RuntimeError, ~r/DSL constructor `edge` must be called inside a DSL block/, fn ->
      edge(:a, :b)
    end
  end

  test "raises on unknown node variables" do
    assert_raise ArgumentError, ~r/unknown dataflow node variable `sink`/, fn ->
      Code.eval_quoted(
        quote do
          import Choreo.Lab.DSL.Dataflow

          dataflow do
            src = source("Input")
            src ~> sink
          end
        end
      )
    end
  end
end
