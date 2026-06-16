# Choreo

[![Hex Version](https://img.shields.io/hexpm/v/choreo.svg)](https://hex.pm/packages/choreo)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/choreo/)
[![CI](https://github.com/code-shoily/choreo/actions/workflows/ci.yml/badge.svg)](https://github.com/code-shoily/choreo/actions)
[![Coverage Status](https://coveralls.io/repos/github/code-shoily/choreo/badge.svg?branch=main)](https://coveralls.io/github/code-shoily/choreo?branch=main)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

> Domain-specific diagram builders and graph analyzers on top of [Yog](https://github.com/code-shoily/yog_ex).

Choreo is a family of Elixir libraries that let you model, analyze, and render complex systems as graphs. Instead of drawing boxes and arrows by hand, you write code. Instead of static pictures, you get live analysis — reachability, cycles, bottlenecks, threat generation, and more.

```elixir
alias Choreo.Dataflow

# A dataflow pipeline with one line of analysis
pipeline =
  Dataflow.new()
  |> Dataflow.add_source(:sensor, label: "IoT Sensor")
  |> Dataflow.add_transform(:parse, label: "JSON Parser")
  |> Dataflow.add_sink(:db, label: "TimescaleDB")
  |> Dataflow.connect(:sensor, :parse, data_type: "raw bytes")
  |> Dataflow.connect(:parse, :db, data_type: "event")

Dataflow.Analysis.cyclic?(pipeline)      #=> false
Dataflow.to_mermaid(pipeline)            #=> Mermaid diagram
```

```mermaid
graph TD
  classDef default color:white
  parse[["JSON Parser"]]
  db["TimescaleDB"]
  sensor(["IoT Sensor"])
  style parse fill:#3b82f6
  style db fill:#f43f5e
  style sensor fill:#10b981
  sensor -->|raw bytes| parse
  parse -->|event| db
```

---

## Installation

Add `choreo` to your `mix.exs`:

```elixir
def deps do
  [
    {:choreo, "~> 0.9"}
  ]
end
```

---

## Detailed Guides

Choreo supports 13 different artifact modeling vocabularies. They are categorized and detailed in the following guides:

1. **[Architecture & Design Modeling](guides/architecture_and_design.md)**
   * System Architecture (`Choreo`)
   * Cloud Network Topology (`Choreo.Infrastructure`)
   * C4 Model Architecture (`Choreo.C4`)
   * STRIDE Threat Modeling (`Choreo.ThreatModel`)
   * Domain-Driven Design & Event Storming (`Choreo.Domain`)
   * Database ERD Design (`Choreo.ERD`)
   * UML Class & Struct Diagrams (`Choreo.UML`)

2. **[Behavior & Flow Modeling](guides/behavior_and_flows.md)**
   * Finite State Machines (`Choreo.FSM`)
   * Sequence Diagrams (`Choreo.Sequence`)
   * Saga Task Orchestration (`Choreo.Workflow`)
   * Dataflow Pipelines (`Choreo.Dataflow`)

3. **[Data & Structure Modeling](guides/data_and_structure.md)**
   * Software Dependency Graphs (`Choreo.Dependency`)
   * Decision Trees (`Choreo.DecisionTree`)
   * Concept Mapping / Mind Maps (`Choreo.MindMap`)
   * Project Task Planning (`Choreo.Planner`)

---

## Interactive Notebooks

The `livebooks/` directory contains interactive walkthroughs and integration examples that you can run directly in [Livebook](https://livebook.dev/):

- **`livebooks/guides/`** — step-by-step introductions to each Choreo module and diagram type.
- **`livebooks/integrations/`** — notebooks that bridge Choreo with third-party tools and data sources:
  - [Finitomata](livebooks/integrations/choreo_finitomata.livemd) — design FSMs in Choreo, run them with Finitomata, and analyze them back in Choreo.
  - [GitHub Issues](livebooks/integrations/github_issues_explorer.livemd) — turn a public repo's issues into a Planner and Mind Map.
  - [Hex Dependencies](livebooks/integrations/hex_dependency_explorer.livemd) — crawl any Hex package's dependency tree.
  - [Mix Xref](livebooks/integrations/mix_xref_explorer.livemd) — visualize and analyze internal Elixir project dependencies.
  - [Ecto Schema ERD](livebooks/integrations/ecto_schema_erd.livemd) — introspect Ecto schemas and render them as an interactive ERD.
  - [Phoenix LiveView Explorer](livebooks/integrations/phoenix_liveview_explorer.livemd) — discover LiveView modules and render their callback sequence and state machine.
- **`livebooks/extending_choreo/`** — tutorials that walk through adding new diagram types, analysis vocabularies, and protocol implementations to Choreo:
  - [Git Graph](livebooks/extending_choreo/git_graph.livemd) — extend Choreo with a Mermaid `gitGraph` renderer, from builder to real `git log` adapter.
  - [Call Graph Analysis](livebooks/extending_choreo/call_graph_analysis.livemd) — extend Choreo with an analysis-first call graph: dead functions, cycles, hotspots, and impact analysis.
  - [FSM Viewable](livebooks/extending_choreo/fsm_viewable.livemd) — add `Choreo.Viewable` support to `Choreo.FSM` so it can be zoomed, focused, and filtered.

---

## Graph Analysis & Heatmaps

Choreo provides graph analysis tools to identify "hotspots" in your architecture, workflows, and pipelines. Use `heatmap/2` to automatically color nodes based on importance or performance metrics.

| Metric | Measure | Question | Best for |
|--------|---------|----------|----------|
| **Structural Importance** | Betweenness Centrality | "Which nodes are critical bridges/connectors?" | `Choreo`, `Dependency` |
| **Connectivity** | Degree Centrality | "Which nodes have the most connections?" | `MindMap`, `Dependency` |
| **SPOF Detection** | Articulation Points | "Which nodes would disconnect the system if they failed?" | `Choreo`, `Dataflow` |
| **Nucleus Detection** | K-Core Decomposition | "Which nodes form the most tightly-coupled core?" | `Choreo`, `Dependency` |
| **Dependency Reduction** | Transitive Reduction | "What is the minimal set of dependencies that preserve reachability?" | `Dependency` |
| **Path Analysis** | Dijkstra / Widest Path | "What is the fastest or highest-throughput path between two points?" | `Workflow`, `Dataflow` |
| **Execution Hotspots** | Latency Heatmap | "Which tasks slow down the entire workflow?" | `Workflow` |
| **Volume Hotspots** | Throughput Heatmap | "Which stages handle the most data volume?" | `Dataflow` |
| **Security Hotspots** | Risk Heatmap | "Which components have the most security threats?" | `ThreatModel` |

---

## Themes & Rendering

All modules render to **DOT (Graphviz)** and **Mermaid.js** via a shared theming pipeline.

```elixir
# DOT output (Graphviz)
Choreo.to_dot(system, theme: :default)
Choreo.to_dot(system, theme: :dark)

# Mermaid.js output (GitHub, GitLab, Notion, Livebook)
Choreo.to_mermaid(system, theme: :default)
Choreo.to_mermaid(system, theme: :ocean)

# Custom theme
theme = Choreo.Theme.custom(
  colors: %{database: "#ff0000", service: "#00ff00"},
  graph_bgcolor: "#0f172a",
  node_fontcolor: "white"
)
Choreo.to_dot(system, theme: theme)
Choreo.to_mermaid(system, theme: theme)
```

---

## Testing

```bash
mix test
```

All modules ship with comprehensive ExUnit test suites covering builders, analysis, rendering, and doctests.

---

## License

MIT
