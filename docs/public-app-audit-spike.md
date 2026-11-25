# Public LiveView application audit spike

## Question

How often does the current LiveLift auditor find a candidate in existing
LiveView web code, and which checks stop it first?

## Method

On 2026-11-25, run the unmodified auditor from LiveLift commit `377e964`
against 12 public repositories with pinned revisions, on macOS arm64 with
Elixir 1.20.2, OTP 29.0.3 and LiveView 1.2.15. The corpus covers scheduling,
analytics, notebooks, content management, media, and infrastructure. It
includes projects of different sizes and favors web source directories
over framework fixtures or test code. The runner fetches source into
temporary directories and executes Mix from LiveLift. Each recorded result
is for a detected `handle_event/3` clause rather than a unique event name.

```sh
mix deps.get
python3 bench/audit_public_apps.py
```

The [manifest](../bench/public_apps.tsv) pins the commits and paths. The
[weekly workflow](../.github/workflows/public-app-audit.yml) reports the same
cohort against the current default branch. Local execution was verified.
The hosted schedule takes effect after the workflow reaches the default branch.

## Result

| Source revision | Audited directory | Candidate clauses | Total clauses |
| --- | --- | ---: | ---: |
| [algora-io/tv @ d7427db](https://github.com/algora-io/tv/tree/d7427db9f117a069a8c21a95696545702a345378/lib/algora_web) | `lib/algora_web` | 0 | 66 |
| [BeaconCMS/beacon @ 2e7b8c2](https://github.com/BeaconCMS/beacon/tree/2e7b8c2a3b1f51b4ed1fa7909b49c07311bb2256/lib/beacon/web) | `lib/beacon/web` | 0 | 3 |
| [BeaconCMS/beacon_live_admin @ c9ac916](https://github.com/BeaconCMS/beacon_live_admin/tree/c9ac916bbb842eef65df53944444a329d120a73a/lib/beacon/live_admin) | `lib/beacon/live_admin` | 0 | 64 |
| [firezone/firezone @ 2e87f15](https://github.com/firezone/firezone/tree/2e87f15f49f1027e4156c2d58ac39a58f8ff5cb1/elixir/lib/portal_web) | `elixir/lib/portal_web` | 0 | 540 |
| [fly-apps/live_beats @ ac97804](https://github.com/fly-apps/live_beats/tree/ac9780472e7019af274110a1cf71250a8d40c986/lib/live_beats_web) | `lib/live_beats_web` | 0 | 10 |
| [kieraneglin/pinchflat @ 67d8bd5](https://github.com/kieraneglin/pinchflat/tree/67d8bd5598f4461c5435bcc66fc8d02b00c607cb/lib/pinchflat_web) | `lib/pinchflat_web` | 0 | 12 |
| [livebook-dev/livebook @ a1cef4e](https://github.com/livebook-dev/livebook/tree/a1cef4e603f71bcd2493928fc52630cabd818cc7/lib/livebook_web) | `lib/livebook_web` | 0 | 239 |
| [papercups-io/papercups @ 6a6f5ad](https://github.com/papercups-io/papercups/tree/6a6f5adc7f0cef5813b2c2f1c0659922defaf976/lib/chat_api_web) | `lib/chat_api_web` | 0 | 0 |
| [pentacent/keila @ 09638db](https://github.com/pentacent/keila/tree/09638db646ea5ff9ad99a2f164b35fe624c7aa1f/lib/keila_web) | `lib/keila_web` | 0 | 43 |
| [plausible/analytics @ 0855e28](https://github.com/plausible/analytics/tree/0855e28671ae1d04d9340dcbbc758e288233738c/lib/plausible_web) | `lib/plausible_web` | 0 | 73 |
| [thechangelog/changelog.com @ 31c4330](https://github.com/thechangelog/changelog.com/tree/31c433019df946a309896a69ddc787d590ef9850/lib/changelog_web) | `lib/changelog_web` | 0 | 0 |
| [Tymeslot/tymeslot @ 6cd1be1](https://github.com/Tymeslot/tymeslot/tree/6cd1be1519165209a874e56dad6d91239709b26e/lib/tymeslot_web) | `lib/tymeslot_web` | 0 | 512 |
| **Total** | | **0** | **1562** |

| First diagnostic per clause | Clauses |
| --- | ---: |
| [E055 — Unsupported marked handler](errors/E055.md) | 1,222 |
| [E060 — Unsupported render or list shape](errors/E060.md) | 302 |
| [E056 — Unsupported handler expression](errors/E056.md) | 16 |
| [E065 — Invalid HEEx syntax](errors/E065.md) | 13 |
| [E062 — Unsupported function component](errors/E062.md) | 4 |
| [E053 — Unsupported native click command](errors/E053.md) | 2 |
| [E061 — Unsupported HEEx binding](errors/E061.md) | 2 |
| [E059 — Unsupported native timer](errors/E059.md) | 1 |

E055 breaks down into 564 handlers without the required simple return
shape, 298 without an admitted socket update, 201 clauses in events with
multiple clauses, and 159 guarded clauses or nonliteral event names.
E060 was reported on 302 clauses without a literal inline `~H` render,
before the auditor reached their handler bodies.

A second run isolated handler compilation. In a temporary copy of the
Mix task, remove the early check for a literal render and omit template
compilation and the timer target validation that relies on that template.
Keep event-name checks, clause checks, timer syntax, helper expansion,
and expression compilation exactly as in the original task. Run that
copy on the same paths. It accepted 33 of the 1,562 clauses at the
handler step, including 27 in Tymeslot, three in Beacon LiveAdmin,
two in Livebook, and one in Algora.

## Limits

These counts describe the auditor's recognized source and its first
diagnostic per clause. The two zero-clause paths contribute no data
to the compatibility ratio. Custom macros and generated callbacks can
escape detection. The handler-only run provides leads for manual
migration experiments. It does not measure DOM parity, runtime behavior,
authorization, or production adoption.

## Decision

Keep the corpus fixed to show how changes in LiveLift affect the
results. Use examples from the 33 handler-only candidates to distinguish
a render-source limitation from a template that genuinely needs server
behavior. Sample the 862 return-shape and socket-update rejections to
identify common pure assign patterns before extending the compiler.
