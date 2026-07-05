---
name: choreo-system-design
description: Use Choreo to turn system design prompts, architecture conversations, or interview questions into executable Livebook design notebooks with C4, dataflow, workflows, ERD, requirements, threat models, analysis, tradeoffs, and LLM review prompts.
---

# Choreo System Design

Use this skill when the user asks to design a system, prepare for a system design interview, convert architecture notes into a Choreo Livebook, or review/refine an existing Choreo design notebook.

The goal is to turn conversational design intent into a durable, executable `.livemd` architecture artifact that can be rendered, analyzed, reviewed by humans, and reused as compact source context for another LLM conversation.

## Core Principle

Treat Choreo as an intermediate design layer between prompts and prose documentation:

```text
architecture prompt / rough conversation
        ↓
Choreo Livebook design notebook
        ↓
review, refinement, system design doc, ADR, or interview answer
```

Do not add new Choreo library features. Prefer existing modules and established Livebook conventions.

## Default Workflow

1. **Clarify only what is necessary**
   - Ask follow-up questions only when the system goal, primary users, or core constraints are genuinely unclear.
   - For system design interview prompts, make reasonable assumptions and list them explicitly rather than blocking.

2. **Create or update a Livebook**
   - Prefer `livebooks/projects/<slug>_system_design.livemd` for new design notebooks unless the user gives a path.
   - Use a clear title: `# System Design: <System Name>`.
   - Keep code executable and examples realistic but not over-engineered.

3. **Extract the design frame**
   Include markdown sections for:
   - problem statement;
   - users and external actors;
   - functional requirements;
   - non-functional requirements;
   - assumptions and constraints;
   - explicit out-of-scope items.

4. **Model the architecture with Choreo**
   Pick modules based on the design need:

   | Concern | Prefer |
   |---|---|
   | System context, containers, components | `Choreo.C4` |
   | Generic service topology | `Choreo` |
   | Cloud/network/deployment topology | `Choreo.Infrastructure` |
   | Request or data pipeline | `Choreo.Dataflow` |
   | Business workflow, saga, orchestration | `Choreo.Workflow` |
   | Domain/Event Storming model | `Choreo.Domain` |
   | Database model | `Choreo.ERD` |
   | API/runtime interaction timeline | `Choreo.Sequence` |
   | Requirements and traceability | `Choreo.Requirement` |
   | Security and STRIDE risks | `Choreo.ThreatModel` |
   | Decision logic | `Choreo.DecisionTree` |
   | Implementation plan | `Choreo.Planner` |

5. **Use C4 as the default architecture spine**
   For most systems, start with `Choreo.C4`:
   - L1 System Context: people + in-scope system + external systems.
   - L2 Container: apps, services, databases, queues, object stores.
   - L3 Component: only for one important container when useful.
   - Use `Choreo.View.zoom/2` for L1/L2/L3 views.
   - Use `C4.set_scope/2` before component views.

   Do not default to C4 when the problem is clearly dominated by another view:
   - data pipelines or stream processing → start with `Choreo.Dataflow`;
   - domain/event-storming exploration → start with `Choreo.Domain`;
   - database-heavy designs → start with `Choreo.ERD`;
   - workflow/saga choreography → start with `Choreo.Workflow`.
   You can still add C4 later as the integrating view.

6. **Render Livebook diagrams consistently**
   Prefer this tab pattern:

   ```elixir
   Kino.Layout.tabs(
     Siren: Choreo.Lab.Siren.new(...),
     Graphviz: Kino.VizJS.render(...),
     Sketch: Choreo.Lab.Sketch.new(...)
   )
   ```

   Include Mermaid source tabs when useful. To avoid breaking Livebook markdown fences inside Elixir strings, build fences at runtime:

   ```elixir
   mermaid_source = fn source ->
     fence = String.duplicate("`", 3)
     Kino.Markdown.new(fence <> "mermaid\n" <> source <> "\n" <> fence)
   end

   render_tabs = fn mermaid, dot, height ->
     Kino.Layout.tabs(
       Siren: Choreo.Lab.Siren.new(mermaid),
       Graphviz: Kino.VizJS.render(dot, height: height),
       Sketch: Choreo.Lab.Sketch.new(mermaid),
       Source: mermaid_source.(mermaid)
     )
   end
   ```

7. **Add analysis and validation**
   Include analysis sections where available. Examples:

   ```elixir
   Choreo.C4.Analysis.validate(c4)
   Choreo.ERD.Analysis.validate(erd)
   Choreo.Requirement.Analysis.coverage(requirements)
   Choreo.ThreatModel.Analysis.validate(threat_model)
   ```

   Explain warnings as design-review prompts, not just test failures.

8. **Capture tradeoffs**
   Add concise tables for major decisions:
   - SQL vs NoSQL;
   - sync vs async;
   - monolith vs services;
   - cache strategy;
   - queue/streaming strategy;
   - consistency model;
   - operational risks.

9. **Add an LLM review prompt at the end**
   Every generated design notebook should end with a section like:

   ```markdown
   ## LLM Review Prompt

   Use this Livebook as the source of truth. Review the design for:

   - scalability bottlenecks;
   - single points of failure;
   - unclear requirements;
   - missing data ownership;
   - consistency and race-condition risks;
   - security and abuse cases;
   - operational complexity;
   - places where the design is over-engineered.
   ```

10. **Validate the Livebook**
    After writing or editing a `.livemd`, parse all Elixir blocks:

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

    For a stronger check, open the notebook in Livebook and evaluate all cells. Run focused tests only if changing library code. For notebook-only changes, parsing code blocks is usually sufficient.

## Default Livebook Outline

Use this structure unless the user asks for something different:

```markdown
# System Design: <Name>

## 1. Problem Statement
## 2. Requirements
## 3. Assumptions and Constraints
## 4. C4 System Context
## 5. C4 Container View
## 6. Core Dataflow
## 7. Workflow / Saga
## 8. Data Model / ERD
## 9. Threat Model
## 10. Requirements Traceability
## 11. Analysis and Risks
## 12. Tradeoffs
## 13. Open Questions
## 14. Final Design Summary
## 15. LLM Review Prompt
```

### Minimal Outline

For quick interview sketches or early exploration, collapse to:

```markdown
# System Design: <Name>

## 1. Problem Statement
## 2. Requirements
## 3. Assumptions and Constraints
## 4. C4 System Context
## 5. C4 Container View
## 6. Tradeoffs
## 7. LLM Review Prompt
```

Add dataflow, ERD, threat model, or traceability sections only when they materially improve the design discussion.

## Livebook Setup

Use this setup for project-local development inside the Choreo repository:

```elixir
Mix.install([
  # {:choreo, "~> 0.11.0"},
  # For notebooks inside the Choreo repo, resolve the library relative to the notebook.
  {:choreo, path: Path.expand("../..", __DIR__), force: true},
  {:kino_vizjs, "~> 0.9.0"}
])
```

Include aliases based on modules used:

```elixir
alias Choreo.C4
alias Choreo.Dataflow
alias Choreo.ERD
alias Choreo.Requirement
alias Choreo.ThreatModel
alias Choreo.Workflow
```

## Style Guidelines

- Prefer a small, coherent model over an exhaustive one.
- Use realistic labels and technologies.
- Keep relationships labeled with verbs: “Uses”, “Publishes”, “Reads from”, “Consumes”, “Stores”, “Authenticates via”.
- Prefer C4 containers for deployable/runnable units and data stores; do not equate C4 containers with Docker containers.
- Mark assumptions explicitly when details are inferred.
- For interview prep, favor clarity and tradeoffs over implementation minutiae; add a `Choreo.Planner` implementation plan only if the user asks for next steps.
- For production design, favor validation, risks, operational concerns, and traceability.

## Working with Existing Material

- If the user provides an existing `.livemd`, read it first and ask what to change, or propose specific updates.
- If the user provides architecture notes, a transcript, or a requirements doc, extract the design frame (problem, users, requirements, constraints) and convert it into the notebook rather than copying prose verbatim.
- When updating an existing notebook, preserve its existing structure unless the user asks for a rewrite.

## Output Expectations

When finished, tell the user:

- the Livebook path;
- the Choreo modules used;
- validations run;
- any important assumptions;
- recommended next step, such as “review the LLM Review Prompt with another model” or “turn this into an ADR/design doc.”
