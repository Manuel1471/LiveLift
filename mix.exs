defmodule LiveLift.MixProject do
  use Mix.Project

  def project do
    [
      app: :live_lift,
      version: "0.1.0-rc.1",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Opt-in client-side interactions for Phoenix LiveView",
      package: [
        files: [
          "lib",
          "assets/js/live_lift/client_hook.js",
          "docs",
          "mix.exs",
          "README.md",
          "CHANGELOG.md",
          "LICENSE"
        ],
        exclude_patterns: ["docs/release.md"],
        licenses: ["MIT"],
        links: %{"GitHub" => "https://github.com/Manuel1471/LiveLift"}
      ]
    ]
  end

  def application, do: [extra_applications: [:logger]]

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
