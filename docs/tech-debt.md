**English** | [Русский](tech-debt.ru.md)

# Technical debt and open questions

Status as of 2026-10-09. Items are ordered by how much they hurt in daily use.

## 1. Sudden laptop resets (HONOR BMH-WDX9)

The laptop reset hard several times while running on battery, always right after a burst of all-core load; the journal ends without any
error, `pstore` is empty, and there are no power-key events. The cause is **not proven**. Evidence so far: four resets (two during a 16-thread
compile, two during trivial work); a telemetry log (`crash-telemetry`, one line every 2 s) shows a load ramp a few seconds before the last one;
runs limited to two cores did not reset. After the laptop was plugged in it ran for more than an hour without a reset (not conclusive).

To do, separately: run for several hours on AC power; start `crash-telemetry` automatically (a user service); check the battery health (about 89%
of the design capacity, 132 cycles) and for a BIOS/EC update (BIOS 1.15 from 2024-01); if resets continue on AC, suspect the hardware.

## 2. The installed driver in daily use

The three patches (retry weak frames, coverage limit 85%, early report) are verified by unit tests and `fprintd-verify` runs, not yet on every
real path (lock screen, `sudo`, resume from sleep): see the result of the live check in the notes below. After the early-report patch the number
of retry prompts rose (all caused by blank frames); an A/B run of two package versions with the same technique would show whether it is the patch.

## 2b. Lock screen starts the fingerprint check late (KDE, not the driver)

Plasma 6.7.4 starts the fingerprint check only when the lock screen interface is shown (key, click or mouse move), 8-12 s after locking in the
logs. Quick taps also give blank frames. Documented in `install.md`. Possible fix, **not done** because it edits the security-critical lock screen
and would be overwritten by updates: a copy of the lock screen theme with one extra `authenticator.startAuthenticating()` call, to be tried first
with `kscreenlocker_greet --testing`. A frame taken after waiting for full finger contact was considered and **rejected on the data**: in the
collected natural taps no touch had a blank first frame and a good later frame.

**Experiment (2026-10-09), result: the lock screen could not be made to start the check by itself.** A user-level copy of the
lock screen (`kscreenlocker_greet --testing --shell local.fptest`, system files untouched) with an extra `authenticator.startAuthenticating()`
call, first at creation and then after 600 ms, did **not** start fprintd until the first touch (lock at 14:25:44, fprintd at 14:25:54; lock at
14:26:54, fprintd at 14:27:15), so the call alone is not enough and the greeter's internals would have to be studied. The copy was removed.
**Likely root cause of the lost first touch:** the sensor is the power button, so the touch itself wakes the lock screen; the check then starts
while the finger still rests on the sensor and the driver's initialization refuses to calibrate with a finger on it (`Finger contact changed during
Goodix calibration; remove the finger`), after which the lock screen restarts the check. Possible driver-side fixes, not done: wait for the finger
to be lifted instead of failing, or reuse a cached no-finger base so that a resting finger is tolerated (both change the recorded device tests).

## 3. Windows pairing

A new random PSK was written to the sensor, so the Windows driver no longer matches the key it stored. Windows Hello may need the finger enrolled
again and Linux may then need re-pairing; not verified. Never delete `/var/lib/fprint/goodix5125/psk` (the old key is unrecoverable).

## 4. Clean-matcher project (stopped after stage 1)

Candidate B (BLPOC) failed against `openchicago`; the project was stopped by decision. To resume: collect new, carefully labelled data (one finger
per run), prototype candidate C, collect the missing `natural-2` session. Open items from the final review (all minor): the exclusion list is not
versioned and a typo in it is silently ignored; the one-time holdout lock is written before the evaluation, has no default path and no hash of the
holdout keys; the shim does not check `malloc`, does not reject `n_frames <= 0` and is not thread-safe; scores of the adaptive `openchicago`
session may depend on the probe order; the collector runs as root with user-writable code (documented); `load_dataset` loads any `*.npz` under its
root.

## 5. Upstream

The message to the driver author (three patches, with the measurements and their limits) is drafted in `accuracy-patch.md` and was **not sent**.

## 6. Small things

- `sudo` waits 15 s for a finger and then falls back to the password when nobody touches the sensor.
- The notes repository had unpublished local commits until it was published (see the git log).
