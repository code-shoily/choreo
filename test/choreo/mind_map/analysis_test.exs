defmodule Choreo.MindMap.AnalysisTest do
  use ExUnit.Case

  doctest Choreo.MindMap.Analysis

  alias Choreo.MindMap
  alias Choreo.MindMap.Analysis

  describe "depth/1" do
    test "returns 0 for empty map" do
      assert Analysis.depth(MindMap.new()) == 0
    end

    test "returns 0 for single root" do
      map = MindMap.new() |> MindMap.set_root(:a)
      assert Analysis.depth(map) == 0
    end

    test "measures max branch depth" do
      map =
        MindMap.new()
        |> MindMap.set_root(:a)
        |> MindMap.add_topic(:b)
        |> MindMap.add_subtopic(:c)
        |> MindMap.branch(:a, :b)
        |> MindMap.branch(:b, :c)

      assert Analysis.depth(map) == 2
    end
  end

  describe "breadth/1 and leaves/1" do
    test "counts leaf nodes" do
      map =
        MindMap.new()
        |> MindMap.set_root(:a)
        |> MindMap.add_topic(:b)
        |> MindMap.add_topic(:c)
        |> MindMap.add_subtopic(:d)
        |> MindMap.branch(:a, :b)
        |> MindMap.branch(:a, :c)
        |> MindMap.branch(:c, :d)

      assert Analysis.breadth(map) == 2
      assert Enum.sort(Analysis.leaves(map)) == [:b, :d]
    end

    test "root alone is a leaf" do
      map = MindMap.new() |> MindMap.set_root(:a)
      assert Analysis.leaves(map) == [:a]
      assert Analysis.breadth(map) == 1
    end
  end

  describe "orphan_nodes/1" do
    test "returns empty when all reachable" do
      map =
        MindMap.new()
        |> MindMap.set_root(:a)
        |> MindMap.add_topic(:b)
        |> MindMap.branch(:a, :b)

      assert Analysis.orphan_nodes(map) == []
    end

    test "finds disconnected nodes" do
      map =
        MindMap.new()
        |> MindMap.set_root(:a)
        |> MindMap.add_topic(:b)
        |> MindMap.add_topic(:c)
        |> MindMap.branch(:a, :b)

      assert Analysis.orphan_nodes(map) == [:c]
    end

    test "returns empty for empty map" do
      assert Analysis.orphan_nodes(MindMap.new()) == []
    end
  end

  describe "max_width/1" do
    test "returns 0 for empty map" do
      assert Analysis.max_width(MindMap.new()) == 0
    end

    test "returns 1 for single root" do
      map = MindMap.new() |> MindMap.set_root(:a)
      assert Analysis.max_width(map) == 1
    end

    test "measures widest level" do
      map =
        MindMap.new()
        |> MindMap.set_root(:a)
        |> MindMap.add_topic(:b)
        |> MindMap.add_topic(:c)
        |> MindMap.add_topic(:d)
        |> MindMap.branch(:a, :b)
        |> MindMap.branch(:a, :c)
        |> MindMap.branch(:a, :d)

      assert Analysis.max_width(map) == 3
    end
  end

  describe "paths/1" do
    test "returns empty for empty map" do
      assert Analysis.paths(MindMap.new()) == []
    end

    test "returns root-only for single node" do
      map = MindMap.new() |> MindMap.set_root(:a)
      assert Analysis.paths(map) == [[:a]]
    end

    test "enumerates root-to-leaf paths" do
      map =
        MindMap.new()
        |> MindMap.set_root(:a)
        |> MindMap.add_topic(:b)
        |> MindMap.add_topic(:c)
        |> MindMap.add_subtopic(:d)
        |> MindMap.branch(:a, :b)
        |> MindMap.branch(:a, :c)
        |> MindMap.branch(:c, :d)

      paths = Analysis.paths(map)
      assert [:a, :b] in paths
      assert [:a, :c, :d] in paths
    end
  end

  describe "type_frequencies/1" do
    test "counts node types" do
      map =
        MindMap.new()
        |> MindMap.set_root(:a)
        |> MindMap.add_topic(:b)
        |> MindMap.add_subtopic(:c)
        |> MindMap.add_note(:d)

      freqs = Analysis.type_frequencies(map)
      assert freqs[:root] == 1
      assert freqs[:topic] == 1
      assert freqs[:subtopic] == 1
      assert freqs[:note] == 1
    end
  end

  describe "cyclic?/1" do
    test "true when cycle exists" do
      map =
        MindMap.new()
        |> MindMap.set_root(:a)
        |> MindMap.add_topic(:b)
        |> MindMap.add_topic(:c)
        |> MindMap.branch(:a, :b)
        |> MindMap.branch(:b, :c)
        |> MindMap.branch(:c, :b)

      assert Analysis.cyclic?(map)
    end

    test "false for tree structure" do
      map =
        MindMap.new()
        |> MindMap.set_root(:a)
        |> MindMap.add_topic(:b)
        |> MindMap.add_topic(:c)
        |> MindMap.branch(:a, :b)
        |> MindMap.branch(:a, :c)

      refute Analysis.cyclic?(map)
    end

    test "false for empty graph" do
      refute Analysis.cyclic?(MindMap.new())
    end
  end

  describe "validate/1" do
    test "returns empty for valid map" do
      map =
        MindMap.new()
        |> MindMap.set_root(:a)
        |> MindMap.add_topic(:b)
        |> MindMap.branch(:a, :b)

      assert Analysis.validate(map) == []
    end

    test "errors when no root" do
      map = MindMap.new() |> MindMap.add_topic(:b)
      assert {:error, "Mind map has no root"} in Analysis.validate(map)
    end

    test "errors when cycle detected" do
      map =
        MindMap.new()
        |> MindMap.set_root(:a)
        |> MindMap.add_topic(:b)
        |> MindMap.add_topic(:c)
        |> MindMap.branch(:a, :b)
        |> MindMap.branch(:b, :c)
        |> MindMap.branch(:c, :b)

      assert {:error, "Cycle detected in mind map hierarchy"} in Analysis.validate(map)
    end

    test "warns on orphan nodes" do
      map =
        MindMap.new()
        |> MindMap.set_root(:a)
        |> MindMap.add_topic(:b)
        |> MindMap.add_topic(:c)
        |> MindMap.branch(:a, :b)

      issues = Analysis.validate(map)

      assert Enum.any?(issues, fn {sev, msg} ->
               sev == :warning and String.contains?(msg, "Orphan nodes")
             end)
    end

    test "warns on multiple branch parents" do
      map =
        MindMap.new()
        |> MindMap.set_root(:a)
        |> MindMap.add_topic(:b)
        |> MindMap.add_topic(:c)
        |> MindMap.add_subtopic(:d)
        |> MindMap.branch(:a, :b)
        |> MindMap.branch(:a, :c)
        |> MindMap.branch(:b, :d)
        |> MindMap.branch(:c, :d)

      issues = Analysis.validate(map)

      assert Enum.any?(issues, fn {sev, msg} ->
               sev == :warning and String.contains?(msg, "multiple branch parents")
             end)
    end
  end
end
