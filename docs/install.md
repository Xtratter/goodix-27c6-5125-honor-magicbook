**English** | [Русский](install.ru.md)

# Installing on Arch/Manjaro

Tested on Manjaro (kernel 6.18, KDE Plasma 6.7, fprintd 1.94.5, libfprint 1.94.100) on an HONOR
MagicBook BMH-WDX9. Run the `sudo` commands yourself in a terminal.

**Read the driver code first.** It is installed as a replacement for the system `libfprint` and
runs with root privileges inside fprintd. I read commit `a9286cc` (branch `goodix5125-mr`): it
does not start processes, use the network or write outside `/var/lib/fprint/goodix5125`; writing
the PSK to the reader happens only with `GOODIX5125_PROVISION_PSK=random`.

## 1. Dependencies and build

```sh
sudo pacman -S --needed base-devel git meson libgusb glib2-devel fprintd

git clone https://github.com/RuVl/FingerprintDriver_27c6_5125
git clone --branch goodix5125-mr https://gitlab.freedesktop.org/RuVl/libfprint.git libfprint-goodix5125
# pin to the exact commit that was reviewed and tested
git -C libfprint-goodix5125 checkout -B goodix5125-mr a9286cc

cd FingerprintDriver_27c6_5125/packaging/arch
LIBFPRINT_GOODIX5125_REPO=file://$HOME/libfprint-goodix5125 \
LIBFPRINT_GOODIX5125_BRANCH=goodix5125-mr \
makepkg -C
```

This builds exactly the code you just read, not the latest version of the branch. The result is
a `libfprint-goodix5125-git-*.pkg.tar.zst` file in `packaging/arch/`.

## 2. Install

```sh
sudo pacman -U libfprint-goodix5125-git-*.pkg.tar.zst   # answer "yes" when asked to replace libfprint
sudo systemctl restart fprintd
```

Rollback: `sudo pacman -S libfprint`.

## 3. Pairing key (PSK)

The driver reads the key from `/var/lib/fprint/goodix5125/psk` and compares its hash with the one
the reader stores. Try the all-zero key first (the driver author's Windows driver uses it):

```sh
sudo install -d -m 700 /var/lib/fprint/goodix5125
printf '%064d\n' 0 | sudo install -m 600 /dev/stdin /var/lib/fprint/goodix5125/psk
fprintd-enroll -f right-thumb
```

If enrollment failed with `enroll-unknown-error`, the cause is in the journal:
`journalctl -u fprintd --since -5min --no-pager`. The message `hash differs` means the reader holds
a different key. The reader is not modified in that case.

### Writing a new key (only if the zero key did not match)

This is irreversible and may break pairing with Windows. First **delete the key file**; otherwise
the driver will write the key from that file (all zeros) to the reader:

```sh
sudo rm /var/lib/fprint/goodix5125/psk
sudo systemctl set-environment GOODIX5125_PROVISION_PSK=random
sudo systemctl restart fprintd
fprintd-enroll -f right-thumb      # the first open of the device writes the key
sudo systemctl unset-environment GOODIX5125_PROVISION_PSK
sudo systemctl restart fprintd
```

Afterwards **do not delete** `/var/lib/fprint/goodix5125/psk`: it is the only copy of the key.

## 4. Verify

```sh
fprintd-verify
```

Expected answer: `verify-match`. Enrollment takes about 13 touches: shift your finger slightly
each time, but keep it on the same part of the fingertip.

## 5. Fingerprint for sudo

```sh
sudo cp /etc/pam.d/sudo /etc/pam.d/sudo.bak-before-fprint
```

Then add this as the **first `auth` line** of `/etc/pam.d/sudo`:

```
auth  sufficient  pam_fprintd.so max-tries=3 timeout=15
```

Edit the file with a root shell open in another window. Without a touch `sudo` waits 15 seconds
and falls back to the password. Rollback: `sudo cp /etc/pam.d/sudo.bak-before-fprint /etc/pam.d/sudo`.

## 6. KDE lock screen

Nothing to change: `kscreenlocker` ships `/usr/lib/pam.d/kde-fingerprint` with `pam_fprintd.so`,
and the lock screen uses the fingerprint enrolled in fprintd.

## 7. Fingerprint in KDE password dialogs (polkit)

`/etc/pam.d/polkit-1` does not exist by default (the system one is `/usr/lib/pam.d/polkit-1`). Create it with the same content plus a first line
`auth  sufficient  pam_fprintd.so max-tries=3 timeout=15`, then test with `pkexec true`. Rollback: delete `/etc/pam.d/polkit-1`.
Write the file from a temporary file (`sudo install -m 644 file /etc/pam.d/polkit-1`): an empty PAM file breaks these dialogs.

## Using it on the lock screen (KDE Plasma 6.7)

- **Wake the lock screen first.** The Plasma lock screen starts the fingerprint check only when its interface becomes visible, i.e. after a key
  press, a click or a mouse movement (its `LockScreenUi.qml` calls `authenticator.startAuthenticating()` only on that event). Logs show the
  reader being claimed 8-12 s after the lock, when the user first interacted. A finger placed right after locking is not read.
- **Keep the finger down for about half a second** instead of tapping. A quick tap often gives a blank frame (the finger is gone before the image
  is taken); the driver asks for another touch after three blank frames, which feels like "it does not work".
- The interface hides again after 10 s and the check restarts when it is shown; move the mouse and touch again.

## Optional: accuracy and speed patches

Three small patches to the driver (retry weak frames, a coverage limit, an answer in ~0.15 s instead of ~1.5 s)
are in [`patches/`](../patches/); see [accuracy-patch.md](accuracy-patch.md) for what they change and how far
the measurements can be trusted. Apply them to `libfprint-goodix5125` with `git am` before step 1's `makepkg`.

## Health check

```sh
scripts/check.sh            # read-only checks, no touch needed
scripts/check.sh --verify   # also runs fprintd-verify (touch the reader)
```

It checks that the reader is visible, the custom `libfprint` package and its `goodix5125` driver are
installed, the PSK file exists, a finger is enrolled and PAM is configured. Run it after any system update.

## Updates

The built package is named `libfprint-goodix5125-git` and provides `libfprint`, so a normal
`pacman -Syu` does not install the stock `libfprint` over it. Two things can still break the setup:

- **A new `fprintd` that needs a newer `libfprint` ABI.** `pacman` then reports a dependency error.
  Rebuild the driver on a newer base (repeat steps 1-2 with a newer driver branch) instead of
  forcing the update.
- **Installing the stock package by hand** (`pacman -S libfprint`). Adding `libfprint` to `IgnorePkg`
  in `/etc/pacman.conf` makes `pacman` ask for confirmation first. This is optional: it guards
  against a mistake, not against normal updates.

**Rebuilding after an update.** `scripts/rebuild.sh` clones the two repositories, pins the reviewed driver commit, applies `patches/` and builds the
package in a gentle mode (`nice`, two cores). It installs nothing; it prints the `pacman -U` command. Optional warning after updates: install
`scripts/goodix5125-libfprint-warn.hook` as `/etc/pacman.d/hooks/goodix5125-libfprint-warn.hook` (root); it prints a warning when the custom
driver is no longer the installed `libfprint`.

After any system update run `scripts/check.sh`: it shows whether the driver is still in place.
