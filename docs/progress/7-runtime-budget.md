# Phase 7 — Check the shared runtime size in CI

CI checks the existing 8 KiB budget after installing the demo's pinned
esbuild binary. The Python script minifies the shared `client_hook.js`
as ES2022 ESM, compresses its output at gzip level 9 with a fixed
timestamp, and exits with an error if it exceeds 8,192 bytes. The test
matrix must pass before the Hex publishing job runs.

This measurement uses the shared hook. App code, generated view chunks
and Phoenix bundles have separate measurements in
[`performance-and-adoption.md`](../performance-and-adoption.md).

```sh
cd examples/demo
mix deps.get
mix assets.setup
esbuild=$(mix run --no-start --no-compile -e 'IO.write(Esbuild.bin_path())')
python3 ../../bench/runtime_budget.py "$esbuild"
```

On 2026-11-24, baseline `917a458` measured 8,189 bytes with esbuild
0.25.4 on macOS 26.5.2 (Apple M4) and in a Debian Linux ARM64 container
with Python 3.11.2 and zlib 1.2.13. An oversized copy measured 11,895
bytes and failed the same command. Node 22.15.0's bundled compressor
produced 8,202 bytes for the same minified input. The gate uses the
Python gzip method from the earlier runtime measurements.

The check is configured in GitHub Actions. Hosted execution remains
pending.
