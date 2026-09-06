defmodule Choreo.Lab.SequenceDSLTest do
  use ExUnit.Case, async: true

  alias Choreo.Lab.DSL.Sequence, as: DSL
  import Choreo.Lab.DSL.Sequence

  doctest Choreo.Lab.DSL.Sequence

  test "taxonomy returns the Livebook discovery vocabulary" do
    taxonomy = DSL.taxonomy()

    assert :actor in taxonomy.participants
    assert :participant in taxonomy.participants
    assert :reply in taxonomy.messages
    assert :activate in taxonomy.events
    assert :between in taxonomy.notes
    assert :loop in taxonomy.fragments
    assert :call in taxonomy.modifiers
    assert :type in taxonomy.modifiers
    assert DSL.verbs() == taxonomy
  end

  test "builds ordered participant, message, and activation events" do
    diagram =
      sequence do
        user = actor("User")
        api = participant("API")
        db = participant("Database")

        user ~> api |> call("GET /accounts")
        activate api
        api ~> db |> call("SELECT accounts")
        reply db ~> api, "rows"
        deactivate api
        reply api ~> user, "200 OK"
      end

    assert Choreo.Sequence.participants(diagram) == [:user, :api, :db]
    assert diagram.graph.nodes[:user].node_type == :actor
    assert diagram.graph.nodes[:api].node_type == :participant

    messages = Choreo.Sequence.messages(diagram)

    assert Enum.map(messages, & &1[:label]) == [
             "GET /accounts",
             "SELECT accounts",
             "rows",
             "200 OK"
           ]

    assert Enum.map(messages, & &1[:type]) == [:sync, :sync, :return, :return]

    activations = Enum.filter(Choreo.Sequence.events(diagram), &(&1.type == :activation))
    assert Enum.map(activations, & &1.action) == [:activate, :deactivate]
  end

  test "supports inline participant constructors" do
    diagram =
      sequence do
        actor("User") ~> participant("API") |> request("GET /health")
      end

    assert Choreo.Sequence.participants(diagram) == [:user, :api]
    assert [message] = Choreo.Sequence.messages(diagram)
    assert message.from == :user
    assert message.to == :api
    assert message.label == "GET /health"
  end

  test "supports id option while keeping display label" do
    diagram =
      sequence do
        client = actor("Mobile App", id: :app)
        api = service("API")

        async client ~> api, "prefetch"
      end

    assert diagram.graph.nodes[:app].label == "Mobile App"
    assert [message] = Choreo.Sequence.messages(diagram)
    assert message.from == :app
    assert message.type == :async
    assert message.label == "prefetch"
  end

  test "supports typed keyword edges and self messages" do
    diagram =
      sequence do
        api = participant("API")
        worker = participant("Worker")

        edge api ~> worker, async: "enqueue"
        edge worker ~> api, return: "accepted"
        api ~> api |> call("validate token")
      end

    messages = Choreo.Sequence.messages(diagram)
    assert Enum.map(messages, & &1.type) == [:async, :return, :self]
    assert Enum.map(messages, & &1.label) == ["enqueue", "accepted", "validate token"]
  end

  test "supports notes" do
    diagram =
      sequence do
        user = actor("User")
        api = participant("API")

        over api, "Validates bearer token"
        left user, "External caller"
        between user, api, "HTTPS boundary"
        note over(api), "Rate limited"
      end

    notes = Choreo.Sequence.events(diagram) |> Enum.filter(&(&1.type == :note))

    assert Enum.map(notes, & &1.position) == [
             {:over, :api},
             {:left, :user},
             {:between, :user, :api},
             {:over, :api}
           ]

    assert Enum.map(notes, & &1.text) == [
             "Validates bearer token",
             "External caller",
             "HTTPS boundary",
             "Rate limited"
           ]
  end

  test "supports fragment blocks" do
    diagram =
      sequence do
        api = participant("API")
        worker = participant("Worker")
        user = actor("User")

        loop "retry up to 3 times" do
          api ~> worker |> async("process job")
        end

        alt "authorized" do
          api ~> user |> reply("200")
          otherwise "denied"
          api ~> user |> reply("403")
        end
      end

    fragments = Choreo.Sequence.events(diagram) |> Enum.filter(&(&1.type == :fragment))
    assert Enum.map(fragments, & &1.kind) == [:loop, nil, :alt, :else, nil]
    assert Enum.map(fragments, & &1.action) == [:start, :end, :start, :arm, :end]

    messages = Choreo.Sequence.messages(diagram)
    assert Enum.map(messages, & &1.label) == ["process job", "200", "403"]
  end

  test "raises on unknown participant variables" do
    assert_raise ArgumentError, ~r/unknown sequence participant variable `api`/, fn ->
      Code.eval_quoted(
        quote do
          import Choreo.Lab.DSL.Sequence

          sequence do
            user = actor("User")
            user ~> api |> call("GET")
          end
        end
      )
    end
  end

  test "supports edge/3 with label and keyword options" do
    diagram =
      sequence do
        api = participant("API")
        worker = participant("Worker")

        edge(api ~> worker, "enqueue", async: true)
      end

    [message] = Choreo.Sequence.messages(diagram)
    assert message.from == :api
    assert message.to == :worker
    assert message.label == "enqueue"
    assert message.type == :async
  end

  test "supports piped modifiers with options and type/1,2 modifiers" do
    diagram =
      sequence do
        api = participant("API")
        worker = participant("Worker")
        db = participant("Database")
        user = actor("User")

        api ~> worker |> async(label: "enqueue")
        worker ~> db |> type(:sync, "save")
        db ~> worker |> type(:return)
        api ~> user |> reply("done")
      end

    messages = Choreo.Sequence.messages(diagram)
    assert Enum.map(messages, & &1.label) == ["enqueue", "save", nil, "done"]
    assert Enum.map(messages, & &1.type) == [:async, :sync, :return, :return]
  end

  test "supports standalone participant declarations inside DSL" do
    diagram =
      sequence do
        actor "User"
        participant "API"
      end

    assert Choreo.Sequence.participants(diagram) == [:user, :api]
  end

  test "autocomplete stubs raise outside DSL block" do
    assert_raise RuntimeError, ~r/must be called inside a DSL block/, fn -> DSL.actor() end
    assert_raise RuntimeError, ~r/must be called inside a DSL block/, fn -> DSL.edge() end
    assert_raise RuntimeError, ~r/must be called inside a DSL block/, fn -> DSL.type() end
    assert_raise RuntimeError, ~r/must be called inside a DSL block/, fn -> DSL.on() end
  end

  test "supports edge keywords, typed edges, and raises on unsupported statements" do
    diagram =
      sequence do
        u = actor("User")
        api = participant("API")

        edge u ~> api
        edge u ~> api, "sync message"
        call u ~> api
        call u ~> api, "fetch"
        call u ~> api, type: :sync
        call u ~> api, "fetch", type: :sync
      end

    assert %Choreo.Sequence{} = diagram

    assert_raise ArgumentError, ~r/expected sequence constructor/, fn ->
      Code.eval_string("""
      import Choreo.Lab.DSL.Sequence
      sequence do
        x = 999
      end
      """)
    end

    assert_raise ArgumentError, ~r/unsupported statement in sequence DSL/, fn ->
      Code.eval_string("""
      import Choreo.Lab.DSL.Sequence
      sequence do
        bad_statement("test")
      end
      """)
    end
  end
end
