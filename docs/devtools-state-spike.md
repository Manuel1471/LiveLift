# State inspector spike

For LiveLift contributors working on the experimental development inspector.

Can the inspector capture client predictions and LiveView corrections without
growing the shared hook or shipping the inspector in deployed JavaScript?

The current hook initializes and updates state by assigning to its hook
instance. Phoenix 1.2 copies the user-supplied callbacks into that instance.
The LiveLift `mountView` method runs for both eager and split views. A
development wrapper can install a state accessor after a successful mount and
observe later assignments without patching Phoenix or changing the shared
hook.

A two-module esbuild 0.25.4 fixture verified the mechanism on Node 26.5.0
with the same esbuild binary used by the demo. The entry points at a
CommonJS inspector behind an esbuild define. It invokes a mount and an
action and prints the final count.

| Variant | Observation |
| --- | --- |
| `--define:LIVE_LIFT_INSPECT=true` | Two snapshots and final count 1 |
| `--minify` | Final count 1; the output still contains inspector code |
| `--minify --define:LIVE_LIFT_INSPECT=false` | Final count 1; the inspector marker is absent from the bundle |

The fixture tests property assignment and build-time elimination. Browser
tests cover asynchronous mounting, actual acknowledgments, navigation and
the dialog. The wrapper depends on LiveLift continuing to replace hook state
through that property. Revisit the design if the hook changes that contract.

Use an explicit false define for deployment, a development-only build
option and an optional URL query to start recording. Show historical
snapshots in a separate panel so the running island stays synchronized.
