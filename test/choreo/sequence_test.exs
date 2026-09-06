defmodule Choreo.SequenceTest do
  use ExUnit.Case

  doctest Choreo.Sequence

  alias Choreo.Sequence
  alias Choreo.Sequence.Analysis

  describe "new/0" do
    test "creates an empty sequence diagram" do
      seq = Sequence.new()
      assert Sequence.participants(seq) == []
      assert Sequence.events(seq) == []
    end
  end

  describe "participants" do
    test "adds actors and participants" do
      seq =
        Sequence.new()
        |> Sequence.add_actor(:user, label: "User")
        |> Sequence.add_participant(:api, label: "API")
        |> Sequence.add_participant(:db, label: "Database")

      assert Sequence.participants(seq) == [:user, :api, :db]
    end
  end

  describe "messages" do
    test "records ordered messages" do
      seq =
        Sequence.new()
        |> Sequence.add_actor(:user)
        |> Sequence.add_participant(:api)
        |> Sequence.add_participant(:db)
        |> Sequence.message(:user, :api, label: "GET")
        |> Sequence.message(:api, :db, label: "SELECT")
        |> Sequence.return(:db, :api, label: "rows")

      messages = Sequence.messages(seq)
      assert length(messages) == 3

      labels = Enum.map(messages, & &1[:label])
      assert labels == ["GET", "SELECT", "rows"]

      types = Enum.map(messages, & &1[:type])
      assert types == [:sync, :sync, :return]
    end

    test "detects self messages" do
      seq =
        Sequence.new()
        |> Sequence.add_participant(:api)
        |> Sequence.self_message(:api, label: "timeout")

      [msg] = Sequence.messages(seq)
      assert msg[:type] == :self
    end

    test "async messages" do
      seq =
        Sequence.new()
        |> Sequence.add_actor(:a)
        |> Sequence.add_participant(:b)
        |> Sequence.async(:a, :b, label: "fire")

      [msg] = Sequence.messages(seq)
      assert msg[:type] == :async
    end
  end

  describe "activations" do
    test "records activate and deactivate events" do
      seq =
        Sequence.new()
        |> Sequence.add_actor(:user)
        |> Sequence.add_participant(:api)
        |> Sequence.message(:user, :api)
        |> Sequence.activate(:api)
        |> Sequence.return(:api, :user)
        |> Sequence.deactivate(:api)

      events = Sequence.events(seq)
      assert Enum.any?(events, &(&1.type == :activation and &1.action == :activate))
      assert Enum.any?(events, &(&1.type == :activation and &1.action == :deactivate))
    end
  end

  describe "notes" do
    test "records note events" do
      seq =
        Sequence.new()
        |> Sequence.add_actor(:user)
        |> Sequence.note({:over, :user}, "hello")

      [note] = Sequence.events(seq)
      assert note.type == :note
      assert note.position == {:over, :user}
      assert note.text == "hello"
    end
  end

  describe "fragments" do
    test "records loop fragments" do
      seq =
        Sequence.new()
        |> Sequence.add_actor(:a)
        |> Sequence.add_participant(:b)
        |> Sequence.fragment(:loop, "for each")
        |> Sequence.message(:a, :b)
        |> Sequence.end_fragment()

      events = Sequence.events(seq)
      assert Enum.at(events, 0).type == :fragment
      assert Enum.at(events, 0).kind == :loop
      assert Enum.at(events, 0).action == :start
      assert List.last(events).action == :end
    end

    test "records alt/else fragments" do
      seq =
        Sequence.new()
        |> Sequence.add_actor(:a)
        |> Sequence.add_participant(:b)
        |> Sequence.fragment(:alt, "x > 0")
        |> Sequence.message(:a, :b, label: "positive")
        |> Sequence.fragment(:else, "otherwise")
        |> Sequence.message(:a, :b, label: "negative")
        |> Sequence.end_fragment()

      frags = Enum.filter(Sequence.events(seq), &(&1.type == :fragment))
      assert length(frags) == 3
      assert Enum.map(frags, & &1.kind) == [:alt, :else, nil]
    end

    test "alt/else does not count as unclosed fragment" do
      seq =
        Sequence.new()
        |> Sequence.add_actor(:a)
        |> Sequence.add_participant(:b)
        |> Sequence.fragment(:alt, "x > 0")
        |> Sequence.message(:a, :b, label: "positive")
        |> Sequence.fragment(:else, "otherwise")
        |> Sequence.message(:a, :b, label: "negative")
        |> Sequence.end_fragment()

      assert Analysis.unclosed_fragments(seq) == []
    end
  end

  describe "Mermaid rendering" do
    test "renders a basic sequence diagram" do
      out =
        Sequence.new()
        |> Sequence.add_actor(:user, label: "User")
        |> Sequence.add_participant(:api, label: "API")
        |> Sequence.message(:user, :api, label: "GET")
        |> Sequence.to_mermaid()

      assert String.starts_with?(out, "sequenceDiagram")
      assert out =~ "actor User"
      assert out =~ "participant API"
      assert out =~ "User->>API: GET"
    end

    test "renders activations" do
      out =
        Sequence.new()
        |> Sequence.add_actor(:user, label: "User")
        |> Sequence.add_participant(:api, label: "API")
        |> Sequence.message(:user, :api)
        |> Sequence.activate(:api)
        |> Sequence.deactivate(:api)
        |> Sequence.to_mermaid()

      assert out =~ "activate API"
      assert out =~ "deactivate API"
    end

    test "renders notes" do
      out =
        Sequence.new()
        |> Sequence.add_actor(:user, label: "User")
        |> Sequence.add_participant(:api, label: "Api")
        |> Sequence.note({:over, :user}, "hi")
        |> Sequence.note({:between, :user, :api}, "shared")
        |> Sequence.to_mermaid()

      assert out =~ "Note over User: hi"
      assert out =~ "Note over User, Api: shared"
    end

    test "sanitizes note text with newlines" do
      out =
        Sequence.new()
        |> Sequence.add_actor(:user, label: "User")
        |> Sequence.note({:over, :user}, "line1\nline2")
        |> Sequence.to_mermaid()

      assert out =~ "Note over User: line1 line2"
    end

    test "renders async arrows" do
      out =
        Sequence.new()
        |> Sequence.add_actor(:a)
        |> Sequence.add_participant(:b)
        |> Sequence.async(:a, :b, label: "fire")
        |> Sequence.to_mermaid()

      assert out =~ "A-)B: fire"
    end

    test "renders fragments" do
      out =
        Sequence.new()
        |> Sequence.add_actor(:a)
        |> Sequence.add_participant(:b)
        |> Sequence.fragment(:loop, "for each")
        |> Sequence.message(:a, :b)
        |> Sequence.end_fragment()
        |> Sequence.to_mermaid()

      assert out =~ "loop for each"
      assert out =~ "end"
    end

    test "renders themes when requested" do
      out =
        Sequence.new()
        |> Sequence.add_actor(:user)
        |> Sequence.to_mermaid(theme: :dark)

      assert String.starts_with?(out, "%%{init:")
      assert out =~ "sequenceDiagram"
      assert out =~ "actorBkg"
    end
  end

  describe "DOT rendering" do
    test "renders a DOT graph" do
      out =
        Sequence.new()
        |> Sequence.add_actor(:user)
        |> Sequence.add_participant(:api)
        |> Sequence.message(:user, :api, label: "GET")
        |> Sequence.to_dot()

      assert String.starts_with?(out, "digraph SequenceDiagram")
      assert out =~ "\"user\""
      assert out =~ "\"api\""
    end

    test "renders a themed DOT graph" do
      out =
        Sequence.new()
        |> Sequence.add_actor(:user)
        |> Sequence.to_dot(theme: :dark)

      assert out =~ "bgcolor=\"#0f172a\""

      out_ocean =
        Sequence.new()
        |> Sequence.add_actor(:user)
        |> Sequence.to_dot(theme: :ocean)

      assert out_ocean =~ "bgcolor=\"#f0f9ff\""
    end

    test "supports theme/2 helper" do
      t = Sequence.theme(:dark, graph_rankdir: :lr)
      assert t.name == :sequence_dark
      assert t.graph_rankdir == :lr
      assert Sequence.theme(:warm).name == :sequence_warm
      assert Sequence.theme(:forest).name == :sequence_forest
      assert Sequence.theme(:ocean).name == :sequence_ocean
    end
  end

  describe "Analysis" do
    test "finds isolated participants" do
      seq =
        Sequence.new()
        |> Sequence.add_actor(:user)
        |> Sequence.add_participant(:api)
        |> Sequence.message(:user, :api, label: "ping")

      assert Analysis.isolated_participants(seq) == []

      seq2 =
        Sequence.new()
        |> Sequence.add_actor(:user)
        |> Sequence.add_participant(:api)
        |> Sequence.add_participant(:ghost)
        |> Sequence.message(:user, :api, label: "ping")

      assert Analysis.isolated_participants(seq2) == [:ghost]
    end

    test "finds missing labels" do
      seq =
        Sequence.new()
        |> Sequence.add_actor(:user)
        |> Sequence.add_participant(:api)
        |> Sequence.message(:user, :api)

      assert [{:error, msg}] = Analysis.missing_labels(seq)
      assert msg =~ "has no label"
    end

    test "finds unknown participants in messages" do
      seq =
        Sequence.new()
        |> Sequence.add_actor(:user)
        |> Sequence.message(:user, :api, label: "ping")

      assert [{:error, msg}] = Analysis.unknown_participants(seq)
      assert msg =~ "Receiver at step 0 references unknown participant :api"
    end

    test "finds unknown participants in notes and activations" do
      seq =
        Sequence.new()
        |> Sequence.add_actor(:user)
        |> Sequence.note({:over, :ghost}, "hello")
        |> Sequence.activate(:ghost)

      issues = Analysis.unknown_participants(seq)
      assert length(issues) == 2

      assert Enum.any?(issues, fn {_, m} ->
               m =~ "Note at step 0 references unknown participant :ghost"
             end)

      assert Enum.any?(issues, fn {_, m} ->
               m =~ "Activation at step 1 references unknown participant :ghost"
             end)
    end

    test "finds unbalanced activations" do
      seq =
        Sequence.new()
        |> Sequence.add_participant(:api)
        |> Sequence.activate(:api)
        |> Sequence.deactivate(:api)
        |> Sequence.deactivate(:api)

      assert [{:warning, msg}] = Analysis.unbalanced_activations(seq)
      assert msg =~ "unmatched deactivate"
    end

    test "finds unclosed fragments" do
      seq =
        Sequence.new()
        |> Sequence.add_actor(:a)
        |> Sequence.fragment(:loop, "forever")
        |> Sequence.message(:a, :a)

      assert [{:error, msg}] = Analysis.unclosed_fragments(seq)
      assert msg =~ "unclosed"
    end

    test "validate returns all issues" do
      seq =
        Sequence.new()
        |> Sequence.add_actor(:user)
        |> Sequence.add_participant(:api)
        |> Sequence.add_participant(:ghost)
        |> Sequence.message(:user, :api)
        |> Sequence.activate(:api)

      issues = Analysis.validate(seq)
      assert Enum.any?(issues, fn {_, m} -> m =~ "no label" end)
      assert Enum.any?(issues, fn {_, m} -> m =~ "unclosed activation" end)
      assert Enum.any?(issues, fn {_, m} -> m =~ "isolated" end)
    end
  end
end
