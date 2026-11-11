#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
consumer_dir=$(mktemp -d "${TMPDIR:-/tmp}/live_lift_consumer.XXXXXX")
trap 'rm -rf "$consumer_dir"' EXIT

mix phx.new "$consumer_dir/consumer_lift" --module ConsumerLift \
  --no-ecto --no-dashboard --no-mailer --no-gettext --no-install >/dev/null

python3 - "$consumer_dir/consumer_lift" "$repo_dir" <<'PY'
from pathlib import Path
import sys

app = Path(sys.argv[1])
repo = sys.argv[2]
mix = app / "mix.exs"
source = mix.read_text()
assert "      {:phoenix," in source
mix.write_text(source.replace("      {:phoenix,", '      {:live_lift, path: "' + repo + '"},\n      {:phoenix,', 1))
router = app / "lib/consumer_lift_web/router.ex"
source = router.read_text()
assert '    get "/", PageController, :home' in source
router.write_text(source.replace('    get "/", PageController, :home', '    get "/", PageController, :home\n    live "/counter", CounterLive'))
PY

mkdir -p "$consumer_dir/consumer_lift/lib/consumer_lift_web/live"
cat > "$consumer_dir/consumer_lift/lib/consumer_lift_web/live/counter_live.ex" <<'EOF'
defmodule ConsumerLiftWeb.CounterLive do
  use ConsumerLiftWeb, :live_view

  def mount(_, _, socket), do: {:ok, assign(socket, count: 3, saved: "")}

  def render(assigns) do
    ~H"""
    <main>
      <.live_component module={ConsumerLiftWeb.CounterComponent} id="counter" count={@count} saved={@saved} />
    </main>
    """
  end
end
EOF

cat > "$consumer_dir/consumer_lift/lib/consumer_lift_web/live/counter_component.ex" <<'EOF'
defmodule ConsumerLiftWeb.CounterComponent do
  use Phoenix.LiveComponent
  use LiveLift

  def render(assigns) do
    ~H"""
    <section>
      <button id="inc" phx-click="inc" phx-target={@myself}>Add</button>
      <button id="save" phx-click="save" phx-target={@myself}>Save</button>
      <output id="count">{@count}</output>
      <span id="saved">{@saved}</span>
    </section>
    """
  end

  @client true
  def handle_event("inc", _params, socket), do: {:noreply, update(socket, :count, &(&1 + 1))}

  def handle_event("save", _params, socket) do
    {:noreply, assign(socket, :saved, "Saved #{socket.assigns.count}")}
  end
end
EOF

mkdir -p "$consumer_dir/consumer_lift/test/consumer_lift_web/live"
cat > "$consumer_dir/consumer_lift/test/consumer_lift_web/live/counter_live_test.exs" <<'EOF'
defmodule ConsumerLiftWeb.CounterLiveTest do
  use ConsumerLiftWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  test "saves authoritative server state", %{conn: conn} do
    {:ok, view, html} = live(conn, "/counter")
    assert html =~ ~s(phx-hook="LiveLift")
    assert view |> element("#count") |> render() =~ ">3</output>"
    view |> element("#save") |> render_click()
    assert view |> element("#counter") |> render() =~ "Saved 3"
  end
end
EOF

cat > "$consumer_dir/consumer_lift/legacy_score.ex" <<'EOF'
defmodule ConsumerLift.LegacyScore do
  use LiveLift.Client
  client_template("<button $server='save'>Save</button>")
  defclient inc(state), do: %{state | count: state.count + 1}
end
EOF

(
  cd "$consumer_dir/consumer_lift"
  mix deps.get >/dev/null
  mix live_lift.install >/dev/null
  if mix live_lift.migrate legacy_score.ex --module ConsumerLiftWeb.LegacyScoreComponent \
      --output lib/consumer_lift_web/live/legacy_score_component.ex >migration.log 2>&1; then
    echo 'Expected the legacy $server migration to stop' >&2
    exit 1
  fi
  rg -q 'sends client state and revision' migration.log
  test ! -e lib/consumer_lift_web/live/legacy_score_component.ex
  mix format
  mix format --check-formatted
  mix test test/consumer_lift_web/live/counter_live_test.exs
  mix live_lift.test ConsumerLiftWeb.CounterComponent --event inc --state '{"count":0,"saved":""}'
  mix assets.build
  mix assets.deploy
)
