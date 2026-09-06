defmodule Mix.Tasks.Choreo.RenderTest do
  use ExUnit.Case

  alias Mix.Tasks.Choreo.Render

  @moduletag :tmp_dir

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  test "renders a single artifact to stdout", %{tmp_dir: tmp_dir} do
    script = Path.join(tmp_dir, "single.choreo.exs")

    File.write!(script, """
    Choreo.new()
    |> Choreo.add_service(:api)
    """)

    Render.run([script])

    assert_receive {:mix_shell, :info, [output]}
    assert output =~ "graph TD"
    assert output =~ "api"
  end

  test "renders a single artifact to a file", %{tmp_dir: tmp_dir} do
    script = Path.join(tmp_dir, "single.choreo.exs")
    out = Path.join(tmp_dir, "single.mmd")

    File.write!(script, """
    Choreo.new()
    |> Choreo.add_service(:api)
    """)

    Render.run([script, "--out", out])

    assert File.read!(out) =~ "graph TD"
  end

  test "renders multiple artifacts to a directory", %{tmp_dir: tmp_dir} do
    script = Path.join(tmp_dir, "multi.choreo.exs")
    out_dir = Path.join(tmp_dir, "diagrams")

    File.write!(script, """
    api = Choreo.new() |> Choreo.add_service(:api)
    db = Choreo.new() |> Choreo.add_database(:db)

    [architecture: api, storage: db]
    """)

    Render.run([script, "--out", out_dir])

    assert File.read!(Path.join(out_dir, "architecture.mmd")) =~ "api"
    assert File.read!(Path.join(out_dir, "storage.mmd")) =~ "db"
  end

  test "passes tuple render options per artifact", %{tmp_dir: tmp_dir} do
    script = Path.join(tmp_dir, "domain.choreo.exs")
    out_dir = Path.join(tmp_dir, "diagrams")

    File.write!(script, """
    import Choreo.Lab.DSL.Domain

    model =
      domain do
        customer = actor("Customer")
        place_order = command("Place Order")
        order = aggregate("Order", invariants: ["Cannot place an empty order."])
        placed = event("Order Placed")

        customer ~> place_order |> initiates("starts")
        place_order ~> order |> handles("validates")
        order ~> placed |> emits("records")

        scenario :happy_path, path: [customer, place_order, order, placed]
      end

    %{
      flow: model,
      timeline: {model, syntax: :event_modeling, scenario: :happy_path}
    }
    """)

    Render.run([script, "--out", out_dir])

    assert File.read!(Path.join(out_dir, "flow.mmd")) =~ "graph TD"
    assert File.read!(Path.join(out_dir, "timeline.mmd")) =~ "eventmodeling"
  end

  test "supports dot target", %{tmp_dir: tmp_dir} do
    script = Path.join(tmp_dir, "single.choreo.exs")
    out = Path.join(tmp_dir, "single.dot")

    File.write!(script, """
    Choreo.new()
    |> Choreo.add_service(:api)
    """)

    Render.run([script, "--to", "dot", "--out", out])

    assert File.read!(out) =~ "digraph"
  end

  test "supports selecting one named artifact", %{tmp_dir: tmp_dir} do
    script = Path.join(tmp_dir, "multi.choreo.exs")
    out = Path.join(tmp_dir, "selected.mmd")

    File.write!(script, """
    api = Choreo.new() |> Choreo.add_service(:api)
    db = Choreo.new() |> Choreo.add_database(:db)

    [architecture: api, storage: db]
    """)

    Render.run([script, "--only", "storage", "--out", out])

    assert File.read!(out) =~ "db"
    refute File.read!(out) =~ "api"
  end

  test "raises Mix.Error on missing arguments or invalid options" do
    assert_raise Mix.Error, ~r/requires a FILE argument/, fn ->
      Render.run([])
    end

    assert_raise Mix.Error, ~r/accepts exactly one FILE argument/, fn ->
      Render.run(["file1.exs", "file2.exs"])
    end

    assert_raise Mix.Error, ~r/invalid option/, fn ->
      Render.run(["file1.exs", "--bogus-flag"])
    end
  end

  test "raises Mix.Error when multiple artifacts rendered to stdout without --out", %{
    tmp_dir: tmp_dir
  } do
    script = Path.join(tmp_dir, "multi_stdout.choreo.exs")

    File.write!(script, """
    [a: Choreo.new(), b: Choreo.new()]
    """)

    assert_raise Mix.Error, ~r/multiple artifacts require --out/, fn ->
      Render.run([script])
    end
  end
end
