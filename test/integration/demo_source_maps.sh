#!/bin/sh
set -eu

# Run from examples/demo after installing the dependencies and esbuild.
mix assets.build
test -s priv/static/assets/js/app.js.map
node --input-type=module <<'NODE'
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {SourceMap} from "node:module";

const assets = "priv/static/assets/js";
const app = readFileSync(`${assets}/app.js`, "utf8");
const chunk = /import\("\.\/(chunks\/LiveLiftDemoWeb\.NativeCounterComponent-[^"]+\.js)"\)/.exec(app)?.[1];
assert.ok(chunk, "missing generated counter chunk");
const generated = readFileSync(`${assets}/${chunk}`, "utf8").split("\n");
const payload = JSON.parse(readFileSync(`${assets}/${chunk}.map`, "utf8"));
const line = generated.findIndex((text) => text.includes("inc: (state) =>"));
assert.ok(line >= 0, "missing generated inc action");
const entry = new SourceMap(payload).findEntry(line, generated[line].indexOf("inc: (state) =>"));
assert.match(entry.originalSource, /\/native_counter_component\.ex$/);
const source = payload.sourcesContent[payload.sources.indexOf(entry.originalSource)];
assert.match(source.split("\n")[entry.originalLine], /def handle_event\("inc"/);
console.log("Verified that the esbuild development chunk maps inc to its Elixir handler.");
NODE
mix esbuild live_lift_demo --sourcemap=inline --define:LIVE_LIFT_INSPECT=true
mix phx.digest

check_maps() {
  python3 - "$1" <<'PY'
import gzip
import json
from pathlib import Path
import sys

stage = sys.argv[1]
static = Path("priv/static")
output = static / "assets/js"
manifest = json.loads((static / "cache_manifest.json").read_text())
suffixes = (".map", ".map.gz", ".map.br")
files = [path for path in output.rglob("*") if path.name.endswith(suffixes)]
entries = [
    path
    for field in ("latest", "digests")
    for path in manifest[field]
    if path.startswith("assets/js/") and path.endswith(suffixes)
]
inline = [
    path
    for path in output.rglob("*")
    if path.suffix in (".js", ".css") and b"sourceMappingURL=data:" in path.read_bytes()
]
compressed_inline = [
    path
    for path in output.rglob("*.gz")
    if path.name.endswith((".js.gz", ".css.gz"))
    and b"sourceMappingURL=data:" in gzip.decompress(path.read_bytes())
]

if stage == "before":
    assert "assets/js/app.js.map" in entries
    assert any(path.name.endswith(".map.gz") for path in files)
    assert inline and compressed_inline
else:
    assert not files, files
    assert not entries, entries
    assert not inline, inline
    assert not compressed_inline, compressed_inline
    for entry in ("assets/js/app.js", "robots.txt"):
        assert (static / manifest["latest"][entry]).is_file()
    assert any(Path("assets/js/generated_views_views").glob("*.js.map"))
    print("Verified that deployment removes public maps and keeps private compiler maps.")
PY
}

check_maps before
mix assets.deploy
check_maps after
