defmodule Choreo.Lab.DomainDSLTest do
  use ExUnit.Case

  doctest Choreo.Lab.DSL.Domain

  import Choreo.Lab.DSL.Domain

  alias Choreo.Domain
  alias Choreo.Domain.Analysis

  test "taxonomy returns the Livebook discovery vocabulary" do
    taxonomy = Choreo.Lab.DSL.Domain.taxonomy()

    assert :aggregate in taxonomy.nodes
    assert :context in taxonomy.nodes
    assert :context_boundary in taxonomy.clusters
    assert :emits in taxonomy.edges
    assert :scenario in taxonomy.events
    assert :with in taxonomy.options
    assert Choreo.Lab.DSL.Domain.verbs() == taxonomy
  end

  test "builds a tactical event-storming model with variable-bound nodes" do
    model =
      domain do
        checkout = context_boundary("Checkout")
        customer = actor("Customer")
        place_order = command("Place Order", cluster: checkout)

        order =
          aggregate("Order", cluster: checkout, invariants: ["Cannot place an empty order."])

        placed = event("Order Placed", cluster: checkout)
        summary = read_model("Order Summary", cluster: checkout)

        customer ~> place_order |> initiates("starts")
        place_order ~> order |> handles("validates")
        order ~> placed |> emits("records")
        placed ~> summary |> projects_to("updates")
      end

    assert model.clusters["cluster_checkout"].label == "Checkout"
    assert Domain.nodes(model).order.type == :aggregate
    assert Domain.nodes(model).order.cluster == "cluster_checkout"
    assert Domain.nodes(model).summary.type == :read_model
    assert [] = Analysis.validate(model)

    edge_meta = Map.values(model.edge_meta)
    assert Enum.any?(edge_meta, &(&1.relationship == :initiates and &1.label == "starts"))
    assert Enum.any?(edge_meta, &(&1.relationship == :projects_to and &1.label == "updates"))
  end

  test "builds strategic context maps with context relationships" do
    model =
      domain do
        ordering = context("Ordering", subdomain: :core, owner: "Checkout Team")
        billing = bounded_context("Billing", subdomain: :supporting)
        shipping = context("Shipping", subdomain: :supporting)

        customer_supplier(ordering ~> billing, "Invoice requests")
        anti_corruption(billing ~> shipping, "Shipment adapter")
      end

    assert Domain.nodes(model).ordering.type == :context
    assert Domain.nodes(model).ordering.subdomain == :core

    relationships = Enum.map(Map.values(model.edge_meta), & &1.relationship)
    assert :customer_supplier in relationships
    assert :acl in relationships

    labels = Enum.map(Map.values(model.edge_meta), & &1.label)
    assert Enum.any?(labels, &String.contains?(&1, "Invoice requests"))
    assert Enum.any?(labels, &String.contains?(&1, "Shipment adapter"))
  end

  test "builds a domain model with nested context blocks" do
    model =
      domain do
        customer = actor("Customer")

        context_boundary("Checkout") do
          place_order = command("Place Order")
          order = aggregate("Order", invariants: ["Cannot place empty order."])
        end

        customer ~> place_order |> initiates("starts")
      end

    assert model.clusters["cluster_checkout"].label == "Checkout"
    assert Domain.nodes(model).order.type == :aggregate
    assert Domain.nodes(model).order.cluster == "cluster_checkout"
    assert Domain.nodes(model).place_order.type == :command
    assert Domain.nodes(model).place_order.cluster == "cluster_checkout"
  end

  test "supports inline constructors for one-off sketches" do
    model =
      domain do
        actor("Customer") ~> command("Place Order") |> initiates("submits")
      end

    assert Map.has_key?(Domain.nodes(model), :customer)
    assert Map.has_key?(Domain.nodes(model), :place_order)
    assert [{:customer, :place_order, _weight}] = Domain.edges(model)
    assert [%{relationship: :initiates, label: "submits"}] = Map.values(model.edge_meta)
  end

  test "supports id options, type fields, and generic edges" do
    model =
      domain do
        order = aggregate("Order Aggregate", id: :order, fields: [{:id, :uuid}])
        line = type("Order Line", id: :order_line, fields: [{:product_id, :string}])

        edge order ~> line, "has lines"
      end

    assert Domain.nodes(model).order.name == "Order Aggregate"
    assert Domain.nodes(model).order_line.fields == [{:product_id, :string}]
    assert [{:order, :order_line, _weight}] = Domain.edges(model)
    assert [%{label: "has lines", type: :sequence}] = Map.values(model.edge_meta)
  end

  test "supports named scenarios with variable-bound paths" do
    model =
      domain do
        customer = actor("Customer")
        place_order = command("Place Order")
        order = aggregate("Order", invariants: ["Cannot place an empty order."])
        placed = domain_event("Order Placed")
        summary = projection("Order Summary")

        customer ~> place_order |> initiates("starts")
        place_order ~> order |> handles("validates")
        order ~> placed |> emits("records")
        placed ~> summary |> projects_to("updates")

        scenario(:happy_path, "Happy path", path: [customer, place_order, order, placed, summary])
      end

    assert Domain.scenario(model, :happy_path).label == "Happy path"

    assert Domain.scenario(model, :happy_path).path == [
             :customer,
             :place_order,
             :order,
             :placed,
             :summary
           ]

    focused = Domain.focus_scenario(model, :happy_path)
    assert focused.highlighted_nodes == [:customer, :place_order, :order, :placed, :summary]
  end

  test "supports typed edge keyword forms" do
    model =
      domain do
        order = aggregate("Order", invariants: ["Cannot place an empty order."])
        placed = event("Order Placed")
        policy = policy("Payment Policy")
        authorize = command("Authorize Payment")
        customer = user("Customer")

        edge order ~> placed, emits: "records"
        edge placed ~> policy, triggers: "reacts"
        edge policy ~> authorize, triggers: "dispatches"
        edge placed ~> customer, notifies: "email"
      end

    edge_meta = Map.values(model.edge_meta)
    assert Enum.any?(edge_meta, &(&1.relationship == :emits and &1.label == "records"))
    assert Enum.any?(edge_meta, &(&1.relationship == :notifies and &1.label == "email"))
  end

  test "raises on unknown node variables" do
    assert_raise ArgumentError, ~r/unknown domain node variable `missing`/, fn ->
      Code.eval_quoted(
        quote do
          import Choreo.Lab.DSL.Domain

          domain do
            order = aggregate("Order")
            order ~> missing
          end
        end
      )
    end
  end

  test "raises on unknown cluster variables" do
    assert_raise ArgumentError, ~r/unknown domain cluster variable `checkout`/, fn ->
      Code.eval_quoted(
        quote do
          import Choreo.Lab.DSL.Domain

          domain do
            command("Place Order", cluster: checkout)
          end
        end
      )
    end
  end
end
