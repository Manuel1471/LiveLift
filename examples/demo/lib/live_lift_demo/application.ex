defmodule LiveLiftDemo.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      LiveLiftDemoWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:live_lift_demo, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: LiveLiftDemo.PubSub},
      # Start a worker by calling: LiveLiftDemo.Worker.start_link(arg)
      # {LiveLiftDemo.Worker, arg},
      # Start to serve requests, typically the last entry
      LiveLiftDemoWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: LiveLiftDemo.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    LiveLiftDemoWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
