# Island loading spike

The current registry puts every view and action into the app entry. A
per-view registry can keep the root view and its transitive presentation
components together and expose a manifest of dynamic import functions.
The compiler already walks those dependencies when it builds a registry
and source map.

We built a two-module fixture using the demo's esbuild binary with
`--bundle --format=esm --splitting --chunk-names=chunks/[name]-[hash]`.
The entry contained the dynamic import and excluded the view contents.
After a local `mix phx.digest`, the digested entry still imported the
original content-hashed chunk. The digest output contained that original
and its Phoenix digest counterpart. The root script needs module mode to
use this configuration. [esbuild splitting documentation](https://esbuild.github.io/api/#splitting)

## Integration

Use the same hook import and generated registry as in the ordinary
installation. Add `--split` to `mix live_lift.compile` in both assets
aliases. Set the Phoenix esbuild profile to bundle with `--format=esm`,
`--splitting` and `--chunk-names=chunks/[name]-[hash]` and set the entry
script to `type="module"`. Add `/assets/js/generated_views_views/` to the
app's ignore file. The demo has a working configuration. The compile task
still generates an eager registry without `--split`.

The split registry holds import functions. Each generated module includes
its transitive presentation components and source map. The hook shares a
pending import between instances of the same view, discards a completion
after the island is destroyed, and mounts from the latest snapshot. Native
events during loading still run on LiveView. If the download fails,
LiveLift displays its load error and leaves the native handlers connected.
The interactive preview still needs the view module to display the
updated state.

Run the deployment checks from `bench/`:

```sh
LIVE_LIFT_TEST_DEPLOY=1 npm run e2e -- e2e/island_loading.spec.mjs
```

The tests check zero view downloads on the server-only route, loading
one view after native navigation, a click during a delayed download, and
the error path. In deploy mode they also check that the app entry is
served under its Phoenix digest name.

## Measured results

From the repository root, `python3 bench/island_bundle.py` compares the
same demo and esbuild settings with both registry modes. Eager mode puts
61,600 gzip bytes in the initial JavaScript. Split mode starts with
55,162 bytes and leaves eight view chunks to be requested on demand.
The standalone minified runtime is 8,119 gzip bytes. These byte counts
measure build outputs, and depend on the demo's set of views.
