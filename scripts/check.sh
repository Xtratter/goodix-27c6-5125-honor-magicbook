#!/usr/bin/env bash
# Read-only health check for the Goodix 27c6:5125 setup (does not change anything).
# Проверка состояния установки (только чтение, ничего не меняет).
#
#   scripts/check.sh            # all checks that need no touch
#   scripts/check.sh --verify   # also run fprintd-verify (touch the reader)

set -u
ok=0; bad=0; warn=0
pass() { printf '  [ OK ] %s\n' "$1"; ok=$((ok + 1)); }
fail() { printf '  [FAIL] %s\n' "$1"; bad=$((bad + 1)); }
note() { printf '  [WARN] %s\n' "$1"; warn=$((warn + 1)); }

echo "== USB / устройство"
if command -v lsusb >/dev/null && lsusb -d 27c6:5125 >/dev/null 2>&1; then
  pass "reader 27c6:5125 is visible on USB"
else
  fail "reader 27c6:5125 not found in lsusb"
fi

echo "== Packages / пакеты"
if command -v pacman >/dev/null; then
  if pkg=$(pacman -Q libfprint-goodix5125-git 2>/dev/null); then
    pass "custom package installed: $pkg"
  else
    fail "libfprint-goodix5125-git is not installed (stock libfprint? see docs/install.md step 2)"
  fi
  if pacman -Q fprintd >/dev/null 2>&1; then
    pass "fprintd installed: $(pacman -Q fprintd)"
  else
    fail "fprintd is not installed"
  fi
  if grep -Eqs '^\s*IgnorePkg\s*=.*\blibfprint\b' /etc/pacman.conf; then
    pass "libfprint is in IgnorePkg (pacman will not replace the custom build)"
  else
    note "libfprint is not in IgnorePkg: a system update may replace the custom package"
  fi
else
  note "pacman not found - package checks skipped"
fi

lib=$(ls /usr/lib/libfprint-2.so.2.* 2>/dev/null | head -1)
if [ -n "$lib" ]; then
  if grep -qa goodix5125 "$lib"; then
    pass "libfprint contains the goodix5125 driver"
  else
    fail "libfprint at $lib has no goodix5125 driver"
  fi
else
  fail "libfprint-2.so not found"
fi

echo "== Pairing key / ключ"
psk=/var/lib/fprint/goodix5125/psk
if [ -r "$psk" ] || { command -v sudo >/dev/null && sudo -n test -f "$psk" 2>/dev/null; }; then
  pass "PSK file exists ($psk) - do NOT delete it"
else
  note "cannot confirm $psk (root-only directory; run: sudo test -f $psk && echo yes)"
fi

echo "== fprintd / отпечатки"
if systemctl cat fprintd.service >/dev/null 2>&1; then
  pass "fprintd.service is present ($(systemctl is-active fprintd 2>/dev/null); starts on demand)"
else
  fail "fprintd.service not found"
fi
if command -v fprintd-list >/dev/null; then
  out=$(fprintd-list "$USER" 2>&1)
  if grep -q 'right-\|left-' <<<"$out"; then
    pass "enrolled fingers: $(grep -o '\(left\|right\)-[a-z-]*' <<<"$out" | sort -u | paste -sd, -)"
  elif grep -qi 'no devices' <<<"$out"; then
    fail "fprintd sees no device: $out"
  else
    note "no enrolled fingers for $USER (run: fprintd-enroll -f right-thumb)"
  fi
fi
if grep -qs 'pam_fprintd.so' /etc/pam.d/sudo; then
  pass "sudo uses pam_fprintd"
else
  note "sudo does not use pam_fprintd (optional, docs/install.md step 5)"
fi
if [ -e /usr/lib/pam.d/kde-fingerprint ]; then
  pass "KDE lock screen has a fingerprint PAM service"
fi

if [ "${1:-}" = "--verify" ]; then
  echo "== fprintd-verify (touch the reader / приложите палец)"
  if timeout 30 fprintd-verify 2>&1 | tee /dev/stderr | grep -q 'verify-match'; then
    pass "fingerprint verified"
  else
    fail "verify did not return verify-match (journalctl -u fprintd --since -5min)"
  fi
fi

echo
echo "Result: $ok ok, $warn warnings, $bad failures"
[ "$bad" -eq 0 ]
