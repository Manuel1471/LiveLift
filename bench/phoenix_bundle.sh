#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
bench_dir=$(mktemp -d "${TMPDIR:-/tmp}/live_lift_bundle.XXXXXX")
trap 'rm -rf "$bench_dir"' EXIT

mix phx.new "$bench_dir/phoenix_baseline" --module PerfApp --no-ecto --no-dashboard --no-mailer --no-gettext --no-install >/dev/null
cp -R "$bench_dir/phoenix_baseline" "$bench_dir/phoenix_with_lift"

(
  cd "$bench_dir/phoenix_baseline"
  mix deps.get >/dev/null
  mix compile >/dev/null
  mix esbuild phoenix_baseline --minify >/dev/null
)

python3 - "$bench_dir/phoenix_with_lift/mix.exs" "$repo_dir" <<'PY'
from pathlib import Path
import sys
mix_file = Path(sys.argv[1])
source = mix_file.read_text()
source = source.replace('      {:phoenix,', '      {:live_lift, path: "' + sys.argv[2] + '"},\n      {:phoenix,', 1)
mix_file.write_text(source)
PY

mkdir -p "$bench_dir/phoenix_with_lift/lib/perf_app"
cat > "$bench_dir/phoenix_with_lift/lib/perf_app/score_view.ex" <<'EOF'
defmodule PerfApp.ScoreView do
  use LiveLift.Client
  client_template("<button type=\"button\" $click=\"add\">Add</button><output>{@count}</output>")
  defclient(add(state), do: %{state | count: state.count + 1})
end
EOF

(
  cd "$bench_dir/phoenix_with_lift"
  mix deps.get >/dev/null
  mix live_lift.install >/dev/null
  mix live_lift.compile --output assets/js/generated_views.js >/dev/null
  mix esbuild phoenix_baseline --minify >/dev/null
)

for variant in phoenix_baseline phoenix_with_lift; do
  bundle="$bench_dir/$variant/priv/static/assets/js/app.js"
  raw=$(wc -c < "$bundle" | tr -d ' ')
  zipped=$(gzip -c "$bundle" | wc -c | tr -d ' ')
  printf '%s raw=%s gzip=%s\n' "$variant" "$raw" "$zipped"
done
