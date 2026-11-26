#!/bin/sh
set -eu

# Run inside the generated app. Give it an existing hook factory and socket.
python3 - <<'PY'
from pathlib import Path

app = Path("assets/js/app.js")
source = app.read_text()
assert source.count("hooks: {...colocatedHooks}") == 1
assert source.count('new LiveSocket("/live", Socket,') == 1
source = source.replace("hooks: {...colocatedHooks}", "hooks: buildCustomHooks()")
source = source.replace('new LiveSocket("/live", Socket,', 'new LiveSocket("/workbench", Socket,')
source = source.replace("const csrfToken", '''function buildCustomHooks() {
  return {
    ...colocatedHooks,
    ConsumerStatus: {
      mounted() { this.el.dataset.consumerHook = "mounted" }
    }
  }
}

const csrfToken''')
app.write_text(source)

endpoint = Path("lib/consumer_lift_web/endpoint.ex")
source = endpoint.read_text()
assert source.count('socket "/live",') == 1
endpoint.write_text(source.replace('socket "/live",', 'socket "/workbench",'))

view = Path("lib/consumer_lift_web/live/counter_live.ex")
source = view.read_text()
assert source.count("<main>") == 1
view.write_text(source.replace("<main>", '<main><span id="consumer-status" phx-hook="ConsumerStatus"></span>'))
PY

cp assets/js/app.js original-app.js
cp mix.exs original-mix.exs
cp .gitignore original-gitignore
if mix live_lift.install >unsupported-manual.log 2>&1; then
  printf '%s\n' 'Expected the installer to reject the custom hook factory.' >&2
  exit 1
fi
grep -Fq 'unsupported LiveSocket hooks configuration' unsupported-manual.log
cmp original-app.js assets/js/app.js
cmp original-mix.exs mix.exs
cmp original-gitignore .gitignore
test ! -e assets/js/generated_views.js
test ! -e assets/js/live_lift_runtime.js

# Apply the manual integration outlined in the Phoenix guide.
python3 - <<'PY'
from pathlib import Path

app = Path("assets/js/app.js")
imports = '''import {createClientHook} from "./live_lift_runtime.js"
import {views} from "./generated_views.js"

'''
source = app.read_text()
app.write_text(imports + source.replace("hooks: buildCustomHooks()", "hooks: {...buildCustomHooks(), LiveLift: createClientHook(views)}"))

mix = Path("mix.exs")
source = mix.read_text()
for bundler in ['"esbuild consumer_lift"', '"esbuild consumer_lift --minify"']:
    assert source.count(bundler) == 1
    source = source.replace(bundler, '"live_lift.compile --output assets/js/generated_views.js", ' + bundler)
mix.write_text(source)
PY
cat >>.gitignore <<'EOF'

/assets/js/generated_views.js
/assets/js/generated_views.js.map
/assets/js/generated_views.d.ts
/assets/js/live_lift_runtime.js
/assets/js/live_lift_runtime.d.ts
EOF
printf '%s\n' 'Verified the custom hook factory is preserved and configured manually.'
