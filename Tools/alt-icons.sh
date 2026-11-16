#!/usr/bin/env bash
# Apply Lyssna branding to a staged .app or IPA. The legacy entry-point name
# remains shared by the local build and existing packaging workflows.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

patch_app() {
    python3 "$ROOT_DIR/Tools/brand-app.py" "$1"
    python3 - "$1/Info.plist" <<'PY'
import plistlib
import sys
from pathlib import Path

path = Path(sys.argv[1])
with path.open("rb") as file:
    info = plistlib.load(file)
# Rotation is enabled at runtime only while the lyric player is visible.
for key in ["UISupportedInterfaceOrientations", "UISupportedInterfaceOrientations~ipad"]:
    orientations = info.setdefault(key, ["UIInterfaceOrientationPortrait"])
    for value in ["UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"]:
        if value not in orientations:
            orientations.append(value)
services = info.setdefault("NSBonjourServices", [])
if "_airplay._tcp" not in services:
    services.append("_airplay._tcp")
info.setdefault("NSLocalNetworkUsageDescription", "Find and identify your selected AirPlay speakers.")
with path.open("wb") as file:
    plistlib.dump(info, file, fmt=plistlib.FMT_BINARY, sort_keys=False)
PY
}

patch_ipa() {
    local ipa="$1" absolute temporary app
    absolute="$(cd "$(dirname "$ipa")" && pwd)/$(basename "$ipa")"
    temporary="$(mktemp -d -t lyssna-branding.XXXXXX)"
    trap 'rm -rf "$temporary"' RETURN
    (cd "$temporary" && unzip -q "$absolute")
    app=$(find "$temporary/Payload" -maxdepth 2 -name '*.app' -type d | head -1)
    [ -n "$app" ] || { echo "[branding] No app in $ipa" >&2; return 1; }
    patch_app "$app"
    rm -f "$absolute"
    (cd "$temporary" && zip -qry "$absolute" Payload)
}

target="${1:-}"
[ -n "$target" ] || { echo "Lyssna primary icon: Assets/AppIcon/sources/Lyssna.png"; exit 0; }
if [ -d "$target" ]; then patch_app "$target"
elif [ -f "$target" ] && [[ "$target" == *.ipa || "$target" == *.zip ]]; then patch_ipa "$target"
else echo "[branding] Invalid target: $target" >&2; exit 1
fi
