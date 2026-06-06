defmodule Choreo.C4Test do
  use ExUnit.Case

  doctest Choreo.C4
  doctest Choreo.C4.Render.DOT
  doctest Choreo.C4.Render.Mermaid
  doctest Choreo.C4.Analysis

  alias Choreo.C4

  describe "new/0" do
    test "creates an empty C4 model" do
      c4 = C4.new()
      assert C4.nodes(c4) == []
      assert C4.edges(c4) == []
      assert c4.scope == nil
    end
  end

  describe "add_person/3" do
    test "adds a person node" do
      c4 = C4.new() |> C4.add_person(:customer, label: "Customer")
      assert :customer in C4.nodes(c4)
      assert Map.get(c4.graph.nodes, :customer).node_type == :person
      assert Map.get(c4.graph.nodes, :customer).label == "Customer"
    end

    test "raises on arbitrary options" do
      assert_raise NimbleOptions.ValidationError, fn ->
        C4.new() |> C4.add_person(:customer, arbitrary: true)
      end
    end
  end

  describe "add_software_system/3" do
    test "adds a software system node" do
      c4 = C4.new() |> C4.add_software_system(:banking, label: "Banking", scope: :in)
      assert :banking in C4.nodes(c4)
      assert Map.get(c4.graph.nodes, :banking).node_type == :software_system
      assert Map.get(c4.graph.nodes, :banking).scope == :in
    end

    test "defaults scope to :out" do
      c4 = C4.new() |> C4.add_software_system(:banking)
      assert Map.get(c4.graph.nodes, :banking).scope == :out
    end
  end

  describe "add_container/3" do
    test "adds a container with parent" do
      c4 =
        C4.new()
        |> C4.add_software_system(:banking)
        |> C4.add_container(:api, label: "API", technology: "Phoenix", parent: :banking)

      assert :api in C4.nodes(c4)
      assert Map.get(c4.graph.nodes, :api).node_type == :container
      assert Map.get(c4.graph.nodes, :api).parent == :banking
      assert Map.get(c4.graph.nodes, :api).technology == "Phoenix"
    end

    test "auto-assigns cluster from parent" do
      c4 =
        C4.new()
        |> C4.add_software_system(:banking)
        |> C4.add_container(:api, parent: :banking)

      assert Map.get(c4.graph.nodes, :api).cluster == "cluster_banking"
    end
  end

  describe "add_component/3" do
    test "adds a component with parent" do
      c4 =
        C4.new()
        |> C4.add_software_system(:banking)
        |> C4.add_container(:api, parent: :banking)
        |> C4.add_component(:auth, label: "Auth", technology: "Phoenix", parent: :api)

      assert :auth in C4.nodes(c4)
      assert Map.get(c4.graph.nodes, :auth).node_type == :component
      assert Map.get(c4.graph.nodes, :auth).parent == :api
    end
  end

  describe "add_relationship/3" do
    test "adds a relationship between nodes" do
      c4 =
        C4.new()
        |> C4.add_person(:customer)
        |> C4.add_software_system(:banking)
        |> C4.add_relationship(:customer, :banking, label: "Uses")

      assert [{:customer, :banking, 1}] == C4.edges(c4)
      [{_, _, _, meta}] = C4.edges_with_meta(c4)
      assert meta.label == "Uses"
    end

    test "auto-creates missing nodes" do
      c4 = C4.new() |> C4.add_relationship(:a, :b, label: "Uses")
      assert :a in C4.nodes(c4)
      assert :b in C4.nodes(c4)
    end
  end

  describe "add_cluster/3" do
    test "adds a cluster with prefix" do
      c4 = C4.new() |> C4.add_cluster("banking", label: "Internet Banking")
      assert c4.clusters["cluster_banking"].label == "Internet Banking"
    end

    test "preserves existing cluster_ prefix" do
      c4 = C4.new() |> C4.add_cluster("cluster_internal")
      assert Map.has_key?(c4.clusters, "cluster_internal")
    end
  end

  describe "scope/2" do
    test "sets and clears scope" do
      c4 = C4.new() |> C4.add_software_system(:banking)
      c4 = C4.set_scope(c4, :banking)
      assert C4.scope(c4) == :banking

      c4 = C4.clear_scope(c4)
      assert C4.scope(c4) == nil
    end

    test "raises when scope node does not exist" do
      assert_raise ArgumentError, fn ->
        C4.new() |> C4.set_scope(:missing)
      end
    end
  end

  describe "parent/2 and children/2" do
    test "returns parent and children" do
      c4 =
        C4.new()
        |> C4.add_software_system(:banking)
        |> C4.add_container(:api, parent: :banking)
        |> C4.add_container(:web, parent: :banking)

      assert C4.parent(c4, :api) == :banking
      assert C4.children(c4, :banking) == [:api, :web]
      assert C4.parent(c4, :banking) == nil
    end
  end

  describe "nodes_of_type/2" do
    test "filters by node type" do
      c4 =
        C4.new()
        |> C4.add_person(:a)
        |> C4.add_person(:b)
        |> C4.add_software_system(:c)

      assert Enum.sort(C4.nodes_of_type(c4, :person)) == [:a, :b]
      assert C4.nodes_of_type(c4, :software_system) == [:c]
      assert C4.nodes_of_type(c4, :container) == []
    end
  end

  describe "to_dot/2" do
    test "renders to DOT" do
      c4 =
        C4.new()
        |> C4.add_person(:user, label: "User")
        |> C4.add_software_system(:app, label: "App")
        |> C4.add_relationship(:user, :app, label: "Uses")

      dot = C4.to_dot(c4)
      assert String.contains?(dot, "digraph")
      assert String.contains?(dot, "User")
      assert String.contains?(dot, "App")
    end
  end

  describe "to_mermaid/2" do
    test "renders to Mermaid" do
      c4 =
        C4.new()
        |> C4.add_person(:user, label: "User")
        |> C4.add_software_system(:app, label: "App")
        |> C4.add_relationship(:user, :app, label: "Uses")

      mermaid = C4.to_mermaid(c4)
      assert String.contains?(mermaid, "graph LR")
      assert String.contains?(mermaid, "User")
      assert String.contains?(mermaid, "App")
    end
  end

  describe "zoom_predicate via Choreo.View" do
    test "level 0 shows only person and software_system" do
      c4 =
        C4.new()
        |> C4.add_person(:user)
        |> C4.add_software_system(:banking)
        |> C4.add_container(:api, parent: :banking)
        |> C4.add_component(:auth, parent: :api)

      zoomed = Choreo.View.zoom(c4, level: 0)
      assert Enum.sort(Choreo.C4.nodes(zoomed)) == [:banking, :user]
    end

    test "level 1 includes containers" do
      c4 =
        C4.new()
        |> C4.add_person(:user)
        |> C4.add_software_system(:banking)
        |> C4.add_container(:api, parent: :banking)
        |> C4.add_component(:auth, parent: :api)

      zoomed = Choreo.View.zoom(c4, level: 1)
      assert Enum.sort(Choreo.C4.nodes(zoomed)) == [:api, :banking, :user]
    end

    test "level 2 includes components" do
      c4 =
        C4.new()
        |> C4.add_person(:user)
        |> C4.add_software_system(:banking)
        |> C4.add_container(:api, parent: :banking)
        |> C4.add_component(:auth, parent: :api)

      zoomed = Choreo.View.zoom(c4, level: 2)
      assert Enum.sort(Choreo.C4.nodes(zoomed)) == [:api, :auth, :banking, :user]
    end
  end
end
