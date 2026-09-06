# Changelog

## [Unreleased]

### Added

- `Choreo.Planner.Analysis`: Added `workload_by_assignee/2` to summarize open task counts, estimates, and statuses by owner.
- `Choreo.Domain`: Added `downstream/2` to trace downstream effects from a domain node.
- **ThreatModel Hardening & Advanced Security Analysis**:
  - `Choreo.ThreatModel`: Added support for `:role` (`:anonymous`, `:user`, `:partner`, `:admin`, `:third_party`), `:privilege`, and `:controls` in external entities; `:controls` in processes and data stores; and `:authenticated`, `:data`, `:sensitivity`, and `:controls` in data flows.
  - `Choreo.ThreatModel`: Added `:highlighted_nodes` and `:highlighted_edges` fields to the struct, and forwarded them seamlessly through `to_dot/2` and `to_mermaid/2`. Added `clear_highlight/1`.
  - `Choreo.ThreatModel.Analysis`: Added `entry_points/1` and `exit_points/1` to detect ingress vectors entering trusted domains and egress vectors leaving trusted boundaries.
  - `Choreo.ThreatModel.Analysis`: Added `blast_radius/2` to compute downstream compromise reachability, affected sensitive data stores, exposed trust boundaries, and qualitative risk rating.
  - `Choreo.ThreatModel.Analysis`: Added `highlight_attack_paths/2` to automatically highlight multi-hop attack paths across Graphviz and Mermaid visualizations.
  - `Choreo.ThreatModel.Analysis`: Added mitigation and control tracking to STRIDE threat generation (`:mitigated?`, `:controls`, `:owasp`), plus `unmitigated_threats/2` and `threats_for/3`.
  - `Choreo.ThreatModel.Analysis`: Added `to_markdown/2` for exporting structured, executive GitHub Flavored Markdown threat tables.
  - `Choreo.ThreatModel.Analysis`: Enhanced `validate/2` to check for direct flows between external entities and data stores, sensitive stores in low-trust boundaries, and missing boundary levels (`require_levels: true`).
  - `Choreo.ThreatModel.Analysis`: Added reviewer-layer analyses for residual risk scoring, control gap detection, exfiltration paths, boundary flow matrices, and prioritized findings.
  - `Choreo.Lab.DSL.ThreatModel`: Added edge modifiers `authenticated`, `carries`, `controls`/`protects`, and `sensitivity`.
  - Updated `livebooks/guides/threat_model_walkthrough.livemd` with ingress/egress analysis, blast radius, attack path highlighting, mitigations, reviewer-layer analysis, and Markdown matrices.

### Fixed

- Fixed stale Planner walkthrough `to_dot/2` option references and added an assignee workload analysis example.
- Fixed stale Sequence walkthrough rendering wording and async Mermaid arrow reference.
- Fixed stale UML walkthrough connector references and ERD Mermaid `:many_to_many` cardinality rendering.
- Fixed stale C4 walkthrough Mermaid rendering references and Domain Modeling cheat sheet API entries.
- Fixed stale Requirement walkthrough API references and added validation for duplicate human requirement IDs.
- Fixed stale FSM walkthrough API/rendering references and theme option documentation, and added defensive validation for duplicate outgoing transition labels.
- Fixed stale MindMap walkthrough API references and rendering/theme option documentation, and added defensive validation for invalid root pointers.
- Fixed sequence diagram flow label resolution in `Choreo.ThreatModel.Render.Mermaid.to_sequence/2` when flow labels are empty strings.
- Fixed non-constructor node expression handling in `Choreo.Lab.DSL.Sequence`.

## [0.13.0] - 2026-09-06

### Added

- **Universal Lab DSL Hardening**:
  - Added support for `edge/3` with both label and keyword options (`edge from ~> to, "label", opts`) across all 15 diagram vocabularies.
  - Added support for keyword options and label tuples in edge and relationship pipe modifiers across all DSLs.
  - Added `:type` (and `:edge_type`) modifiers across all DSLs for explicit relationship typing.
  - Expanded autocomplete helper stubs and `taxonomy/0` discovery across all diagram DSL modules.
  - Supported scoped hierarchical blocks (`vpc`, `subnet`, `boundary`, `cluster`, `swimlane`) with automatic parent and boundary inheritance.
- **Domain-Specific Enhancements**:
  - `Choreo.Requirement`: Added support for `:docref` in relationship schemas and edge metadata.
  - `Choreo.Infrastructure`: Allowed `nodes/1`, `edges/1`, `to_dot/2`, and `to_mermaid/2` to accept `%Choreo{}` diagrams.
  - `Choreo.DecisionTree`: Added optional keyword options `opts \\ []` to `branch/5`.
  - `Choreo.Planner`: Added `task_labels/2`, `tags/2`, and `tagged_tasks/2` query helpers.
  - `Choreo.Lab.DSL.ERD`: Added `:from_column`, `:to_column`, and `:cardinality` relationship modifiers.

### Changed

- **Walkthrough Livebooks**:
  - Updated all 15 walkthrough guides to showcase Lab DSL syntax across diagrams alongside canonical programmatic pipe APIs.
  - Added dual Cheat Sheet reference tables (Lab DSL syntax and Programmatic Pipe/Analysis APIs) to all walkthrough guides.

### Fixed

- **Block Scoping & Environment State**:
  - Ensured standalone node, boundary, and cluster declarations automatically register IDs into variable scope for subsequent edge statements.
  - Fixed parent/cluster environment state restoration after exiting nested blocks.
  - Fixed `pop_do_block/1` in `Choreo.Lab.DSL.Compiler` to recognize `do` blocks with preceding keyword options.
- **Rendering & Diagram Normalization**:
  - Hardened native Mermaid rendering for ERD, Sequence, and UML with sanitized identifiers and normalized member formatting.
  - Fixed `Choreo.Lab.Sketch` preprocessing for UML diagrams to preserve native `classDiagram` declarations.
- **DSL Defaults & Modifier Parsing**:
  - Ensured user constructors in Planner DSL populate default `:name` attributes matching title/id.
  - Fixed modifier delegation argument order and keyword option parsing in Domain, UML, and ERD DSLs.

## [0.12.0] - 2026-07-26

### Added

- Added `Choreo.Infrastructure.from_choreo/1` function to cast generic `%Choreo{}` diagrams into `%Choreo.Infrastructure{}` diagrams.
- Added `Choreo.Lab.DSL.Compiler` module to consolidate shared AST parsing helpers (`statements/1`, `pop_trailing_opts/1`, `slug_atom/1`, etc.) used by experimental diagram DSLs.
- Added autocomplete helper function stubs to all 15 incubating `Choreo.Lab.DSL.*` modules to support editor and Livebook autocompletion for diagram constructors and modifiers.
- Added visual hierarchy/nested do-block support to C4, Workflow, and Domain DSLs. Nested node declarations inside a system, container, swimlane, or bounded_context automatically inherit parent scope options.
- Added incubating `Choreo.Lab.DSL.*` sketch syntax across all current Choreo diagram/modeling modules, providing Livebook-friendly constructors, variable-bound nodes, typed edges, pipe modifiers, `taxonomy/0` discovery, and compilation back to the stable pipe-first builders.
- Added `mix choreo.render` for rendering `.choreo.exs` or `.exs` Choreo model files into Mermaid (`.mmd`) or Graphviz DOT (`.dot`) artifacts, including named multi-artifact outputs and per-artifact render options.
- Added the `Lab DSLs and Sketch Syntax` guide covering DSL philosophy, shared grammar, current DSL modules, Compose/View usage, and `.choreo.exs` rendering workflows.
- Added the `Lab DSL + Compose/View Cheatsheet` guide with quick DSL grammar, nouns/verbs, copy-paste examples, Compose helpers, View helpers, and rendering shortcuts.
- Added `Choreo.Lab.View` pipe-friendly helpers for Livebook zoom, focus, filter, path, and collapse exploration over `Choreo.View`, alongside rendering pipeline helper functions `tabs/2`, `to_siren/2`, `to_sketch/2`, `to_mermaid/2`, and `to_dot/2` for quick Livebook diagram presentation.
- Added `Choreo.Lab.Compose` pipe-friendly helpers for Livebook cluster, embed, connect, and trace composition over `Choreo`.

### Changed

- Expanded the `Lab DSLs and Sketch Syntax` guide with shared grammar details, a diagram nouns/verbs reference table, canonical vocabulary guidance, per-DSL cheat sheets, examples, and rendering notes.
- Updated FSM-focused Livebooks to demonstrate the incubating `Choreo.Lab.DSL.FSM` sketch syntax for hand-authored state machines while keeping pipe builders for dynamic adapter code.
- Updated the MindMap walkthrough Livebook to demonstrate the incubating `Choreo.Lab.DSL.MindMap` sketch syntax for hand-authored maps.
- Optimized compile-time statement processing in `Choreo.Lab.DSL.*` modules to use linear $O(N)$ prepending and reversing instead of $O(N^2)$ list append (`steps ++ statement_steps`).

### Fixed

- Hardened native Mermaid `mindmap` and `ishikawa` rendering for `Choreo.MindMap` by normalizing hierarchy labels and clarifying native syntax limitations.
- Hardened native Mermaid `stateDiagram-v2` rendering for `Choreo.FSM` by escaping state and transition labels, and clarified FSM complement, guard, and Mermaid syntax documentation.
- Fixed a parsing bug in `Choreo.Lab.Sketch` where `end` statements in sequence diagrams were stripped, which caused loop and conditional blocks to remain unclosed and crash the Excalidraw diagram renderer.
- Fixed shape normalization in `Choreo.Lab.Sketch` to support hyphens inside node IDs (by updating node ID matching from `\w+` to `[\w\-]+`).
- Fixed a crash in `Choreo.Infrastructure.Analysis.validate/1` and `warnings/1` when scanning diagrams generated by the infrastructure DSL (which produces a `%Choreo{}` struct) by enabling the validation methods to accept both `%Choreo{}` and `%Choreo.Infrastructure{}` structs.

## [0.11.0] - 2026-07-17

### Added

- Added an MCP section to `README.md` with setup instructions, client configuration, and example prompts.
- **Livebook execution test runner**:
  - Added `mix choreo.test_livebooks` task to find, parse, and execute all Elixir cells inside `.livemd` files.
  - Implements a headless `Kino` mock suite (inputs, layouts, frames, etc.) and a nested-aware markdown code block parser to safely validate Livebooks at runtime without dependencies or browser instances.
  - Integrated the validation task directly into the GitHub Actions CI/CD workflow (`ci.yml`).

- **Agent guidance and project skill for system design notebooks**:
  - Added `AGENTS.md` with project-specific guidance for build/test workflows, Livebook conventions, skill conventions, changelog style, and guardrails.
  - Added `.agents/skills/choreo-system-design/SKILL.md` to guide creation of Choreo-based system design Livebooks.
  - Covers clarifying prompts, choosing Choreo modules, C4/dataflow/ERD/threat-model workflows, validation, and LLM review prompts.
  - Added `livebooks/projects/api_gateway_system_design.livemd` and `livebooks/projects/web_crawler_system_design.livemd` as worked examples of the skill.

- **Lightweight Zero-Dependency MCP Server**:
  - Added `Choreo.MCP` module implementing an stdio MCP server for system design loops.
  - Added mix task `mix choreo.mcp` to run the server via standard JSON-RPC.
  - Includes tools for initializing design notebooks (`choreo_initialize_design_notebook`), parsing notebook sections (`choreo_read_design_notebook`), updating design blocks (`choreo_update_design_section`), and verifying Elixir code syntax (`choreo_verify_design`).
  - Added unit test suite in `test/choreo/mcp_test.exs`.

- **Requirements traceability diagrams with `Choreo.Requirement`**:
  - Added `Choreo.Requirement` builder for requirements, components, tests, and stakeholders with `satisfies`, `verifies`, `refines`, `depends`, `traces`, `contains`, `derives`, and custom `relate` relationships.
  - Added Graphviz DOT and Mermaid `requirementDiagram` renderers with risk-based coloring and relationship styling.
  - Added `Choreo.Requirement.Analysis` for coverage, orphan detection, risk propagation, high-risk gaps, impact analysis, circular dependency detection, and validation.
  - Added `livebooks/integrations/requirements_exchange.livemd` — import requirements from CSV, JIRA, and DOORS-style exports, render them, and export back to CSV.

- **Native Mermaid `swimlane-beta` syntax support for `Choreo.Workflow`**:
  - Added `:syntax` option to `Choreo.Workflow.to_mermaid/2`; accepts `:flowchart` (default) or `:swimlane` (Mermaid 11.16+ `swimlane-beta`).
  - Maps defined swimlanes to subgraphs and renders tasks, decisions, starts/ends, and styled sequence or compensation edges.

- **DDD/Event Modeling API additions for `Choreo.Domain`**:
  - Added semantic relationship helpers: `initiates/4`, `handles/4`, `emits/4`, `triggers/4`, `projects_to/4`, `notifies/4`, and `translates_via/4`.
  - Added bounded-context metadata for `:subdomain` and `:owner`, plus aggregate/workflow `:invariants` documentation.
  - Added named scenarios with `add_scenario/3`, `scenarios/1`, `scenario/2`, and `focus_scenario/2`.
  - Added native Mermaid `eventmodeling` projection via `Domain.to_mermaid(domain, syntax: :event_modeling, path: [...])` or `scenario: :name`.
  - Extended `Choreo.Domain.Analysis.validate/1` with semantic relationship endpoint checks, scenario path validation, and DDD metadata quality hints.
  - Revamped `livebooks/guides/domain_modeling_walkthrough.livemd` around the v0.11 Domain API, including semantic edges, invariants, named scenarios, Event Modeling projection, and audit output.

- **Native Mermaid `ishikawa` syntax support for `Choreo.MindMap`**:
  - Added `:syntax` option value `:ishikawa` to `Choreo.MindMap.to_mermaid/2` for cause-and-effect/root-cause projections (Mermaid 11.12.3+).
  - Renders the mind-map root as the effect/problem and branch edges as cause/sub-cause hierarchy; associative cross-links are omitted like native `:mindmap` rendering.
  - Revamped `livebooks/guides/mind_map_walkthrough.livemd` around flowchart, native mindmap, native Ishikawa, analysis, validation, and graph lenses.

### Changed

- Refactored Livebook validation internals so the MCP server and `mix choreo.test_livebooks` share the same parser, evaluator, and `Kino` mock suite via `Choreo.Livebook` and `Choreo.Livebook.KinoMock`.
- `choreo_verify_design` now evaluates Elixir code blocks (with `Mix.install` stripped and `Kino` redirected to mocks) instead of only checking syntax.
- Disabled protocol consolidation in `mix.exs` so Livebooks that define protocol implementations at runtime validate headlessly.
- **Validation Signature Harmonization**:
  - Harmonized `validate/1` and `validate_messages/1` in `Choreo.Planner.Analysis` and `Choreo.Requirement.Analysis` to return standard `[{severity, message_string}]` 2-tuples consistent with all other domains.
  - Added theme helpers `theme/0`, `theme/1`, and `theme/2` to `Choreo.Requirement.Render.Mermaid` and added `:minimal` theme support in `Choreo.Requirement.Render.DOT`.
  - Added `Choreo.Requirement` and its submodules to the API stability suite in `test/choreo/api_stability_test.exs`.
  - Fixed runtime crash vulnerability in direction option parsing of `Choreo.ERD.Render.DOT` and `Choreo.UML.Render.DOT` by replacing unsafe `String.to_existing_atom` with static mapping.

### Fixed

- Made markdown section parsing code-fence-aware so Elixir comments are not mistaken for section headers.
- Made section replacement in `choreo_update_design_section` use exact normalized header matching rather than substring matching.
- Fixed `Mix.install/2` stripping to handle additional keyword arguments such as `consolidate_protocols: false`.
- Fixed `KinoMock.Input.select/3` crash when the options list is empty.
- `mix choreo.test_livebooks` now skips integration notebooks that require external project features (e.g. `ecto_schema_erd.livemd`).
- `call_graph_analysis.livemd` now removes the temporary `xref_graph.dot` it creates; added the generated pattern to `.gitignore`.
- Fixed `Choreo.C4.Analysis` false positives where parent boundary nodes (software systems/containers) were reported as isolated when their descendant containers/components had relationships.
- Fixed Mermaid `requirementDiagram` renderer so multi-line requirement and element blocks are joined with newlines instead of being collapsed onto a single line.
- Fixed Mermaid `requirementDiagram` rendering syntax error by mapping the `:depends` relationship type (not natively supported by Mermaid's parser) to `traces`.
- **Mermaid `architecture-beta` syntax support for `Choreo` and `Choreo.Infrastructure`**:
  - Added `Choreo.Render.Architecture` to render system and infrastructure diagrams using Mermaid's native `architecture-beta` diagram type.
  - Added `:syntax` option to `Choreo.to_mermaid/2` and `Choreo.Infrastructure.to_mermaid/2`; accepts `:flowchart` (default) or `:architecture`.
  - Maps Choreo node types to architecture icons (`:internet` → `internet`, `:database`/`:managed_db`/`:cache` → `database`, `:storage` → `disk`, `:network` → `cloud`, others → `server`).
  - Renders Choreo clusters as nested `group` declarations and edges as port-aware connections.
  - Sanitizes node IDs and labels to the character set supported by Mermaid's `architecture-beta` parser.

## [0.10.0] - 2026-07-04

### Added

- **Uniform Theming API across all diagrams**:
  - Implemented `theme/2` helper function for `Choreo.Domain`, `Choreo.Infrastructure`, `Choreo.Planner`, and `Choreo.Sequence` diagrams to provide a uniform theming interface.
  - Implemented complete theme support for sequence diagrams (`Choreo.Sequence`) in both DOT timeline rendering and native Mermaid `sequenceDiagram` rendering, using theme variables profiles (default, dark, minimal, warm, forest, ocean).

- **Choreo.Lab.Siren & Choreo.Lab.Sketch (Experimental)**:
  - Added `Choreo.Lab.Siren` module — an enhanced Mermaid.js renderer for Livebook with hardware-accelerated zoom/pan controls, dynamic fit-to-screen scaling, and automatic dark/light theme detection.
  - Added `Choreo.Lab.Sketch` module — an interactive Excalidraw whiteboard renderer that parses Mermaid syntax in the browser and displays it as a fully editable hand-drawn sketch.

- **Choreo.FSM.Analysis — Advanced Analysis Suite**:
  - Added `Analysis.generate_test_cases/2` to generate transition sequences for `:state` and `:transition` test coverage.
  - Added `Analysis.equivalent?/2` to check equivalence of two FSMs using product automaton BFS traversal.
  - Added `Analysis.minimize/1` to minimize a DFA using Partition Refinement (Moore's algorithm).
  - Added `Analysis.violates_invariant?/2` to validate safety/liveness state invariants.

- **Choreo.DecisionTree.Analysis — Rule Extraction, Test Cases, and Completeness**:
  - Added `Analysis.rules/1` to extract IF-THEN rules from every root-to-leaf path.
  - Added `Analysis.generate_test_cases/1` to generate feature maps that exercise every reachable leaf path.
  - Added `Analysis.orphan_nodes/1` to detect declared nodes that are unreachable from the root.
  - Added `Analysis.missing_branches/2` to find decision nodes that do not cover an expected set of feature values.
  - Extended `Analysis.validate/1` to warn about orphan nodes.

- **Choreo.ERD.Analysis — Dependency & Cascade Analysis**:
  - Added `Analysis.affected_by/2` to find tables that transitively depend on a target table.
  - Added `Analysis.depends_on/2` to find tables that a target table transitively depends on.
  - Added `Analysis.transitive_reduction/1` to identify redundant relationships implied by longer paths.
  - Added `Analysis.longest_dependency_chain/1` to find the longest relationship cascade in an acyclic schema.

- **Choreo.UML.Analysis — Validation & Dependency Analysis**:
  - Added `Analysis.validate/1` to report cycles, broken contracts, isolated classes, and Law of Demeter violations as `{severity, message}` tuples.
  - Added `Analysis.affected_by/2` to find classes that transitively depend on a target class.
  - Added `Analysis.depends_on/2` to find classes that a target class transitively depends on.
  - Added `Analysis.transitive_reduction/1` to identify redundant relationships implied by longer paths.

## [0.9.0] - 2026-06-09

### Fixed

- **Choreo.embed/4** — replaced fragile key-shape heuristic for determining simple-vs-multigraph with an explicit `match?(%Yog.Multi.Graph{}, ...)` struct check; eliminates silent branch fall-through when `edge_meta` is empty.
- **Choreo.embed/4** — replaced `String.replace/3` with `String.replace_prefix/3` for cluster name sanitization to avoid corrupting cluster names that contain `"cluster_"` as an interior substring.
- **Choreo.connect/4** — added `:strict` boolean option; when `true`, raises `ArgumentError` if either endpoint is missing; when `false` (default) and both endpoints are absent, emits a `Logger.warning/1` instead of silently auto-creating two generic nodes.
- **Choreo.Viewable** — removed `@fallback_to_any true` directive (no `Any` implementation existed); Elixir's default protocol dispatch now produces the cleaner `Protocol.UndefinedError` for unimplemented types.
- **Choreo.Render.DOT / Choreo** — corrected stale `:theme` option documentation in `Choreo.to_dot/2` and `Choreo.Render.DOT`; both now list all six supported themes (`:default`, `:dark`, `:minimal`, `:warm`, `:forest`, `:ocean`).

### Changed

- **Choreo** — centralized zoom-tier type taxonomy into a single `@zoom_tiers` module attribute inside `defimpl Choreo.Viewable, for: Choreo`; adding a new node type now requires touching one place instead of three `zoom_predicate/2` clauses.

### Removed

- **Choreo.FSM**:
  - Removed the former `initial_states/1` helper. Use `Choreo.FSM.initial_state/1` instead.

- **Choreo.FSM.Analysis**:
  - Removed `Analysis.deterministic?/1` and `Analysis.nondeterministic_states/1` since `Choreo.FSM` enforces DFA determinism strictly at build-time.

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

- **Choreo.Domain — DDD, Event Storming & Functional Modeling**:
  - Implemented `Choreo.Domain` vocabulary layer mapping Strategic Bounded Context maps and Tactical Event Storming models.
  - Added builders for Event Storming sticky notes: `add_actor/3`, `add_command/3`, `add_aggregate/3`, `add_event/3`, `add_read_model/3`, `add_policy/3`, `add_external_system/3`, `add_acl/3`, and `add_workflow/3`.
  - Added support for UML-style structured field specifications on `:type` and `:aggregate` nodes, rendering them as clean HTML-like table grids in Graphviz and newline-separated lists in Mermaid.
  - Implemented context-mapping relationship decorators in `connect_contexts/4` with automatic suppliers, customers, conformists, OHS, PL, and ACL markings on arrows.
  - Implemented scenario highlighting lens via `focus_path/2` to visually gray-out nodes outside of targeted execution paths.
  - Implemented recursive root-cause verification using `trace_cause/2`.
  - Implemented semantic audit validations in `Choreo.Domain.Analysis` checking for orphaned commands, dead-end events, parentless events, and dangling saga policies.
  - Added interactive walkthrough notebook (`livebooks/guides/domain_modeling_walkthrough.livemd`).

- **Cross-Diagram Semantic Tracing & Impact Analysis**:
  - Implemented trace helpers for declaring semantic connections between nodes across different diagram schemas (e.g. Workflow task -> C4 component -> ERD table).
  - Implemented `Choreo.Analysis.Tracing` with `impact_analysis/2` (transitively walks dependency graphs backwards to find all impacted components) and `trace_path/3` (computes cross-diagram execution paths).
  - Added `:show_traces` option to `Choreo.to_dot/2` and `Choreo.to_mermaid/2` to render trace links as styled red dashed arrows with layout constraint bypass (`constraint=false` in Graphviz).

- **Choreo.Infrastructure — Cloud Network Topology Preset**:
  - Implemented `Choreo.Infrastructure` as a domain-specific vocabulary layer on top of Choreo's existing graph, cluster, and rendering stack — not a parallel implementation.
  - Added typed network boundary builders: `add_vpc/3`, `add_subnet_public/3`, `add_subnet_private/3` — clusters with security semantics (`:vpc`, `:subnet_public`, `:subnet_private` types).
  - Added infrastructure node builders: `add_internet/3`, `add_load_balancer/3`, `add_compute/3`, `add_managed_db/3`, `add_storage/3`.
  - Added `connect/3` with `:protocol` metadata (`:https`, `:ssl`, `:tcp`, etc.) for styled edge rendering.
  - Extended the shared `Choreo.Render.DOT` pipeline with infrastructure-specific VPC/subnet cluster boundary coloring (theme-aware: light and dark variants), and node shapes/colors resolved via `Choreo.Theme`.
  - Extended the shared `Choreo.Render.Mermaid` pipeline with Mermaid-compatible infrastructure node shapes (`:circle`, `:hexagon`, `:subroutine`, `:cylinder`) and styled edges.
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
  - Added ExDoc groupings and a full interactive Livebook walkthrough guide (`livebooks/guides/erd_walkthrough.livemd`).

- **Choreo.UML — Class & Struct Diagrams**:
  - Implemented `Choreo.UML` schema builder with strict `NimbleOptions` field, arity, visibility, and relationship constraint validation.
  - Implemented themed three-compartment HTML record table visualization (`Choreo.UML.Render.DOT`) supporting standard class/struct/interface/behavior/protocol types, visibilities (`+`, `-`, `#`), and proper hollow/solid arrowhead line layouts.
  - Implemented Mermaid visual syntax rendering (`Choreo.UML.Render.Mermaid`) supporting both flowchart layouts and native `classDiagram` rendering.
  - Implemented `Choreo.Viewable` protocol for standard graph lens operations (`focus`, `zoom`, `filter`, `collapse`).
  - Implemented a static analysis suite (`Choreo.UML.Analysis`) including circular dependency detection, behavior contract validation, and Robert C. Martin's coupling & stability metrics.
  - Added ExDoc groupings and a full interactive Livebook walkthrough guide (`livebooks/guides/uml_walkthrough.livemd`).

- **Choreo.Planner — Project Planning Diagrams**:
  - Implemented `Choreo.Planner` builder for project planning with tasks, milestones, users, and labels.
  - Implemented relationship builders: `contains/3` (milestone hierarchy), `depends_on/3` (finish-to-start), `blocks/3` (semantic blocker), `assign/3` (ownership), `tag/3` (categorization), and `relates/3` (association).
  - Implemented native Mermaid rendering (`Choreo.Planner.Render.Mermaid`) supporting `:kanban`, `:kanban_compat`, `:gantt`, and `:flowchart` syntaxes with status columns, color coding, and dependency scheduling.
  - Implemented themed DOT flowchart rendering (`Choreo.Planner.Render.DOT`) via `Yog.Multi.DOT`.
  - Implemented a planning analysis suite (`Choreo.Planner.Analysis`) including `ready/1`, `blocked/1`, `critical_path/2`, `bottlenecks/1`, and `validate/1`.
  - Added a full interactive Livebook walkthrough guide (`livebooks/guides/planner_walkthrough.livemd`).

- **Choreo.C4 — C4 Model Architecture Diagrams**:
  - Implemented `Choreo.C4` schema builder for L1–L3 C4 modeling with `add_person/3`, `add_software_system/3`, `add_container/3`, and `add_component/3`.
  - Implemented parent/child clustering with automatic container assignment from `:parent` references.
  - Implemented zoom-aware rendering via `Choreo.Viewable` protocol, enabling level-based filtering (System Context, Containers, Components).
  - Implemented themed DOT rendering (`Choreo.C4.Render.DOT`) with C4-specific visual conventions: persons as ellipses, systems as boxes, containers as rounded boxes, and components as dashed boxes.
  - Implemented native Mermaid rendering (`Choreo.C4.Render.Mermaid`) with matching shapes and built-in theme support.
  - Implemented a structural analysis suite (`Choreo.C4.Analysis`) including missing parent detection, missing description/technology detection, isolated node detection, missing relationship labels, and general `validate/1`.
  - Added a full interactive Livebook walkthrough guide (`livebooks/guides/c4_walkthrough.livemd`).

- **Choreo.Sequence — Sequence Diagrams**:
  - Implemented `Choreo.Sequence` builder for ordered participant interactions with `add_actor/3`, `add_participant/3`, `message/4`, `async/4`, `return/4`, and `self_message/3`.
  - Implemented activation boxes via `activate/2` and `deactivate/2`, plus notes (`note/3`) and fragments (`loop`, `opt`, `alt`/`else`, `par`, `break`, `critical`).
  - Implemented native Mermaid `sequenceDiagram` rendering (`Choreo.Sequence.Render.Mermaid`) with actors, participants, activation boxes, notes, and fragments.
  - Implemented a best-effort DOT timeline fallback (`Choreo.Sequence.Render.DOT`) for static image and PDF pipelines.
  - Implemented a quality analysis suite (`Choreo.Sequence.Analysis`) including missing labels, unknown participants, isolated participants, unbalanced activations, unclosed fragments, and general `validate/1`.
  - Added a full interactive Livebook walkthrough guide (`livebooks/guides/sequence_walkthrough.livemd`).

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
- The FSM determinism analysis now enforces a **single initial state** in addition to unique outgoing transition labels, aligning with classical DFA definition.

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
