defmodule Choreo.RenderScriptTest do
  use ExUnit.Case, async: true

  alias Choreo.RenderScript

  test "normalizes a single renderable model" do
    model = Choreo.new() |> Choreo.add_service(:api)

    assert [%{name: "diagram", model: ^model, opts: []}] =
             RenderScript.normalize(model, default_name: "diagram")
  end

  test "normalizes a single model with tuple render options" do
    model = Choreo.new() |> Choreo.add_service(:api)

    assert [%{name: "diagram", model: ^model, opts: [theme: :ocean]}] =
             RenderScript.normalize({model, theme: :ocean}, default_name: "diagram")
  end

  test "normalizes maps and slugifies artifact names" do
    model = Choreo.new() |> Choreo.add_service(:api)

    assert [
             %{name: "api_flow", model: ^model, opts: []},
             %{name: "class_view", model: ^model, opts: [syntax: :class_diagram]}
           ] =
             RenderScript.normalize(
               %{"API Flow" => model, class_view: {model, syntax: :class_diagram}},
               default_name: "ignored"
             )
  end

  test "normalizes keyword lists with last-write-wins duplicate names" do
    first = Choreo.new() |> Choreo.add_service(:first)
    second = Choreo.new() |> Choreo.add_service(:second)

    assert [%{name: "diagram", model: ^second, opts: []}] =
             RenderScript.normalize([diagram: first, diagram: second], default_name: "ignored")
  end

  test "filters artifacts by normalized name" do
    model = Choreo.new() |> Choreo.add_service(:api)

    assert [%{name: "api_flow"}] =
             RenderScript.normalize(%{"API Flow" => model},
               default_name: "ignored",
               only: "api flow"
             )
  end

  test "rejects invalid return shapes" do
    assert_raise ArgumentError, ~r/expected render script to return/, fn ->
      RenderScript.normalize([:not, :a, :keyword], default_name: "diagram")
    end
  end

  test "rejects invalid artifact names" do
    model = Choreo.new() |> Choreo.add_service(:api)

    assert_raise ArgumentError, ~r/artifact names must be atoms or strings/, fn ->
      RenderScript.normalize(%{123 => model}, default_name: "diagram")
    end

    assert_raise ArgumentError, ~r/artifact names cannot be empty/, fn ->
      RenderScript.normalize(%{"   " => model}, default_name: "diagram")
    end
  end

  test "render_artifact renders to mermaid and dot" do
    model = Choreo.new() |> Choreo.add_service(:api)
    artifact = %{name: "test", model: model, opts: []}

    mermaid = RenderScript.render_artifact(artifact, :mermaid)
    assert mermaid =~ "graph" or mermaid =~ "flowchart"

    dot = RenderScript.render_artifact(artifact, :dot)
    assert dot =~ "digraph"
  end

  test "extension and parse_target helpers" do
    assert RenderScript.extension(:mermaid) == ".mmd"
    assert RenderScript.extension(:dot) == ".dot"

    assert RenderScript.parse_target(nil) == :mermaid
    assert RenderScript.parse_target("mermaid") == :mermaid
    assert RenderScript.parse_target("mmd") == :mermaid
    assert RenderScript.parse_target("dot") == :dot

    assert_raise ArgumentError, ~r/unsupported render target/, fn ->
      RenderScript.parse_target("svg")
    end
  end

  test "default_name extracts clean name from path" do
    assert RenderScript.default_name("path/to/my_arch.choreo.exs") == "my_arch"
    assert RenderScript.default_name("path/to/diagram.exs") == "diagram"
    assert RenderScript.default_name("diagram.ex") == "diagram"
  end

  test "output_path resolves correctly and enforces directory for multiple artifacts" do
    artifact = %{name: "arch", model: %{}, opts: []}

    # Directory
    assert RenderScript.output_path(artifact, :mermaid, "/tmp/out/", single?: true) ==
             "/tmp/out/arch.mmd"

    assert RenderScript.output_path(artifact, :dot, "/tmp/out/", single?: false) ==
             "/tmp/out/arch.dot"

    # Single file
    assert RenderScript.output_path(artifact, :mermaid, "/tmp/out/custom.mmd", single?: true) ==
             "/tmp/out/custom.mmd"

    # Multiple artifacts to a non-directory path raises
    assert_raise ArgumentError, ~r/multiple artifacts require --out to be a directory/, fn ->
      RenderScript.output_path(artifact, :mermaid, "/tmp/single_file.mmd", single?: false)
    end
  end

  test "filters artifacts by only raises on unknown name" do
    model = Choreo.new() |> Choreo.add_service(:api)

    assert_raise ArgumentError, ~r/artifact "missing" was not found/, fn ->
      RenderScript.normalize(%{present: model}, default_name: "ignored", only: "missing")
    end
  end

  test "eval_file evaluates an Elixir script file" do
    tmp_path = Path.expand("../../tmp/render_script_test.exs", __DIR__)
    File.mkdir_p!(Path.dirname(tmp_path))
    File.write!(tmp_path, "Choreo.new() |> Choreo.add_service(:worker)")

    on_exit(fn -> File.rm(tmp_path) end)

    evaluated = RenderScript.eval_file(tmp_path)
    assert %Choreo{} = evaluated
  end
end
