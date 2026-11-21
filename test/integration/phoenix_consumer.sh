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

cp "$repo_dir/test/integration/fixtures/counter_component.ex" \
  "$consumer_dir/consumer_lift/lib/consumer_lift_web/live/counter_component.ex"

cat > "$consumer_dir/consumer_lift/lib/consumer_lift_web/live/mailbox_live.ex" <<'EOF'
defmodule ConsumerLiftWeb.MailboxLive do
  use Phoenix.LiveView
  use LiveLift

  def render(assigns) do
    ~H"""
    <button phx-click="preview">{@label}</button>
    """
  end

  @client true
  def handle_event("preview", _params, socket) do
    Process.send_after(self(), :ready, 50)
    {:noreply, socket}
  end

  def handle_info(:ready, socket) do
    {:noreply, assign(socket, :label, "Prêt 👩‍👩‍👧‍👦")}
  end
end
EOF

python3 - "$consumer_dir/consumer_lift/test" <<'PYTHON'
from pathlib import Path
import json
import sys

directory = Path(sys.argv[1])
counter = "ConsumerLiftWeb.CounterComponent"
mailbox = "ConsumerLiftWeb.MailboxLive"
cases = [
    {"module": counter, "event": "inc", "state": {"count": 9007199254740990, "saved": None}},
    {"module": counter, "event": "preview", "state": {"count": 0, "saved": "Déjà"}},
    {"module": mailbox, "event": "preview", "state": {"label": None}},
]
variants = {
    "live_lift_cases.json": cases,
    "missing_event.json": [case for case in cases if case["module"] != counter or case["event"] != "preview"],
    "missing_module.json": [case for case in cases if case["module"] != mailbox],
}
for name, selected in variants.items():
    (directory / name).write_text(json.dumps(selected), encoding="utf-8")
PYTHON

mkdir -p "$consumer_dir/consumer_lift/test/consumer_lift_web/live"
cat > "$consumer_dir/consumer_lift/test/consumer_lift_web/live/counter_live_test.exs" <<'EOF'
defmodule ConsumerLiftWeb.CounterLiveTest do
  use ConsumerLiftWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  test "saves authoritative server state", %{conn: conn} do
    {:ok, view, html} = live(conn, "/counter")
    baseline? = System.get_env("LIVE_LIFT_MIGRATION_BASELINE") == "1"
    assert String.contains?(html, ~s(phx-hook="LiveLift")) == not baseline?

    assert_state(view, baseline?, 3, "")
    view |> element("#inc") |> render_click()
    assert_state(view, baseline?, 4, "")
    view |> element("#save") |> render_click()
    assert_state(view, baseline?, 4, "Saved 4")
  end

  defp assert_state(view, true, count, saved) do
    assert view |> element("#count") |> render() =~ ">#{count}</output>"
    assert view |> element("#saved") |> render() =~ ">#{saved}</span>"
  end

  defp assert_state(view, false, count, saved) do
    [state] =
      view
      |> element("#counter")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#counter")
      |> LazyHTML.attribute("data-live-lift-state")

    assert Jason.decode!(state) == %{"count" => count, "saved" => saved}
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
  LIVE_LIFT_MIGRATION_BASELINE=1 mix test test/consumer_lift_web/live/counter_live_test.exs
  mix live_lift.audit --path lib/consumer_lift_web/live/counter_component.ex >audit.log
  rg -q 'ConsumerLiftWeb.CounterComponent.handle_event\("inc"\): compatible' audit.log
  rg -q 'ConsumerLiftWeb.CounterComponent.handle_event\("preview"\): compatible' audit.log
  python3 - "$repo_dir/docs/liveview-migration-diff.md" <<'PYTHON'
from pathlib import Path
import subprocess
import sys

guide = Path(sys.argv[1]).read_text()
diff = guide.split('```diff\n', 1)[1].split('```\n', 1)[0]
component = Path("lib/consumer_lift_web/live/counter_component.ex")
before = component.read_text().splitlines()
subprocess.run(["git", "apply", "--check"], input=diff, text=True, check=True)
subprocess.run(["git", "apply"], input=diff, text=True, check=True)
after = component.read_text().splitlines()
assert after.count("  use LiveLift") == 1
assert after.count("  @client true") == 2
assert [line for line in after if line not in ("  use LiveLift", "  @client true")] == before
PYTHON
  mix format --check-formatted
  LIVE_LIFT_MIGRATION_BASELINE=0 mix test test/consumer_lift_web/live/counter_live_test.exs
  printf '%s\n' 'Verified the documented migration diff before and after opt-in.'
  mix live_lift.test --cases test/live_lift_cases.json >parity.log
  rg -q '3 parity cases passed across 2 modules' parity.log
  if mix live_lift.test --cases test/missing_event.json >missing-event.log 2>&1; then
    echo 'Expected parity to fail for a missing marked event' >&2
    exit 1
  fi
  rg -q 'marked events without cases: preview' missing-event.log
  if mix live_lift.test --cases test/missing_module.json >missing-module.log 2>&1; then
    echo 'Expected parity to fail for a missing opted-in module' >&2
    exit 1
  fi
  rg -q 'without parity cases: ConsumerLiftWeb.MailboxLive' missing-module.log
  cat parity.log
  printf '%s\n' 'Verified missing event and missing module failures.'
  mix assets.build
  mix assets.deploy
)
