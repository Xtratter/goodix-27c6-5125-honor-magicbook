**English** | [Русский](README.ru.md)

# Goodix 27c6:5125 on HONOR MagicBook (BMH-WDX9) under Linux

Notes and tools for getting the **Goodix 27c6:5125** fingerprint reader working on an HONOR
MagicBook (model BMH-WDX9) under Manjaro (KDE Plasma 6, Wayland). The reader worked in Windows,
but Linux did not see it: neither libfprint nor fprintd supported it.

## Result

The reader works: `fprintd-enroll`, `fprintd-verify`, fingerprint `sudo` and KDE lock-screen
unlock were tested on 2026-10-09.

I did not write the driver; the community already has one. This setup uses the `goodix5125`
libfprint driver by [RuVl](https://github.com/RuVl/FingerprintDriver_27c6_5125)
(merge request [libfprint!669](https://gitlab.freedesktop.org/libfprint/libfprint/-/merge_requests/669),
branch `goodix5125-mr`). It was built from source as the package `libfprint-goodix5125-git`,
which replaces the system `libfprint`.

The main difficulty is the pairing key (TLS-PSK) shared by the reader and the host. The
all-zero key from the driver author's instructions did not match, the real key could not be
extracted from Windows, so a new random PSK was written to the reader. Details and the
consequences for dual-boot are in [docs/install.md](docs/install.md) and
[docs/findings.md](docs/findings.md).

## Contents

| Path | What it is |
|---|---|
| [docs/install.md](docs/install.md) | step-by-step install and rollback (Arch/Manjaro) |
| [docs/findings.md](docs/findings.md) | what was learned about the device, the protocol and the Windows driver |
| [docs/accuracy-patch.md](docs/accuracy-patch.md) | three driver patches: retry weak frames, a coverage limit, and a 0.15 s answer instead of ~1.5 s, with measurements |
| [patches/](patches/) | the patch series (`git am`) |
| [scripts/check.sh](scripts/check.sh) | read-only health check of the whole setup (run it after any system update) |
| [tools/usbpcap.py](tools/usbpcap.py) | USBPcap pcap parser that does not need tshark |
| [tools/frida_psk.py](tools/frida_psk.py) | attempt to capture the PSK on Windows (**did not work**) |

## Warnings

- **Never erase or flash the reader's MCU.** According to the driver authors, another 5125 was
  bricked by reflashing.
- Writing a new PSK is irreversible (the old key cannot be read back from the reader) and may
  break the pairing with Windows Hello on the same machine.
- The driver's "unlock by power button" mode skips the touch check for about 3 minutes
  (including for `sudo`). Do not enable it unless you need it.
- Everything was tested on a single unit. Your results may differ.

## What is not published

The Windows Goodix driver files, the `Goodix_Cache.bin` blob, the sensor calibration, USB
captures and Windows logs contain proprietary code or machine-specific data, so they are not in
this repository.

## License

[MIT](LICENSE) - covers the texts and scripts in this repository. The libfprint driver and the
openchicago algorithm linked above are distributed under their own licenses.
