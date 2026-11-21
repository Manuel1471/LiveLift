"""Compare the demo's eager and split initial JavaScript using the same minifier."""

import gzip
import json
import os
from pathlib import Path
import subprocess
import tempfile

demo = Path(__file__).resolve().parents[1] / "examples" / "demo"
assets = demo / "assets"
esbuild = subprocess.check_output(
    ["mix", "run", "--no-start", "--no-compile", "-e", "IO.puts(Esbuild.bin_path())"],
    cwd=demo,
    text=True,
).strip()
env = {**os.environ, "NODE_PATH": os.pathsep.join(
    str(path) for path in (demo / "deps", demo / "_build" / "dev")
)}


def measure(split):
    with tempfile.TemporaryDirectory(prefix="livelift-size-", dir=assets / "js") as tmp:
        folder = Path(tmp)
        args = ["mix", "live_lift.compile", "--output", str(folder / "generated_views.js")]
        if split:
            args.append("--split")
        subprocess.run(args, cwd=demo, check=True, stdout=subprocess.DEVNULL)
        entry = (assets / "js" / "app.js").read_text()
        (folder / "app.js").write_text(entry.replace('from "../', 'from "../../')
                                      .replace('import "../', 'import "../../'))
        metadata = folder / "meta.json"
        subprocess.run([
            esbuild, str(folder / "app.js"), "--bundle", "--format=esm", "--splitting",
            "--chunk-names=chunks/[name]-[hash]", "--target=es2022", "--minify",
            "--external:/fonts/*", "--external:/images/*", "--alias:@=.",
            f"--outdir={folder / 'out'}", f"--metafile={metadata}",
        ], cwd=assets, env=env, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        outputs = json.loads(metadata.read_text())["outputs"]
        main = next(key for key, info in outputs.items()
                    if key.endswith("/app.js") and info.get("entryPoint"))
        initial = set()

        def collect(path):
            if path in initial:
                return
            initial.add(path)
            for dependency in outputs[path]["imports"]:
                if dependency["kind"] == "import-statement" and not dependency.get("external"):
                    collect(dependency["path"])

        collect(main)

        def size(path):
            return len(gzip.compress((assets / path).read_bytes(), mtime=0))

        return {
            "initial_gzip_bytes": sum(size(path) for path in initial),
            "deferred_js_chunks": sum(key.endswith(".js") and key not in initial for key in outputs),
        }


if __name__ == "__main__":
    print(json.dumps({"eager": measure(False), "split": measure(True)}, indent=2))
