**English** | [Русский](accuracy-patch.ru.md)

# Patches: fewer false rejections and a faster answer

Three small patches to the `goodix5125` libfprint driver
([patches/](../patches/), based on `a9286cc` of the `goodix5125-mr` branch). They are **not part of the
upstream driver**. This page says what each one changes, what was measured and how far the numbers can be
trusted. All measurements are from one unit (HONOR MagicBook BMH-WDX9), one person, one finger.

| # | Patch | Effect |
|---|---|---|
| 1 | retry frames below the engine's quality/coverage limits when matching | a weak frame asks for another touch instead of counting as a mismatch |
| 2 | require 85% coverage for a verification frame | a partial touch is retried instead of being scored 0 |
| 3 | report the match when the touch is decided, not on lift | the answer arrives about 0.15 s after the touch instead of about 1.5 s |

Apply them to the driver sources before building (see [install.md](install.md)):

```sh
cd libfprint-goodix5125
git am ../goodix-27c6-5125-honor-magicbook/patches/*.patch
```

The series applies cleanly to `a9286cc`, builds, and the driver's unit tests pass (10 of 10).

## Patch 1: weak frames are retried, not scored

**Problem.** With the stock driver about half of the touches were rejected. With debug logging on
(`G_MESSAGES_DEBUG=all`) every verification prints `match: score S subtemplate N q=Q c=C -> ...` with the
frame quality `q` and coverage `c`. In a run of 20 touches (right index finger) 14 matched and 6 did not. All six
had a `score` of 0:

| q (quality) | c (coverage) | frame |
|---|---|---|
| 14 | 96 | weak (quality below 25) |
| 24 | 75 | weak (quality below 25) |
| 17 | 56 | weak (quality below 25, coverage below 65) |
| 89 | 58 | partial touch (coverage below 65) |
| 82 | 95 | looks fine, no match found |
| 86 | 81 | looks fine, no match found |

Four of six were below the engine's own minimums (quality 25, coverage 65).

**Cause.** The enrolment path of `openchicago` rejects frames with `coverage < 65` (`OC_REJECT_TOO_SHORT`) or
`quality < 25` (`OC_REJECT_LOW_QUALITY`), so the user is asked to touch again. `oc_identify()` (verification) had no
such check: a weak frame was compared, scored 0 and reported as a mismatch. The Windows driver applies the same
limits when it compares a touch (its log: `min_image_quality 25, min_image_coverage 65`, then a retry, up to 3 frames).

**Change.** Ten lines in `chicago/openchicago.c`: reject such a frame in `oc_identify()` before the comparison. The driver
already turns a rejection into a retry and captures another frame (up to 3 per touch,
`GOODIX5125_VERIFY_CAPTURE_ATTEMPTS`).

## Patch 2: 85% coverage for verification

**Problem.** Frames with coverage 65 to 84 pass the limits of patch 1 but did not match either: among all compared
frames, the 8 with coverage below 90 (56 to 84) all scored 0. The weakest match seen had coverage 91 (quality 66,
score 67), so the margin is narrow.

**Change.** A separate constant `OC_VERIFY_MIN_COVERAGE` (85) used only by verification. Enrolment keeps 65. The value
was first set to 90 and lowered to 85 after the match at coverage 91 showed that 90 left a margin of 1.

**Evidence that it fires.** In one run with the 90 limit, a frame with coverage 78 (quality 29) was rejected and the next
frame of the same touch matched. What the previous driver would have done with that frame was not observed; earlier
frames like it scored 0.

## Patch 3: the answer comes when the touch is decided

**Problem.** The time from the finger being detected to the result reaching fprintd's client was a median of
**1.54 s** (0.65 to 2.66 s, 11 touches). The log showed why: the driver compares the touch within **0.14 s**
(`finger present` at 11:02:31.234, `match: score ...` at 31.374), but it handed the result to libfprint
(`finish_match()`) only after the finger was lifted (`finger_removed()` -> `finish_action()`), so the client waited for
the user to lift the finger.

**Change.** The new `report_match_result()` reports the verify or identify result as soon as the touch is decided.
The action still completes after the lift, so the sensor is not re-armed under a resting finger. The openchicago
state is saved at the same moment, because a client may cancel the action before the lift. The power-button frames
(POV) are tried one after another and keep a deferred report (`match_defer_report`).

**Result.** Median **0.15 s** (0.14 to 0.17 s, 10 results). The driver's unit tests caught a first version that reported
twice in the power-button path (`fpi_device_verify_report: assertion 'data->result_reported == FALSE'`); that is fixed.

**Risks.**
- A client that gets the result stops the verification while the finger is still down. The next open of the sensor then
  refuses to initialize with a finger on it (`Remove the finger before Goodix calibration and try again`). It is an
  error, not corrupted data, and it only matters if something reopens the sensor within a second.
- Not tested on the real device: the power-button unlock mode (only the unit test covers it), the KDE lock screen and
  `sudo` with the new timing.

## Measurements

| Run | Driver | Result |
|---|---|---|
| 1 | stock | 9 of 20 (first enrolled finger, no log) |
| 2 | stock | 14 of 20 (right index finger) |
| 3 | patch 1 | **20 of 20**; scores 29 to 74 (mean 48); 11 weak frames rejected inside the touches |
| 4 | patch 1 | own finger 3 of 3 (scores 53 to 77); another finger 0 of 3 (all scored 0, frames quality 75 to 90, coverage 100) |
| 5 | patches 1+2 (limit 90) | 10 of 10; scores 64 to 100 (mean 79); all frames coverage 100 |
| 6 | patches 1+2 (limit 90), deliberately sloppy touches | 8 of 10; the two misses had coverage 99 and 100 (no match found), one match at coverage 91 |
| 7 | patches 1 to 3 | 10 of 10; scores 32 to 100; answer in 0.15 s (median) |

## How far to trust this

- **One person, one reader, one finger, 10 to 20 touches per run.** The spread of one run is several percentage points; 3
  touches in run 4 only show "own finger passes, another does not" and say nothing about the false-accept rate.
- **The comparison between runs is not controlled.** Touch technique changed and the driver keeps learning the
  template (`template learned, stored`; mean scores rose from 48 to 79). The 20 of 20 cannot be credited to patch 1 alone.
- **Patches 1 and 2 only help when weak frames occur.** In runs 5 and 7 every accepted frame had coverage 100, so the
  coverage limit was not exercised. A touch whose frames are all empty still ends in a retry prompt.
- **More retries in run 7 are unexplained.** There were 9 retry prompts in 4 of 10 touches (run 5: 1 of 10), all caused by
  empty frames (`no-features`), none by coverage. It may be the touches; it may be a side effect of patch 3 (the sensor is
  left before the lift). Not established.
- The initialization of about 0.8 s per opening of the sensor (key check, TLS, base frame) is unchanged; `sudo` pays it on
  every call.
- Security: rejecting a frame cannot cause a false accept, and the early report only changes when the result is
  delivered, not what it is.

## Draft message to the driver author

Not sent. Review and send it yourself if you agree with it.

> Subject: goodix5125: three small changes - retry weak frames when matching, a verification coverage limit, and
> reporting the match when the touch is decided
>
> 1. `oc_identify()` compares any frame that preprocessing accepted, while enrolment rejects `coverage < 65` and
>    `quality < 25`. A weak frame at verification scored 0 and counted as a mismatch (4 of 6 misses on one unit: q=14/24/17,
>    c=56/58). The Windows engine logs `min_image_quality 25, min_image_coverage 65` in its compare step and retries.
>    Patch: reject those frames in `oc_identify()` (10 lines).
> 2. Frames with coverage below 90 never matched on my unit (8 of 8 scored 0, coverage 56 to 84); the weakest match had
>    coverage 91. Patch: `OC_VERIFY_MIN_COVERAGE 85` for verification only; enrolment is unchanged.
> 3. The decision takes ~0.15 s but `fpi_device_verify_report()` was called only after the finger was lifted, so fprintd's
>    client got the result 1.5 s later on average (median 1.54 s, 0.65 to 2.66 s). Patch: report in `match_frame()`; the action
>    still completes after the lift; the power-button frames keep a deferred report. Median is now 0.15 s.
>
> Caveats: one unit, one finger, 10 to 20 touches per run, not a controlled A/B (touch technique and learned templates differ
> between runs). Unit tests pass (10/10). The series applies cleanly to `a9286cc`. I also saw more retry prompts after patch
> 3 (all `no-features`), cause unknown.
