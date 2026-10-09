**English** | [Русский](accuracy-patch.ru.md)

# Fewer false rejections: retry weak frames when matching

A small patch to the `goodix5125` libfprint driver
([patch file](../patches/0001-goodix5125-retry-weak-frames-when-matching.patch), based on
`a9286cc` of the `goodix5125-mr` branch). It is **not part of the upstream driver**; this page
describes what it changes, the measurements behind it and how far they can be trusted.

## Problem

With the stock driver about half of the touches were rejected (9 of 20 matched on the first
attempt with the first enrolled finger). With debug logging on (`G_MESSAGES_DEBUG=all`) every
verification prints one line, `match: score S subtemplate N q=Q c=C -> ...`, with the frame
quality `q` and coverage `c`. In a run of 20 touches (right index finger, old driver) 14 matched
and 6 did not. All six failures had a `score` of 0:

| q (quality) | c (coverage) | frame |
|---|---|---|
| 14 | 96 | weak (quality below 25) |
| 24 | 75 | weak (quality below 25) |
| 17 | 56 | weak (quality below 25, coverage below 65) |
| 89 | 58 | partial touch (coverage below 65) |
| 82 | 95 | looks fine, algorithm found no match |
| 86 | 81 | looks fine, algorithm found no match |

Four of six failures were frames below the engine's own minimums (quality 25, coverage 65).
All matching touches had q of 88 or more and c of 98 or more.

## Cause

The enrolment path of `openchicago` rejects frames with `coverage < 65`
(`OC_REJECT_TOO_SHORT`) or `quality < 25` (`OC_REJECT_LOW_QUALITY`), so the user is asked to touch
again. `oc_identify()` (verification) had no such check: a weak frame was compared against the
template, got a score of 0 and was reported as a mismatch. The Windows driver applies the same
limits when it compares a touch: its log shows
`CompareTemplateToCurrentFeatureSet: min_image_quality 25, min_image_coverage 65` followed by a
retry (up to 3 frames).

## Change

Ten lines in `libfprint/drivers/goodix5125/chicago/openchicago.c`: in `oc_identify()`, before the
comparison, reject a frame whose coverage or quality is below the existing constants
`OC_ENGINE_MIN_COVERAGE` and `OC_ENGINE_MIN_QUALITY`. The driver already turns any rejection into a
retry (`FP_DEVICE_RETRY_GENERAL`) and captures another frame (up to 3 per touch,
`GOODIX5125_VERIFY_CAPTURE_ATTEMPTS`). Nothing is written to the reader, the template and the PSK
are not touched, and the matching algorithm itself is unchanged.

Apply and build (see [install.md](install.md) for the full procedure):

```sh
cd libfprint-goodix5125
git am ../goodix-27c6-5125-honor-magicbook/patches/0001-goodix5125-retry-weak-frames-when-matching.patch
```

## Results

| Run | Driver | Result |
|---|---|---|
| 1 | stock | 9 of 20 (first enrolled finger, no log) |
| 2 | stock | 14 of 20 (right index finger) |
| 3 | patched | 7 of 11 valid attempts (4 attempts discarded: the reader was claimed by another process) |
| 4 | patched | **20 of 20**, no retry visible to the user; scores 29 to 74 (mean 48) |

In run 4, 11 frames (weak or without features) were rejected internally and replaced by a better
frame, which is exactly the mechanism of the patch. In run 3, attempts 5 to 8 were partial presses:
frames with coverage 17 to 62 were rejected (one or two retry prompts per attempt), and each attempt
still ended on a frame accepted at a borderline coverage of 67 to 84 that scored 0.

## How far to trust this

- **One person, one reader, one finger, 20 touches per run.** The spread of a single run is several
  percentage points.
- **The comparison is not controlled.** Between runs 2 and 4 the touch technique changed and the driver
  kept learning the template (`template learned, stored`). The 20 of 20 cannot be attributed to the
  patch alone. A fair test swaps the packages with the same finger and the same technique.
- **Not a cure for everything.** A touch whose three frames are all weak or borderline can still fail.
  Matches only ever happened at coverage of about 98 or more; in the Windows log lines I read, matches were at 92 to 99.
  A stricter coverage gate in verification (for example 90) is a possible next step, not tested.
- Security: rejecting a frame cannot cause a false accept. It only turns some mismatches into retries.

## Draft message to the driver author

Not sent. Review and send it yourself if you agree with it.

> Subject: goodix5125: apply the engine's frame thresholds when matching (fewer false rejections)
>
> `oc_identify()` compares any frame that preprocessing accepted. The enrolment path rejects frames
> with `coverage < OC_ENGINE_MIN_COVERAGE (65)` or `quality < OC_ENGINE_MIN_QUALITY (25)`, but a weak
> frame at verification is scored 0 and reported as a mismatch. The Windows driver logs
> `min_image_quality 25, min_image_coverage 65` in its compare step and retries.
>
> The attached 10-line patch rejects such frames in `oc_identify()` so the existing retry path
> (`GOODIX5125_VERIFY_CAPTURE_ATTEMPTS`) re-captures. On one unit (right index finger, 20 touches per
> run): 4 of 6 failures of the unpatched driver were frames below these limits (q=14/24/17, c=56/58).
> The patched driver went 20 of 20 in a clean run, with 11 frames rejected and replaced inside the
> touches. Caveat: my runs are not a controlled A/B (touch technique and learned templates
> differ), one unit, one finger. Unit tests pass (10/10). Applies cleanly to `a9286cc`.
