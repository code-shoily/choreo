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
  end
end
