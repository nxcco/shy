#!/bin/bash
# Points Homebrew at the version just released: the cask in
# github.com/nxcco/homebrew-tap gets this version and the checksums of
# the two disk images on its GitHub release, so that
#
#   brew install --cask nxcco/tap/shy
#
# installs the one for the Mac it runs on, and brew upgrade brings it. Run it
# once the release is on GitHub (tag vX.Y.Z, Shy.dmg for Apple Silicon and
# Shy-Intel.dmg for Intel attached); it reads the version from VERSION.
set -euo pipefail

cd "$(dirname "$0")"
VERSION="$(tr -d '[:space:]' < VERSION)"
BASE="https://github.com/nxcco/shy/releases/download/v$VERSION"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

for DMG in Shy.dmg Shy-Intel.dmg; do
  curl -fsSL -o "$WORK/$DMG" "$BASE/$DMG" \
    || { echo "no $DMG on the v$VERSION release yet — publish the release first" >&2; exit 1; }
done
ARM="$(shasum -a 256 "$WORK/Shy.dmg" | cut -d' ' -f1)"
INTEL="$(shasum -a 256 "$WORK/Shy-Intel.dmg" | cut -d' ' -f1)"

git clone -q https://github.com/nxcco/homebrew-tap.git "$WORK/tap"
CASK="$WORK/tap/Casks/shy.rb"
# Everything above the name — the chip, the version, both checksums and the
# address they fill in — is written afresh; the rest of the cask stays as
# the tap has it.
python3 - "$CASK" "$VERSION" "$ARM" "$INTEL" <<'PY'
import re, sys
path, version, arm, intel = sys.argv[1:]
text = open(path).read()
head = f'''  arch arm: "", intel: "-Intel"

  version "{version}"
  sha256 arm:   "{arm}",
         intel: "{intel}"

  url "https://github.com/nxcco/shy/releases/download/v#{{version}}/Shy#{{arch}}.dmg"
'''
text, found = re.subn(r'(cask "shy" do\n)(.*?)(  name )', lambda m: m.group(1) + head + m.group(3), text, count=1, flags=re.S)
if not found:
    sys.exit("the cask doesn't have the shape tap.sh knows — look at it by hand")
text = text.replace("  depends_on arch: :arm64\n", "")
open(path, "w").write(text)
PY
if git -C "$WORK/tap" diff --quiet; then
  echo "the tap already has Shy $VERSION"
  exit 0
fi
git -C "$WORK/tap" commit -qam "Shy $VERSION"
git -C "$WORK/tap" push -q
echo "tap: Shy $VERSION, sha256 $ARM (Apple Silicon), $INTEL (Intel)"
