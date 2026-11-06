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
          "LICENSE"
        ],
        licenses: ["MIT"],
        links: %{"GitHub" => "https://github.com/Manuel1471/LiveLift"}
      ]
    ]
  end

  def application, do: [extra_applications: [:logger]]

  defp deps do
    [
      {:phoenix_live_view, "~> 1.2.0"},
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false}
    ]
  end
end
