# ADR 0007 — Optional Igniter installation

Accepted 2026-11-21 for the experimental installer.

Phoenix apps using Igniter should be able to install LiveLift with an
Igniter preview and a safe asset edit. Apps using the existing Mix
installer need to continue compiling without another dependency.

A mandatory Igniter dependency would extend the dependency graph of
every consumer. A conditional module compiled when Igniter happens to
be loaded would depend on the order in which sibling dependencies
compile. The [spike](../igniter-install-spike.md) verified a third route.
The existing Mix task defines the task callbacks and resolves optional
tooling when Igniter calls it. Igniter uses its source rewrite plan to
apply the file changes. Existing literal esbuild aliases retain their
commands and comments, and unsupported layouts produce an issue with
manual instructions.

Revisit this decision if the documented task callback interface changes,
or if consumer examples establish demand for a new hook layout or
bundler.
