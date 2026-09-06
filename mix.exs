defmodule Choreo.MixProject do
  use Mix.Project

  @version "0.13.0"
  @source_url "https://github.com/code-shoily/choreo"

  def project do
    [
      app: :choreo,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: false,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      dialyzer: [plt_add_apps: [:mix], flags: [:no_opaque]],

      # Hex
      description: "Domain-specific diagram builders and graph analyzers on top of Yog",
      package: package(),

      # Docs
      name: "Choreo",
      source_url: @source_url,
      homepage_url: @source_url,
      docs: docs(),

      # Test Coverage
      test_coverage: [tool: ExCoveralls],
      coverage_options: [minimum_coverage: 82]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:yog_ex, "~> 0.99"},
      {:nimble_options, "~> 1.1"},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:jump_credo_checks, "~> 0.2", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:kino, "~> 0.14", optional: true}
    ]
  end

  defp package do
    [
      name: "choreo",
      files: ~w(lib .formatter.exs mix.exs README.md CHANGELOG.md LICENSE guides livebooks),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "guides/architecture_and_design.md",
        "guides/behavior_and_flows.md",
        "guides/data_and_structure.md",
        "guides/livebooks.md",
        "guides/lab_dsl.md",
        "guides/lab_cheatsheet.md",
        "guides/ALGORITHMS.md",
        "CHANGELOG.md"
      ],
      source_ref: "v#{@version}",
      source_url: @source_url,
      before_closing_body_tag: &before_closing_body_tag/1,
      groups_for_modules: [
        Core: [
          Choreo,
          Choreo.Theme,
          Choreo.View,
          Choreo.Viewable,
          Choreo.Mermaid,
          Choreo.Domain,
          Choreo.Sequence
        ],
        "System Architecture": [
          Choreo.C4,
          Choreo.C4.Render.DOT,
          Choreo.C4.Render.Mermaid,
          Choreo.Render.DOT,
          Choreo.Render.Mermaid
        ],
        "Cloud Infrastructure": [
          Choreo.Infrastructure
        ],
        "State Machines": [
          Choreo.FSM,
          Choreo.FSM.Render.DOT,
          Choreo.FSM.Render.Mermaid
        ],
        "Dataflow & Pipelines": [
          Choreo.Dataflow,
          Choreo.Dataflow.Render.DOT,
          Choreo.Dataflow.Render.Mermaid
        ],
        "Dependency Graphs": [
          Choreo.Dependency,
          Choreo.Dependency.Render.DOT,
          Choreo.Dependency.Render.Mermaid
        ],
        "Decision Trees": [
          Choreo.DecisionTree,
          Choreo.DecisionTree.Render.DOT,
          Choreo.DecisionTree.Render.Mermaid
        ],
        "Threat Modeling": [
          Choreo.ThreatModel,
          Choreo.ThreatModel.Render.DOT,
          Choreo.ThreatModel.Render.Mermaid,
          Choreo.ThreatModel.Render.PlantUML
        ],
        "Workflow & Orchestration": [
          Choreo.Workflow,
          Choreo.Workflow.Render.DOT,
          Choreo.Workflow.Render.Mermaid
        ],
        "Planning & Task Management": [
          Choreo.Planner,
          Choreo.Planner.Render.DOT,
          Choreo.Planner.Render.Mermaid,
          Choreo.Planner.Analysis
        ],
        "Mind Maps": [
          Choreo.MindMap,
          Choreo.MindMap.Render.DOT,
          Choreo.MindMap.Render.Mermaid
        ],
        "Database Design": [
          Choreo.ERD,
          Choreo.ERD.Render.DOT,
          Choreo.ERD.Render.Mermaid
        ],
        "UML Design": [
          Choreo.UML,
          Choreo.UML.Render.DOT,
          Choreo.UML.Render.Mermaid
        ],
        Lab: [
          Choreo.Lab.Compose,
          Choreo.Lab.View,
          Choreo.Lab.Siren,
          Choreo.Lab.Sketch,
          Choreo.Lab.DSL.C4,
          Choreo.Lab.DSL.Dataflow,
          Choreo.Lab.DSL.DecisionTree,
          Choreo.Lab.DSL.Dependency,
          Choreo.Lab.DSL.Domain,
          Choreo.Lab.DSL.ERD,
          Choreo.Lab.DSL.FSM,
          Choreo.Lab.DSL.Infrastructure,
          Choreo.Lab.DSL.MindMap,
          Choreo.Lab.DSL.Planner,
          Choreo.Lab.DSL.Requirement,
          Choreo.Lab.DSL.Sequence,
          Choreo.Lab.DSL.ThreatModel,
          Choreo.Lab.DSL.UML,
          Choreo.Lab.DSL.Workflow
        ],
        Analysis: [
          Choreo.Analysis,
          Choreo.Analysis.Tracing,
          Choreo.C4.Analysis,
          Choreo.FSM.Analysis,
          Choreo.Dataflow.Analysis,
          Choreo.Dependency.Analysis,
          Choreo.DecisionTree.Analysis,
          Choreo.MindMap.Analysis,
          Choreo.ThreatModel.Analysis,
          Choreo.Workflow.Analysis,
          Choreo.ERD.Analysis,
          Choreo.UML.Analysis,
          Choreo.Infrastructure.Analysis,
          Choreo.Domain.Analysis,
          Choreo.Sequence.Analysis
        ]
      ],
      groups_for_extras: [
        "Getting Started": [
          "README.md",
          "guides/architecture_and_design.md",
          "guides/behavior_and_flows.md",
          "guides/data_and_structure.md",
          "guides/livebooks.md",
          "guides/lab_dsl.md",
          "guides/ALGORITHMS.md"
        ],
        Resources: [
          "CHANGELOG.md"
        ]
      ]
    ]
  end

  defp before_closing_body_tag(:html) do
    File.read!("priv/docs/graphviz.html")
  end

  defp before_closing_body_tag(_), do: ""
end
