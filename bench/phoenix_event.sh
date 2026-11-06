#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
bench_dir=$(mktemp -d "${TMPDIR:-/tmp}/live_lift_event.XXXXXX")
trap 'rm -rf "$bench_dir"' EXIT

mix phx.new "$bench_dir/phoenix_baseline" --module PerfApp --no-ecto --no-dashboard --no-mailer --no-gettext --no-install >/dev/null
cp -R "$bench_dir/phoenix_baseline" "$bench_dir/phoenix_with_lift"

python3 - "$bench_dir" "$repo_dir" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
repo = sys.argv[2]
for variant in ("phoenix_baseline", "phoenix_with_lift"):
    app = root / variant
    router = app / "lib/phoenix_baseline_web/router.ex"
    router.write_text(router.read_text().replace('    get "/", PageController, :home', '    get "/", PageController, :home\n    live "/score", ScoreLive'))
    island = '<LiveLift.View.island id="score" module={PerfApp.ScoreView} state={%{count: 1}} />' if variant == "phoenix_with_lift" else ''
    live = app / "lib/phoenix_baseline_web/live/score_live.ex"
    live.parent.mkdir(parents=True, exist_ok=True)
    live.write_text('''defmodule PerfAppWeb.ScoreLive do
  use PerfAppWeb, :live_view
  def mount(_, _, socket), do: {:ok, assign(socket, count: 0)}
  def render(assigns) do
    ~H"""
    <main>
      ''' + island + '''
      <button id="add" phx-click="add">Add</button>
      <output id="count">{@count}</output>
    </main>
    """
  end
  def handle_event("add", _, socket), do: {:noreply, update(socket, :count, &(&1 + 1))}
end
''')
    test = app / "test/phoenix_baseline_web/live/perf_test.exs"
    test.parent.mkdir(parents=True, exist_ok=True)
    test.write_text('''defmodule PerfAppWeb.PerfTest do
  use PerfAppWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  test "server event cost", %{conn: conn} do
    {:ok, view, _} = live(conn, "/score")
    for _ <- 1..20, do: view |> element("#add") |> render_click()
    times = for _ <- 1..200 do
      start = System.monotonic_time(:microsecond)
      view |> element("#add") |> render_click()
      System.monotonic_time(:microsecond) - start
    end |> Enum.sort()
    IO.puts("median_us=" <> Integer.to_string(Enum.at(times, 100)))
    assert view |> element("#count") |> render() =~ ">220</output>"
  end
end
''')

mix = root / "phoenix_with_lift/mix.exs"
mix.write_text(mix.read_text().replace('      {:phoenix,', '      {:live_lift, path: "' + repo + '"},\n      {:phoenix,', 1))
view = root / "phoenix_with_lift/lib/perf_app/score_view.ex"
view.parent.mkdir(parents=True, exist_ok=True)
view.write_text('''defmodule PerfApp.ScoreView do
  use LiveLift.Client
  client_template("<button type=\\"button\\" $click=\\"add\\">Add</button><output>{@count}</output>")
  defclient(add(state), do: %{state | count: state.count + 1})
end
''')
PY

for variant in phoenix_baseline phoenix_with_lift; do
  (
    cd "$bench_dir/$variant"
    mix deps.get >/dev/null
    for run in 1 2 3 4 5; do
      result=$(mix test test/phoenix_baseline_web/live/perf_test.exs --seed 1 | sed -n 's/^median_us=//p')
      printf '%s run=%s median_us=%s\n' "$variant" "$run" "$result"
    done
  )
done
