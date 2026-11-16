"""Bundle third-party notices and complete companion relink source, without runtime data."""
from pathlib import Path
import shutil
ROOT=Path(__file__).resolve().parents[1]

def notices():
    return {
        'Payload/Spotify.app/LyssnaOfflineExportLicenses/M4A-NOTICES.md':(ROOT/'vendor/M4A-NOTICES.md').read_bytes(),
    }

def retain_relink_sources(output):
    destination=Path(output).with_suffix('.relink-sources')
    destination.mkdir()
    for name in ['src','tools','targets','vendor']:
        shutil.copytree(ROOT/name,destination/'NativeDownloads'/name,ignore=shutil.ignore_patterns('__pycache__','*.pyc','.DS_Store'))
    (destination/'README.md').write_text('''# LyssnaOffline companion relink source

Complete companion source and the stb_vorbis decoder source are included. No phone data or keys are included.

Requires macOS, Xcode with the iPhoneOS SDK and Python 3. The active target is declared in NativeDownloads/tools/lyssnaOffline_target.py. Rebuild from the matching clean Lyssna IPA and the corresponding Lyssna UI library:

    python3 NativeDownloads/tools/build_lyssna_9192.py /path/to/base.ipa --lyssna-dylib /path/to/Lyssna.dylib --output /path/to/new.ipa

The builder compiles the provided application source and Swift bridge. M4A/AAC uses Apple system frameworks; Ogg decoding uses the bundled stb_vorbis source. See NativeDownloads/vendor/M4A-NOTICES.md.
''')
    return str(destination)
