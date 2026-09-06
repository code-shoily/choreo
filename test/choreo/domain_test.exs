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
    assert length(warnings) == 7

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

    assert Enum.any?(warnings, fn {_sev, w} ->
             w =~ "order_agg" and w =~ "no documented invariants"
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

  test "supports DDD semantic relationship helpers and aggregate invariants" do
    domain =
      Domain.new()
      |> Domain.add_actor(:customer, label: "Customer")
      |> Domain.add_command(:place_order, label: "Place Order")
      |> Domain.add_aggregate(:order,
        label: "Order",
        invariants: ["An order cannot be paid before pricing."]
      )
      |> Domain.add_event(:order_placed, label: "Order Placed")
      |> Domain.add_read_model(:order_summary, label: "Order Summary")
      |> Domain.initiates(:customer, :place_order)
      |> Domain.handles(:place_order, :order)
      |> Domain.emits(:order, :order_placed)
      |> Domain.projects_to(:order_placed, :order_summary)

    assert [] = Analysis.validate(domain)

    mermaid = Domain.to_mermaid(domain)
    assert mermaid =~ "initiates"
    assert mermaid =~ "projects to"
  end

  test "supports subdomain metadata on bounded contexts" do
    map =
      Domain.new()
      |> Domain.add_context(:ordering,
        label: "Ordering",
        subdomain: :core,
        owner: "Checkout Team"
      )
      |> Domain.add_context(:billing, label: "Billing", subdomain: :supporting)
      |> Domain.connect_contexts(:ordering, :billing, relationship: :customer_supplier)

    assert map.graph.nodes.ordering.subdomain == :core
    assert map.graph.nodes.ordering.owner == "Checkout Team"

    refute Enum.any?(Analysis.validate(map), fn {_severity, message} -> message =~ "subdomain" end)
  end

  test "supports named scenarios and native Mermaid eventmodeling projection" do
    domain =
      Domain.new()
      |> Domain.add_actor(:customer, label: "Customer")
      |> Domain.add_command(:place_order, label: "Place Order")
      |> Domain.add_aggregate(:order,
        label: "Order",
        invariants: ["Cannot place an empty order."]
      )
      |> Domain.add_event(:order_placed, label: "Order Placed")
      |> Domain.add_policy(:payment_policy, label: "Payment Policy")
      |> Domain.add_command(:authorize_payment, label: "Authorize Payment")
      |> Domain.add_read_model(:order_summary, label: "Order Summary")
      |> Domain.initiates(:customer, :place_order)
      |> Domain.handles(:place_order, :order)
      |> Domain.emits(:order, :order_placed)
      |> Domain.triggers(:order_placed, :payment_policy)
      |> Domain.triggers(:payment_policy, :authorize_payment)
      |> Domain.projects_to(:order_placed, :order_summary)
      |> Domain.add_scenario(:happy_path,
        label: "Happy path",
        path: [
          :customer,
          :place_order,
          :order,
          :order_placed,
          :payment_policy,
          :authorize_payment
        ]
      )

    focused = Domain.focus_scenario(domain, :happy_path)
    assert focused.highlighted_nodes == Domain.scenario(domain, :happy_path).path

    mermaid = Domain.to_mermaid(domain, syntax: :event_modeling, scenario: :happy_path)
    assert mermaid =~ "eventmodeling"
    assert mermaid =~ "tf 01 ui Customer"
    assert mermaid =~ "tf 02 cmd PlaceOrder"
    assert mermaid =~ "tf 03 evt OrderPlaced"
    assert mermaid =~ "tf 04 pcr PaymentPolicy"
    assert mermaid =~ "tf 05 cmd AuthorizePayment"
  end

  test "validates scenario paths and semantic relationship endpoint shapes" do
    domain =
      Domain.new()
      |> Domain.add_actor(:customer)
      |> Domain.add_event(:order_placed)
      |> Domain.add_command(:place_order)
      |> Domain.handles(:customer, :order_placed)
      |> Domain.add_scenario(:broken, path: [:customer, :missing, :place_order])

    warnings = Analysis.validate(domain)

    assert Enum.any?(warnings, fn {_severity, message} ->
             message =~ "Relationship :handles" and message =~ "unusual endpoint types"
           end)

    assert Enum.any?(warnings, fn {severity, message} ->
             severity == :error and message =~ "Scenario :broken references missing nodes"
           end)
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

  test "supports all strategic DDD relationship types in connect_contexts/4" do
    base =
      Domain.new()
      |> Domain.add_context(:ctx_a, label: "Context A")
      |> Domain.add_context(:ctx_b, label: "Context B")

    rels = [
      {:shared_kernel, "[Shared Kernel]"},
      {:customer_supplier, "[U: Supplier] -> [D: Customer]"},
      {:conformist, "[U: Supplier] -> [D: Conformist]"},
      {:open_host_service, "[U: OHS] -> [D]"},
      {:published_language, "[U: PL] -> [D]"},
      {:acl, "[U] -> [ACL] -> [D]"}
    ]

    for {rel, expected_label} <- rels do
      connected = Domain.connect_contexts(base, :ctx_a, :ctx_b, relationship: rel)
      assert [{:ctx_a, :ctx_b, 1}] = Domain.edges(connected)
      dot = Domain.to_dot(connected)
      assert dot =~ expected_label
    end
  end

  test "connect_contexts/4 raises ArgumentError on invalid endpoints" do
    d =
      Domain.new()
      |> Domain.add_context(:ctx_a)
      |> Domain.add_actor(:actor_b)

    assert_raise ArgumentError, ~r/requires both endpoints to exist/, fn ->
      Domain.connect_contexts(d, :ctx_a, :missing, relationship: :shared_kernel)
    end

    assert_raise ArgumentError, ~r/requires both endpoints to be :context nodes/, fn ->
      Domain.connect_contexts(d, :ctx_a, :actor_b, relationship: :shared_kernel)
    end
  end

  test "connect/4 raises ArgumentError when endpoints do not exist" do
    d = Domain.new() |> Domain.add_command(:cmd_a)

    assert_raise ArgumentError, ~r/Node :missing_b does not exist/, fn ->
      Domain.connect(d, :cmd_a, :missing_b)
    end

    assert_raise ArgumentError, ~r/Node :missing_a does not exist/, fn ->
      Domain.connect(d, :missing_a, :cmd_a)
    end
  end

  test "supports notifies and translates_via semantic connections" do
    d =
      Domain.new()
      |> Domain.add_actor(:user, label: "User")
      |> Domain.add_event(:order_shipped, label: "Order Shipped")
      |> Domain.add_external_system(:stripe, label: "Stripe")
      |> Domain.add_acl(:stripe_acl, label: "Stripe Gateway")
      |> Domain.add_workflow(:shipping_flow, label: "Shipping Flow")
      |> Domain.notifies(:order_shipped, :user)
      |> Domain.translates_via(:stripe, :stripe_acl)

    mermaid = Domain.to_mermaid(d)
    assert mermaid =~ "notifies"
    assert mermaid =~ "translates via"
  end

  test "focus_scenario/2 raises on non-existent scenario and clear_focus/1 resets focus" do
    d =
      Domain.new()
      |> Domain.add_actor(:user)
      |> Domain.add_command(:cmd)
      |> Domain.connect(:user, :cmd)

    assert_raise ArgumentError, ~r/Scenario :unknown does not exist/, fn ->
      Domain.focus_scenario(d, :unknown)
    end

    focused = Domain.focus_path(d, [:user, :cmd])
    assert focused.highlighted_nodes == [:user, :cmd]
    cleared = Domain.clear_focus(focused)
    assert cleared.highlighted_nodes == []
    assert cleared.highlighted_edges == []
  end

  test "causes/2 returns empty list for non-existent target" do
    d = Domain.new() |> Domain.add_actor(:user)
    assert Domain.causes(d, :missing) == []
  end

  test "infers single linear event modeling path automatically" do
    d =
      Domain.new()
      |> Domain.add_actor(:customer, label: "Customer")
      |> Domain.add_command(:submit, label: "Submit")
      |> Domain.add_event(:submitted, label: "Submitted")
      |> Domain.connect(:customer, :submit)
      |> Domain.connect(:submit, :submitted)

    em = Domain.to_mermaid(d, syntax: :event_modeling)
    assert em =~ "eventmodeling"
    assert em =~ "tf 01 ui Customer"
    assert em =~ "tf 02 cmd Submit"
    assert em =~ "tf 03 evt Submitted"
  end

  test "raises ArgumentError when inferring event modeling path on branching graph" do
    d =
      Domain.new()
      |> Domain.add_actor(:customer)
      |> Domain.add_command(:cmd1)
      |> Domain.add_command(:cmd2)
      |> Domain.connect(:customer, :cmd1)
      |> Domain.connect(:customer, :cmd2)

    assert_raise ArgumentError, ~r/Cannot infer Event Modeling timeline/, fn ->
      Domain.to_mermaid(d, syntax: :event_modeling)
    end
  end

  test "supports namespaced cluster entity IDs in event modeling" do
    d =
      Domain.new()
      |> Domain.add_context_boundary("orders", label: "Orders Boundary")
      |> Domain.add_command(:place, label: "Place", cluster: "orders")
      |> Domain.add_read_model(:summary, label: "Summary", cluster: "orders")
      |> Domain.add_workflow(:process, label: "Process", cluster: "orders")
      |> Domain.add_acl(:payment_gateway, label: "Gateway", cluster: "orders")
      |> Domain.add_external_system(:bank, label: "Bank")

    em =
      Domain.to_mermaid(d,
        syntax: :event_modeling,
        path: [:place, :summary, :process, :payment_gateway, :bank]
      )

    assert em =~ "tf 01 cmd OrdersBoundary.Place"
    assert em =~ "tf 02 rmo OrdersBoundary.Summary"
    assert em =~ "tf 03 pcr OrdersBoundary.Process"
    assert em =~ "tf 04 pcr OrdersBoundary.Gateway"
    assert em =~ "tf 05 pcr Bank"
  end

  test "supports union types in class_diagram and erd rendering, plus empty entity in erd" do
    d =
      Domain.new()
      |> Domain.add_type(:order_state,
        fields: [
          {:status, [:draft, :submitted, :cancelled]}
        ]
      )
      |> Domain.add_type(:empty_state)

    classes = Domain.to_mermaid(d, syntax: :class_diagram)
    assert classes =~ "+status draft | submitted | cancelled"

    erd = Domain.to_mermaid(d, syntax: :erd)
    assert erd =~ "draft_or_submitted_or_cancelled status"
    assert erd =~ "empty_state"
  end

  test "implements Choreo.Viewable zoom levels and Choreo.theme/2" do
    d =
      Domain.new()
      |> Domain.add_context(:orders, label: "Orders")
      |> Domain.add_actor(:buyer, label: "Buyer")
      |> Domain.add_command(:pay, label: "Pay")
      |> Domain.add_aggregate(:order_agg, label: "Order Agg")
      |> Domain.add_event(:paid, label: "Paid")
      |> Domain.add_read_model(:dashboard, label: "Dashboard")
      |> Domain.connect(:buyer, :pay)
      |> Domain.connect(:pay, :order_agg)
      |> Domain.connect(:order_agg, :paid)
      |> Domain.connect(:paid, :dashboard)

    # Zoom 0 keeps only :context and :actor
    z0 = Choreo.View.zoom(d, level: 0)
    z0_nodes = Map.keys(Domain.nodes(z0))
    assert :orders in z0_nodes
    assert :buyer in z0_nodes
    refute :pay in z0_nodes

    # Zoom 1 keeps :context, :actor, :command, :aggregate, :event
    z1 = Choreo.View.zoom(d, level: 1)
    z1_nodes = Map.keys(Domain.nodes(z1))
    assert :pay in z1_nodes
    refute :dashboard in z1_nodes

    # Zoom 2 keeps everything
    z2 = Choreo.View.zoom(d, level: 2)
    assert Map.has_key?(Domain.nodes(z2), :dashboard)

    # Theme helper
    t = Domain.theme(:sketch)
    assert %Choreo.Theme{} = t

    # Deprecated trace_cause alias
    assert Domain.trace_cause(d, :paid) == Domain.causes(d, :paid)

    # Viewable rebuild with filtered highlights
    focused_d = Domain.focus_path(d, [:buyer, :pay])
    focused_z0 = Choreo.View.zoom(focused_d, level: 0)
    assert focused_z0.highlighted_nodes == [:buyer]
  end
end
