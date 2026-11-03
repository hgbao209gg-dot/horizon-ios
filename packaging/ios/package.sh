#!/usr/bin/env bash
# Packages the iOS client: Payload/Horizon.app (the binary, Info.plist, the icons), then the
# unsigned Horizon.ipa a signing service re-signs for the phone. iOS takes a plain zip of a
# Payload folder, not a macOS .app laid out inside one.
#
#   packaging/ios/package.sh BINARY VERSION OUTDIR
#
# Needs macOS (sips, plutil, ditto, lipo). Unsigned by default: an iOS app only runs when a
# provisioning profile authorizes it, and the profile has to name the device, so the signature
# comes last, outside this script. With IOS_SIGN_IDENTITY and IOS_PROVISION_PROFILE set, the app
# is signed with that identity and the profile is embedded as embedded.mobileprovision, which
# needs the profile's App ID to match CFBundleIdentifier (dev.horizon.ios) and the device's UDID
# in its list.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
binary=$1
version=$2
out=$(mkdir -p "$3" && cd "$3" && pwd)
[[ "$(lipo -archs "$binary")" == arm64 ]] || { echo "$binary is $(lipo -archs "$binary"), not arm64" >&2; exit 1; }

staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
app=$staging/Payload/Horizon.app
mkdir -p "$app"
cp "$binary" "$app/horizon-client"
chmod 755 "$app/horizon-client"
sed "s/@VERSION@/$version/g" "$here/Info.plist" > "$app/Info.plist"
printf 'APPL????' > "$app/PkgInfo"
plutil -lint "$app/Info.plist"

# The Files' icons, at the two sizes iOS asks for by name; the source is the 512px Linux icon.
src=$here/../icons/hicolor/512x512/apps/horizon.png
sips -Z 120 -s format png "$src" --out "$app/AppIcon60x60@2x.png" >/dev/null
sips -Z 180 -s format png "$src" --out "$app/AppIcon60x60@3x.png" >/dev/null
sips -Z 76 -s format png "$src" --out "$app/AppIcon76x76@1x.png" >/dev/null
sips -Z 152 -s format png "$src" --out "$app/AppIcon76x76@2x.png" >/dev/null

if [[ -n "${IOS_SIGN_IDENTITY:-}" ]]; then
  profile=${IOS_PROVISION_PROFILE:?IOS_SIGN_IDENTITY needs IOS_PROVISION_PROFILE pointing at a .mobileprovision}
  cp "$profile" "$app/embedded.mobileprovision"
  codesign --force --timestamp --sign "$IOS_SIGN_IDENTITY" "$app"
  codesign --verify --strict --verbose=2 "$app"
fi

rm -f "$out/Horizon.ipa"
# No resource forks or extended attributes: they would land as ._ files inside the bundle.
(cd "$staging" && ditto -c -k --noscancrk --norsrc --noextattr --noqtn Payload "$out/Horizon.ipa")
unzip -l "$out/Horizon.ipa" | grep -q 'Payload/Horizon.app/Info.plist'
if [[ -n "${IOS_SIGN_IDENTITY:-}" ]]; then
  echo "Packaged $out/Horizon.ipa, signed: installs on the devices in the profile"
else
  echo "Packaged $out/Horizon.ipa, unsigned: sign it (Xcode, or a re-signing service) before it runs"
fi
