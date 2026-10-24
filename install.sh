#!/bin/bash
# Builds Shy and puts it in /Applications, in place of the one there: the
# way to have it on this Mac, and to bring it up to date, without a
# download, an update feed or anything in the app that fetches one.
#
#   ./install.sh
#
# Signed with "Shy Local", a code-signing certificate of your own in the
# login keychain (build.sh finds it), so each build is the same app to
# macOS: the passwords in the keychain and the camera's and microphone's
# yes stay with it from one build to the next. Without it the build is
# ad-hoc, a new app to macOS every time, and this stops rather than install
# one.
#
# A running Shy is asked to quit first, as ⌘Q would, so its session is
# written; it opens again once the new one is in place.
set -euo pipefail
cd "$(dirname "$0")"

ID="io.github.nxcco.shy"
SIGNER="${SHY_SIGN_IDENTITY:-Shy Local}"
TARGET="/Applications/Shy.app"

./build.sh release

APP="build/Shy.app"
codesign --verify --strict --deep "$APP"
# Signed by that certificate: a certificate of your own names no authority
# macOS knows, so the check is the certificate itself — its hash, which the
# app's designated requirement carries, and which stays the same build after
# build.
want="$(security find-certificate -c "$SIGNER" -Z 2>/dev/null | awk '/SHA-1 hash/ { print tolower($3); exit }')"
[ -n "$want" ] || { echo "no \"$SIGNER\" certificate in the keychain — not installing an ad-hoc build" >&2; exit 1; }
codesign -d -r- "$APP" 2>&1 | grep -q "certificate leaf = H\"$want\"" \
  || { echo "build/Shy.app is not signed by \"$SIGNER\" — not installing" >&2; exit 1; }
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")" = "$ID" ]

# Only ever Shy in its place: something else at that path is left alone.
if [ -e "$TARGET" ]; then
  there="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$TARGET/Contents/Info.plist" 2>/dev/null || true)"
  [ "$there" = "$ID" ] || { echo "$TARGET is not Shy ($there) — not replacing it" >&2; exit 1; }
fi

# Asked to quit, then waited for: never killed, so nothing is lost.
was_running=false
if pgrep -xq Shy; then
  was_running=true
  osascript -e "tell application id \"$ID\" to quit" >/dev/null 2>&1 || true
  for _ in $(seq 1 60); do pgrep -xq Shy || break; sleep 0.5; done
  pgrep -xq Shy && { echo "Shy is still running — quit it and run this again" >&2; exit 1; }
fi

# Copied beside the old one first, then swapped in: never a moment without
# an app at that path, or with half of one.
NEXT="/Applications/.Shy.next.app"
rm -rf "$NEXT"
ditto "$APP" "$NEXT"
codesign --verify --strict --deep "$NEXT"
if [ -e "$TARGET" ]; then
  OLD="/Applications/.Shy.old.app"
  rm -rf "$OLD"
  mv "$TARGET" "$OLD"
  mv "$NEXT" "$TARGET"
  rm -rf "$OLD"
else
  mv "$NEXT" "$TARGET"
fi
echo "installed: $TARGET ($(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$TARGET/Contents/Info.plist"), build $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$TARGET/Contents/Info.plist"))"

$was_running && open "$TARGET"
exit 0
