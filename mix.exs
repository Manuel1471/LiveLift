defmodule LiveLift.MixProject do
  use Mix.Project

  @repository "https://github.com/Manuel1471/LiveLift"

  def project do
    [
      app: :live_lift,
      version: "0.1.0-rc.1",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      source_url: @repository,
      docs: docs(),
      description: "Opt-in client-side interactions for Phoenix LiveView",
      package: [
        files: [
          "lib",
          "assets/js/live_lift/client_hook.js",
          "assets/js/live_lift/local_actions.js",
          "assets/js/live_lift/client_hook.d.ts",
          "assets/js/live_lift/class_commands.js",
          "assets/js/live_lift/form_drafts.js",
          "assets/js/live_lift/devtools.js",
          "assets/js/live_lift/component_timers.js",
          "docs",
          "mix.exs",
          "README.md",
          "ROADMAP.md",
          "CHANGELOG.md",
          "LICENSE"
        ],
        exclude_patterns: ["docs/release.md"],
        licenses: ["MIT"],
        links: %{"GitHub" => @repository}
      ]
    ]
  end

  def application, do: [extra_applications: [:logger, :crypto]]

  defp docs do
    guides = [
      "README.md",
      "docs/phoenix-integration.md",
      "docs/native-livecomponent.md",
      "docs/liveview-migration-diff.md",
      "docs/language.md",
      "docs/production-readiness.md"
    ]

    diagnostic_catalog = "docs/errors/README.md"
    reference = Path.wildcard("docs/**/*.md") -- ["docs/release.md", diagnostic_catalog | guides]

    [
      main: "readme",
      source_ref: "main",
      extras:
        guides ++
          [{diagnostic_catalog, [filename: "compiler-diagnostics"]}] ++
          ["CHANGELOG.md", "ROADMAP.md"] ++ reference,
      groups_for_extras: [
        "Getting started": guides,
        "Compiler diagnostics": ~r{docs/errors/},
        "Implementation evidence": ~r{docs/(progress|decisions)/|-spike[s]?\.md$},
        Releases: ["CHANGELOG.md", "ROADMAP.md"]
      ]
    ]
  end

  defp deps do
    [
      live_view_dependency(),
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.4"},
      {:stream_data, "~> 1.4", only: :test},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false}
    ]
  end

  defp live_view_dependency do
    case System.get_env("LIVE_LIFT_LIVE_VIEW_VERSION") do
      "main" ->
        {:phoenix_live_view,
         git: "https://github.com/phoenixframework/phoenix_live_view.git", branch: "main"}

      version ->
        {:phoenix_live_view, version || "~> 1.2.0"}
    end
  end
end
