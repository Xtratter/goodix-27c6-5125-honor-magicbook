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

## Updates

`pacman` may replace the built package with the stock `libfprint`, after which the reader stops
working. In that case repeat step 2, or add `libfprint` to `IgnorePkg` in `/etc/pacman.conf`.
