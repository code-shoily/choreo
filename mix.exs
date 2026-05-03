defmodule Choreo.MixProject do
  use Mix.Project

  @version "0.7.0"
  @source_url "https://github.com/code-shoily/choreo"

  def project do
    [
      app: :choreo,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
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
      test_coverage: [tool: ExCoveralls]
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
      {:yog_ex, "~> 0.97.1"},
      {:nimble_options, "~> 1.1"},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test}
    ]
  end

  defp package do
    [
      name: "choreo",
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE),
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
          Choreo.Viewable
        ],
        "System Architecture": [
          Choreo.Render.DOT
        ],
        "State Machines": [
          Choreo.FSM,
          Choreo.FSM.Render.DOT
        ],
        "Dataflow & Pipelines": [
          Choreo.Dataflow,
          Choreo.Dataflow.Render.DOT
        ],
        "Dependency Graphs": [
          Choreo.Dependency,
          Choreo.Dependency.Render.DOT
        ],
        "Decision Trees": [
          Choreo.DecisionTree,
          Choreo.DecisionTree.Render.DOT
        ],
        "Threat Modeling": [
          Choreo.ThreatModel,
          Choreo.ThreatModel.Render.DOT
        ],
        "Workflow & Orchestration": [
          Choreo.Workflow,
          Choreo.Workflow.Render.DOT
        ],
        "Mind Maps": [
          Choreo.MindMap,
          Choreo.MindMap.Render.DOT
        ],
        Analysis: [
          Choreo.FSM.Analysis,
          Choreo.Dataflow.Analysis,
          Choreo.Dependency.Analysis,
          Choreo.DecisionTree.Analysis,
          Choreo.MindMap.Analysis,
          Choreo.ThreatModel.Analysis,
          Choreo.Workflow.Analysis
        ]
      ],
      groups_for_extras: [
        Guides: [
          "README.md"
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
