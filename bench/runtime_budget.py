import argparse
import gzip
from pathlib import Path
import subprocess


BUDGET_BYTES = 8 * 1024
ROOT = Path(__file__).resolve().parents[1]
RUNTIME = "assets/js/live_lift/client_hook.js"


def main():
    parser = argparse.ArgumentParser(description="Measure the shared LiveLift runtime.")
    parser.add_argument("esbuild", nargs="?", default="esbuild", help="esbuild executable")
    args = parser.parse_args()

    runtime = subprocess.run(
        [args.esbuild, RUNTIME, "--minify", "--target=es2022", "--format=esm"],
        cwd=ROOT,
        check=True,
        stdout=subprocess.PIPE,
    ).stdout
    size = len(gzip.compress(runtime, compresslevel=9, mtime=0))
    measurement = f"Shared LiveLift runtime: {size:,} of {BUDGET_BYTES:,} gzip bytes"

    if size > BUDGET_BYTES:
        raise SystemExit(f"{measurement} (over budget)")

    print(measurement)


if __name__ == "__main__":
    main()
