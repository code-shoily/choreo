defmodule Choreo.DomainTest do
  use ExUnit.Case, async: true

  doctest Choreo.Domain

  alias Choreo.Domain
  alias Choreo.Domain.Analysis

  test "can build high level context maps" do
    map =
      Domain.new()
      |> Domain.add_context(:order_taking, label: "Order Taking")
      |> Domain.add_context(:billing, label: "Billing")
      |> Domain.connect_contexts(:order_taking, :billing,
        relationship: :customer_supplier,
        label: "Request invoice"
      )

    assert %Domain{} = map
    nodes = Domain.nodes(map)
    assert Map.has_key?(nodes, :order_taking)
    assert Map.has_key?(nodes, :billing)

    edges = Domain.edges(map)
    assert length(edges) == 1

    dot = Domain.to_dot(map)
    assert dot =~ "order_taking"
    assert dot =~ "billing"
    assert dot =~ "Request invoice"
    assert dot =~ "Supplier"

    mermaid = Domain.to_mermaid(map)
    assert mermaid =~ "Order Taking"
    assert mermaid =~ "Request invoice"
  end

  test "can build tactical event storming graphs with cluster boundaries" do
    storm =
      Domain.new()
      |> Domain.add_context_boundary("checkout", label: "Checkout Context")
      |> Domain.add_actor(:customer, label: "Customer")
      |> Domain.add_command(:place_order, label: "Place Order", cluster: "checkout")
      |> Domain.add_aggregate(:order_agg, label: "Order", cluster: "checkout")
      |> Domain.add_event(:order_placed, label: "Order Placed", cluster: "checkout")
      |> Domain.add_policy(:payment_saga, label: "Payment Saga", cluster: "checkout")
      |> Domain.connect(:customer, :place_order)
      |> Domain.connect(:place_order, :order_agg)
      |> Domain.connect(:order_agg, :order_placed)
      |> Domain.connect(:order_placed, :payment_saga)

    assert %Domain{} = storm
    dot = Domain.to_dot(storm)
    assert dot =~ "subgraph cluster_checkout"
    assert dot =~ "place_order"
  end

  test "supports UML class/type field rendering in DOT and Mermaid" do
    domain =
      Domain.new()
      |> Domain.add_type(:unvalidated_order,
        label: "Unvalidated Order",
        fields: [
          {:customer_id, :string},
          {:lines, "list of UnvalidatedLine"}
        ]
      )

    dot = Domain.to_dot(domain)
    # Checks that HTML tables are generated
    assert dot =~ "<TABLE"
    assert dot =~ "customer_id"
    assert dot =~ "Unvalidated Order"

    mermaid = Domain.to_mermaid(domain)
    # Checks that field info is rendered separated by <br> tags in strings
    assert mermaid =~ "customer_id"
    assert mermaid =~ "list of UnvalidatedLine"
  end

  test "can trace path scenarios using highlight properties" do
    storm =
      Domain.new()
      |> Domain.add_actor(:customer)
      |> Domain.add_command(:place_order)
      |> Domain.add_aggregate(:order_agg)
      |> Domain.connect(:customer, :place_order)
      |> Domain.connect(:place_order, :order_agg)

    focused = Domain.focus_path(storm, [:customer, :place_order])
    assert focused.highlighted_nodes == [:customer, :place_order]
    assert focused.highlighted_edges == [{:customer, :place_order}]
  end

  test "traces root causes correctly" do
    storm =
      Domain.new()
      |> Domain.add_actor(:customer)
      |> Domain.add_command(:place_order)
      |> Domain.add_aggregate(:order_agg)
      |> Domain.add_event(:order_placed)
      |> Domain.connect(:customer, :place_order)
      |> Domain.connect(:place_order, :order_agg)
      |> Domain.connect(:order_agg, :order_placed)

    ancestors = Domain.causes(storm, :order_placed)
    assert :order_placed in ancestors
    assert :order_agg in ancestors
    assert :place_order in ancestors
    assert :customer in ancestors
  end

  test "enforces semantic Event Storming validator rules" do
    storm =
      Domain.new()
      # Dangling command (no target aggregate)
      |> Domain.add_command(:orphan_cmd, label: "Orphan Cmd")
      # Event missing a cause
      |> Domain.add_event(:mysterious_event, label: "Mysterious Event")
      # Dead-end event (no outbound edges)
      |> Domain.add_aggregate(:order_agg)
      |> Domain.add_event(:dead_end_event, label: "Dead End Event")
      |> Domain.connect(:order_agg, :dead_end_event)
      # Policy missing triggered command
      |> Domain.add_policy(:dangling_policy, label: "Dangling Policy")

    warnings = Analysis.warnings(storm)
    assert length(warnings) == 6

    assert Enum.any?(warnings, fn {_sev, w} -> w =~ "Orphan Cmd" and w =~ "orphaned" end)

    assert Enum.any?(warnings, fn {_sev, w} ->
             w =~ "Mysterious Event" and w =~ "missing a cause"
           end)

    assert Enum.any?(warnings, fn {_sev, w} -> w =~ "Dead End Event" and w =~ "dead-end" end)

    assert Enum.any?(warnings, fn {_sev, w} ->
             w =~ "Dangling Policy" and w =~ "does not trigger"
           end)

    assert Enum.any?(warnings, fn {_sev, w} ->
             w =~ "order_agg" and w =~ "no incoming commands"
           end)
  end

  test "extracts term definitions into a Ubiquitous Language glossary table" do
    map =
      Domain.new()
      |> Domain.add_context_boundary("checkout", label: "Checkout Context")
      |> Domain.add_aggregate(:order_agg,
        label: "Order Aggregate",
        cluster: "checkout",
        description: "Consistency boundary wrapping order entities."
      )

    glossary = Analysis.ubiquitous_language(map)
    assert glossary =~ "| Term | Stereotype | Bounded Context | Description"
    assert glossary =~ "**Order Aggregate**"
    assert glossary =~ "`Aggregate`"
    assert glossary =~ "Checkout Context"
    assert glossary =~ "Consistency boundary wrapping order entities."
  end

  test "supports native class_diagram and erd syntax overrides in to_mermaid/2" do
    map =
      Domain.new()
      |> Domain.add_aggregate(:order_agg,
        label: "Order",
        fields: [
          {:id, :uuid},
          {:total, :money}
        ]
      )
      |> Domain.add_type(:order_line,
        label: "OrderLine",
        fields: [
          {:product_id, :string}
        ]
      )
      |> Domain.connect(:order_agg, :order_line, label: "has")

    # Native Class Diagram syntax
    classes = Domain.to_mermaid(map, syntax: :class_diagram)
    assert classes =~ "classDiagram"
    assert classes =~ "class order_agg {"
    assert classes =~ "<<aggregate>>"
    assert classes =~ "+id uuid"
    assert classes =~ "order_agg --> order_line : has"

    # Native ERD syntax
    erd = Domain.to_mermaid(map, syntax: :erd)
    assert erd =~ "erDiagram"
    assert erd =~ "order_agg {"
    assert erd =~ "uuid id"
    assert erd =~ "order_agg }|..|{ order_line : \"has\""
  end
end
