Mix.install([
  {:bandit, "1.15.0"},
  {:ecto, "3.14.3"},
  {:phoenix_ecto, "4.7.0"},
  {:phoenix_live_view, "1.2.15"},
  {:live_lift, path: Path.expand("..", __DIR__)}
])

Code.require_file("support/changeset_component.exs", __DIR__)

defmodule ChangesetFixture.Layout do
  use Phoenix.Component

  def root(assigns) do
    ~H"""
    <!doctype html>
    <html lang="en">
      <head>
        <meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()} />
        <script type="module" src="/assets/app.mjs"></script>
      </head>
      <body>{@inner_content}</body>
    </html>
    """
  end
end

defmodule ChangesetFixture.Live do
  use Phoenix.LiveView, layout: false

  def render(assigns) do
    ~H"""
    <main>
      <.live_component
        module={ChangesetParityComponent}
        id="profile"
        data={%{name: nil, code: nil, zone: nil}}
        name=""
        valid={false}
        used={false}
        raw={nil}
        raw_code={nil}
        quiet_errors={[]}
        code_errors={[]}
      />
    </main>
    """
  end
end

defmodule ChangesetFixture.Assets do
  import Plug.Conn

  def init(action), do: action

  def call(conn, :show) do
    asset = Map.get(:persistent_term.get(__MODULE__), conn.path_params["asset"])

    if asset do
      conn |> put_resp_content_type("text/javascript") |> send_resp(200, asset)
    else
      send_resp(conn, 404, "")
    end
  end
end

defmodule ChangesetFixture.Router do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:protect_from_forgery)
    plug(:put_root_layout, html: {ChangesetFixture.Layout, :root})
  end

  scope "/" do
    get("/assets/:asset", ChangesetFixture.Assets, :show)
    pipe_through(:browser)
    live("/", ChangesetFixture.Live)
  end
end

defmodule ChangesetFixture.Endpoint do
  use Phoenix.Endpoint, otp_app: :live_lift

  @session [store: :cookie, key: "_changeset_fixture", signing_salt: "changeset-fixture"]
  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session]])
  plug(Plug.Session, @session)
  plug(ChangesetFixture.Router)
end

app = """
import {Socket} from "./phoenix.mjs";
import {LiveSocket} from "./live-view.mjs";
import {createClientHook} from "./runtime.mjs";
const csrf = document.querySelector("meta[name=csrf-token]").content;
const liveSocket = new LiveSocket("/live", Socket, {
  hooks: {LiveLift: createClientHook({ChangesetParityComponent: () => import("./registry.mjs")})},
  params: {_csrf_token: csrf},
});
liveSocket.connect();
"""

:persistent_term.put(ChangesetFixture.Assets, %{
  "app.mjs" => app,
  "phoenix.mjs" => File.read!(Application.app_dir(:phoenix, "priv/static/phoenix.mjs")),
  "live-view.mjs" =>
    File.read!(Application.app_dir(:phoenix_live_view, "priv/static/phoenix_live_view.esm.js")),
  "runtime.mjs" => File.read!(Path.expand("../assets/js/live_lift/client_hook.js", __DIR__)),
  "registry.mjs" => LiveLift.Client.Compiler.compile_registry([ChangesetParityComponent])
})

Application.put_env(:live_lift, ChangesetFixture.Endpoint,
  server: true,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "127.0.0.1"],
  http: [ip: {127, 0, 0, 1}, port: 0],
  live_view: [signing_salt: "changeset-live"],
  secret_key_base: Base.encode64(:crypto.strong_rand_bytes(48))
)

{:ok, _} = ChangesetFixture.Endpoint.start_link()
{:ok, {{127, 0, 0, 1}, port}} = ChangesetFixture.Endpoint.server_info(:http)
IO.puts("CHANGESET_FIXTURE_URL=http://127.0.0.1:#{port}/")
Process.sleep(:infinity)
