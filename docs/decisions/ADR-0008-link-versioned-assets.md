# ADR 0008 — Link the generated registry to the versioned runtime

Accepted 2026-11-21 for the experimental browser assets.

Apps can keep the runtime copied by Mix, or install the npm artifact for
their asset pipeline. The registry must fail to build with an incompatible
runtime in either route. A runtime assertion would ship extra work in every
app and report the problem after deployment. Comparing package versions
alone would miss two local builds with the same version and different code.

Use a static ESM link named with both the package version and the digest
of the exact version and runtime source. The [spike](../asset-compatibility-spike.md) showed
why this is a re-export: esbuild can drop an unused named import before
checking it. Generate matching TypeScript declarations for the entry
registry and copied runtime. The npm package exposes the same declaration
for its root and existing hook subpath.

Keep the Mix copy as the default to fit the normal Phoenix asset task.
Revisit this decision if the runtime is split across independently shipped
modules or a supported bundler starts dropping the link before validating it.
