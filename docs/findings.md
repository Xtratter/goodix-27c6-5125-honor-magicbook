**English** | [Русский](findings.ru.md)

# Findings

Everything below comes from observing my own device and the Windows driver's logs. Guesses are
marked as such.

## USB descriptor

`lsusb -v -d 27c6:5125`:

- device class 2 (CDC), subclass 1, protocol 1; Full Speed;
- interface 0: CDC Communications, interrupt IN `0x82` (8 bytes);
- interface 1: CDC Data, bulk OUT `0x01` and bulk IN `0x81` (64 bytes each);
- no kernel driver binds by default (there is no `/dev/ttyACM*`); access goes through libusb.

Class 2 sets it apart from many other Goodix readers, most of which use a vendor-specific
interface.

## Sensor and data

From the Windows driver's debug log (`gfusb.dll` 1.1.125.12, 2021-05-25):

- sensor type 12, frame 64 x 80 pixels, 10240 bytes per frame (so 16 bits per pixel; the
  libfprint driver's author describes the data as 12-bit);
- fingerprint matching runs **on the host** (`AlgoMilan.dll`, `AlgoChicago*.dll`, the log shows
  `CompareTime 15ms`). The reader returns images, not a match result (it is not match-on-chip).

## Transport

In the Windows capture (USBPcap) the reader's traffic goes over bulk endpoints `0x01`/`0x81`.
Frames look like `[type byte][length, 2 bytes LE][data ...]`. Observations:

- type `0xa0` - short command messages and acknowledgements;
- type `0xb0` - TLS transfer: `17 03 03` records (TLS application data) are visible inside, so
  images travel over TLS;
- the driver log shows a TLS handshake in PSK mode; the capture does not contain the handshake
  itself because it started in the middle of a session.

## Pairing key (PSK)

From the Windows driver's log (`production_get_host_psk_data`, `gf_unseal_data`):

1. the driver reads `C:\ProgramData\Goodix\Goodix_Cache.bin` (332 bytes);
2. it unseals the blob with `CryptUnprotectData` (DPAPI): 324 bytes in, a **48-byte entropy**
   (function `generate_entropy2` inside `gfusb.dll`), 32 bytes out - that is the PSK;
3. a "white-box" block is built from the PSK (32 -> 102 bytes), hashed (32 bytes) and compared
   with the hash the reader stores.

`gfusb.dll` imports `CryptUnprotectData` from `CRYPT32.dll`.

I found no published description of how the entropy is computed (searches of the goodix-fp-dump
and libfprint issues and public repositories turned up nothing). The blob cannot be decrypted
without it: the DPAPI master key and the context of the account the driver runs under are also
needed.

## What did not work

- **The all-zero PSK.** On the driver author's unit the Windows driver uses an all-zero key. On
  mine the libfprint driver answered `The Goodix PSK ... does not match the sensor (hash
  differs)`. The reader had been paired with a different key beforehand.
- **Capture with Frida** (`tools/frida_psk.py`): a hook on `CryptUnprotectData` in
  `WUDFHost.exe` caught no calls. The cause was not established (possible: the process was not
  attached, the key was read before the hook was installed, process protection).

## What worked

Writing a new random PSK to the reader with the libfprint driver's own mechanism
(`GOODIX5125_PROVISION_PSK=random`, once). The key is saved to
`/var/lib/fprint/goodix5125/psk` before it is written to the reader.

**Consequences for Windows** (from other people's descriptions, not verified on my laptop): on a
key mismatch the Windows driver will probably re-pair on its own; the fingerprint templates are
stored on the host. Windows Hello may need to be set up again, and Linux will then need to be
re-paired.

## Useful links

- [RuVl/FingerprintDriver_27c6_5125](https://github.com/RuVl/FingerprintDriver_27c6_5125) -
  the driver, the openchicago matching algorithm and tools;
- [libfprint!669](https://gitlab.freedesktop.org/libfprint/libfprint/-/merge_requests/669) -
  the merge request with the driver;
- [goodix-fp-dump](https://github.com/goodix-fp-linux-dev/goodix-fp-dump) - Goodix protocol
  research, issues [#60](https://github.com/goodix-fp-linux-dev/goodix-fp-dump/issues/60),
  [#63](https://github.com/goodix-fp-linux-dev/goodix-fp-dump/issues/63),
  [#80](https://github.com/goodix-fp-linux-dev/goodix-fp-dump/issues/80);
- [Neodyme: reversing a fingerprint reader](https://neodyme.io/en/blog/fingerprint_reversing) -
  a general walkthrough of Goodix TLS-PSK.
