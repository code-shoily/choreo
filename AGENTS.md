# Agent Guide for Choreo

This file contains project-specific guidance for AI agents and other automated contributors working on Choreo.

## Project Overview

Choreo is an Elixir library for modeling, analyzing, and rendering complex systems as graphs. It provides domain-specific builders (C4, Dataflow, ERD, Workflow, Threat Model, etc.) and analysis tools on top of [Yog](https://github.com/code-shoily/yog_ex).

Key entry points:

- `lib/choreo.ex` — top-level API and shared graph functions.
- `lib/choreo/<domain>/` — one directory per diagram vocabulary (e.g., `c4/`, `dataflow/`, `erd/`).
- `lib/choreo/<domain>/analysis.ex` — analysis and validation for that domain.
- `lib/choreo/<domain>/render/` — Mermaid and Graphviz renderers.
- `test/choreo/` — mirrors the `lib/choreo/` structure.
- `livebooks/` — guides, walkthroughs, and project-specific design notebooks.
- `guides/` — long-form documentation and algorithm notes.

## Build, Test, and Quality

Use the standard Elixir tooling:

```sh
mix deps.get          # Install dependencies
mix compile           # Compile the project
mix test              # Run the test suite
mix test --cover      # Run tests with coverage
mix coveralls.html    # Generate HTML coverage report
mix docs              # Generate documentation
```

Code quality is enforced by the pre-commit hook:

```sh
mix format --check-formatted
mix credo --strict
```

Run `mix format` before committing if formatting fails. The hook lives at `.githooks/pre-commit`.

## Livebook Conventions

Livebooks are first-class artifacts in Choreo. Follow these conventions:

- Store project-specific design notebooks under `livebooks/projects/<slug>_system_design.livemd`.
- Store guides and walkthroughs under `livebooks/guides/`.
- Use this setup block for notebooks inside the Choreo repo:

  ```elixir
  Mix.install([
    # {:choreo, "~> 0.12.0"},
    {:choreo, path: Path.expand("../..", __DIR__), force: true},
    {:kino_vizjs, "~> 0.9.0"}
  ])
  ```

- Alias the modules you use at the top of the notebook.
- Render diagrams with the standard tab pattern:

  ```elixir
  Kino.Layout.tabs(
    Siren: Choreo.Lab.Siren.new(mermaid),
    Graphviz: Kino.VizJS.render(dot, height: height),
    Sketch: Choreo.Lab.Sketch.new(mermaid)
  )
  ```

- Validate Elixir blocks after editing a `.livemd`:

  ```sh
  mix run -e '
    text = File.read!("PATH_TO_LIVEMD")
    blocks = Regex.scan(~r/```elixir\n(.*?)```/s, text) |> Enum.map(fn [_, code] -> code end)
    IO.puts("elixir blocks: #{length(blocks)}")

    blocks
    |> Enum.with_index(1)
    |> Enum.each(fn {code, idx} ->
      case Code.string_to_quoted(code) do
        {:ok, _} -> :ok
        {:error, error} -> raise "Elixir block #{idx} does not parse: #{inspect(error)}\n#{code}"
      end
    end)
  '
  ```

## Skills

Project-specific skills live under `.agents/skills/`. Each skill should have its own directory and a `SKILL.md` file.

Current skills:

- `choreo-system-design` — guides creation of system design Livebooks using Choreo modules.

When adding or updating a skill:

- Keep it focused on a single workflow or capability.
- Use concrete examples and copy-pasteable snippets.
- Update `CHANGELOG.md` under `[Unreleased]`.

## Changelog Conventions

Keep `CHANGELOG.md` up to date. Use the `[Unreleased]` section at the top with these subsections:

- `### Added`
- `### Fixed`
- `### Changed`

Group related bullets. Mention new modules, significant behavior changes, new guides/livebooks, and new skills.

## API and DSL Philosophy

Choreo's stable API should remain pipe-first and explicit. Builders such as
`Choreo.C4.add_container/3`, `Choreo.Dataflow.add_source/3`, and
`Choreo.Infrastructure.connect/4` are the canonical programmatic interface.

Macro DSLs are valuable for sketches, examples, tests, and Livebook ergonomics, but they should incubate under
`Choreo.Lab.DSL.*` unless there is a strong reason to make them part of a stable domain module. Prefer this maturity path:

```text
Choreo.Lab.DSL.<Domain>
  experimental / Livebook-friendly / sketch syntax

→ maybe later

Choreo.<Domain>.DSL or Choreo.<NewDomain>
  stable public API, only after the syntax and semantics prove durable
```

DSL design guardrails:

- DSLs should compile down to existing stable builders and return ordinary Choreo structs.
- Do not replace or obscure the pipe API; document DSLs as convenience syntax.
- Keep DSL grammars small and strict: fail on unknown constructors or variables instead of silently creating odd models.
- Prefer variable-bound semantic nodes in Lab DSLs when labels/metadata matter, e.g. `api = service("API")` then `api ~> db`.
- Use pipe modifiers for edge metadata when possible, e.g. `api ~> db |> on("reads")`, and explicit forms like `edge api ~> db, label: "reads"` when clarity is needed.
- Avoid adding a generic cross-domain DSL engine to core Choreo unless multiple Lab DSLs converge on the same proven grammar.

## Style Guidelines

- Prefer small, coherent models over exhaustive ones.
- Use realistic labels and technologies in examples.
- Label relationships with verbs: "Uses", "Publishes", "Reads from", "Consumes", "Stores", "Authenticates via".
- Prefer C4 containers for deployable/runnable units and data stores; do not equate C4 containers with Docker containers.
- Mark assumptions explicitly when details are inferred.
- Keep lines within 120 characters when practical.

## Guardrails

- Do not add new Choreo library features when using the system-design skill. Prefer existing modules.
- Do not modify `.gitignore`, CI workflows, or pre-commit hooks without a clear reason.
- Do not commit build artifacts (`_build/`, `deps/`, `cover/`, `doc/`, `.elixir_ls/`).
- Avoid hardcoding absolute paths, especially user home directories, in notebooks or scripts.

## When in Doubt

Ask before making architectural changes, adding new dependencies, or changing public APIs. Prefer minimal, focused changes that follow the existing conventions.
