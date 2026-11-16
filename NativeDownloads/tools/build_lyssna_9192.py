"""Build the guarded Lyssna/LyssnaOffline IPA for the active lyssnaOffline_target profile.

The filename is retained for the existing project build entry point.
"""
import argparse
import hashlib
import json
import plistlib
import subprocess
import tempfile
from datetime import datetime
from pathlib import Path
from zipfile import ZipFile

from patch_imports import patch as patch_audio_imports
from patch_native_restrictions import patch as patch_limits, guard_header, limits_header, layout
from patch_key_request_mode import patch as patch_key_mode, key_header
from patch_native_trace import patch as patch_native_trace,header as native_trace_header
from patch_export import patch as patch_export
from strip_stale_signature import strip_stale_signature
from export_headers import headers as export_headers
from export_release_materials import notices, retain_relink_sources
from companion_build import build_companion
from patch_offline import patch_reminder
from signing_metadata import sign_preserving_entitlements

from lyssnaOffline_target import PROFILE, ROOT, resolve_source, validate_sources
UUID = bytes.fromhex(PROFILE["uuid"])


def run(*command):
    subprocess.run([str(part) for part in command], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", type=Path)
    parser.add_argument("--lyssna-dylib", type=Path, help="Lyssna rebuilt from the local sources")
    parser.add_argument("--output", type=Path, default=ROOT.parent / "outputs" /
        datetime.now().strftime("build-%Y%m%d-%H%M%S-%f") / f"Spotify-{PROFILE['spotify_version']}-Lyssna-LyssnaOffline-v{PROFILE['lyssnaOffline_version']}.ipa")
    args = parser.parse_args()
    validate_sources()
    source = args.ipa.resolve()
    output = args.output.resolve()
    if output.exists():
        parser.error("Choose a new output folder; the output IPA already exists")
    lyssna = args.lyssna_dylib.resolve() if args.lyssna_dylib else None
    if lyssna:
        # The dylib from a .deb is unsigned; it is ad-hoc signed and validated below.
        if b"LyssnaOfflineUpdateArtistDownloads" not in lyssna.read_bytes():
            raise RuntimeError("The rebuilt Lyssna lacks the LyssnaOffline artist controls")
    if not source.is_file():
        parser.error("Input IPA not found")
    if resolve_source("NativeRestrictionsPatch.h").read_text() != guard_header():
        raise RuntimeError("Native restriction header is out of sync")
    if resolve_source("OfflineLimits.h").read_text() != limits_header():
        raise RuntimeError("Offline limits header is out of sync")
    if resolve_source("NativeKeyModePatch.h").read_text() != key_header():
        raise RuntimeError("Native key-mode header is out of sync")
    if resolve_source("NativeTracePatch.h").read_text() != native_trace_header():
        raise RuntimeError("Native trace header is out of sync")
    for name, expected in export_headers().items():
        if resolve_source(name).read_text() != expected:
            raise RuntimeError(f"Generated export header is out of sync: {name}")

    with ZipFile(source) as archive:
        info_name = "Payload/Spotify.app/Info.plist"
        info = plistlib.loads(archive.read(info_name))
        if info.get("CFBundleShortVersionString") != PROFILE["spotify_version"]:
            raise RuntimeError(f"Expected Spotify {PROFILE['spotify_version']}")
        executable = "Payload/Spotify.app/Spotify"
        native = archive.read(executable)
        if layout(native)[3] != UUID:
            raise RuntimeError("Unsupported Spotify executable UUID")
        if "Payload/Spotify.app/Frameworks/Lyssna.dylib" not in archive.namelist():
            raise RuntimeError("Expected Lyssna's Lyssna.dylib")
        lyssna_bytes = lyssna.read_bytes() if lyssna else archive.read("Payload/Spotify.app/Frameworks/Lyssna.dylib")

    patched, audio = patch_audio_imports(native)
    patched, limits = patch_limits(patched)
    patched, key = patch_key_mode(patched, runtime_selectable=False)
    patched, native_trace = patch_native_trace(patched)
    patched, export = patch_export(patched)
    patched, stale_bytes = strip_stale_signature(patched)
    key['implementation']='verified static observation boundary restores fixed w2=0 before the original indirect call'
    key['configuration_source']='verified_static_trace_argument'
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="lyssna-9192-") as temporary:
        temporary = Path(temporary)
        staged_lyssna = temporary / "Lyssna.dylib"
        lyssna_bytes, reminder = patch_reminder(lyssna_bytes)
        staged_lyssna.write_bytes(lyssna_bytes)
        run("codesign", "--force", "--sign", "-", "--timestamp=none", staged_lyssna)
        run("codesign", "--verify", "--strict", staged_lyssna)
        run("xcrun", "dyld_info", "-validate_only", staged_lyssna)
        lyssna = staged_lyssna
        companion = temporary / "SpotifyAudioProbe.dylib"
        build_companion(companion, temporary)
        binary = temporary / "Spotify"
        binary.write_bytes(patched)
        binary.chmod(0o755)
        signing_metadata = sign_preserving_entitlements(binary, native, temporary / "Spotify.entitlements.plist")
        run("xcrun", "dyld_info", "-validate_only", binary)
        imports = subprocess.check_output(["xcrun", "dyld_info", "-imports", str(binary)], text=True)
        for change in audio["changes"]:
            matches = [line for line in imports.splitlines() if change["symbol"] in line]
            if not matches or not all("SpotifyAudioProbe" in line for line in matches):
                raise RuntimeError(f"Audio import not redirected: {change['symbol']}")
        with ZipFile(source) as original, ZipFile(output, "w", allowZip64=True) as result:
            for member in original.infolist():
                replacement = binary.read_bytes() if member.filename == executable else lyssna.read_bytes() if lyssna and member.filename == "Payload/Spotify.app/Frameworks/Lyssna.dylib" else original.read(member.filename)
                result.writestr(member, replacement)
            result.write(companion, "Payload/Spotify.app/Frameworks/SpotifyAudioProbe.dylib")
            for name, data in notices().items():
                result.writestr(name, data)

    with ZipFile(output) as check:
        if check.testzip() is not None:
            raise RuntimeError("IPA ZIP integrity check failed")
        with ZipFile(source) as original:
            changed = [item.filename for item in original.infolist()
                       if original.read(item.filename) != check.read(item.filename)]
            if set(changed) != {executable, "Payload/Spotify.app/Frameworks/Lyssna.dylib"}:
                raise RuntimeError(f"Unexpected changed IPA entries: {changed}")
            plugins = {name: hashlib.sha256(check.read(name)).hexdigest()
                       for name in original.namelist() if name.endswith('.dylib') and 'Lyssna' not in name}
    from source_provenance import snapshot
    report = {"output": str(output), "sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
                      "input": str(source), "input_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
                      "spotify_version": PROFILE['spotify_version'], "lyssnaOffline_version": PROFILE['lyssnaOffline_version'],
                      "source_commit": subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT.parent,text=True).strip(),
                      "source_sha256_by_file": snapshot(), "changed_entries": changed,
                      "preserved_plugin_sha256": plugins,
                      "lyssna_ui_artifact_sha256": hashlib.sha256(args.lyssna_dylib.read_bytes()).hexdigest() if args.lyssna_dylib else None,
                      "phone_runtime_tested": False,
                      "spotify_uuid": UUID.hex(), "audio_imports": audio,
                      "native_limits": limits, "key_request_mode": key, "native_observation": native_trace,
                      "export_observation": export, "stale_signature_bytes_removed": stale_bytes, "relink_sources": retain_relink_sources(output),
                      "signing_metadata": signing_metadata,
                      "lyssna_native_download_reminder": reminder}
    output.with_suffix('.build.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
