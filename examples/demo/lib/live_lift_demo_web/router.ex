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

  pipeline :script_csp do
    plug :put_script_csp
  end

  scope "/", LiveLiftDemoWeb do
    pipe_through :browser

    live "/", CounterLive
    live "/form-parity", FormParityLive
    live "/native-counter", NativeCounterLive
    live "/native-counter-server", NativeCounterLive, :server
    live "/native-timer", NativeTimerLive
    live "/native-form", NativeFormLive
    live "/native-optional", NativeOptionalLive
    live "/native-float", NativeFloatLive
    live "/native-list", NativeListLive
    live "/local-actions", LocalActionsLive
    live "/many-islands", ManyIslandsLive
  end

  scope "/", LiveLiftDemoWeb do
    pipe_through [:browser, :script_csp]

    live "/local-actions-csp", LocalActionsLive
  end

  defp put_script_csp(conn, _opts) do
    url = conn |> request_url() |> URI.new!()
    scheme = if url.scheme == "https", do: "wss", else: "ws"
    socket = %URI{scheme: scheme, host: url.host, port: url.port}

    put_resp_header(
      conn,
      "content-security-policy",
      "script-src 'self'; connect-src 'self' #{socket}; object-src 'none'; base-uri 'none'"
    )
  end

  # Other scopes may use custom stacks.
  # scope "/api", LiveLiftDemoWeb do
  #   pipe_through :api
  # end
end
