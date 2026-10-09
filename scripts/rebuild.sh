#!/usr/bin/env bash
# Rebuild the libfprint-goodix5125-git package from the pinned commit plus our patches.
# Пересборка пакета libfprint-goodix5125-git: закреплённый коммит + наши патчи.
#
#   scripts/rebuild.sh                 # build only (gentle: nice, 2 cores); prints the install command
#   COMMIT=<sha> scripts/rebuild.sh    # build another driver commit (read its code first!)
#
# It does NOT install anything and does not need root. Installing is your decision:
#   sudo pacman -U <printed .pkg.tar.zst> && sudo systemctl restart fprintd
# The heavy build uses `nice` and `taskset -c 0,1` because the laptop reset under all-core load
# (see docs/tech-debt.md); run it on AC power.

set -euo pipefail

COMMIT=${COMMIT:-a9286cc}                      # reviewed driver commit (branch goodix5125-mr)
WORK=${WORK:-$HOME/src}                        # where the two clones live
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BRANCH=goodix5125-patches

mkdir -p "$WORK"
cd "$WORK"

[ -d FingerprintDriver_27c6_5125 ] || git clone https://github.com/RuVl/FingerprintDriver_27c6_5125
[ -d libfprint-goodix5125 ] || git clone --branch goodix5125-mr https://gitlab.freedesktop.org/RuVl/libfprint.git libfprint-goodix5125

git -C libfprint-goodix5125 fetch -q origin
git -C libfprint-goodix5125 cat-file -e "$COMMIT^{commit}" || { echo "commit $COMMIT not found in the driver repo" >&2; exit 1; }
git -C libfprint-goodix5125 checkout -q -B "$BRANCH" "$COMMIT"

echo "== applying patches from $HERE/patches"
if ! git -C libfprint-goodix5125 -c user.name=build -c user.email=build@localhost am "$HERE"/patches/*.patch; then
  git -C libfprint-goodix5125 am --abort || true
  echo "patches do not apply to $COMMIT: adapt them first (docs/accuracy-patch.md)" >&2
  exit 1
fi

echo "== building (nice, cores 0-1)"
cd FingerprintDriver_27c6_5125/packaging/arch
LIBFPRINT_GOODIX5125_REPO="file://$WORK/libfprint-goodix5125" \
LIBFPRINT_GOODIX5125_BRANCH="$BRANCH" \
  nice -n 19 taskset -c 0,1 makepkg -fC --noconfirm

pkg=$(ls -t "$PWD"/libfprint-goodix5125-git-*.pkg.tar.zst | grep -v debug | head -1)
echo
echo "Built: $pkg"
echo "Install (after reading the diff): sudo pacman -U '$pkg' && sudo systemctl restart fprintd"
echo "Then: $HERE/scripts/check.sh --verify"
