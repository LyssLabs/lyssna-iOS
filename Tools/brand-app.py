#!/usr/bin/env python3
"""Apply Lyssna presentation to a staged Spotify app without changing identity."""

import argparse
import hashlib
import plistlib
import shutil
import subprocess
from pathlib import Path


def apply_branding(app: Path) -> None:
    root = Path(__file__).resolve().parent.parent
    source = root / "Assets/AppIcon/sources/Lyssna.png"
    plist = app / "Info.plist"
    with plist.open("rb") as file:
        info = plistlib.load(file)
    identity = (info["CFBundleIdentifier"], info.get("CFBundleExecutable"))
    info["CFBundleDisplayName"] = "Lyssna"
    info["CFBundleName"] = "Lyssna"
    info.pop("CFBundleIconName", None)
    info.pop("CFBundleAlternateIcons", None)

    # Loose primary icon files override the original asset-catalog icon name.
    # iOS applies its own rounded mask. The opaque artwork includes its own
    # subtle gloss; declare that rather than requesting a second shine pass.
    # A new artwork filename prevents reuse of the previous icon rendition.
    stem = "LyssnaIcon-" + hashlib.sha256(source.read_bytes()).hexdigest()[:12] + "-"
    sizes = {
        f"{stem}20x20@2x.png": 40,
        f"{stem}20x20@3x.png": 60,
        f"{stem}29x29@2x.png": 58,
        f"{stem}29x29@3x.png": 87,
        f"{stem}40x40@2x.png": 80,
        f"{stem}40x40@3x.png": 120,
        f"{stem}60x60@2x.png": 120,
        f"{stem}60x60@3x.png": 180,
        f"{stem}76x76.png": 76,
        f"{stem}76x76@2x.png": 152,
        f"{stem}83.5x83.5@2x.png": 167,
        f"{stem}1024.png": 1024,
    }
    for filename, size in sizes.items():
        subprocess.run(
            ["sips", "-s", "format", "png", "-z", str(size), str(size),
             str(source), "--out", str(app / filename)],
            check=True, stdout=subprocess.DEVNULL,
        )
    for key, files in {
        "CFBundleIcons": [f"{stem}20x20", f"{stem}29x29", f"{stem}40x40", f"{stem}60x60"],
        "CFBundleIcons~ipad": [f"{stem}60x60", f"{stem}76x76", f"{stem}83.5x83.5"],
    }.items():
        info[key] = {"CFBundlePrimaryIcon": {"CFBundleIconFiles": files, "UIPrerenderedIcon": True}}
    info["CFBundleIconFiles"] = [f"{stem}60x60", f"{stem}76x76", f"{stem}83.5x83.5"]
    if (info["CFBundleIdentifier"], info.get("CFBundleExecutable")) != identity:
        raise ValueError("Branding must preserve Spotify's bundle ID and executable")
    with plist.open("wb") as file:
        plistlib.dump(info, file, fmt=plistlib.FMT_BINARY, sort_keys=False)

    # Localized display names take precedence over the root Info.plist.
    for strings in app.glob("*.lproj/InfoPlist.strings"):
        result = subprocess.run(
            ["plutil", "-convert", "xml1", "-o", "-", "--", str(strings)],
            check=True, capture_output=True,
        )
        localized = plistlib.loads(result.stdout)
        localized.update(CFBundleDisplayName="Lyssna", CFBundleName="Lyssna")
        with strings.open("wb") as file:
            plistlib.dump(localized, file, fmt=plistlib.FMT_BINARY, sort_keys=False)

    # Widget/share-extension labels can surface outside the main app. Keep
    # their identifiers and executable names intact as well.
    for extension in app.glob("PlugIns/*.appex"):
        extension_plist = extension / "Info.plist"
        if not extension_plist.is_file():
            continue
        with extension_plist.open("rb") as file:
            extension_info = plistlib.load(file)
        for key in ["CFBundleDisplayName", "CFBundleName"]:
            value = extension_info.get(key)
            if isinstance(value, str) and "Spotify" in value:
                extension_info[key] = value.replace("Spotify", "Lyssna")
        with extension_plist.open("wb") as file:
            plistlib.dump(extension_info, file, fmt=plistlib.FMT_BINARY, sort_keys=False)
        for strings in extension.glob("*.lproj/InfoPlist.strings"):
            result = subprocess.run(
                ["plutil", "-convert", "xml1", "-o", "-", "--", str(strings)],
                check=True, capture_output=True,
            )
            localized = plistlib.loads(result.stdout)
            for key in ["CFBundleDisplayName", "CFBundleName"]:
                value = localized.get(key)
                if isinstance(value, str) and "Spotify" in value:
                    localized[key] = value.replace("Spotify", "Lyssna")
            with strings.open("wb") as file:
                plistlib.dump(localized, file, fmt=plistlib.FMT_BINARY, sort_keys=False)

    # The desktop mark also serves as artwork for document and settings previews.
    shutil.copyfile(root / "Assets/Brand/LyssnaMark.png", app / "LyssnaMark.png")
    print("[branding] Applied Lyssna name and primary icon; bundle ID preserved")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    apply_branding(parser.parse_args().app)
