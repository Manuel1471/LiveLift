# Versioned browser assets

For app developers using LiveLift 0.1.0-rc.1.

LiveLift ships on Hex. The standard installer copies the matching runtime
and its TypeScript declaration from the Mix dependency. It also generates
a typed entry registry. The app's existing `mix assets.build` and
`mix assets.deploy` commands use these files automatically.

## Maintainer test for the local archive

Use this workflow when testing packaging and TypeScript resolution in the
LiveLift repository. The asset manifest is private and packing it creates
a local archive. Its sources must match the installed Hex version.

```sh
(cd /path/to/LiveLift/assets && npm pack)
npm install --prefix assets --save-exact /path/to/LiveLift/assets/live-lift-assets-0.1.0-rc.1.tgz
```

In both `assets.build` and `assets.deploy`, use this generator command before
esbuild.

```sh
mix live_lift.compile --npm-runtime --output assets/js/generated_views.js
```

Use the package in the existing LiveSocket entry point.

```typescript
import {createClientHook} from "live-lift-assets";
import {views} from "./generated_views.js";

const hooks = {...colocatedHooks, LiveLift: createClientHook(views)};
```

Keep the existing colocated hooks import. TypeScript can resolve the
declarations with NodeNext in an ESM directory, or with Bundler module resolution. The compiler
supports `--split` with either runtime. For the copied runtime, import
`createClientHook` from `./live_lift_runtime.js` as before.

A bundler message about a missing `__liveLiftRuntime_` export identifies a
runtime and registry built from different releases or different source
bytes. Use a local artifact that matches Hex, then regenerate and rebuild
the assets. For copied assets, rerun the generator and deploy the rebuilt
assets together.
