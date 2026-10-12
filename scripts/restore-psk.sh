#!/usr/bin/env bash
# Write the Linux pairing key (PSK) back into the sensor after Windows replaced it (dual boot).
# Вернуть ключ Linux в датчик после того, как его заменила Windows (двойная загрузка).
#
#   sudo scripts/restore-psk.sh
#
# Symptom: fprintd logs "Goodix PSK ... does not match the sensor (hash differs)".
# It uses the key already in /var/lib/fprint/goodix5125/psk and never prints it.
# Windows will then stop recognising the sensor until it rewrites its own key.

set -euo pipefail

PSK=/var/lib/fprint/goodix5125/psk
[ "$(id -u)" -eq 0 ] || { echo "run as root: sudo $0" >&2; exit 1; }
[ "$(stat -c %s "$PSK" 2>/dev/null)" = 32 ] || { echo "$PSK is missing or not 32 bytes: restore it from your backup first" >&2; exit 1; }

cleanup() { systemctl unset-environment GOODIX5125_PROVISION_PSK; systemctl restart fprintd; }
trap cleanup EXIT

systemctl set-environment GOODIX5125_PROVISION_PSK=random
systemctl restart fprintd
# any open of the device writes the key; fprintd-list opens it
timeout 20 fprintd-list "${SUDO_USER:-root}" >/dev/null 2>&1 || true
journalctl -u fprintd --since -1min --no-pager | grep -E 'provisioning|does not match' || echo "no provisioning message: check 'journalctl -u fprintd'"
echo "Now run: fprintd-verify (touch the sensor)"
