#!/usr/bin/env bash
# Local IPA build — mirror of .github/workflows/main.yml. Produces an IPA
# you can sign with Sideloadly/AltStore/TrollStore.
#
# Pipeline:
#   1. Build LyssnaProtobuf.framework from apple/swift-protobuf source
#      (renamed module — see Tools/SwiftProtobufBuild/).
#   2. theos `make package FINALPACKAGE=1` — produces .deb with
#      Lyssna.dylib + Lyssna.bundle + framework.
#   3. Build zxPluginsInject.dylib — sideload compat shim (keychain redirect,
#      group containers, CloudKit stub). LC-injected via ipapatch in step 6.
#   4. cyan inject deb-contents (dylib + framework + bundle) into vanilla IPA.
#   5. ipapatch LC-inject zxPluginsInject into main exec + every appex.
#   6. Strip Watch.app if it survived cyan -du.
#      Include OpenSpotifySafariExtension, matching the patched workflow.
#
# Requires: theos, cyan (pyzule-rw), ipapatch, dpkg, ldid, plutil.
# LYSSNA_MINIMAL_IPA=1 omits optional extensions for single-App-ID signing.
# LYSSNA_IPA_OUTPUT overrides the final output path.

set -euo pipefail

VANILLA_IPA="${1:-}"
[ -n "$VANILLA_IPA" ] && [ -f "$VANILLA_IPA" ] || {
    echo "usage: $0 <path/to/Spotify-vanilla.ipa>" >&2
    exit 1
}

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

[ -n "${THEOS:-}" ] || { [ -d "$HOME/theos" ] && export THEOS="$HOME/theos" || { echo "THEOS not set"; exit 1; }; }

VERSION=$(grep -E '^Version:' control | awk '{print $2}')
SPOT_VERSION=$(unzip -p "$VANILLA_IPA" 'Payload/Spotify.app/Info.plist' \
    | plutil -extract CFBundleShortVersionString raw - 2>/dev/null || echo "unknown")
PUBLISH_IPA="${LYSSNA_IPA_OUTPUT:-${EEVEE_IPA_OUTPUT:-$HOME/Library/Mobile Documents/com~apple~CloudDocs/iOS IPAs/Lyssna-${VERSION}-${SPOT_VERSION}.ipa}}"
[[ "$PUBLISH_IPA" == /* ]] || PUBLISH_IPA="$REPO_DIR/$PUBLISH_IPA"
OUT_DIR=$(mktemp -d)
OUT_IPA="$OUT_DIR/Lyssna-${VERSION}-${SPOT_VERSION}.ipa"
EXT_DIR=""
PUBLISH_TEMP=""
trap 'rm -rf "$OUT_DIR"; if [ -n "$EXT_DIR" ]; then rm -rf "$EXT_DIR"; fi; if [ -n "$PUBLISH_TEMP" ]; then rm -f "$PUBLISH_TEMP"; fi' EXIT

color() { printf '\033[1;32m==> %s\033[0m\n' "$*"; }

color "1/7  LyssnaProtobuf.framework"
chmod +x Tools/SwiftProtobufBuild/build-lyssnaprotobuf.sh
Tools/SwiftProtobufBuild/build-lyssnaprotobuf.sh

color "2/7  theos make package"
THEOS_PACKAGE_SCHEME=rootless make package FINALPACKAGE=1
DEB_FILE=$(ls -t packages/com.lyssna.spotify_*.deb 2>/dev/null | head -1)
[ -n "$DEB_FILE" ] || { echo "deb not produced"; exit 1; }

color "3/7  zxPluginsInject.dylib"
chmod +x Tools/build-zxpi.sh
Tools/build-zxpi.sh >/dev/null

color "4/7  extract deb"
DEB_EXTRACT="$REPO_DIR/Outputs/deb-extract"
rm -rf "$DEB_EXTRACT"; mkdir -p "$DEB_EXTRACT"
dpkg-deb -R "$DEB_FILE" "$DEB_EXTRACT"
DYLIB_SRC=$(find "$DEB_EXTRACT" -name 'Lyssna.dylib' | head -1)
BUNDLE_SRC=$(find "$DEB_EXTRACT" -type d -name 'Lyssna.bundle' | head -1)
FRAMEWORK_SRC=$(find "$DEB_EXTRACT" -type d -name 'LyssnaProtobuf.framework' | head -1)
[ -n "$DYLIB_SRC" ] || { echo "dylib not in deb"; exit 1; }

color "5/7  cyan inject"
INJECT=("$DYLIB_SRC")
[ -n "$FRAMEWORK_SRC" ] && INJECT+=("$FRAMEWORK_SRC")
[ -n "$BUNDLE_SRC" ]    && INJECT+=("$BUNDLE_SRC")
rm -f "$OUT_IPA"
cyan -i "$VANILLA_IPA" -o "$OUT_IPA" -f "${INJECT[@]}" -c 9 -m 15.0 -du

color "6/7  ipapatch LC-inject zxPluginsInject"
ipapatch --input "$OUT_IPA" --inplace --noconfirm --dylib packages/zxPluginsInject.dylib

# Match the patched workflow unless a single-App-ID package was requested.
if [ "${LYSSNA_MINIMAL_IPA:-${EEVEE_MINIMAL_IPA:-0}}" != 1 ]; then
    EXT_DIR=$(mktemp -d)
    git clone --depth 1 https://github.com/BillyCurtis/OpenSpotifySafariExtension.git "$EXT_DIR"
    EXT_SRC="$EXT_DIR/OpenSpotifySafariExtension.appex"
    [ -d "$EXT_SRC" ] || { echo "OpenSpotifySafariExtension.appex not found" >&2; exit 1; }
fi
cd "$OUT_DIR"
rm -rf Payload
unzip -q "$(basename "$OUT_IPA")"
if [ "${LYSSNA_MINIMAL_IPA:-${EEVEE_MINIMAL_IPA:-0}}" = 1 ]; then
    rm -rf Payload/Spotify.app/PlugIns Payload/Spotify.app/AppClips
else
    mkdir -p Payload/Spotify.app/PlugIns
    cp -R "$EXT_SRC" Payload/Spotify.app/PlugIns/
fi
rm -rf Payload/Spotify.app/Watch Payload/Spotify.app/com.apple.WatchPlaceholder
# The receiver-model fallback resolves only selected AirPlay Bonjour services.
# Declare the type so iOS can apply the app's Local Network permission.
python3 - <<'PY'
import plistlib
from pathlib import Path

path = Path("Payload/Spotify.app/Info.plist")
with path.open("rb") as file:
    info = plistlib.load(file)
services = list(info.get("NSBonjourServices", []))
if "_airplay._tcp" not in services:
    services.append("_airplay._tcp")
info["NSBonjourServices"] = services
info.setdefault("NSLocalNetworkUsageDescription", "Find and identify your selected AirPlay speakers.")
with path.open("wb") as file:
    plistlib.dump(info, file, fmt=plistlib.FMT_BINARY, sort_keys=False)
PY
rm -f "$(basename "$OUT_IPA")"
zip -qry "$(basename "$OUT_IPA")" Payload
rm -rf Payload
cd - >/dev/null

color "7/7  stage alternate app icons"
# Apply the Lyssna primary icon, localized display names, supported rotations,
# and AirPlay service declaration using the shared packaging entry point.
chmod +x Tools/alt-icons.sh
Tools/alt-icons.sh "$OUT_IPA"

# Publish atomically after every packaging step; installers must not consume intermediates.
mkdir -p "$(dirname "$PUBLISH_IPA")"
PUBLISH_TEMP="$(dirname "$PUBLISH_IPA")/.lyssna-publish-$$.ipa.partial"
cp "$OUT_IPA" "$PUBLISH_TEMP"
mv -f "$PUBLISH_TEMP" "$PUBLISH_IPA"
PUBLISH_TEMP=""
color "Done"
echo "$PUBLISH_IPA"
echo "Sign with Sideloadly / AltStore / TrollStore."
