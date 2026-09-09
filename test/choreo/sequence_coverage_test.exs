defmodule Choreo.SequenceCoverageTest do
  use ExUnit.Case, async: true

  alias Choreo.Sequence
  alias Choreo.Sequence.Analysis
  import Choreo.Lab.DSL.Sequence

  test "Sequence.Analysis missing branches and positions" do
    # Note positions: left, right, between with unknown participants
    seq_unknown =
      Sequence.new()
      |> Sequence.add_actor(:user)
      |> Sequence.note({:left, :unknown_left}, "left note")
      |> Sequence.note({:right, :unknown_right}, "right note")
      |> Sequence.note({:between, :unknown_a, :unknown_b}, "between note")

    issues = Analysis.unknown_participants(seq_unknown)
    assert Enum.any?(issues, fn {_, m} -> m =~ "unknown_left" end)
    assert Enum.any?(issues, fn {_, m} -> m =~ "unknown_right" end)
    assert Enum.any?(issues, fn {_, m} -> m =~ "unknown_a" end)
    assert Enum.any?(issues, fn {_, m} -> m =~ "unknown_b" end)

    # Note positions with known participants
    seq_known =
      Sequence.new()
      |> Sequence.add_actor(:user)
      |> Sequence.add_participant(:api)
      |> Sequence.note({:left, :user}, "left note")
      |> Sequence.note({:right, :api}, "right note")
      |> Sequence.note({:between, :user, :api}, "between note")

    assert Analysis.unknown_participants(seq_known) == []

    # Unbalanced activations: more deactivates than activates
    seq_deact =
      Sequence.new()
      |> Sequence.add_participant(:api)
      |> Sequence.deactivate(:api)

    assert [{:warning, msg}] = Analysis.unbalanced_activations(seq_deact)
    assert msg =~ "unmatched deactivate"

    # Unexpected end of fragment (depth <= 0)
    seq_end =
      Sequence.new()
      |> Sequence.add_actor(:user)
      |> Sequence.end_fragment()

    assert [{:error, frag_err}] = Analysis.unclosed_fragments(seq_end)
    assert frag_err =~ "Unexpected end of fragment"
  end

  test "Sequence.Render.DOT comprehensive themes and steps" do
    seq =
      Sequence.new()
      |> Sequence.add_actor(:user, label: "User")
      |> Sequence.add_participant(:api, label: "API Gateway")
      |> Sequence.activate(:api)
      |> Sequence.message(:user, :api, label: "POST /login")
      |> Sequence.self_message(:api, label: "hash_pw")
      |> Sequence.async(:api, :api, label: "emit_event")
      |> Sequence.return(:api, :user, label: "token")
      |> Sequence.deactivate(:api)

    for theme <- [:default, :dark, :warm, :forest, :ocean, :minimal] do
      dot = Sequence.to_dot(seq, theme: theme)
      assert dot =~ "digraph SequenceDiagram"
      assert dot =~ "POST /login"
      assert dot =~ "hash_pw"
    end

    custom_theme = Choreo.Sequence.Render.DOT.theme(:ocean, edge_color: "#abcdef")
    assert Sequence.to_dot(seq, theme: custom_theme) =~ "#abcdef"
  end

  test "Sequence DSL fragments and note forms" do
    diagram =
      sequence do
        u = actor("User")
        s = service("Service")
        w = participant("Worker")

        right u, "Right note"
        note left(u), "Note left"
        note right(s), "Note right"
        note between(u, s), "Note between"

        opt "cache hit" do
          s ~> u |> reply("cached")
        end

        par "parallel tasks" do
          s ~> w |> async("task 1")
          s ~> w |> async("task 2")
        end

        critical "atomic" do
          s ~> w |> call("debit")
        end

        break "on error" do
          s ~> u |> reply("abort")
        end

        alt "condition" do
          s ~> u |> reply("ok")
          otherwise "alternative"
          s ~> u |> reply("fail")
        end
      end

    assert %Choreo.Sequence{} = diagram
    events = Sequence.events(diagram)

    notes = Enum.filter(events, &(&1.type == :note))
    assert length(notes) == 4

    fragments = Enum.filter(events, &(&1.type == :fragment))
    assert Enum.any?(fragments, &(&1.kind == :opt))
    assert Enum.any?(fragments, &(&1.kind == :par))
    assert Enum.any?(fragments, &(&1.kind == :critical))
    assert Enum.any?(fragments, &(&1.kind == :break))
    assert Enum.any?(fragments, &(&1.kind == :else))
  end
end
