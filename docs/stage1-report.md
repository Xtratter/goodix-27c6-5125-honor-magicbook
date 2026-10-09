**English** | [Русский](stage1-report.ru.md)

# Clean matcher, stage 1 report (M0-M2)

Stage 1 of [the design](superpowers/specs/2026-10-09-goodix5125-clean-matcher-design.md), executed with
[the plan](superpowers/plans/2026-10-09-goodix5125-matcher-stage1.md). Only aggregated numbers are published here; the touch frames are
biometric data and stay on the owner's machine. The lab is a local repository and is not published.

## Verdict

**Candidate B (band-limited phase-only correlation with a multi-patch template) does not reach the current matcher, `openchicago`, if one
impostor touch was the enrolled finger (the evidence points this way); the verdict is open until the owner confirms which finger it was.**

Protocol `varied -> natural-1`, development split, one effective fold, **12 distinct genuine** and **17-21 distinct impostor** touches:

| Matcher | touch excluded: FRR@FAR0 / gap | touch kept: FRR@FAR0 / gap | time per score |
|---|---|---|---|
| `openchicago` (current) | **0.0% / +28** | **100% / -39** | 11 ms |
| SIFT with pairwise checks (approximation of SIGFM) | 25.0% / -2.0 | 25.0% / -2.0 | 3 ms |
| BLPOC, best of 36 tuned candidates | 25.0% / -2.0 | 25.0% / -2.0 | 64 ms |

The doubtful touch (the first touch of the left-index run) scores 54 with `openchicago` against the `varied` template and 71 / 67 against
templates built from other touches, like the enrolled finger, while the other impostors score at most 0. The evidence comes from
`openchicago` itself, so excluding the touch favours it; both readings are shown above with equal weight. No BLPOC candidate has a positive
gap. Counting blank (rejected) genuine frames as failures, FRR is 52% for `openchicago` and 64% for the other two.

## What was built

A Python laboratory (dataset loader, protocols, stable per-touch development/holdout split with a guard, metrics with a bootstrap over distinct
touches, matcher interface, evaluation runner, a ctypes shim over `openchicago` using its public header only, a collection wrapper for the driver
author's collector, the BLPOC prototype, tuning with a record of every candidate, ridge statistics). 108 tests.

## What the data taught

- About half of the quick natural taps contain no finger in any collected frame, as the driver itself sees many blank frames and asks for another
  touch. Natural groups are therefore counted in usable touches; blank frames are retries, not errors.
- The collector reads its frames after the finger-down event; for quick taps only the first frame holds a finger, so the first frame is the default.
- The author's collector connects with an all-zero PSK; this sensor holds a random one, so the wrapper puts the key in at run time (read as root,
  never copied).
- The ridge period is 10.7 px (0.094 cycles/pixel) in every group.

## The final review changed the results

A fresh review found that the first split depended on the group size, so excluding one touch had reshuffled most of the holdout, and that the
tuning criterion (normalised gap) could pick a clearly worse candidate. The split is now a stable hash of each touch's own key and the tuning
selects by FRR, then raw gap. Every number in the first drafts (including "no BLPOC candidate separates the fingers, best FRR 100%") was recomputed:
the best BLPOC candidate reaches 25%. The holdout (5 usable impostor, 4 usable natural-1 and 3 varied touches) was never used for a decision, but
many of its touches belonged to the development split in the drafts and were scored by the baselines; for a clean final test of the next candidate
collect fresh data (and the missing `natural-2` session).

## Limits

One person, one enrolled finger, one sensor, one session of natural touches. 12 genuine probes give an FRR resolution of about 8%; about 20
impostors do not show a FAR below roughly 15%. The `openchicago` session is adaptive and probes were scored in a fixed order. `natural-2` was not
collected. The laptop reset several times on battery right after bursts of all-core load (cause not proven), so the lab limits every computation to
two threads and two cores.

## Decision for the owner

1. **Confirm which finger the doubtful touch was.** It decides whether `openchicago` is 0% or 100% FRR@FAR0 on this set.
2. **Candidate C** (the design's default after a failed M2): local patches or keypoints with a consistent-displacement check, prototyped on the same
   development split and decided on fresh data plus `natural-2`.
3. **Or stop** and keep `openchicago` with the three published patches; the design replaces it because it is a port of the Windows logic, not
   because of its accuracy.
