# Versioned browser assets

For app developers using LiveLift 0.1.0-rc.1.

The standard installer copies the matching runtime and its TypeScript
declaration. It also generates a typed entry registry. Existing Phoenix
build and deploy commands use these files automatically.

## Use the npm runtime

Use the npm artifact when your Phoenix assets already use npm. Install the
version matching your Hex dependency after both packages are published.

```sh
npm install --prefix assets --save-exact live-lift-assets@0.1.0-rc.1
```

For a local package, substitute its `.tgz` file for the registry package
reference. Create one with `npm pack` in the repository's `assets/` directory.
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
bytes. Install the npm version that matches Hex, then regenerate and rebuild
the assets. For copied assets, rerun the generator and deploy the rebuilt
assets together.
