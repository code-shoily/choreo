# Changelog

## [Unreleased]

### Changed

- **Choreo.C4 — Scoped Zooming & Relationship Roll-up**:
  - Implemented automatic relationship roll-up (edge rewiring) when zooming/filtering lower-level components and containers to higher-level elements.
  - Implemented scoped Container (L2) and Component (L3) diagram filtering based on the active diagram scope, hiding expanded parent nodes and showing their respective sub-elements.
  - Implemented automatic cluster boundary generation and nested hierarchy mapping for parent systems and containers of visible nodes.
  - Rewrote the C4 walkthrough Livebook guide to showcase a unified banking architecture model, scoped zooming, relationship roll-up, auto-clustering, and themes.

- **Choreo.Theme — Infrastructure node types & shared helpers**:
  - Added `:internet`, `:compute`, and `:managed_db` as first-class node types in `@default_shapes`, `@default_colors`, and all named themes (`:minimal`, `:warm`, `:forest`, `:ocean`). Infrastructure diagrams now participate in the full theme system without any special-casing.
  - Added `Theme.resolve/1` — converts an atom shortcut (`:default`, `:dark`, etc.) to a `%Theme{}` struct, eliminating the duplicated `resolve_theme/1` private functions previously spread across renderers.
  - Added `Theme.dark?/1` — returns `true` for dark-background themes, eliminating the duplicated `is_dark_theme?/1` private functions previously in the Infrastructure renderers.

### Added

- **Cross-Diagram Semantic Tracing & Impact Analysis**:
  - Implemented `Choreo.trace/5` for declaring semantic connections (traces) between nodes across different diagram schemas (e.g. Workflow task -> C4 component -> ERD table).
  - Implemented `Choreo.Analysis.Tracing` with `impact_analysis/2` (transitively walks dependency graphs backwards to find all impacted components) and `trace_path/3` (computes cross-diagram execution paths).
  - Added `:show_traces` option to `Choreo.to_dot/2` and `Choreo.to_mermaid/2` to render trace links as styled red dashed arrows with layout constraint bypass (`constraint=false` in Graphviz).

- **Choreo.Infrastructure — Cloud Network Topology Preset**:
  - Implemented `Choreo.Infrastructure` as a domain-specific vocabulary layer on top of Choreo's existing graph, cluster, and rendering stack — not a parallel implementation.
  - Added typed network boundary builders: `add_vpc/3`, `add_subnet_public/3`, `add_subnet_private/3` — clusters with security semantics (`:vpc`, `:subnet_public`, `:subnet_private` types).
  - Added infrastructure node builders: `add_internet/3`, `add_load_balancer/3`, `add_compute/3`, `add_managed_db/3`, `add_storage/3`.
  - Added `connect/3` with `:protocol` metadata (`:https`, `:ssl`, `:tcp`, etc.) for styled edge rendering.
  - Implemented `Choreo.Infrastructure.Render.DOT` with VPC/subnet cluster boundary coloring (theme-aware: light and dark variants), and node shapes/colors resolved via `Choreo.Theme`.
  - Implemented `Choreo.Infrastructure.Render.Mermaid` with Mermaid-compatible node shapes (`:circle`, `:hexagon`, `:subroutine`, `:cylinder`) and styled edges.
  - Implemented `Choreo.Infrastructure.Analysis` with structural audit rules:
    - `:direct_internet_to_private_subnet` — flags connections that bypass the DMZ.
    - `:db_not_in_private_subnet` — flags managed databases placed in public subnets or outside any subnet.
    - `:load_balancer_not_in_public_subnet` — flags load balancers placed in private subnets.
  - Implemented `Choreo.Viewable` protocol for standard graph lens operations (`focus`, `zoom`, `filter`, `collapse`).
  - Added ExDoc groupings for all `Choreo.Infrastructure` modules.


## [0.8.0] - 2026-06-06

### Changed

- Bumped `yog_ex` requirement to `~> 0.98.2`.
  - **Mermaid rendering**: Node IDs are now sanitized to `n_0`, `n_1`, etc. by Yog for Mermaid compatibility. Labels and styles remain unchanged.
  - **DOT rendering**: HTML-like labels are now emitted with proper single-angle bracket syntax (`label=<TABLE...>`) instead of the previous double-angle bracket form.

### Added

- **Choreo.ERD — Database Entity-Relationship Modeling**:
  - Implemented `Choreo.ERD` schema builder with strict `NimbleOptions` column and relationship constraint validation.
  - Implemented themed HTML-like table record visualization (`Choreo.ERD.Render.DOT`) supporting standard crow's foot multiplicities and post-rendering unquoting.
  - Implemented native Mermaid `erDiagram` visual syntax rendering (`Choreo.ERD.Render.Mermaid`).
  - Implemented a topological analysis suite (`Choreo.ERD.Analysis`) including undirected BFS join path discovery, DFS circular foreign key cycle detection, isolated orphan entity tracking, and table coupling metrics.
  - Implemented `Choreo.Viewable` protocol for `Choreo.ERD` to enable standard graph lens operations (`focus`, `zoom`, `filter`, `collapse`).
  - Added ExDoc groupings and a full interactive Livebook walkthrough guide (`livebooks/erd_walkthrough.livemd`).

- **Choreo.UML — Class & Struct Diagrams**:
  - Implemented `Choreo.UML` schema builder with strict `NimbleOptions` field, arity, visibility, and relationship constraint validation.
  - Implemented themed three-compartment HTML record table visualization (`Choreo.UML.Render.DOT`) supporting standard class/struct/interface/behavior/protocol types, visibilities (`+`, `-`, `#`), and proper hollow/solid arrowhead line layouts.
  - Implemented Mermaid visual syntax rendering (`Choreo.UML.Render.Mermaid`) supporting both flowchart layouts and native `classDiagram` rendering.
  - Implemented `Choreo.Viewable` protocol for standard graph lens operations (`focus`, `zoom`, `filter`, `collapse`).
  - Implemented a static analysis suite (`Choreo.UML.Analysis`) including circular dependency detection, behavior contract validation, and Robert C. Martin's coupling & stability metrics.
  - Added ExDoc groupings and a full interactive Livebook walkthrough guide (`livebooks/uml_walkthrough.livemd`).

- **Choreo.Planner — Project Planning Diagrams**:
  - Implemented `Choreo.Planner` builder for project planning with tasks, milestones, users, and labels.
  - Implemented relationship builders: `contains/3` (milestone hierarchy), `depends_on/3` (finish-to-start), `blocks/3` (semantic blocker), `assign/3` (ownership), `tag/3` (categorization), and `relates/3` (association).
  - Implemented native Mermaid rendering (`Choreo.Planner.Render.Mermaid`) supporting `:kanban`, `:kanban_compat`, `:gantt`, and `:flowchart` syntaxes with status columns, color coding, and dependency scheduling.
  - Implemented themed DOT flowchart rendering (`Choreo.Planner.Render.DOT`) via `Yog.Multi.DOT`.
  - Implemented a planning analysis suite (`Choreo.Planner.Analysis`) including `ready/1`, `blocked/1`, `critical_path/2`, `bottlenecks/1`, and `validate/1`.
  - Added a full interactive Livebook walkthrough guide (`livebooks/planner_walkthrough.livemd`).

- **Choreo.C4 — C4 Model Architecture Diagrams**:
  - Implemented `Choreo.C4` schema builder for L1–L3 C4 modeling with `add_person/3`, `add_software_system/3`, `add_container/3`, and `add_component/3`.
  - Implemented parent/child clustering with automatic container assignment from `:parent` references.
  - Implemented zoom-aware rendering via `Choreo.Viewable` protocol, enabling level-based filtering (System Context, Containers, Components).
  - Implemented themed DOT rendering (`Choreo.C4.Render.DOT`) with C4-specific visual conventions: persons as ellipses, systems as boxes, containers as rounded boxes, and components as dashed boxes.
  - Implemented native Mermaid rendering (`Choreo.C4.Render.Mermaid`) with matching shapes and built-in theme support.
  - Implemented a structural analysis suite (`Choreo.C4.Analysis`) including missing parent detection, missing description/technology detection, isolated node detection, missing relationship labels, and general `validate/1`.
  - Added a full interactive Livebook walkthrough guide (`livebooks/c4_walkthrough.livemd`).

- **Choreo.Sequence — Sequence Diagrams**:
  - Implemented `Choreo.Sequence` builder for ordered participant interactions with `add_actor/3`, `add_participant/3`, `message/4`, `async/4`, `return/4`, and `self_message/3`.
  - Implemented activation boxes via `activate/2` and `deactivate/2`, plus notes (`note/3`) and fragments (`loop`, `opt`, `alt`/`else`, `par`, `break`, `critical`).
  - Implemented native Mermaid `sequenceDiagram` rendering (`Choreo.Sequence.Render.Mermaid`) with actors, participants, activation boxes, notes, and fragments.
  - Implemented a best-effort DOT timeline fallback (`Choreo.Sequence.Render.DOT`) for static image and PDF pipelines.
  - Implemented a quality analysis suite (`Choreo.Sequence.Analysis`) including missing labels, unknown participants, isolated participants, unbalanced activations, unclosed fragments, and general `validate/1`.
  - Added a full interactive Livebook walkthrough guide (`livebooks/sequence_walkthrough.livemd`).

- **Native Mermaid Visualizers & Syntaxes**:
  - **`Choreo.FSM`**: Added native `:state_diagram` (`stateDiagram-v2`) syntax support mapping initial/final states to entry/acceptance targets (`[*] --> state` and `state --> [*]`) and mapping custom labels.
  - **`Choreo.Dependency`**: Added native `:class_diagram` (`classDiagram`) syntax support mapping application/module/library types to standard UML stereotypes (e.g. `<<module>>`) and mapping relationships to standard UML connectors (`..>`, `--|>`, `-->`).
  - Updated all walkthrough Livebooks and the `README.md` to demonstrate and utilize these alternative syntaxes.

- **Structural & Heatmap Analysis Suite**:
  - Implemented `Choreo.Analysis.heatmap/2` for automatic, data-driven diagram coloring using configurable color scales.
  - **Structural Analysis Suite**:
    *   Implemented `Choreo.Analysis.cut_vertices/1` (Articulation Points) to identify Single Points of Failure.
    *   Implemented `Choreo.Analysis.core_numbers/1` using K-Core decomposition to isolate tightly-coupled architectural "nuclei."
    *   Implemented `Choreo.Analysis.reduce_transitive/1` for transitive reduction of dependency meshes.
    *   Implemented `Choreo.Analysis.path/4` for domain-aware pathfinding (Fastest Path, Widest Path, etc.).
    *   Added support for **Custom Weight Variables** in pathfinding via arbitrary metadata keys or custom lambda functions.
    *   Added `Choreo.Analysis.highlight/1` to easily visualize pathfinding results in rendered diagrams.
  - Added domain-specific heatmap analysis:
    - `Choreo.Workflow.Analysis.heatmap/2` for identifying execution latency hotspots.
    - `Choreo.Dataflow.Analysis.heatmap/2` for identifying throughput and data-volume hotspots.
    - `Choreo.ThreatModel.Analysis.heatmap/2` for identifying security risk hotspots based on threat density.
  - Added `Choreo.Analysis.legend/1` to generate visual color-scale keys for diagrams.
  - Generalized `Choreo.Analysis.centrality/2` to support all Choreo diagram types (Workflow, Dataflow, etc.).
  - Added standard color palettes to `Choreo.Theme`: `:heat` (Yellow-Red), `:cool` (Blue), and `:spectral` (Rainbow).
- **Structural Enhancements**:
  - Updated cluster schema to support both atom and string `:style` options, resolving rendering crashes in `Yog.Multi.DOT`.

## [0.7.1] - 2026-05-04

### Added

- **Theming API Overhaul**:
  - Implemented `Choreo.Theme.override/2` to allow non-destructive deep-merging of nested theme maps (`colors`, `shapes`) while replacing top-level attributes like `graph_rankdir`.
  - Added a standardized `theme/2` helper function across all core modules (`Workflow`, `Dataflow`, `MindMap`, `FSM`, `DecisionTree`, `Dependency`, and `ThreatModel`) to easily apply specific overrides while preserving default module schemas.
- Added `:retention` option to `Choreo.ThreatModel.add_data_store/3` for modeling data lifecycles.

### Fixed

- Added `:none` to the allowed `privilege` types in `Choreo.ThreatModel` processes to support modeling unprivileged services.
- `Choreo.ThreatModel.Analysis` now correctly downgrades the base severity of STRIDE threats (Spoofing, Tampering, Information Disclosure, Denial of Service) for processes with `:none` privilege to reflect their lower impact surface.

## [0.7.0] - 2026-05-03

### Added

- **Cross-module diagram composition (`Choreo.embed/4`)**:
  - Safely merge modular sub-diagrams (`Workflow`, `Dataflow`, etc.) into root clusters.
  - Automatic cluster namespace isolation and node ID prefixing.

- **Custom theme presets and per-node style overrides** across all modules:
  - Overriding shape, fillcolor, fontcolor, style, and penwidth for individual nodes.
  - Global theme preset capabilities.
- **Automated validation parameter docs** using `NimbleOptions.docs/1`.
- **Strict Schema Validation** using `NimbleOptions` across all core modules:
  - All diagram builders (`Choreo.FSM`, `Choreo.DecisionTree`, `Choreo.ThreatModel`, `Choreo.Workflow`, `Choreo.Dataflow`, and `Choreo.Dependency`) now enforce compile-time and runtime options validation on nodes and edges.

- **Multigraph support (parallel edges)** for `Choreo` and `Choreo.FSM`:
  - Multiple distinct edges can now exist between the same pair of nodes
  - `Choreo.edges_with_meta/1` — returns `[{from, to, cost, meta}]` tuples
  - `Choreo.to_simple_graph/2` — collapses parallel edges for algorithm analysis (default combine: `min/2`)
- `Choreo.MindMap` — concept-mapping builder with hierarchical branches and associative cross-links
  - Nodes: `set_root/3`, `add_topic/3`, `add_subtopic/3`, `add_note/3`
  - Edges: `branch/4` (hierarchical), `associate/4` (cross-link with dashed, undirected rendering)
  - Analysis: `depth/1`, `breadth/1`, `leaves/1`, `orphan_nodes/1`, `max_width/1`, `paths/1`, `type_frequencies/1`, `cyclic?/1`, `validate/1`
  - 5 built-in themes (`:default`, `:dark`, `:warm`, `:forest`, `:ocean`) with mind-map-specific colour palettes
  - Same-rank sibling alignment in DOT output
- `Choreo.View` — graph lens layer for zoom, focus, filter, and collapse transforms across diagram modules
  - `focus/3` — ego-graph view (node + N-hop neighbourhood, bidirectional by default)
  - `focus_between/4` — shortest-path view between two nodes, with optional neighbourhood radius
  - `zoom/2` — module-defined level-based filtering with optional `transitive: true` for virtual edges through removed intermediates
  - `filter/3` — predicate-based node filtering with optional `transitive: true`
  - `collapse/4` — aggregate multiple nodes into one, automatically rewiring all incoming/outgoing edges and removing duplicates/self-loops
  - Protocol-based design (`Choreo.Viewable`) so each module defines its own rebuild, root-resolution, zoom-predicate, and virtual-edge styling
  - Virtual edges are automatically styled (dashed, pale) via the protocol's `virtual_edge_meta/1` callback
  - Supports all diagram modules: `Choreo`, `Choreo.MindMap`, `Choreo.DecisionTree`, `Choreo.Dataflow`, `Choreo.ThreatModel`, `Choreo.Dependency`, and `Choreo.Workflow`
  - `Choreo.View` transparently handles both simple graphs (`Yog.Graph`) and multigraphs (`Yog.Multi.Graph`) via internal dispatch helpers
- `Choreo.FSM` enforces **100% DFA purity** at build time:
  - Epsilon transitions (empty labels) are rejected with `ArgumentError`
  - Different transition labels between the same state pair are now allowed (e.g., `q0 --"a"--> q1` and `q0 --"b"--> q1`)
  - Duplicate labels from the same state are still rejected (DFA determinism)

### Changed

- **Breaking:** `Choreo` core module converted from simple graph (`Yog.Graph`) to multigraph (`Yog.Multi.Graph`):
  - `edge_meta` is now keyed by `edge_id` (integer) instead of `{from, to}` tuples
  - `connect/4` and `add_dataflow/4` use `Yog.Multi.add_edge/4`
  - `Choreo.Render.DOT` uses `Yog.Multi.DOT` for rendering parallel edges
  - `Choreo.Analysis` internally collapses multigraphs to simple graphs before running algorithms
- **Breaking:** `Choreo.FSM` converted from simple graph to multigraph:
  - `add_transition/4` uses `Yog.Multi.add_edge/4`
  - `Choreo.FSM.Render.DOT` uses `Yog.Multi.DOT`
  - `Choreo.FSM.Analysis` rewritten with multigraph-aware BFS and reverse-reachability helpers
- Bumped `yog_ex` requirement to `~> 0.97.1` (provides `Yog.Multi.DOT`)
- **Breaking:** Restored pure DFA boundaries across execution engines.
- Dropped ambiguous NFA mappings (`Analysis.to_dfa/1`).
- Refactored `%Choreo.FSM{meta: %{initial_state: state}}` singular state vectors.
- All edge builders now raise `ArgumentError` on duplicate `(from, to)` pairs instead of silently overwriting:
  - `Choreo.Dataflow.connect/4`
  - `Choreo.Workflow.connect/4`
  - `Choreo.Dependency.depends_on/4`
  - `Choreo.ThreatModel.data_flow/4`
- `Choreo.FSM.add_transition/4` no longer raises on duplicate `(from, to)` pairs — it allows parallel edges with different labels (DFA-compliant)
- Removed obsolete "single-edge-per-pair limitation" notes from docstrings where multigraph is now supported.

## 0.6.0 — 2026-04-25

### Added

- `Choreo.FSM.remove_initial_state/2` — explicitly demotes a state from initial status without deleting the node.
- `Choreo.FSM.remove_final_state/2` — explicitly demotes a state from final status without deleting the node.

### Changed

- **Breaking:** `Choreo.FSM` state typing moved from node `state_type` field to `meta` MapSets (`initial_states` and `final_states`). `add_state/3` with `type: :initial` or `type: :final` now populates these sets directly.
- `Choreo.FSM.add_state/3` with `type: :normal` now explicitly clears a state from both `initial_states` and `final_states` in meta. Omitting the `:type` option (e.g. updating a label) preserves existing status.
- `Choreo.FSM.Analysis.deterministic?/1` now enforces a **single initial state** in addition to unique outgoing transition labels, aligning with classical DFA definition.

### Fixed

- `add_state/3 with type: :initial` now correctly registers the state in `meta.initial_states` so that `reachable_states/1`, `accepts?/2`, and rendering treat it as an entry point.
- Fixed broken doctests in `Choreo.FSM.add_initial_state/2` and `Choreo.FSM.add_final_state/2` that still referenced the removed `state_type` node field.

## 0.5.0 — 2026-04-24

### Added

- `Choreo.Workflow` — task orchestration builder with Saga-pattern compensation support
  - Nodes: `add_start/3`, `add_end/3`, `add_task/3`, `add_decision/3`, `add_fork/3`, `add_join/3`, `add_compensation/3`, `add_event/3`
  - Edge types: `:sequence`, `:compensation`, `:retry`, `:failure`, `:timeout`
  - Swimlane grouping for visual organization
  - Analysis: `critical_path/1`, `parallelizable_tasks/1`, `failure_scenarios/1`, `missing_compensations/1`, `bottlenecks/2`, `simulate/1`, `validate/1`
- Internal helpers module — shared `bfs_reachable/2`, `build_cluster_subgraphs/2`, `best_predecessor/3` extracted to eliminate Credo duplicate-code warnings

### Changed

- **Breaking:** Package and all modules renamed from `YogSystem` to `Choreo`
- `Choreo.DecisionTree.set_root/3` and `branch/4` now return `t()` directly (pipeable), raising `ArgumentError` on invalid use. Removed redundant `branch!/4`.

### Fixed

- All `mix credo --strict` warnings resolved (double filters, deep nesting, unused aliases, list append inefficiencies, `Enum.map_join/3` usage, `with`→`case` conversions)
- Incorrect `@spec` return types for edge-returning functions (`String.t()` → `number()`)

## 0.1.0 — 2026-04-24

### Added

- `Choreo` — infrastructure architecture diagrams with typed nodes (database, cache, service, queue, etc.), clusters, and MST/topological-sort analysis
- `Choreo.FSM` — finite-state machine builder with initial/final states, transitions, determinism checks, NFA simulation, equivalence checking, and pruning
- `Choreo.Dataflow` — pipeline / ETL diagram builder with sources, transforms, buffers, conditionals, merges, and sinks
  - Analysis: cycle detection, topological sort, orphan/dead-end detection, bottlenecks, critical-path (longest path), throughput simulation, backpressure detection
  - Edge types: normal, error, retry, dead-letter
  - Cluster support
- `Choreo.Dependency` — software dependency graphs with applications, libraries, modules, interfaces, and tests
  - Analysis: circular dependency extraction (actual paths), impact analysis (`affected_by/2`, `depends_on/2`), layer violation detection, centrality ranking, longest dependency chain
  - Cycle edge highlighting in DOT output
- `Choreo.DecisionTree` — classification tree builder with enforced tree invariants
  - Analysis: `decide/2` evaluation, path enumeration, depth/breadth metrics, feature importance, redundant-branch pruning
- `Choreo.ThreatModel` — STRIDE threat modeling with automated threat generation
  - Analysis: auto-generated STRIDE threats per element type, trust-boundary crossing detection, exposed data stores, high-risk processes, unencrypted flow detection
  - Severity scoring based on sensitivity, privilege, encryption, and trust level
- Shared DOT rendering pipeline with `:default`, `:dark`, and custom `Choreo.Theme` support
- Graphviz integration in ExDoc for inline diagram rendering
- Credo, Dialyzer, and ExCoveralls tooling
