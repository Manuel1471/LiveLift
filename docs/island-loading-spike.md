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

The runtime still needs to coordinate a pending import with the hook's
mount, update, disconnect and destroy callbacks. Native controls should
remain usable through LiveView before the import finishes. Initialization
should read the latest server snapshot, and a stale import must not attach
listeners to an island that has already been destroyed. The loader needs
to cache imports shared by multiple islands.

The deployment gate should request a page with no LiveLift islands and
confirm it downloads no view chunks. Visiting a page with one island
should request only that view and its dependencies. Verify a delayed and
a failed request, the first interaction, native navigation, plus
`mix assets.build` and the actual digested deploy output.
