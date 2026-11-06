defmodule LiveLiftDemoWeb.Router do
  use LiveLiftDemoWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {LiveLiftDemoWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", LiveLiftDemoWeb do
    pipe_through :browser

    live "/", CounterLive
    live "/form-parity", FormParityLive
    live "/native-counter", NativeCounterLive
    live "/native-counter-server", NativeCounterLive, :server
  end

  # Other scopes may use custom stacks.
  # scope "/api", LiveLiftDemoWeb do
  #   pipe_through :api
  # end
end
