defmodule Mix.Tasks.Choreo.Render do
  use Mix.Task

  @shortdoc "Renders Choreo .exs artifacts to Mermaid or DOT files"

  @moduledoc """
  Renders Choreo models from an `.exs` file into Mermaid (`.mmd`) or Graphviz DOT (`.dot`) artifacts.

  This task is meant for Choreo-as-code workflows: keep diagram definitions in an
  executable Elixir file, then materialize renderable text artifacts for docs,
  editor previews, CI, or static sites.

  ## Usage

      mix choreo.render FILE [--to mermaid|dot] [--out PATH] [--only NAME]

  Examples:

      mix choreo.render diagrams/api_gateway.choreo.exs
      mix choreo.render diagrams/api_gateway.choreo.exs --to dot --out diagrams/api_gateway.dot
      mix choreo.render diagrams/system.choreo.exs --to mermaid --out priv/diagrams/
      mix choreo.render diagrams/system.choreo.exs --only architecture --out architecture.mmd

  `--to` defaults to `mermaid`. Mermaid output uses `.mmd`; DOT output uses `.dot`.

  ## Render script contract

  The final expression in the file must evaluate to one of these shapes:

    * a single Choreo renderable struct
    * `{model, render_opts}` for a single Choreo renderable struct with per-artifact options
    * a map of `name => model | {model, render_opts}`
    * a keyword list of `name => model | {model, render_opts}`

  Keyword-list duplicate names use last-write-wins semantics.

  `render_opts` are passed directly to `Choreo.to_mermaid/2` or `Choreo.to_dot/2`.
  This is where per-diagram settings belong, such as `:syntax`, `:scenario`,
  `:direction`, `:theme`, `:highlighted_nodes`, or `:highlighted_edges`.

  The command line intentionally stays small: it chooses the target format, output
  location, and optional artifact selection. Diagram-specific render intent should
  live next to the model in the `.choreo.exs` file.

  ## Single artifact example

      alias Choreo.Lab.DSL.C4, as: C4DSL

      C4DSL.c4 do
        user = person("User")
        api = container("API")

        user ~> api |> uses("Calls")
      end

  Render to stdout:

      mix choreo.render diagrams/api.choreo.exs

  Render to a file:

      mix choreo.render diagrams/api.choreo.exs --out diagrams/api.mmd

  ## Multiple artifact example

      alias Choreo.Lab.DSL.C4, as: C4DSL
      alias Choreo.Lab.DSL.Domain, as: DomainDSL

      architecture =
        C4DSL.c4 do
          user = person("User")
          api = container("API")
          user ~> api |> uses("Calls")
        end

      domain_model =
        DomainDSL.domain do
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
        architecture: architecture,
        domain_flow: domain_model,
        event_timeline: {domain_model, syntax: :event_modeling, scenario: :happy_path},
        focused_domain: {domain_model, highlighted_nodes: [:order, :placed]}
      }

  Render all artifacts to a directory:

      mix choreo.render diagrams/system.choreo.exs --out priv/diagrams/

  This writes:

      priv/diagrams/architecture.mmd
      priv/diagrams/domain_flow.mmd
      priv/diagrams/event_timeline.mmd
      priv/diagrams/focused_domain.mmd
  """

  @switches [to: :string, out: :string, only: :string]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, argv, invalid} = OptionParser.parse(args, strict: @switches)

    case {argv, invalid} do
      {[path], []} ->
        render(path, opts)

      {[], []} ->
        Mix.raise("mix choreo.render requires a FILE argument")

      {_, []} ->
        Mix.raise("mix choreo.render accepts exactly one FILE argument")

      {_argv, invalid} ->
        Mix.raise("invalid option(s): #{inspect(invalid)}")
    end
  end

  defp render(path, opts) do
    target = Choreo.RenderScript.parse_target(opts[:to])
    default_name = Choreo.RenderScript.default_name(path)

    artifacts =
      path
      |> Choreo.RenderScript.eval_file()
      |> Choreo.RenderScript.normalize(default_name: default_name, only: opts[:only])

    artifacts
    |> ensure_renderable!(target)
    |> write_artifacts(target, opts[:out])
  rescue
    exception in [ArgumentError, Protocol.UndefinedError] ->
      Mix.raise(Exception.message(exception))
  end

  defp ensure_renderable!(artifacts, target) do
    Enum.each(artifacts, fn artifact ->
      Choreo.RenderScript.render_artifact(artifact, target)
    end)

    artifacts
  end

  defp write_artifacts([artifact], target, nil) do
    artifact
    |> Choreo.RenderScript.render_artifact(target)
    |> Mix.shell().info()
  end

  defp write_artifacts(artifacts, target, out) when is_binary(out) do
    single? = match?([_one], artifacts)

    if not single? do
      File.mkdir_p!(out)
    end

    Enum.each(artifacts, fn artifact ->
      path = Choreo.RenderScript.output_path(artifact, target, out, single?: single?)
      path |> Path.dirname() |> File.mkdir_p!()
      File.write!(path, Choreo.RenderScript.render_artifact(artifact, target))
      Mix.shell().info("Wrote #{path}")
    end)
  end

  defp write_artifacts(_artifacts, _target, nil) do
    Mix.raise("multiple artifacts require --out to be a directory")
  end
end
