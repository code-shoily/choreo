# Integrations

This directory contains notebooks that bridge Choreo with other Elixir libraries and tools. They show how to use Choreo alongside runtime systems, visualization packages, and third-party DSLs.

- [`choreo_finitomata.livemd`](./choreo_finitomata.livemd) — design FSMs in Choreo, run them with Finitomata, and analyze them back in Choreo.
- [`hex_dependency_explorer.livemd`](./hex_dependency_explorer.livemd) — crawl any Hex package's dependency tree via the Hex API and build an interactive Choreo.Dependency diagram with cycle detection, instability metrics, and impact analysis.
- [`github_issues_explorer.livemd`](./github_issues_explorer.livemd) — fetch issues from any public GitHub repo and build a Choreo Planner (Kanban, Gantt, flowchart) and Mind Map (radial label-grouped concept map) with analysis.
- [`mix_xref_explorer.livemd`](./mix_xref_explorer.livemd) — analyze internal Elixir project dependencies using `mix xref` and generate visual Choreo.Dependency graphs, compile-time cycle detection, instability metrics, and change impact tracking.
- [`ecto_schema_erd.livemd`](./ecto_schema_erd.livemd) — introspect the Ecto schemas of any Phoenix/Elixir project and render them as an interactive Choreo.ERD diagram with orphan detection, circular FK detection, and join-path analysis.
- [`phoenix_liveview_explorer.livemd`](./phoenix_liveview_explorer.livemd) — discover Phoenix LiveView modules in a project and render their callback sequence and state machine.
- [`yogex_algorithm_selector.livemd`](./yogex_algorithm_selector.livemd) — build an interactive decision tree for picking the right YogEx algorithm for pathfinding, flow, matching, centrality, community detection, and more.
