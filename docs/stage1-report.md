**English** | [Русский](stage1-report.ru.md)

# Clean matcher, stage 1 report (M0-M2)

Stage 1 of [the design](superpowers/specs/2026-10-09-goodix5125-clean-matcher-design.md), executed with
[the plan](superpowers/plans/2026-10-09-goodix5125-matcher-stage1.md). Only aggregated numbers are published here; the touch
frames are biometric data and stay on the owner's machine.

## Verdict

**Candidate B (band-limited phase-only correlation with a multi-patch template) fails the success criterion on the
development split.** The holdout was not scored; its one-time lock is kept for the next candidate.

| Matcher (protocol `varied -> natural-1`, development split) | FRR@FAR0 | gap |
|---|---|---|
| `openchicago` (the current matcher) | **0.0%** | **+38** |
| SIFT with pairwise checks (approximation of SIGFM) | 25.0% | -2 |
| BLPOC, first run | 100.0% | -13.9 |
| BLPOC, best of 36 tuned candidates | 100.0% | -14.0 |

`openchicago` separates all 12 usable genuine probes (scores 38-87) from the 25 usable impostors (all <= 0). One impostor
touch had to be excluded (it matched like the enrolled finger, most likely touched by habit); without the exclusion the
figures for `openchicago` are 58.3% / -16. Both versions are reported in the lab repository.

## What was built

A Python laboratory with a dataset loader, protocols, a development/holdout split with a guard, metrics with bootstrap
intervals, a matcher interface, an evaluation runner, a ctypes shim over `openchicago` (public header only), a collection
wrapper for the driver author's collector, and the BLPOC prototype. 92 tests. The lab is a local repository and is not
published.

## What the data taught

- **About half of the quick natural taps contain no finger in any collected frame** (7 of 15 in the first
  run), as the driver itself sees many blank frames and asks for another touch. The plan's "below 10% blank" rule could not hold,
  so natural groups are counted in usable touches.
- The collector reads its frames after the finger-down event; for quick taps only the first frame holds a finger, so the first frame
  is the default.
- The author's collector connects with an all-zero PSK; this sensor holds a random one, so the wrapper patches the key in at run time
  (the key is read as root and never copied).
- The ridge period is 10.7 px (0.094 cycles/pixel), the same in all groups.

## Why B fails

The peak-to-sidelobe ratio for the same finger (22-36) overlaps that for other fingers (10-37). A global phase correlation with a
rotation search does not separate fingers on 64 x 80 pixel touches that overlap only partly; no combination of 3 frequency bands,
2 high-pass widths, 3 novelty limits and 2 overlap limits changed that.

## Limits

One person, one enrolled finger, one sensor. 12 usable genuine probes and about 25 usable impostors per fold; repeats re-use the same
probes, so the intervals are optimistic. The second session (`natural-2`) was not collected because it cannot change a failure of
this size.

## Environment note

The development laptop reset suddenly several times while on battery, always right after a burst of all-core load. The lab therefore limits
OpenCV, OpenMP and BLAS to two threads and runs every command on two cores. The cause is not proven.

## Decision for the owner

1. **Stop.** Keep the existing driver and `openchicago` with the three published patches.
2. **Candidate C**: local patches or keypoints with a consistent-displacement check, prototyped on the same development split; to pass it must
   reach FRR@FAR0 = 0% with a positive gap, which is demanding against `openchicago` on this data.
