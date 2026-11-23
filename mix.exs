defmodule LiveLift.MixProject do
  use Mix.Project

  @repository "https://github.com/Manuel1471/LiveLift"

  @getting_started ~w(
    README.md
    docs/phoenix-integration.md
    docs/liveview-migration-diff.md
    docs/sync.md
    docs/best-practices.md
  )
  @reference_guides ~w(
    docs/architecture.md
    docs/native-livecomponent.md
    docs/language.md
    docs/native-handler-matrix.md
    docs/semantics.md
    docs/security.md
    docs/production-readiness.md
    docs/telemetry.md
    docs/state-inspector.md
    docs/versioned-assets.md
  )
  @compiler_diagnostics "docs/errors/README.md"
  @package_guides @getting_started ++ @reference_guides ++ ~w(docs/errors CHANGELOG.md)
  @prototype_modules [
    LiveLift.Client,
    LiveLift.Client.Component,
    LiveLift.Sync,
    LiveLift.View,
    Mix.Tasks.LiveLift.Migrate
  ]

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
        files:
          [
            "lib",
            "assets/js/live_lift/client_hook.js",
            "assets/js/live_lift/local_actions.js",
            "assets/js/live_lift/client_hook.d.ts",
            "assets/js/live_lift/class_commands.js",
            "assets/js/live_lift/form_drafts.js",
            "assets/js/live_lift/devtools.js",
            "assets/js/live_lift/component_timers.js",
            "mix.exs",
            "LICENSE"
          ] ++ @package_guides,
        licenses: ["MIT"],
        links: %{"GitHub" => @repository}
      ]
    ]
  end

  def application, do: [extra_applications: [:logger, :crypto]]

  defp docs do
    errors = Path.wildcard("docs/errors/*.md") -- [@compiler_diagnostics]

    [
      main: "readme",
      source_ref: "main",
      filter_modules: fn module, _ -> module not in @prototype_modules end,
      extras:
        @getting_started ++
          @reference_guides ++
          [{@compiler_diagnostics, [filename: "compiler-diagnostics"]} | errors] ++
          ["CHANGELOG.md"],
      groups_for_extras: [
        "Getting started": @getting_started,
        Reference: @reference_guides,
        "Compiler diagnostics": ~r{docs/errors/},
        Releases: ["CHANGELOG.md"]
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
