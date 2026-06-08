defmodule Choreo.Infrastructure.ViewTest do
  use ExUnit.Case, async: true

  alias Choreo.Infrastructure
  alias Choreo.View

  describe "zoom/2" do
    test "level 0 keeps only internet and load balancer nodes" do
      infra =
        Infrastructure.new()
        |> Infrastructure.add_internet(:gw)
        |> Infrastructure.add_load_balancer(:lb)
        |> Infrastructure.add_compute(:app)
        |> Infrastructure.add_managed_db(:db)
        |> Infrastructure.connect(:gw, :lb)
        |> Infrastructure.connect(:lb, :app)
        |> Infrastructure.connect(:app, :db)

      zoomed = View.zoom(infra, level: 0)
      assert Enum.sort(Infrastructure.nodes(zoomed)) == [:gw, :lb]
    end

    test "level 1 adds compute nodes" do
      infra =
        Infrastructure.new()
        |> Infrastructure.add_internet(:gw)
        |> Infrastructure.add_load_balancer(:lb)
        |> Infrastructure.add_compute(:app)
        |> Infrastructure.add_managed_db(:db)
        |> Infrastructure.connect(:gw, :lb)
        |> Infrastructure.connect(:lb, :app)
        |> Infrastructure.connect(:app, :db)

      zoomed = View.zoom(infra, level: 1)
      assert Enum.sort(Infrastructure.nodes(zoomed)) == [:app, :db, :gw, :lb]
    end

    test "level 2+ keeps everything including storage and databases" do
      infra =
        Infrastructure.new()
        |> Infrastructure.add_internet(:gw)
        |> Infrastructure.add_load_balancer(:lb)
        |> Infrastructure.add_compute(:app)
        |> Infrastructure.add_managed_db(:db)
        |> Infrastructure.add_storage(:s3)
        |> Infrastructure.connect(:gw, :lb)
        |> Infrastructure.connect(:lb, :app)
        |> Infrastructure.connect(:app, :db)
        |> Infrastructure.connect(:app, :s3)

      zoomed = View.zoom(infra, level: 2)
      assert Enum.sort(Infrastructure.nodes(zoomed)) == [:app, :db, :gw, :lb, :s3]
    end
  end

  describe "focus/3" do
    test "keeps node and its neighbours" do
      infra =
        Infrastructure.new()
        |> Infrastructure.add_internet(:gw)
        |> Infrastructure.add_load_balancer(:lb)
        |> Infrastructure.add_compute(:app)
        |> Infrastructure.add_managed_db(:db)
        |> Infrastructure.connect(:gw, :lb)
        |> Infrastructure.connect(:lb, :app)
        |> Infrastructure.connect(:app, :db)

      focused = View.focus(infra, :app, radius: 1)
      assert Enum.sort(Infrastructure.nodes(focused)) == [:app, :db, :lb]
    end

    test "radius 0 returns only the target node" do
      infra =
        Infrastructure.new()
        |> Infrastructure.add_internet(:gw)
        |> Infrastructure.add_compute(:app)
        |> Infrastructure.connect(:gw, :app)

      focused = View.focus(infra, :app, radius: 0)
      assert Infrastructure.nodes(focused) == [:app]
    end

    test "raises when node does not exist" do
      infra = Infrastructure.new() |> Infrastructure.add_compute(:app)

      assert_raise ArgumentError, "Node :missing does not exist in diagram", fn ->
        View.focus(infra, :missing, radius: 1)
      end
    end
  end

  describe "filter/2" do
    test "removes nodes matching predicate" do
      infra =
        Infrastructure.new()
        |> Infrastructure.add_internet(:gw)
        |> Infrastructure.add_compute(:app)
        |> Infrastructure.add_managed_db(:db)
        |> Infrastructure.connect(:gw, :app)
        |> Infrastructure.connect(:app, :db)

      filtered = View.filter(infra, fn _id, data -> data[:node_type] != :managed_db end)
      assert Enum.sort(Infrastructure.nodes(filtered)) == [:app, :gw]
    end

    test "transitive zoom adds virtual edges between remaining nodes" do
      infra =
        Infrastructure.new()
        |> Infrastructure.add_internet(:gw)
        |> Infrastructure.add_load_balancer(:lb)
        |> Infrastructure.add_compute(:app)
        |> Infrastructure.add_managed_db(:db)
        |> Infrastructure.connect(:gw, :lb)
        |> Infrastructure.connect(:lb, :app)
        |> Infrastructure.connect(:app, :db)

      zoomed = View.zoom(infra, level: 0, transitive: true)
      nodes = Infrastructure.nodes(zoomed)
      assert :gw in nodes
      assert :lb in nodes

      # Virtual edge should connect gw -> lb directly through removed app/db
      edges = Infrastructure.edges(zoomed)
      assert Enum.any?(edges, fn {f, t, _} -> f == :gw and t == :lb end)
    end
  end

  describe "focus_between/3" do
    test "keeps only shortest path between two nodes" do
      infra =
        Infrastructure.new()
        |> Infrastructure.add_internet(:gw)
        |> Infrastructure.add_load_balancer(:lb)
        |> Infrastructure.add_compute(:app)
        |> Infrastructure.add_managed_db(:db)
        |> Infrastructure.connect(:gw, :lb)
        |> Infrastructure.connect(:lb, :app)
        |> Infrastructure.connect(:app, :db)

      path = View.focus_between(infra, :gw, :db)
      assert Enum.sort(Infrastructure.nodes(path)) == [:app, :db, :gw, :lb]
    end

    test "raises when no path exists" do
      infra =
        Infrastructure.new()
        |> Infrastructure.add_internet(:gw)
        |> Infrastructure.add_compute(:app)

      assert_raise ArgumentError, "No path from :gw to :app", fn ->
        View.focus_between(infra, :gw, :app)
      end
    end
  end

  describe "collapse/4" do
    test "aggregates matched nodes into one" do
      infra =
        Infrastructure.new()
        |> Infrastructure.add_internet(:gw)
        |> Infrastructure.add_compute(:app1)
        |> Infrastructure.add_compute(:app2)
        |> Infrastructure.add_managed_db(:db)
        |> Infrastructure.connect(:gw, :app1)
        |> Infrastructure.connect(:gw, :app2)
        |> Infrastructure.connect(:app1, :db)
        |> Infrastructure.connect(:app2, :db)

      collapsed =
        View.collapse(infra, fn id, _data -> id in [:app1, :app2] end, :apps)

      assert Enum.sort(Infrastructure.nodes(collapsed)) == [:apps, :db, :gw]

      assert Enum.any?(Infrastructure.edges(collapsed), fn {f, t, _} ->
               f == :gw and t == :apps
             end)

      assert Enum.any?(Infrastructure.edges(collapsed), fn {f, t, _} ->
               f == :apps and t == :db
             end)
    end
  end
end
