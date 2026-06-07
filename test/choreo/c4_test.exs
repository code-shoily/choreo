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

    test "supports themes and options" do
      c4 =
        C4.new()
        |> C4.add_person(:user, label: "User")
        |> C4.add_software_system(:app, label: "App")
        |> C4.add_container(:api, label: "API", parent: :app)
        |> C4.add_component(:auth, label: "Auth", parent: :api)
        |> C4.add_relationship(:user, :app, label: "Uses")

      for theme <- [:dark, :warm, :forest, :ocean, :default, :custom, :invalid] do
        theme_opt =
          if theme == :custom,
            do: %Choreo.Theme{name: :custom, colors: %{person: "#ff0000"}},
            else: theme

        dot =
          C4.to_dot(c4,
            theme: theme_opt,
            highlighted_nodes: [:user],
            highlighted_edges: [{:user, :app}]
          )

        assert dot =~ "digraph"
      end

      assert %Choreo.Theme{name: :c4_warm} = Choreo.C4.Render.DOT.theme(:warm)
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

    test "supports themes and options" do
      c4 =
        C4.new()
        |> C4.add_person(:user, label: "User")
        |> C4.add_software_system(:app, label: "App")
        |> C4.add_container(:api, label: "API", parent: :app)
        |> C4.add_component(:auth, label: "Auth", parent: :api)
        |> C4.add_relationship(:user, :app, label: "Uses")

      for theme <- [:dark, :warm, :forest, :ocean, :default, :custom, :invalid] do
        theme_opt =
          if theme == :custom,
            do: %Choreo.Theme{name: :custom, colors: %{person: "#ff0000"}},
            else: theme

        mermaid =
          C4.to_mermaid(c4,
            theme: theme_opt,
            direction: :td,
            highlighted_nodes: [:user],
            highlighted_edges: [{:user, :app}]
          )

        assert mermaid =~ "graph TD"
      end

      assert %Choreo.Theme{name: :c4_warm} = Choreo.C4.Render.Mermaid.theme(:warm)
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

    test "scoped level 0 (System Context) rolls up container and component relationships" do
      c4 =
        C4.new()
        |> C4.add_person(:customer)
        |> C4.add_software_system(:banking, scope: :in)
        |> C4.add_software_system(:mainframe, scope: :out)
        |> C4.add_container(:web_app, parent: :banking)
        |> C4.add_container(:api, parent: :banking)
        |> C4.add_component(:auth, parent: :api)
        |> C4.add_relationship(:customer, :web_app, label: "Uses")
        |> C4.add_relationship(:web_app, :auth, label: "Calls")
        |> C4.add_relationship(:auth, :mainframe, label: "Queries")

      zoomed = Choreo.View.zoom(c4, level: 0)

      # In System Context, we expect only people and systems
      assert Enum.sort(C4.nodes(zoomed)) == [:banking, :customer, :mainframe]

      # Edges should roll up to the systems
      edges = C4.edges_with_meta(zoomed)
      assert length(edges) == 2

      # :customer -> :web_app rolls up to :customer -> :banking
      assert Enum.any?(edges, fn {from, to, _, meta} ->
               from == :customer and to == :banking and meta.label == "Uses"
             end)

      # :auth -> :mainframe rolls up to :banking -> :mainframe
      assert Enum.any?(edges, fn {from, to, _, meta} ->
               from == :banking and to == :mainframe and meta.label == "Queries"
             end)
    end

    test "scoped level 1 (Container diagram) zooms into the scoped system" do
      c4 =
        C4.new()
        |> C4.add_person(:customer)
        |> C4.add_software_system(:banking, scope: :in)
        |> C4.add_software_system(:mainframe, scope: :out)
        |> C4.add_container(:web_app, parent: :banking)
        |> C4.add_container(:api, parent: :banking)
        |> C4.add_component(:auth, parent: :api)
        |> C4.add_relationship(:customer, :web_app, label: "Uses")
        |> C4.add_relationship(:web_app, :auth, label: "Calls")
        |> C4.add_relationship(:auth, :mainframe, label: "Queries")

      zoomed = Choreo.View.zoom(c4, level: 1)

      # In Container diagram, we expect customer, mainframe, and containers of :banking
      # :banking system itself is removed (it's the boundary)
      assert Enum.sort(C4.nodes(zoomed)) == [:api, :customer, :mainframe, :web_app]

      edges = C4.edges_with_meta(zoomed)
      assert length(edges) == 3

      # :customer -> :web_app remains
      assert Enum.any?(edges, fn {from, to, _, meta} ->
               from == :customer and to == :web_app and meta.label == "Uses"
             end)

      # :web_app -> :auth rolls up to :web_app -> :api (since :auth is in :api)
      assert Enum.any?(edges, fn {from, to, _, meta} ->
               from == :web_app and to == :api and meta.label == "Calls"
             end)

      # :auth -> :mainframe rolls up to :api -> :mainframe
      assert Enum.any?(edges, fn {from, to, _, meta} ->
               from == :api and to == :mainframe and meta.label == "Queries"
             end)

      # Check auto-clustering: cluster should be set on the nodes and registered in c4.clusters
      assert Map.get(zoomed.graph.nodes, :api).cluster == "cluster_banking"
      assert Map.get(zoomed.graph.nodes, :web_app).cluster == "cluster_banking"
      assert Map.has_key?(zoomed.clusters, "cluster_banking")
      assert zoomed.clusters["cluster_banking"].label == "banking"
    end

    test "scoped level 2 (Component diagram) zooms into the scoped container" do
      c4 =
        C4.new()
        |> C4.add_person(:customer)
        |> C4.add_software_system(:banking, scope: :in)
        |> C4.add_software_system(:mainframe, scope: :out)
        |> C4.add_container(:web_app, parent: :banking)
        |> C4.add_container(:api, parent: :banking)
        |> C4.add_component(:auth, parent: :api)
        |> C4.add_component(:accounts, parent: :api)
        |> C4.add_relationship(:customer, :web_app, label: "Uses")
        |> C4.add_relationship(:web_app, :auth, label: "Calls")
        |> C4.add_relationship(:auth, :mainframe, label: "Queries")

      # Set active scope to container :api
      c4 = C4.set_scope(c4, :api)
      zoomed = Choreo.View.zoom(c4, level: 2)

      # We expect customer, mainframe, web_app (other container), and components of :api
      # :api itself and :banking are removed
      assert Enum.sort(C4.nodes(zoomed)) == [:accounts, :auth, :customer, :mainframe, :web_app]

      edges = C4.edges_with_meta(zoomed)
      assert length(edges) == 3

      assert Enum.any?(edges, fn {from, to, _, _} -> from == :customer and to == :web_app end)
      assert Enum.any?(edges, fn {from, to, _, _} -> from == :web_app and to == :auth end)
      assert Enum.any?(edges, fn {from, to, _, _} -> from == :auth and to == :mainframe end)

      # Check auto-clustering for nested components
      assert Map.get(zoomed.graph.nodes, :auth).cluster == "cluster_api"
      assert Map.get(zoomed.graph.nodes, :web_app).cluster == "cluster_banking"
      assert Map.has_key?(zoomed.clusters, "cluster_api")
      assert Map.has_key?(zoomed.clusters, "cluster_banking")
      assert zoomed.clusters["cluster_api"].label == "api"
      assert zoomed.clusters["cluster_api"].parent == "cluster_banking"
    end
  end
end
