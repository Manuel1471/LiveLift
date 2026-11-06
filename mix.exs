defmodule LiveLift.MixProject do
  use Mix.Project

  def project do
    [
      app: :live_lift,
      version: "0.1.0-dev",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Opt-in client-side interactions for Phoenix LiveView",
      package: [licenses: ["MIT"], links: %{"GitHub" => "https://github.com/Manuel1471/LiveLift"}]
    ]
  end

  def application, do: [extra_applications: [:logger]]

  defp deps do
    [{:phoenix_live_view, "~> 1.0"}, {:jason, "~> 1.4"}]
  end
end
