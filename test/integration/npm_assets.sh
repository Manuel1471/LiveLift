#!/bin/sh
set -eu

# Run from the generated Phoenix project's directory after building the copied runtime.
repo_dir=$1
stage=$2
registry_version=${3:-}
mkdir -p "$stage/repo/assets"
cp -R "$repo_dir/assets/js" "$repo_dir/assets/scripts" "$repo_dir/assets/package.json" "$stage/repo/assets/"
cp "$repo_dir/LICENSE" "$stage/repo/LICENSE"
npm_version=$(node -p 'require(process.argv[1]).version' "$stage/repo/assets/package.json")
tarball="$stage/live-lift-assets-$npm_version.tgz"
package="$tarball"
if [ -n "$registry_version" ]; then
  package="live-lift-assets@$registry_version"
else
  (cd "$stage/repo/assets" && npm pack --pack-destination "$stage" >/dev/null)
fi

cd assets
printf '%s\n' '{"private":true}' >package.json
# Mark the application modules as ESM for NodeNext without changing the vendor directory.
printf '%s\n' '{"type":"module"}' >js/package.json
npm install --ignore-scripts --no-audit --no-fund --no-save "$package" typescript@5.9.3 >/dev/null
cd ..

# The copied runtime and the npm entry must match the same generated registry binding.
cat > assets/js/check_types.mts <<'TYPESCRIPT'
import {createClientHook, type ClientState, type ViewRegistry} from "live-lift-assets";
import {createClientHook as fromSubpath} from "live-lift-assets/client_hook";
import {createClientHook as fromCopy} from "./live_lift_runtime.js";
import {views} from "./generated_views.js";

const registry: ViewRegistry = views;
fromCopy(registry);
fromSubpath(registry);
const hook = createClientHook(registry);
const lifecycle: { mounted(): void | Promise<void>; destroyed(): void } = hook;
const state: ClientState = { title: "test", count: 1, nested: { flags: [true, null] } };
void [lifecycle, state];

// @ts-expect-error A registry entry needs a view or a lazy loader.
createClientHook({ broken: 3 });
// @ts-expect-error Functions cannot be serialized as client state.
const invalid: ClientState = { method() {} };
void invalid;
TYPESCRIPT
assets/node_modules/.bin/tsc --strict --noEmit --module NodeNext   --lib es2022,dom assets/js/check_types.mts

# Preserve the actual Phoenix setup; change both aliases and the runtime import.
python3 - <<'PY'
from pathlib import Path

app = Path("assets/js/app.js")
source = app.read_text()
assert source.count('from "./live_lift_runtime.js"') == 1
app.write_text(source.replace('from "./live_lift_runtime.js"', 'from "live-lift-assets"'))

mix = Path("mix.exs")
source = mix.read_text()
command = "live_lift.compile --output assets/js/generated_views.js"
assert source.count(command) == 2
mix.write_text(source.replace(command, "live_lift.compile --npm-runtime --split --output assets/js/generated_views.js"))
PY
# Remove the copied artifacts so the fresh builds have to resolve the npm package.
rm assets/js/live_lift_runtime.js assets/js/live_lift_runtime.d.ts
mix assets.build
mix assets.deploy
test ! -e assets/js/live_lift_runtime.js
test ! -e assets/js/live_lift_runtime.d.ts
sed '/fromCopy/d' assets/js/check_types.mts > assets/js/check_npm_types.mts
assets/node_modules/.bin/tsc --strict --noEmit --module NodeNext   --lib es2022,dom assets/js/check_npm_types.mts

(
  cd assets
  node --input-type=module <<'NODE'
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {SourceMap} from "node:module";
import {createClientHook} from "live-lift-assets";
import {views} from "./js/generated_views.js";
assert.equal(typeof createClientHook(views).mounted, "function");
const {views: loaded} = await views["ConsumerLiftWeb.CounterComponent"]();
assert.equal(typeof loaded["ConsumerLiftWeb.CounterComponent"].actions.inc, "function");

const chunk = "./js/generated_views_views/ConsumerLiftWeb.CounterComponent.js";
const sourceFile = "lib/consumer_lift_web/live/counter_component.ex";
const javascript = readFileSync(chunk, "utf8");
const source = readFileSync(`../${sourceFile}`, "utf8");
const mapName = /sourceMappingURL=(.+)$/m.exec(javascript)?.[1];
assert.equal(mapName, "ConsumerLiftWeb.CounterComponent.js.map");
const payload = JSON.parse(readFileSync(`${chunk}.map`, "utf8"));
assert.equal(payload.file, "ConsumerLiftWeb.CounterComponent.js");
const viewLine = javascript.split("\n").findIndex((line) =>
  line.includes('"ConsumerLiftWeb.CounterComponent": {actions:'));
assert.ok(viewLine >= 0);
const entry = new SourceMap(payload).findEntry(viewLine, 2);
assert.equal(entry.originalSource, sourceFile);
assert.match(source.split("\n")[entry.originalLine], /^\s*~H"""/);
assert.equal(payload.sourcesContent[payload.sources.indexOf(sourceFile)], source);
NODE
)

rejected_package() {
  artifact=$1
  log=$2
  (
    cd assets
    npm install --ignore-scripts --no-audit --no-fund --no-save "$artifact" >/dev/null
  )
  if mix assets.deploy >"$log" 2>&1; then
    echo "Expected esbuild to reject the mismatched runtime package $artifact" >&2
    exit 1
  fi
  grep -Eq 'No matching export.*__liveLiftRuntime_' "$log"
}

# Same version with different source bytes.
runtime="$stage/repo/assets/js/live_lift/client_hook.js"
cp "$runtime" "$stage/original-runtime.js"
printf '%s\n' '// Different runtime bytes' >>"$runtime"
mkdir "$stage/mismatch"
(cd "$stage/repo/assets" && npm pack --pack-destination "$stage/mismatch" >/dev/null)
rejected_package "$stage/mismatch/$(basename "$tarball")" "$stage/mismatched-runtime.log"

# Same source bytes with a different version. At rc.1 these versions also
# exercise the collision of the human-readable part of the binding name.
cp "$stage/original-runtime.js" "$runtime"
different_version=0.1.0-rc-1
if [ "$npm_version" = "$different_version" ]; then different_version=0.1.0-rc.1; fi
node -e '
  const fs = require("node:fs");
  const [file, version] = process.argv.slice(1);
  const manifest = JSON.parse(fs.readFileSync(file));
  fs.writeFileSync(file, JSON.stringify({...manifest, version}));
' "$stage/repo/assets/package.json" "$different_version"
(cd "$stage/repo/assets" && npm pack --pack-destination "$stage" >/dev/null)
rejected_package "$stage/live-lift-assets-$different_version.tgz" "$stage/mismatched-version.log"
printf '%s\n' 'Verified npm packaging, TypeScript, Phoenix builds, and rejection of incompatible runtime bytes and versions.'
