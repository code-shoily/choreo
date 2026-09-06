defmodule Choreo.ThreatModelTest do
  use ExUnit.Case

  doctest Choreo.ThreatModel
  doctest Choreo.ThreatModel.Render.DOT
  doctest Choreo.ThreatModel.Render.PlantUML
  doctest Choreo.ThreatModel.Render.Mermaid

  alias Choreo.ThreatModel

  describe "new/0" do
    test "creates an empty model" do
      model = ThreatModel.new()
      assert ThreatModel.elements(model) == []
      assert ThreatModel.flows(model) == []
    end

    test "accepts strict mode" do
      model = ThreatModel.new(strict: true)
      assert model.strict == true
    end
  end

  describe "add_trust_boundary/3" do
    test "adds a boundary with prefix" do
      model = ThreatModel.new() |> ThreatModel.add_trust_boundary("internet", label: "Internet")
      assert model.clusters["cluster_internet"].label == "Internet"
    end

    test "preserves existing cluster_ prefix" do
      model = ThreatModel.new() |> ThreatModel.add_trust_boundary("cluster_internal")
      assert Map.has_key?(model.clusters, "cluster_internal")
    end
  end

  describe "element builders" do
    test "add_external_entity/3" do
      model = ThreatModel.new() |> ThreatModel.add_external_entity(:user, label: "User")
      assert :user in ThreatModel.elements(model)
      assert Map.get(model.graph.nodes, :user).element_type == :external_entity
    end

    test "add_process/3 with privilege" do
      model = ThreatModel.new() |> ThreatModel.add_process(:api, label: "API", privilege: :admin)
      assert :api in ThreatModel.elements(model)
      assert Map.get(model.graph.nodes, :api).element_type == :process
      assert Map.get(model.graph.nodes, :api).privilege == :admin
    end

    test "add_data_store/3 with sensitivity" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_data_store(:db, label: "Postgres", sensitivity: :confidential)

      assert :db in ThreatModel.elements(model)
      assert Map.get(model.graph.nodes, :db).element_type == :data_store
      assert Map.get(model.graph.nodes, :db).sensitivity == :confidential
    end

    test "raises on arbitrary options in process" do
      assert_raise NimbleOptions.ValidationError, fn ->
        ThreatModel.new() |> ThreatModel.add_process(:api, compliance: :gdpr, owner: "team-a")
      end
    end

    test "add_data_store/3 with retention" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_data_store(:db, label: "Logs", retention: "90d")

      assert :db in ThreatModel.elements(model)
      assert Map.get(model.graph.nodes, :db).retention == "90d"
    end

    test "raises on arbitrary options in data store" do
      assert_raise NimbleOptions.ValidationError, fn ->
        ThreatModel.new() |> ThreatModel.add_data_store(:db, fake_option: true)
      end
    end

    test "raises on arbitrary options in external entity" do
      assert_raise NimbleOptions.ValidationError, fn ->
        ThreatModel.new() |> ThreatModel.add_external_entity(:user, region: "eu")
      end
    end
  end

  describe "data_flow/4" do
    test "creates a flow edge" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_external_entity(:user)
        |> ThreatModel.add_process(:api)
        |> ThreatModel.data_flow(:user, :api, label: "request")

      assert [{:user, :api, _, meta}] = ThreatModel.edges_with_meta(model)
      assert meta.label == "request"
      refute meta.encrypted
    end

    test "stores encrypted flag" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_external_entity(:user)
        |> ThreatModel.add_process(:api)
        |> ThreatModel.data_flow(:user, :api, encrypted: true)

      assert [{:user, :api, _, meta}] = ThreatModel.edges_with_meta(model)
      assert meta.encrypted
    end

    test "allows parallel connections" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_external_entity(:user)
        |> ThreatModel.add_process(:api)
        |> ThreatModel.data_flow(:user, :api, label: "request1")
        |> ThreatModel.data_flow(:user, :api, label: "request2")

      assert length(ThreatModel.flows(model)) == 2
    end
  end

  describe "boundary queries" do
    test "boundary_of/2 returns boundary name without cluster_ prefix" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_trust_boundary("app")
        |> ThreatModel.add_process(:api, boundary: "app")

      assert ThreatModel.boundary_of(model, :api) == "app"
    end

    test "trust_level/2 returns numeric level" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_trust_boundary("dmz", level: 1)
        |> ThreatModel.add_process(:api, boundary: "dmz")

      assert ThreatModel.trust_level(model, :api) == 1
    end

    test "crosses_boundary?/3 detects boundary crossing" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_trust_boundary("internet", level: 0)
        |> ThreatModel.add_trust_boundary("app", level: 2)
        |> ThreatModel.add_external_entity(:user, boundary: "internet")
        |> ThreatModel.add_process(:api, boundary: "app")
        |> ThreatModel.add_process(:worker, boundary: "app")
        |> ThreatModel.data_flow(:user, :api)
        |> ThreatModel.data_flow(:api, :worker)

      assert ThreatModel.crosses_boundary?(model, :user, :api)
      refute ThreatModel.crosses_boundary?(model, :api, :worker)
    end

    test "crosses_boundary?/3 returns false when one side has no boundary" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_trust_boundary("app", level: 2)
        |> ThreatModel.add_process(:api, boundary: "app")
        |> ThreatModel.add_process(:orphan)
        |> ThreatModel.data_flow(:api, :orphan)

      refute ThreatModel.crosses_boundary?(model, :api, :orphan)
    end
  end

  describe "to_dot/2" do
    test "renders a non-empty DOT string" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_trust_boundary("internet", label: "Internet")
        |> ThreatModel.add_external_entity(:user, label: "User", boundary: "internet")
        |> ThreatModel.add_process(:api, label: "API")
        |> ThreatModel.data_flow(:user, :api, label: "HTTPS")

      dot = ThreatModel.to_dot(model)
      assert String.contains?(dot, "digraph")
      assert String.contains?(dot, "User")
      assert String.contains?(dot, "API")
      assert String.contains?(dot, "cluster_internet")
    end

    test "renders unencrypted cross-boundary flow in red" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_trust_boundary("internet")
        |> ThreatModel.add_trust_boundary("app")
        |> ThreatModel.add_external_entity(:user, boundary: "internet")
        |> ThreatModel.add_process(:api, boundary: "app")
        |> ThreatModel.data_flow(:user, :api)

      dot = ThreatModel.to_dot(model)
      assert String.contains?(dot, "#ef4444")
    end

    test "renders with dark theme" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_external_entity(:user)
        |> ThreatModel.add_process(:api)
        |> ThreatModel.data_flow(:user, :api)

      dot = ThreatModel.to_dot(model, theme: :dark)
      assert String.contains?(dot, "digraph")
    end
  end

  describe "Choreo.Viewable" do
    test "zoom level 0 keeps only external entities" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_external_entity(:user)
        |> ThreatModel.add_process(:api)
        |> ThreatModel.add_data_store(:db)
        |> ThreatModel.data_flow(:user, :api)
        |> ThreatModel.data_flow(:api, :db)

      zoomed = Choreo.View.zoom(model, level: 0)
      assert Enum.sort(ThreatModel.elements(zoomed)) == [:user]
    end

    test "zoom level 1 keeps external entities and processes" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_external_entity(:user)
        |> ThreatModel.add_process(:api)
        |> ThreatModel.add_data_store(:db)
        |> ThreatModel.data_flow(:user, :api)
        |> ThreatModel.data_flow(:api, :db)

      zoomed = Choreo.View.zoom(model, level: 1)
      assert Enum.sort(ThreatModel.elements(zoomed)) == [:api, :user]
    end

    test "zoom level 2 keeps everything" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_external_entity(:user)
        |> ThreatModel.add_process(:api)
        |> ThreatModel.add_data_store(:db)
        |> ThreatModel.data_flow(:user, :api)
        |> ThreatModel.data_flow(:api, :db)

      zoomed = Choreo.View.zoom(model, level: 2)
      assert Enum.sort(ThreatModel.elements(zoomed)) == [:api, :db, :user]
    end

    test "focus keeps node and neighbourhood on multigraph" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_external_entity(:user)
        |> ThreatModel.add_process(:api)
        |> ThreatModel.add_data_store(:db)
        |> ThreatModel.data_flow(:user, :api)
        |> ThreatModel.data_flow(:api, :db)

      focused = Choreo.View.focus(model, :api, radius: 1)
      assert Enum.sort(ThreatModel.elements(focused)) == [:api, :db, :user]
    end

    test "filter removes matching nodes on multigraph" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_external_entity(:user)
        |> ThreatModel.add_process(:api)
        |> ThreatModel.add_data_store(:db)
        |> ThreatModel.data_flow(:user, :api)
        |> ThreatModel.data_flow(:api, :db)

      filtered =
        Choreo.View.filter(model, fn _id, data ->
          data[:element_type] != :data_store
        end)

      assert Enum.sort(ThreatModel.elements(filtered)) == [:api, :user]
    end

    test "transitive edges add virtual metadata on multigraph" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_external_entity(:user)
        |> ThreatModel.add_process(:api)
        |> ThreatModel.add_data_store(:db)
        |> ThreatModel.data_flow(:user, :api)
        |> ThreatModel.data_flow(:api, :db)

      filtered =
        Choreo.View.filter(
          model,
          fn _id, data ->
            data[:element_type] != :process
          end,
          transitive: true
        )

      assert Enum.sort(ThreatModel.elements(filtered)) == [:db, :user]

      edges = ThreatModel.edges_with_meta(filtered)
      assert length(edges) == 1

      {_from, _to, _weight, meta} = hd(edges)
      assert meta[:edge_type] == :virtual
    end

    test "focus_between finds shortest path on multigraph" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_external_entity(:user)
        |> ThreatModel.add_process(:api)
        |> ThreatModel.add_process(:worker)
        |> ThreatModel.add_data_store(:db)
        |> ThreatModel.data_flow(:user, :api)
        |> ThreatModel.data_flow(:api, :worker)
        |> ThreatModel.data_flow(:worker, :db)

      path = Choreo.View.focus_between(model, :user, :db)
      assert Enum.sort(ThreatModel.elements(path)) == [:api, :db, :user, :worker]
    end

    test "collapse aggregates nodes on multigraph" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_external_entity(:user)
        |> ThreatModel.add_process(:api)
        |> ThreatModel.add_process(:worker)
        |> ThreatModel.data_flow(:user, :api)
        |> ThreatModel.data_flow(:user, :worker)

      collapsed =
        Choreo.View.collapse(
          model,
          fn _id, data ->
            data[:element_type] == :process
          end,
          :services
        )

      assert :services in ThreatModel.elements(collapsed)
      assert :user in ThreatModel.elements(collapsed)
      refute :api in ThreatModel.elements(collapsed)
      refute :worker in ThreatModel.elements(collapsed)

      flows = ThreatModel.flows(collapsed)

      assert {:user, :services, _} =
               Enum.find(flows, fn {f, t, _} -> f == :user and t == :services end)
    end

    test "renderer styles virtual edges" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_external_entity(:user)
        |> ThreatModel.add_process(:api)
        |> ThreatModel.add_data_store(:db)
        |> ThreatModel.data_flow(:user, :api)
        |> ThreatModel.data_flow(:api, :db)

      filtered =
        Choreo.View.filter(
          model,
          fn _id, data ->
            data[:element_type] != :process
          end,
          transitive: true
        )

      dot = ThreatModel.to_dot(filtered)
      assert String.contains?(dot, "#cbd5e1")
    end
  end

  describe "hardened edge cases" do
    test "data_flow/4 implicitly defines missing from/to elements as processes" do
      model =
        ThreatModel.new()
        |> ThreatModel.data_flow(:a, :b, label: "request")

      assert Enum.sort(ThreatModel.elements(model)) == [:a, :b]
      assert Map.get(model.graph.nodes, :a).element_type == :process
      assert Map.get(model.graph.nodes, :b).element_type == :process
    end

    test "data_flow/4 raises in strict mode when elements are missing" do
      model = ThreatModel.new(strict: true)

      assert_raise ArgumentError, ~r/Source element :a does not exist/, fn ->
        ThreatModel.data_flow(model, :a, :b)
      end

      model = ThreatModel.add_process(model, :a)

      assert_raise ArgumentError, ~r/Target element :b does not exist/, fn ->
        ThreatModel.data_flow(model, :a, :b)
      end
    end

    test "renderers handle element names with spaces and special characters" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_trust_boundary("internet")
        |> ThreatModel.add_external_entity("my user", boundary: "internet")
        |> ThreatModel.add_process("my-api!")
        |> ThreatModel.data_flow("my user", "my-api!", label: "HTTPS")

      # 1. DOT
      dot = ThreatModel.to_dot(model)
      assert String.contains?(dot, "\"my user\"")
      assert String.contains?(dot, "\"my-api!\"")

      # 2. Mermaid flowchart
      mermaid = ThreatModel.to_mermaid(model)
      assert String.contains?(mermaid, "my user")
      assert String.contains?(mermaid, "my-api!")

      # 3. Mermaid sequence
      seq = ThreatModel.to_sequence(model)
      assert String.contains?(seq, "actor my_user as my user")
      assert String.contains?(seq, "participant my_api_ as my-api!")
      # "my-api!" has no boundary, so crosses_boundary? returns false
      assert String.contains?(seq, "my_user->>my_api_: HTTPS")

      # 4. PlantUML
      puml = Choreo.ThreatModel.Render.PlantUML.to_sequence(model)
      assert String.contains?(puml, "\"my user\" -> \"my-api!\" : HTTPS")
    end

    test "Mermaid renderer supports themes, directions, boundary styling, and sequence generation" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_trust_boundary("dmz")
        |> ThreatModel.add_trust_boundary("internal")
        |> ThreatModel.add_external_entity(:user,
          boundary: "dmz",
          fillcolor: "#ffaaaa",
          penwidth: 2
        )
        |> ThreatModel.add_process(:api, boundary: "internal")
        |> ThreatModel.add_data_store(:db, boundary: "internal")
        |> ThreatModel.add_process("123-cache", boundary: "internal")
        # Unencrypted cross-boundary
        |> ThreatModel.data_flow(:user, :api, encrypted: false, label: "raw HTTP")
        # Encrypted cross-boundary
        |> ThreatModel.data_flow(:api, :user, encrypted: true, protocol: :https)
        # Internal flow
        |> ThreatModel.data_flow(:api, :db, encrypted: true)
        # Flow with digit-prefixed node
        |> ThreatModel.data_flow(:api, "123-cache")

      model =
        model
        |> put_in([Access.key(:graph), Access.key(:nodes), :user, :privilege], "guest")
        |> put_in([Access.key(:graph), Access.key(:nodes), :user, :sensitivity], "public")

      # Themes
      for theme <- [:dark, :warm, :forest, :ocean, :minimal] do
        mermaid = ThreatModel.to_mermaid(model, theme: theme)
        assert mermaid =~ "graph LR"
      end

      # Directions & custom struct theme
      theme_struct =
        Choreo.ThreatModel.Render.Mermaid.theme(:ocean,
          node_fontsize: 14,
          edge_color: "#123456"
        )

      td_out = ThreatModel.to_mermaid(model, theme: theme_struct, direction: :td)
      assert td_out =~ "graph TD"

      # Highlighting
      hl =
        ThreatModel.to_mermaid(model,
          highlighted_nodes: [:user],
          highlighted_edges: [{:user, :api}]
        )

      assert hl =~ "graph LR"
      assert hl =~ "guest"
      assert hl =~ "public"

      # Sequence diagram generation
      seq = ThreatModel.to_sequence(model)
      assert seq =~ "sequenceDiagram"
      assert seq =~ "actor user as user"
      assert seq =~ "participant s_123_cache as 123-cache"
      # Cross-boundary unencrypted uses -->
      assert seq =~ "user-->api: raw HTTP"
      # Cross-boundary encrypted uses ->>
      assert seq =~ "api->>user: https"
      # Internal flow without label or proto uses fallback "flow"
      assert seq =~ "api->>db: flow"
    end
  end

  describe "extended schemas and controls" do
    test "add_external_entity with role and controls" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_external_entity(:admin_user,
          role: :admin,
          privilege: :admin,
          controls: [:mfa, :hardware_token]
        )

      node_data = Map.get(model.graph.nodes, :admin_user)
      assert node_data.role == :admin
      assert node_data.privilege == :admin
      assert node_data.controls == [:mfa, :hardware_token]
    end

    test "add_process with controls" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_process(:gateway, controls: [:rate_limiting, :waf])

      node_data = Map.get(model.graph.nodes, :gateway)
      assert node_data.controls == [:rate_limiting, :waf]
    end

    test "add_data_store with controls" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_data_store(:vault,
          sensitivity: :restricted,
          controls: [:encryption_at_rest, :kms]
        )

      node_data = Map.get(model.graph.nodes, :vault)
      assert node_data.controls == [:encryption_at_rest, :kms]
      assert node_data.sensitivity == :restricted
    end

    test "data_flow with authenticated, data, sensitivity, and controls" do
      model =
        ThreatModel.new()
        |> ThreatModel.add_process(:api)
        |> ThreatModel.add_data_store(:db)
        |> ThreatModel.data_flow(:api, :db,
          label: "Store Card",
          authenticated: true,
          encrypted: true,
          data: :credit_card,
          sensitivity: :restricted,
          controls: [:tls, :field_encryption]
        )

      [{:api, :db, "Store Card", meta}] = ThreatModel.edges_with_meta(model)
      assert meta.authenticated == true
      assert meta.encrypted == true
      assert meta.data == :credit_card
      assert meta.sensitivity == :restricted
      assert meta.controls == [:tls, :field_encryption]
    end
  end

  describe "delegated analysis functions and highlighting on model" do
    setup do
      model =
        ThreatModel.new()
        |> ThreatModel.add_trust_boundary("internet", level: 0)
        |> ThreatModel.add_trust_boundary("app", level: 2)
        |> ThreatModel.add_trust_boundary("db", level: 3)
        |> ThreatModel.add_external_entity(:user, boundary: "internet")
        |> ThreatModel.add_process(:api, boundary: "app")
        |> ThreatModel.add_data_store(:postgres, boundary: "db", sensitivity: :confidential)
        |> ThreatModel.data_flow(:user, :api, label: "Login")
        |> ThreatModel.data_flow(:api, :postgres, label: "Query")

      %{model: model}
    end

    test "entry_points, exit_points, blast_radius delegation", %{model: model} do
      assert [_] = ThreatModel.entry_points(model)
      assert ThreatModel.exit_points(model) == []
      radius = ThreatModel.blast_radius(model, :api)
      assert radius.affected_stores == [:postgres]
    end

    test "highlight_attack_paths and clear_highlight", %{model: model} do
      hl = ThreatModel.highlight_attack_paths(model)
      assert hl.highlighted_nodes == [:user, :api, :postgres]
      assert {:user, :api} in hl.highlighted_edges
      assert {:api, :postgres} in hl.highlighted_edges

      # Rendering forwards highlights
      dot = ThreatModel.to_dot(hl)
      assert dot =~ "penwidth"

      cleared = ThreatModel.clear_highlight(hl)
      assert cleared.highlighted_nodes == []
      assert cleared.highlighted_edges == []
    end

    test "to_markdown, unmitigated_threats, threats_for delegation", %{model: model} do
      md = ThreatModel.to_markdown(model)
      assert md =~ "Threat Model Summary"

      unmitigated = ThreatModel.unmitigated_threats(model)
      assert is_list(unmitigated) and unmitigated != []

      api_threats = ThreatModel.threats_for(model, :api)
      assert api_threats != []
    end
  end
end
