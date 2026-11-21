# Igniter installation spike

Can a published LiveLift package expose an Igniter installer without making
Igniter an application dependency of LiveLift?

The probe used a Phoenix 1.8.16 project, Igniter 0.8.5, Elixir 1.20.2 and OTP
29. A minimal probe package declared an ordinary Mix task and exported
`supports_umbrella?/0`, `info/2`, `parse_argv/1` and `igniter/1`. The probe
compiled with warnings treated as errors in a Mix project with no
dependencies. In the Phoenix project, `mix igniter.install
lift_installer_probe@path:../probe --yes` called the installer and staged its
asset edit through `Igniter.update_file/3`.

A first LiveLift run exposed how Sourceror represents literal task names.
A string command in an alias list sits inside a literal `__block__` node
carrying comments and source metadata. Reading the literal from that node
and inserting the new step at the esbuild zipper preserved the native
alias structure.

Use the optional task callbacks to compose the installer, and Igniter's
zipper to edit existing literal alias lists. System-specific JavaScript
hook factories and computed Mix aliases stay on the manual integration
path. The probe establishes dispatch and structured edits with the
tested version of Igniter. Public package resolution requires an
actual release.

Upstream references are the [Igniter task callbacks](https://igniter.hexdocs.pm/0.8.4/Igniter.Mix.Task.html)
and [Igniter installer source](https://github.com/ash-project/igniter/blob/main/lib/igniter/util/install.ex).
