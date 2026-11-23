# LiveLift, LiveView, and Hologram

LiveLift extends an existing LiveView with selected Elixir interactions in the
browser. Add `use LiveLift` to a routed LiveView or stateful LiveComponent and
mark a supported handler. Keep your app's HEEx, event names, and server logic.

| Aspect | Phoenix LiveView | LiveView with LiveLift | Hologram |
| --- | --- | --- | --- |
| Where UI state lives | Server assigns drive the LiveView. JS commands and hooks can maintain browser state. | LiveView owns shared state. Opted-in islands may have transient browser assigns. | Pages and components maintain UI state in the browser after initial server rendering. |
| Local Elixir | App handlers ordinarily run on the server. | `@client :local` runs a supported handler in the browser without a LiveView event after mount. | Actions implement browser behavior and can trigger server commands. |
| Server work | Ordinary `handle_event/3` and LiveView lifecycle callbacks. | Unmarked handlers stay on LiveView. `@client true` predicts locally and confirms through LiveView. | Commands handle server work and may trigger browser actions. |
| Adoption | Use Phoenix LiveView to build the page. | Opt in a compatible region and run the LiveLift asset compiler. | Build pages and components using Hologram's application model on Phoenix. |

See Hologram's [introduction](https://hologram.page/docs/introduction),
[architecture](https://hologram.page/docs/architecture),
[actions](https://hologram.page/docs/actions), and
[commands](https://hologram.page/docs/commands).

## What changes in an existing app

A list can reverse its preview with `@client :local`, update a shared count
with `@client true`, and persist a selected row with an unmarked handler.
Phoenix still serves the initial HTML, handles navigation and receives the
app's explicit server events. The browser owns the DOM inside the island
boundary and discards transient local edits on a full remount.
See the [native guide](native-livecomponent.md#local-actions).

LiveLift adds generated JavaScript and limits which HEEx and Elixir forms can
run in the browser. Check the [language reference](language.md) before opting
in a region. [Production limits](production-readiness.md) explain source-map
granularity and what the published benchmarks measure. Compare the same app
workload before drawing conclusions about overall performance.
