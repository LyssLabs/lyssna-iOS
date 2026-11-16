<p align="center">
  <img src="Images/Lyssna.png" width="128" alt="Lyssna microphone logo">
</p>

# Lyssna for iOS

Lyssna is an iOS customization of Spotify, with branding shared with the Lyssna desktop app. It combines a custom lyrics player, playback and appearance controls, offline-download tools, and richer AirPlay receiver labels.

The app appears as **Lyssna** on the Home Screen and in its settings. Its device bundle identifier remains **`com.spotify.client`** so Spotify's native integration continues to use the same identity. Installing it with that identifier replaces the existing Spotify app rather than creating a separate app. Signing tools may apply their own bundle-identifier changes; choose their original-ID option when available.

## Features

- Custom lyrics from multiple sources, with source priority, timing controls, fonts, word timing, and landscape artwork or Canvas.
- A dedicated lyrics view with optional Space Gravity motion effects.
- Appearance controls for tabs, player controls, pages, artwork, and Liquid Glass layouts.
- Playback controls, telemetry options, clean sharing links, and rating-prompt controls.
- Offline-download management inherited from the upstream implementation. Availability depends on the Spotify version and account capabilities.
- Spotify Connect labels that reflect the selected AirPlay receiver. Supported model metadata produces labels such as **Living Room (HomePod mini)**; missing metadata leaves the receiver's name visible.
- A Lyssna microphone icon and consistent branding throughout the custom settings, modules, resource bundle, logs, and package.

Spotify's account, authentication, API endpoints, native class names, and media protocols remain Spotify integrations. Lyssna branding does not change server-side entitlements or guarantee that any specific feature works across every Spotify version.

## Building

Build on macOS with Xcode with the iOS SDK, Theos, `cyan` (pyzule-rw), `ipapatch`, `dpkg`, `ldid`, Python 3, and the dependencies used by the build scripts. Supply a compatible decrypted Spotify IPA.

Set the Theos installation path and choose an output file:

```sh
export THEOS="/path/to/theos"
LYSSNA_IPA_OUTPUT="/path/to/Lyssna.ipa" \
  bash build-ipa-local.sh /path/to/Spotify-decrypted.ipa
```

The package version is defined in `control`; the runtime version is defined in `Sources/Lyssna/Tweak.x.swift`. Keep these values aligned when updating the app. Packaging sets both `CFBundleShortVersionString` and `CFBundleVersion` to the Lyssna version for installer update tracking, including app extensions. The original Spotify values are retained in `LyssnaSpotifyVersion` and `LyssnaSpotifyBundleVersion` for hook selection, configuration, and diagnostics. See [Apple's app version reference](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleshortversionstring).

`LYSSNA_MINIMAL_IPA=1` omits optional app extensions for signing setups that require one App ID. The previous `EEVEE_IPA_OUTPUT` and `EEVEE_MINIMAL_IPA` environment variables remain compatibility aliases.

The pipeline builds `Lyssna.dylib` and the isolated `LyssnaProtobuf.framework`, packages `Lyssna.bundle`, injects the sideload compatibility library, and applies the app name, primary icon, localized display names, Lyssna launch screen, and AirPlay Bonjour declaration before publishing the completed IPA. It preserves the input app's bundle identifier and executable name. The package ID `com.lyssna.spotify` identifies the tweak package; it is separate from the app's device bundle ID.

Sign and install the resulting IPA using your preferred compatible installer. No signed IPA is committed to this repository. Additional packaging workflows are available in `.github/workflows`.

## AirPlay labels

Allow **Local Network** access for Lyssna when prompted. The app first reads the selected output's metadata, then resolves that receiver's advertised AirPlay service when its model is missing. Model discovery is asynchronous; the label updates on a subsequent native Connect publication.

The selected receiver must advertise usable metadata and be reachable. Device groups, unknown hardware, and denied Local Network access can leave only the friendly name visible. Bluetooth and wired headphones keep the phone's Spotify Connect identity.

## Source layout

- `Sources/Lyssna`: Swift hooks, settings, lyrics, and playback features.
- `Sources/LyssnaC`: Objective-C and C bridges to native controls.
- `NativeDownloads`: the offline-download implementation, presented as Lyssna Offline.
- `layout/Library/Application Support/Lyssna.bundle`: translations, configuration, and app resources.
- `Assets/Brand`: shared microphone mark and vector source.
- `Assets/LaunchScreen`: centered Lyssna launch logo and storyboard.
- `Assets/AppIcon/sources/Lyssna.png`: opaque primary iOS icon.
- `Tools/brand-app.py`: presentation changes that preserve app identity.
- `Scripts/pull-lyrics-log.py`: retrieve diagnostics from a paired USB device.

Existing preferences are copied into the Lyssna namespace on upgrade, including custom output offsets and saved settings. Legacy names remain only where needed for compatibility, attribution, or genuine external repository links. Runtime caches and new diagnostic files use Lyssna names.

## Upstream and attribution

This project builds on [EeveeSpotifyReincarnated](https://github.com/SideloadLabs/EeveeSpotifyReincarnated), its earlier EeveeSpotify lineage, and the work of its contributors. Upstream credits are retained in `contributors.json` and the contributor UI. The offline implementation's original provenance is recorded in `NativeDownloads/provenance-pixie-v1.4.json`.

Lyssna's microphone mark is shared with the sibling desktop app; its vector derives from Lucide's MicVocal icon. See [branding attribution](Assets/Brand/README.md). Third-party source notices and licenses remain with their dependencies. This customization is not affiliated with Spotify or Apple. See [LICENSE](LICENSE) for the repository license.
