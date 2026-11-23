#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
consumer_dir=$(mktemp -d "${TMPDIR:-/tmp}/live_lift_consumer.XXXXXX")
trap 'rm -rf "$consumer_dir"' EXIT

mix phx.new "$consumer_dir/consumer_lift" --module ConsumerLift \
  --no-ecto --no-dashboard --no-mailer --no-gettext --no-install >/dev/null

live_lift_dep="$repo_dir"
igniter_mode="${LIVE_LIFT_INTEGRATION_IGNITER:-0}"
registry_version="${LIVE_LIFT_REGISTRY_VERSION:-}"
if [ -n "$registry_version" ]; then
  igniter_mode=0
elif [ "$igniter_mode" = "1" ]; then
  live_lift_dep="$consumer_dir/live_lift_package"
  (cd "$repo_dir" && mix hex.build --unpack --output "$live_lift_dep" >/dev/null)
fi

python3 - "$consumer_dir/consumer_lift" "$live_lift_dep" "$igniter_mode" "$registry_version" <<'PY'
from pathlib import Path
import json
import re
import sys

app = Path(sys.argv[1])
dependency_path = sys.argv[2]
igniter = sys.argv[3] == "1"
version = sys.argv[4]
mix = app / "mix.exs"
source = mix.read_text()
assert "      {:phoenix," in source
options = ", override: true" if igniter else ""
if version:
    assert re.fullmatch(r"[0-9A-Za-z.+-]+", version)
    dependency = f'      {{:live_lift, {json.dumps("== " + version)}}},\n'
else:
    dependency = f'      {{:live_lift, path: {json.dumps(dependency_path)}{options}}},\n'
if igniter:
    dependency += '      {:igniter, "== 0.8.5", only: :dev, runtime: false},\n'
    source, changed = re.subn(
        r'("assets.build": )\["compile", ([^\]\n]+)\],',
        r'\1[\n        "compile",\n        # Keep the app-owned build step.\n'
        r'        "deps.loadpaths",\n        \2\n      ],',
        source,
    )
    assert changed == 1
mix.write_text(source.replace("      {:phoenix,", dependency + "      {:phoenix,", 1))
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
    <button phx-click="toggle_preview">Preview</button>
    <span :if={@preview_visible}>Local</span>
    """
  end

  @client true
  def handle_event("preview", _params, socket) do
    Process.send_after(self(), :ready, 50)
    {:noreply, socket}
  end

  @client :local
  def handle_event("toggle_preview", _params, socket) do
    {:noreply, update(socket, :preview_visible, &(&1 == false))}
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
    {"module": mailbox, "event": "preview", "state": {"label": None, "preview_visible": False}},
    {"module": mailbox, "event": "toggle_preview", "state": {"label": None, "preview_visible": False}},
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

  if [ "$igniter_mode" = "1" ]; then
    cp assets/js/app.js original-app.js
    cp mix.exs original-mix.exs
    cp .gitignore original-gitignore
    install_spec="live_lift@path:$live_lift_dep"
    mix igniter.install "$install_spec" --dry-run --yes >igniter-preview.log
    grep -Fq 'live_lift.install' igniter-preview.log
    mix run --no-start -e '
      Application.ensure_all_started(:rewrite)

      Igniter.new()
      |> Mix.Tasks.LiveLift.Install.igniter()
      |> Igniter.do_or_dry_run(dry_run: true, yes: false)
    ' >igniter-diff.log
    grep -Fq 'assets/js/app.js' igniter-diff.log
    grep -Fq 'live_lift_runtime.js' igniter-diff.log
    cmp original-app.js assets/js/app.js
    cmp original-mix.exs mix.exs
    cmp original-gitignore .gitignore

    mix igniter.install "$install_spec" --yes
    cp assets/js/app.js installed-app.js
    cp mix.exs installed-mix.exs
    cp .gitignore installed-gitignore
    mix igniter.install "$install_spec" --yes
    cmp installed-app.js assets/js/app.js
    cmp installed-mix.exs mix.exs
    cmp installed-gitignore .gitignore
    python3 - <<'PYTHON'
from pathlib import Path

mix = Path("mix.exs").read_text()
assert mix.count('live_lift.compile --output assets/js/generated_views.js') == 2
assert mix.count("# Keep the app-owned build step.") == 1
assert mix.index('"deps.loadpaths"') < mix.index('"live_lift.compile')
assert '"esbuild consumer_lift"' in mix
assert '"phx.digest"' in mix
PYTHON

    cp original-mix.exs mix.exs
    cp original-gitignore .gitignore
    python3 - <<'PYTHON'
from pathlib import Path

app = Path("assets/js/app.js")
app.write_text(Path("original-app.js").read_text().replace("hooks: {...colocatedHooks}", "hooks: buildCustomHooks()"))
PYTHON
    cp assets/js/app.js unsupported-app.js
    mix igniter.install "$install_spec" --yes >unsupported-igniter.log 2>&1
    grep -Fq 'unsupported LiveSocket hooks configuration' unsupported-igniter.log
    cmp unsupported-app.js assets/js/app.js
    cmp original-mix.exs mix.exs
    cmp original-gitignore .gitignore
    cp original-app.js assets/js/app.js
    python3 - <<'PYTHON'
from pathlib import Path

mix = Path("mix.exs")
mix.write_text(mix.read_text().replace("esbuild consumer_lift --minify", "custom.assets"))
PYTHON
    cp mix.exs unsupported-mix.exs
    mix igniter.install "$install_spec" --yes >unsupported-alias.log 2>&1
    grep -Fq 'unsupported assets.deploy alias' unsupported-alias.log
    if mix igniter.install "$install_spec" --check --yes >unsupported-check.log 2>&1; then
      echo 'Expected Igniter --check to report the custom alias as an issue' >&2
      exit 1
    fi
    grep -Fq 'unsupported assets.deploy alias' unsupported-check.log
    cmp original-app.js assets/js/app.js
    cmp unsupported-mix.exs mix.exs
    cmp original-gitignore .gitignore
    cp installed-app.js assets/js/app.js
    cp installed-mix.exs mix.exs
    cp installed-gitignore .gitignore

    mix live_lift.install >/dev/null
    cmp installed-app.js assets/js/app.js
    cmp installed-mix.exs mix.exs
    cmp installed-gitignore .gitignore
    printf '%s\n' 'Verified Igniter preview, idempotence, custom steps, and unsupported layouts using an unpacked Hex package.'
  else
    mix live_lift.install >/dev/null
  fi
  if mix live_lift.migrate legacy_score.ex --module ConsumerLiftWeb.LegacyScoreComponent \
      --output lib/consumer_lift_web/live/legacy_score_component.ex >migration.log 2>&1; then
    echo 'Expected the legacy $server migration to stop' >&2
    exit 1
  fi
  grep -Fq 'sends client state and revision' migration.log
  test ! -e lib/consumer_lift_web/live/legacy_score_component.ex
  mix format
  mix format --check-formatted
  LIVE_LIFT_MIGRATION_BASELINE=1 mix test test/consumer_lift_web/live/counter_live_test.exs
  mix live_lift.audit --path lib/consumer_lift_web/live/counter_component.ex >audit.log
  grep -Fq 'ConsumerLiftWeb.CounterComponent.handle_event("inc"): compatible' audit.log
  grep -Fq 'ConsumerLiftWeb.CounterComponent.handle_event("preview"): compatible' audit.log
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
  grep -Fq '4 parity cases passed across 2 modules' parity.log
  if mix live_lift.test --cases test/missing_event.json >missing-event.log 2>&1; then
    echo 'Expected parity to fail for a missing marked event' >&2
    exit 1
  fi
  grep -Fq 'marked events without cases: preview' missing-event.log
  if mix live_lift.test --cases test/missing_module.json >missing-module.log 2>&1; then
    echo 'Expected parity to fail for a missing opted-in module' >&2
    exit 1
  fi
  grep -Fq 'without parity cases: ConsumerLiftWeb.MailboxLive' missing-module.log
  cat parity.log
  printf '%s\n' 'Verified missing event and missing module failures.'
  cat > unsupported_clock.ex <<'EOF'
defmodule ConsumerLiftWeb.UnsupportedClock do
  use Phoenix.LiveComponent

  def render(assigns), do: ~H"<output>{@count}</output>"

  def handle_event("load", _params, socket) do
    {:noreply, assign(socket, :count, System.monotonic_time())}
  end
end
EOF
  mix live_lift.audit --path unsupported_clock.ex >unsupported-audit.log
  grep -Fq 'unsupported_clock.ex:6: unsupported @client handler: unsupported client expression: System.monotonic_time() (E056)' unsupported-audit.log
  grep -Eq 'remove the @client marker.*docs/errors/E056\.md' unsupported-audit.log
  python3 - <<'PYTHON'
from pathlib import Path

source = Path("unsupported_clock.ex").read_text()
source = source.replace("  use Phoenix.LiveComponent", "  use Phoenix.LiveComponent\n  use LiveLift")
source = source.replace('  def handle_event("load"', '  @client true\n  def handle_event("load"')
Path("lib/consumer_lift_web/live/unsupported_clock.ex").write_text(source)
PYTHON
  if mix compile >unsupported-compile.log 2>&1; then
    echo 'Expected an unsupported marked event to fail compilation' >&2
    exit 1
  fi
  grep -Fq 'unsupported_clock.ex:8: unsupported @client handler: unsupported client expression: System.monotonic_time() (E056)' unsupported-compile.log
  grep -Eq 'remove the @client marker.*docs/errors/E056\.md' unsupported-compile.log
  rm lib/consumer_lift_web/live/unsupported_clock.ex
  printf '%s\n' 'Verified the same actionable diagnostic in audit and compilation.'
  mix assets.build
  grep -Fq "function __liveLiftLocalActions" assets/js/generated_views.js
  mix assets.deploy
  if [ "$igniter_mode" = "1" ] || [ -n "$registry_version" ]; then
    sh "$repo_dir/test/integration/npm_assets.sh" "$repo_dir" "$consumer_dir/npm_assets" "$registry_version"
  fi
)
