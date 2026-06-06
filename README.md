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
  |> Dataflow.add_source(:sensor)
  |> Dataflow.add_transform(:parse)
  |> Dataflow.add_sink(:db)
  |> Dataflow.connect(:sensor, :parse)
  |> Dataflow.connect(:parse, :db)

Dataflow.Analysis.cyclic?(pipeline)      #=> false
Dataflow.to_dot(pipeline)                #=> DOT string
Dataflow.to_mermaid(pipeline)            #=> Mermaid.js string
```

---

## Table of Contents

- [Why Choreo?](#why-choreo)
- [Installation](#installation)
- [Graph Analysis & Heatmaps](#graph-analysis--heatmaps)
- [Modules](#modules)
  - [Choreo — Infrastructure Architecture](#choreo--infrastructure-architecture)
  - [Choreo.C4 — C4 Model Architecture](#choreoc4--c4-model-architecture)
  - [Choreo.FSM — Finite State Machines](#choreofsm--finite-state-machines)
  - [Choreo.Dataflow — Pipeline Diagrams](#choreodataflow--pipeline-diagrams)
  - [Choreo.Dependency — Software Dependency Graphs](#choreodependency--software-dependency-graphs)
  - [Choreo.DecisionTree — Classification Trees](#choreodecisiontree--classification-trees)
  - [Choreo.MindMap — Concept Mapping](#choreomindmap--concept-mapping)
  - [Choreo.Planner — Project Planning](#choreoplanner--project-planning)
  - [Choreo.Sequence — Sequence Diagrams](#choreosequence--sequence-diagrams)
  - [Choreo.ThreatModel — STRIDE Threat Modeling](#choreothreatmodel--stride-threat-modeling)
  - [Choreo.Workflow — Task Orchestration](#choreoworkflow--task-orchestration)
  - [Choreo.ERD — Database Entity-Relationship Modeling](#choreoerd--database-entity-relationship-modeling)
  - [Choreo.UML — Class & Struct Diagrams](#choreouml--class--struct-diagrams)
- [Themes & Rendering](#themes--rendering)
- [Testing](#testing)
- [Roadmap](#roadmap)

---

## Why Choreo?

Most diagramming tools are **visualization-only**: you describe a picture, you get a picture.

Choreo is **analysis-first**: you describe a system, you get answers.

| Question | Choreo answer |
|----------|-----------------|
| "Can this state machine accept input `X`?" | `Choreo.FSM.Analysis.accepts?(fsm, ["X"])` |
| "Is my pipeline cyclic?" | `Choreo.Dataflow.Analysis.cyclic?(pipeline)` |
| "What breaks if I change `:auth`?" | `Choreo.Dependency.Analysis.affected_by(deps, :auth)` |
| "What's the slowest path end-to-end?" | `Choreo.Dataflow.Analysis.longest_path(pipeline)` |
| "Are there circular dependencies?" | `Choreo.Dependency.Analysis.cyclic_dependencies(deps)` |
| "What threats exist in my architecture?" | `Choreo.ThreatModel.Analysis.stride_threats(model)` |
| "Which feature drives the most splits?" | `Choreo.DecisionTree.Analysis.feature_importance(tree)` |
| "How deep is this mind map?" | `Choreo.MindMap.Analysis.depth(map)` |
| "Which ideas are orphaned?" | `Choreo.MindMap.Analysis.orphan_nodes(map)` |
| "Which tasks are ready to work on?" | `Choreo.Planner.Analysis.ready(project)` |
| "What's blocking this milestone?" | `Choreo.Planner.Analysis.blocked(project)` |
| "What is the shortest join path from A to B?" | `Choreo.ERD.Analysis.shortest_join_path(erd, :a, :b)` |
| "Does this struct satisfy its behavior contract?" | `Choreo.UML.Analysis.broken_contracts(uml)` |
| "What does our architecture look like at different zoom levels?" | `Choreo.C4.to_mermaid(Choreo.View.zoom(c4, level: 2))` |
| "What order do these service calls happen in?" | `Choreo.Sequence.messages(seq)` |
| "What's the shortest path from A to B?" | `Choreo.View.focus_between(map, :a, :b)` |
| "Collapse these nodes into one?" | `Choreo.View.collapse(map, pred, :agg)` |

Everything renders to **DOT (Graphviz)** for publication-quality output and **Mermaid.js** for native rendering in GitHub, GitLab, Notion, and Livebook — with built-in `:default`, `:dark`, `:warm`, `:forest`, `:ocean`, and custom themes.

---

## Graph Analysis & Heatmaps

Choreo provides powerful graph analysis tools to identify "hotspots" in your architecture, workflows, and pipelines. Use `heatmap/2` to automatically color nodes based on importance or performance metrics.

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

```elixir
# Example: Visualizing security risk hotspots
model = Choreo.ThreatModel.Analysis.heatmap(model, palette: :heat)
Choreo.ThreatModel.to_dot(model)

# Example: Transitive Reduction for dependency cleanup
{:ok, reduced} = Choreo.Analysis.reduce_transitive(deps)

# Example: Finding and highlighting the fastest path
{:ok, path} = Choreo.Analysis.path(wf, :start, :done, measure: :latency)
Choreo.Workflow.to_dot(wf, Choreo.Analysis.highlight(path))

# Example: Custom weighted pathfinding (e.g. by 'cost')
{:ok, path} = Choreo.Analysis.path(system, :a, :b, measure: :cost)
dot = Choreo.Workflow.to_dot(wf, Choreo.Analysis.highlight(path))
```

---

## Installation

Add `choreo` to your `mix.exs`:

```elixir
def deps do
  [
    {:choreo, "~> 0.8"}
  ]
end
```

---

## Modules

### Choreo — Infrastructure Architecture

Model systems with typed infrastructure nodes: databases, caches, services, queues, load balancers, networks, users, and storage.

```elixir
alias Choreo

system =
  Choreo.new()
  |> Choreo.add_database(:db, name: "Postgres", kind: :postgres)
  |> Choreo.add_cache(:cache, name: "Redis")
  |> Choreo.add_service(:api, name: "API Gateway")
  |> Choreo.connect(:api, :cache, cost: 5)
  |> Choreo.connect(:api, :db, cost: 10)

# Analysis
{:ok, mst} = Choreo.Analysis.mst(system)
{:ok, order} = Choreo.Analysis.topological_sort(system)

# Render
dot = Choreo.to_dot(system, theme: :dark)
mermaid = Choreo.to_mermaid(system)
```

**Features:** clusters with nesting, dataflow edges, cost-weighted edges, MST, topological sort, SCC, theming.

```mermaid
graph TD
  classDef default color:white
  cache{{"Redis"}}
  db[("Postgres")]
  api[["API Gateway"]]
  style cache fill:#f59e0b,stroke:#d78000
  style db fill:#3b82f6,stroke:#1d64d8
  style api fill:#10b981,stroke:#009b63
  api --> cache
  api --> db
  linkStyle 0 stroke-width:2px,stroke:#64748b
  linkStyle 1 stroke-width:2px,stroke:#64748b
```

---

### Choreo.C4 — C4 Model Architecture

Model software architecture at multiple zoom levels — from system context down to components — in a single unified graph.

```elixir
alias Choreo.C4
alias Choreo.C4.Analysis

c4 =
  C4.new()
  |> C4.add_person(:customer, label: "Customer")
  |> C4.add_software_system(:banking,
    label: "Internet Banking",
    scope: :in,
    description: "Allows customers to view balances and make payments"
  )
  |> C4.add_software_system(:mainframe,
    label: "Mainframe Banking",
    description: "Stores all core banking information"
  )
  |> C4.add_container(:web_app,
    label: "Web Application",
    technology: "JavaScript",
    parent: :banking
  )
  |> C4.add_container(:api,
    label: "API Application",
    technology: "Elixir/Phoenix",
    parent: :banking
  )
  |> C4.add_component(:accounts_ctx,
    label: "Accounts Context",
    technology: "Elixir",
    parent: :api
  )
  |> C4.relationship(:customer, :banking, label: "Views account balances")
  |> C4.relationship(:banking, :mainframe, label: "Gets account info")

# Zoom to a specific C4 level
C4.to_mermaid(Choreo.View.zoom(c4, level: 0)) # System Context
C4.to_mermaid(Choreo.View.zoom(c4, level: 1)) # Container diagram
C4.to_mermaid(Choreo.View.zoom(c4, level: 2)) # Component diagram

# Analysis
Analysis.missing_descriptions(c4)
Analysis.isolated_nodes(c4)
Analysis.validate(c4)
```

**Features:** L1–L3 C4 modeling (System Context, Containers, Components), zoom-aware rendering, parent/child clustering, missing metadata detection, isolated node detection.

```mermaid
graph TD
  classDef default color:white
  banking["Internet Banking"]
  customer(("Customer"))
  mainframe["Mainframe Banking"]
  style banking fill:#3b82f6,stroke:#1d64d8,stroke-width:3px
  style customer fill:#f59e0b,stroke:#d78000
  style mainframe fill:#64748b,stroke:#46566d
  banking --> mainframe
  customer --> banking
  linkStyle 0 stroke-width:2px,stroke:#64748b
  linkStyle 1 stroke-width:2px,stroke:#64748b
```

---

### Choreo.FSM — Finite State Machines

Classic state machines with initial states, final states, and labeled transitions.

```elixir
alias Choreo.FSM

fsm =
  FSM.new()
  |> FSM.add_initial_state(:idle)
  |> FSM.add_state(:running)
  |> FSM.add_final_state(:done)
  |> FSM.add_transition(:idle, :running, label: "start")
  |> FSM.add_transition(:running, :done, label: "finish")

# Analysis
FSM.Analysis.accepts?(fsm, ["start", "finish"])  #=> true
FSM.Analysis.deterministic?(fsm)                  #=> true
FSM.Analysis.shortest_accepting_path(fsm)         #=> {:ok, ["start", "finish"]}
# Render to native state diagram
FSM.to_mermaid(fsm, syntax: :state_diagram)
```

**Features:** Deterministic execution, reachability, dead-state detection, determinism check, complement, product construction, equivalence checking.

```mermaid
stateDiagram-v2
  [*] --> idle
  idle --> running : start
  running --> done : finish
  done --> [*]
```

---

### Choreo.Dataflow — Pipeline Diagrams

Model stream-processing and ETL pipelines. Nodes are sources, transforms, buffers, conditionals, merges, and sinks.

```elixir
alias Choreo.Dataflow

pipeline =
  Dataflow.new()
  |> Dataflow.add_source(:sensor, label: "IoT Sensor", rate: 1000)
  |> Dataflow.add_transform(:parse, label: "JSON Parser", latency_ms: 50)
  |> Dataflow.add_buffer(:kafka, label: "Events", capacity: 10_000)
  |> Dataflow.add_sink(:db, label: "TimescaleDB")
  |> Dataflow.connect(:sensor, :parse, data_type: "raw bytes")
  |> Dataflow.connect(:parse, :kafka, data_type: "event")
  |> Dataflow.connect(:kafka, :db, data_type: "metrics")

# Analysis
Dataflow.Analysis.cyclic?(pipeline)           #=> false
{:ok, order} = Dataflow.Analysis.topological_sort(pipeline)
Dataflow.Analysis.orphan_nodes(pipeline)       #=> []
Dataflow.Analysis.bottlenecks(pipeline)        #=> [:kafka]
Dataflow.Analysis.simulate(pipeline)           #=> throughput map
{:ok, path, latency} = Dataflow.Analysis.longest_path(pipeline)
```

**Features:** error/retry/dead-letter path types, sub-pipeline clusters, throughput simulation, backpressure detection, critical-path analysis.

```mermaid
graph TD
  classDef default color:white
  parse[["JSON Parser"]]
  db["TimescaleDB"]
  sensor(["IoT Sensor<br/>1000 evt/s"])
  kafka[("Events<br/>(cap: 10000)")]
  style parse fill:#3b82f6
  style db fill:#f43f5e
  style sensor fill:#10b981
  style kafka fill:#f59e0b
  parse -->|event| kafka
  sensor -->|raw bytes| parse
  kafka -->|metrics| db
  linkStyle 0 stroke-width:2px,stroke:#64748b
  linkStyle 1 stroke-width:2px,stroke:#64748b
  linkStyle 2 stroke-width:2px,stroke:#64748b
```

---

### Choreo.Dependency — Software Dependency Graphs

Map modules, libraries, applications, interfaces, and tests. Detect circular dependencies, layering violations, and impact zones.

```elixir
alias Choreo.Dependency

deps =
  Dependency.new()
  |> Dependency.add_application(:api, label: "API Gateway")
  |> Dependency.add_module(:auth, label: "Auth")
  |> Dependency.add_library(:phoenix)
  |> Dependency.depends_on(:api, :auth, type: :calls)
  |> Dependency.depends_on(:auth, :phoenix, type: :uses)

# Analysis
Dependency.Analysis.cyclic_dependencies(deps)     #=> []
Dependency.Analysis.affected_by(deps, :auth)       #=> [:api]
Dependency.Analysis.depends_on(deps, :api)         #=> [:auth, :phoenix]

# Render to native class diagram
Dependency.to_mermaid(deps, syntax: :class_diagram)
```

**Features:** cycle path extraction (not just boolean), transitive impact analysis, layer violation detection, centrality ranking, longest dependency chain, cycle edge highlighting in DOT.

```mermaid
classDiagram
  direction TD
  class api["API Gateway"] {
    <<application>>
  }
  class auth["Auth"] {
    <<module>>
  }
  class phoenix["phoenix"] {
    <<library>>
  }
  api ..> auth : calls
  auth --> phoenix : uses
```

---

### Choreo.UML — Class & Struct Diagrams

Model software module contracts, behaviors, protocols, structs, their fields, arities, and visibilities, and declare exact structural relations with visual parity.

```elixir
alias Choreo.UML

uml =
  UML.new()
  |> UML.add_class(:user,
    type: :struct,
    label: "User Model",
    fields: [
      %{name: :id, type: :integer, visibility: :public},
      %{name: :email, type: :string, visibility: :private}
    ],
    functions: [
      %{name: "authenticate", arity: 2, return: :boolean, visibility: :public}
    ]
  )
  |> UML.add_class(:auth_provider, type: :behavior)
  |> UML.add_relationship(:user, :auth_provider, type: :realizes, label: "implements")

# Render to native Mermaid class diagram
UML.to_mermaid(uml, syntax: :class_diagram)
```

**Features:** multi-compartment record tables, standard visibility markers (`+`, `-`, `#`), functional contracts, protocol realization, behavior adoption, lens focusing via `Choreo.View`.

```mermaid
classDiagram
  direction TD
  class user["User Model"] {
    <<struct>>
    +id integer
    -email string
    +authenticate(2) boolean
  }
  class auth_provider["auth_provider"] {
    <<behavior>>
  }
  user ..|> auth_provider : implements
```

---

### Choreo.DecisionTree — Classification Trees

Build decision trees with enforced tree invariants (single root, single parent, no cycles).

```elixir
alias Choreo.DecisionTree
alias Choreo.DecisionTree.Analysis

tree =
  DecisionTree.new()
  |> DecisionTree.set_root(:weather, feature: "weather")
  |> DecisionTree.add_decision(:wind, feature: "wind")
  |> DecisionTree.add_outcome(:play, label: "Play", class: "yes")
  |> DecisionTree.add_outcome(:stay, label: "Stay", class: "no")
  |> DecisionTree.branch(:weather, :wind, "cloudy")
  |> DecisionTree.branch(:weather, :play, "sunny")
  |> DecisionTree.branch(:wind, :stay, "stormy")

# Evaluation
Analysis.decide(tree, %{"weather" => "cloudy", "wind" => "calm"})
#=> {:ok, [:weather, :wind, ...], "..."}

# Metrics
Analysis.paths(tree)               #=> all root-to-leaf paths
Analysis.depth(tree)               #=> 2
Analysis.feature_importance(tree)  #=> %{"weather" => 1, "wind" => 1}

# Optimization
pruned = Analysis.prune_redundant(tree)
```

**Features:** exact-match decision evaluation, path enumeration with conditions, redundant-branch pruning, feature-importance counting, tree validation.

```mermaid
graph TD
  classDef default color:white
  weather{"weather"}
  wind{"wind"}
  play["Play"]
  stay["Stay"]
  style weather fill:#8b5cf6,stroke:#6d3ed8,stroke-width:3px
  style wind fill:#3b82f6,stroke:#1d64d8
  style play fill:#10b981,stroke:#009b63
  style stay fill:#10b981,stroke:#009b63
  weather -->|cloudy| wind
  weather -->|sunny| play
  wind -->|stormy| stay
  linkStyle 0 stroke-width:2px,stroke:#64748b
  linkStyle 1 stroke-width:2px,stroke:#64748b
  linkStyle 2 stroke-width:2px,stroke:#64748b
```

---

### Choreo.Workflow — Task Orchestration

Model automated task orchestration with Saga-pattern compensations, timeouts, retries, and conditional branching.

```elixir
alias Choreo.Workflow
alias Choreo.Workflow.Analysis

workflow =
  Workflow.new()
  |> Workflow.add_start(:order_received)
  |> Workflow.add_task(:charge_card, timeout_ms: 5000, retry: 3)
  |> Workflow.add_task(:reserve_inventory, timeout_ms: 3000)
  |> Workflow.add_decision(:sufficient_stock)
  |> Workflow.add_task(:pack_items, timeout_ms: 10_000)
  |> Workflow.add_task(:ship_order, timeout_ms: 5000)
  |> Workflow.add_compensation(:refund_payment, for: :charge_card)
  |> Workflow.add_end(:done)
  |> Workflow.connect(:order_received, :charge_card)
  |> Workflow.connect(:charge_card, :reserve_inventory)
  |> Workflow.connect(:reserve_inventory, :sufficient_stock)
  |> Workflow.connect(:sufficient_stock, :pack_items, condition: "yes")
  |> Workflow.connect(:sufficient_stock, :refund_payment, condition: "no", edge_type: :compensation)
  |> Workflow.connect(:pack_items, :ship_order)
  |> Workflow.connect(:ship_order, :done)

# Analysis
Analysis.critical_path(workflow)
#=> {:ok, [:order_received, :charge_card, ...], 23000}

Analysis.parallelizable_tasks(workflow)
Analysis.missing_compensations(workflow)
Analysis.validate(workflow)
```

**Features:** critical-path analysis with latency weights, parallelizable-task grouping, failure-scenario detection, missing-compensation detection, bottleneck detection, execution simulation.

```mermaid
graph TD
  classDef default color:white
  done(("done"))
  order_received(("order_received"))
  charge_card[["charge_card (5000ms) retry: 3"]]
  reserve_inventory[["reserve_inventory (3000ms)"]]
  sufficient_stock{"sufficient_stock"}
  pack_items[["pack_items (10000ms)"]]
  ship_order[["ship_order (5000ms)"]]
  refund_payment["refund_payment"]
  style done fill:#ef4444,stroke:#d12626,stroke-width:3px
  style order_received fill:#10b981,stroke:#009b63,stroke-width:2px
  style charge_card fill:#3b82f6,stroke:#1d64d8
  style reserve_inventory fill:#3b82f6,stroke:#1d64d8
  style sufficient_stock fill:#8b5cf6,stroke:#6d3ed8
  style pack_items fill:#3b82f6,stroke:#1d64d8
  style ship_order fill:#3b82f6,stroke:#1d64d8
  style refund_payment fill:#f87171,stroke:#ef4444,stroke-width:2px,stroke-dasharray:3 3
  order_received --> charge_card
  charge_card --> reserve_inventory
  reserve_inventory --> sufficient_stock
  sufficient_stock -->|yes| pack_items
  sufficient_stock -->|no| refund_payment
  pack_items --> ship_order
  ship_order --> done
  linkStyle 0 stroke-width:2px,stroke:#64748b
  linkStyle 1 stroke-width:2px,stroke:#64748b
  linkStyle 2 stroke-width:2px,stroke:#64748b
  linkStyle 3 stroke-width:2px,stroke:#64748b
  linkStyle 4 stroke-width:2px,stroke:#64748b,stroke-dasharray:5 5
  linkStyle 5 stroke-width:2px,stroke:#64748b
  linkStyle 6 stroke-width:2px,stroke:#64748b
```

---

### Choreo.MindMap — Concept Mapping

Model hierarchical concept maps with a central root, branching topics and subtopics, and associative cross-links.

```elixir
alias Choreo.MindMap
alias Choreo.MindMap.Analysis

map =
  MindMap.new()
  |> MindMap.set_root(:elixir, label: "Elixir")
  |> MindMap.add_topic(:concurrency, label: "Concurrency")
  |> MindMap.add_topic(:ecosystem, label: "Ecosystem")
  |> MindMap.add_subtopic(:processes, label: "Processes")
  |> MindMap.add_note(:beam, label: "BEAM VM")
  |> MindMap.branch(:elixir, :concurrency)
  |> MindMap.branch(:elixir, :ecosystem)
  |> MindMap.branch(:concurrency, :processes)
  |> MindMap.branch(:ecosystem, :beam)
  |> MindMap.associate(:processes, :beam, label: "runs on")

# Analysis
Analysis.depth(map)          #=> 2
Analysis.breadth(map)        #=> 2
Analysis.orphan_nodes(map)   #=> []
Analysis.paths(map)          #=> [[:elixir, :concurrency, :processes], [:elixir, :ecosystem, :beam]]
Analysis.validate(map)       #=> []
```

**Features:** single-root invariant, branch and associate edge types, depth/breadth/width metrics, root-to-leaf path enumeration, orphan detection, cycle detection, type-frequency analysis, validation.

```mermaid
mindmap
elixir((Elixir))
  concurrency(Concurrency)
    processes[Processes]
  ecosystem(Ecosystem)
    beam)BEAM VM(
```

---

### Choreo.Planner — Project Planning

Model projects with tasks, milestones, users, and labels. Render as Kanban boards, Gantt charts, or dependency flowcharts.

```elixir
alias Choreo.Planner
alias Choreo.Planner.Analysis

project =
  Planner.new("Launch v1")
  |> Planner.add_milestone(:v1, title: "V1 Launch")
  |> Planner.add_task(:design, title: "Design", status: :done, estimate_hours: 16)
  |> Planner.add_task(:impl, title: "Implement", status: :in_progress, estimate_hours: 24)
  |> Planner.add_task(:test, title: "Test", status: :backlog, estimate_hours: 8)
  |> Planner.add_user(:alice, name: "Alice")
  |> Planner.contains(:v1, :design)
  |> Planner.contains(:v1, :impl)
  |> Planner.contains(:v1, :test)
  |> Planner.depends_on(:impl, :design)
  |> Planner.depends_on(:test, :impl)
  |> Planner.assign(:design, :alice)

# Analysis
Analysis.ready(project)          #=> tasks with unmet dependencies satisfied
Analysis.blocked(project)        #=> tasks blocked by incomplete dependencies
Analysis.critical_path(project, milestone: :v1)
#=> {:ok, [:design, :impl, :test], total_estimate: 48}
Analysis.bottlenecks(project)    #=> high in-degree tasks

# Render
Planner.to_mermaid(project, syntax: :kanban)
Planner.to_mermaid(project, syntax: :gantt)
Planner.to_mermaid(project, syntax: :flowchart)
Planner.to_dot(project)
```

**Features:** Kanban (`kanban` / `kanban_compat`), Gantt, and flowchart rendering, milestone hierarchy, dependency and assignment tracking, ready/blocked/critical-path/bottleneck analysis, status and priority metadata.

```mermaid
kanban
  title Launch v1
  subgraph Backlog
    test[Test<br/>estimate: 8h]
  end
  subgraph In Progress
    impl[Implement<br/>estimate: 24h]
  end
  subgraph Done
    design[Design<br/>estimate: 16h]
  end
```

---

### Choreo.Sequence — Sequence Diagrams

Model ordered interactions between participants over time. Mermaid-native output with activation boxes, notes, and fragments.

```elixir
alias Choreo.Sequence

seq =
  Sequence.new()
  |> Sequence.add_actor(:user, label: "User")
  |> Sequence.add_participant(:api, label: "API")
  |> Sequence.add_participant(:db, label: "Database")
  |> Sequence.message(:user, :api, label: "GET /accounts")
  |> Sequence.activate(:api)
  |> Sequence.message(:api, :db, label: "SELECT * FROM accounts")
  |> Sequence.return(:db, :api, label: "rows")
  |> Sequence.deactivate(:api)
  |> Sequence.return(:api, :user, label: "200 OK")

Sequence.to_mermaid(seq)
Sequence.to_dot(seq)        # Best-effort timeline fallback
```

**Features:** actors/participants, sync/async/return/self messages, activation boxes, notes, loops/alts/opts, missing-label detection, unbalanced activation detection.

```mermaid
sequenceDiagram
    actor User
    participant API
    participant Database
    User->>API: GET /accounts
    activate API
    API->>Database: SELECT * FROM accounts
    Database-->>API: rows
    API-->>User: 200 OK
    deactivate API
```

---

### Choreo.ThreatModel — STRIDE Threat Modeling

Extend dataflow diagrams with security semantics. Auto-generate STRIDE threats based on element types, trust boundaries, and encryption status.

```elixir
alias Choreo.ThreatModel
alias Choreo.ThreatModel.Analysis

model =
  ThreatModel.new()
  |> ThreatModel.add_trust_boundary("internet", level: 0)
  |> ThreatModel.add_trust_boundary("app", level: 2)
  |> ThreatModel.add_external_entity(:user, boundary: "internet", label: "User")
  |> ThreatModel.add_process(:api, boundary: "app", privilege: :admin, label: "API")
  |> ThreatModel.add_data_store(:db, boundary: "app", sensitivity: :confidential, label: "DB")
  |> ThreatModel.data_flow(:user, :api)
  |> ThreatModel.data_flow(:api, :db, encrypted: true)

# Auto-generated threats
threats = Analysis.stride_threats(model)
#=> [%{id: "T1", category: :spoofing, target: :user, severity: :high, ...}, ...]

# Security analysis
Analysis.exposed_data_stores(model)
Analysis.high_risk_processes(model)
Analysis.unencrypted_boundary_flows(model)

# Sequence diagram
ThreatModel.to_sequence(model)  #=> Mermaid sequenceDiagram string
```

**Features:** automated STRIDE threat generation with severity scoring, trust-boundary crossing detection, exposed-data-store identification, high-risk process detection, encrypted-flow detection, sequence diagram generation.

```mermaid
graph LR
  classDef default color:white
  user["User"]
  api(("API"))
  db[("DB")]
  style user fill:#64748b,stroke:#46566d,stroke-width:3px
  style api fill:#3b82f6,stroke:#1d64d8
  style db fill:#f59e0b,stroke:#d78000
  subgraph app ["app"]
    api
    db
  end
  subgraph internet ["internet"]
    user
  end
  user --> api
  api --> db
  linkStyle 0 stroke-width:2px,stroke:#64748b,stroke-dasharray:5 5
  linkStyle 1 stroke-width:2px,stroke:#64748b
```

---

### Choreo.ERD — Database Entity-Relationship Modeling

Model database schemas, validate data integrity constraints, render beautiful HTML-like tables or native Mermaid `erDiagram` syntaxes, and run advanced topological analysis.

```elixir
alias Choreo.ERD
alias Choreo.ERD.Analysis

erd =
  ERD.new()
  |> ERD.add_table(:users, columns: [
    %{name: :id, type: :integer, key: :pk},
    %{name: :email, type: :varchar, comment: "unique email"}
  ])
  |> ERD.add_table(:posts, columns: [
    %{name: :id, type: :integer, key: :pk},
    %{name: :user_id, type: :integer, key: :fk},
    %{name: :title, type: :varchar}
  ])
  |> ERD.add_table(:comments, columns: [
    %{name: :id, type: :integer, key: :pk},
    %{name: :post_id, type: :integer, key: :fk},
    %{name: :body, type: :text}
  ])
  |> ERD.add_relationship(:users, :posts, cardinality: :one_to_many, label: "writes")
  |> ERD.add_relationship(:posts, :comments, cardinality: :one_to_many, label: "has")

# Topological Analysis
Analysis.shortest_join_path(erd, :users, :comments) #=> {:ok, [:users, :posts, :comments]}
Analysis.cycles(erd)                              #=> [] (no circular foreign keys!)
Analysis.orphans(erd)                             #=> []
Analysis.table_degrees(erd)                       #=> %{users: %{in: 0, out: 1, total: 1}, ...}
```

**Features:** strict columns and relationship validation, customizable themed HTML record labels in DOT output, native Mermaid `erDiagram` generation, undirected BFS join path solver, DFS circular foreign key cycle detection, orphan and coupling metrics.

```mermaid
erDiagram
  users {
    integer id PK
    varchar email "unique email"
  }
  posts {
    integer id PK
    integer user_id FK
    varchar title
  }
  comments {
    integer id PK
    integer post_id FK
    text body
  }
  users ||--o{ posts : "writes"
  posts ||--o{ comments : "has"
```

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

### Built-in themes

| Theme | Description |
|-------|-------------|
| `:default` | Type-coloured nodes, white background |
| `:dark` | Dark background with neon accents |
| `:minimal` | Monochrome wireframe, no fills |
| `:warm` | Sunset palette, warm background |
| `:forest` | Lush green palette, earth tones |
| `:ocean` | Deep blue palette, cool background |

### Per-module node types

| Module | Node types | Shapes |
|--------|-----------|--------|
| `Choreo` | database, cache, service, queue, ... | cylinder, diamond, box3d, cloud, folder |
| `Choreo.C4` | person, software_system, container, component | ellipse, box, rounded box, dashed box |
| `Choreo.FSM` | initial, normal, final | circle, doublecircle |
| `Choreo.Dataflow` | source, sink, transform, buffer, conditional, merge | house, invhouse, box3d, cylinder, diamond, trapezium |
| `Choreo.Dependency` | application, library, module, interface, test | box3d, cylinder, box, diamond, note |
| `Choreo.DecisionTree` | root, decision, outcome | diamond (double), diamond, rounded box |
| `Choreo.MindMap` | root, topic, subtopic, note | doublecircle, ellipse, rounded box, note |
| `Choreo.Planner` | task, milestone, user, label | rounded box, doublecircle, box, ellipse |
| `Choreo.Sequence` | actor, participant | sequence diagram lifelines |
| `Choreo.ThreatModel` | external_entity, process, data_store | box (double), circle, cylinder |
| `Choreo.Workflow` | start, end, task, decision, fork, join, compensation, event | circle, doublecircle, box3d, diamond, invhouse, house, note, cloud |

---

## Testing

```bash
mix test
```

All modules ship with comprehensive ExUnit test suites covering builders, analysis, rendering, and doctests:

**1043 tests** (327 doctests + 716 unit tests), 0 failures.

---

## Roadmap

- [x] Infrastructure architecture diagrams (`Choreo`)
- [x] Finite state machines with analysis (`Choreo.FSM`)
- [x] Dataflow / pipeline diagrams (`Choreo.Dataflow`)
- [x] Software dependency graphs (`Choreo.Dependency`)
- [x] Decision trees (`Choreo.DecisionTree`)
- [x] STRIDE threat modeling (`Choreo.ThreatModel`)
- [x] Task orchestration workflows (`Choreo.Workflow`)
- [x] Mind maps (`Choreo.MindMap`)
- [x] Schema validation for dataflow edges
- [x] Custom theme presets and per-node style overrides
- [x] Centrality metrics, cut vertices, k-core decomposition
- [x] Cross-module composition (e.g. embed a Dataflow inside a Choreo cluster)
- [x] Validation framework across all modules
- [x] Mermaid.js rendering for all modules
- [x] Mermaid sequence diagrams (`ThreatModel`)
- [x] C4 model architecture diagrams (`Choreo.C4`)
- [x] Sequence diagrams (`Choreo.Sequence`)
- [ ] Graph colouring algorithms
- [ ] Property-based testing suite

---

## License

MIT
