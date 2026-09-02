#!/usr/bin/env bash
# Build the member app and install it on a paired iPhone, over the network.
#
# WHY THIS EXISTS
# ---------------
# On a free Personal Team, Apple caps the provisioning profile at SEVEN DAYS.
# When it lapses the app simply stops launching — it does not warn, and it
# does not explain. The fix is always the same: build again, install again.
# So rather than making a person remember that, this script makes it one
# command, and a schedule can run it every six days so the app never dies.
#
# It needs NO cable. `devicectl` talks to a paired device over the network.
#
# Usage:
#   scripts/install-to-iphone.sh                 # default device, build + install
#   scripts/install-to-iphone.sh --launch        # also open the app afterwards
#   DEVICE_UDID=<udid> scripts/install-to-iphone.sh
set -euo pipefail

DEVICE_UDID="${DEVICE_UDID:-C8C95660-0D63-50A1-880E-6CA6EE0CC72D}"   # PastorsiPhone
BUNDLE_ID="org.nuruplace.member"
SCHEME="NuruMember"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DD="${DERIVED_DATA:-$ROOT/build/dd-device}"
LAUNCH=0
[ "${1:-}" = "--launch" ] && LAUNCH=1

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }
die() { printf '\n\033[31mSTOPPED: %s\033[0m\n\n' "$*" >&2; exit 1; }

say "1/3  Is the phone reachable?"
STATE="$(xcrun devicectl list devices 2>/dev/null | grep "$DEVICE_UDID" || true)"
[ -n "$STATE" ] || die "That device is not paired with this Mac. Connect it by cable once and trust the prompt; after that it works over the network."
grep -q "available" <<<"$STATE" || die "The phone is paired but not reachable right now. Put it on the same network, unlock it, and try again.
  Seen as: $(awk '{$1=$1};1' <<<"$STATE")"
echo "     ok — $(sed 's/  */ /g' <<<"$STATE" | cut -c1-70)"

say "2/3  Building (signed)…"
if ! xcodebuild -project "$ROOT/NuruMember.xcodeproj" -scheme "$SCHEME" \
      -configuration Release -destination 'generic/platform=iOS' \
      -derivedDataPath "$DD" -allowProvisioningUpdates build \
      > "$DD.log" 2>&1; then
  # The two failures that actually happen, told apart so nobody debugs the wrong one.
  if grep -q "Unable to log in with account" "$DD.log"; then
    die "Xcode's Apple ID session has been rejected — it cannot fetch a provisioning profile.
  FIX: Xcode → Settings → Accounts → select the Apple ID → sign in again. Then re-run this.
  (Full log: $DD.log)"
  fi
  if grep -q "No profiles for" "$DD.log"; then
    die "No provisioning profile for $BUNDLE_ID. Usually the same cause as above — sign in to Xcode, then re-run.
  (Full log: $DD.log)"
  fi
  die "Build failed. Last errors:
$(grep -E 'error:' "$DD.log" | head -5)
  (Full log: $DD.log)"
fi
APP="$DD/Build/Products/Release-iphoneos/$SCHEME.app"
[ -d "$APP" ] || die "Build reported success but produced no .app at $APP"
BUILD_NO="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist" 2>/dev/null || echo '?')"
echo "     ok — build $BUILD_NO"

say "3/3  Installing over the network…"
xcrun devicectl device install app --device "$DEVICE_UDID" "$APP" >/dev/null
echo "     ok — installed"

if [ "$LAUNCH" = "1" ]; then
  xcrun devicectl device process launch --device "$DEVICE_UDID" --terminate-existing "$BUNDLE_ID" >/dev/null
  echo "     ok — launched"
fi

printf '\n\033[32mDone. Build %s is on the phone.\033[0m\n' "$BUILD_NO"
printf 'On a free Personal Team this install is good for 7 days. Re-run to renew.\n\n'
