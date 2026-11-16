# Lyssna troubleshooting

## App name or icon still shows Spotify

Install an IPA produced by the current Lyssna packaging pipeline. Source changes do not alter an already installed app. The pipeline updates the primary icon and localized names while retaining `com.spotify.client`. An installer can override display names or bundle IDs; check its options before signing.

## AirPlay shows only the receiver name

Allow Local Network access for Lyssna, select the AirPlay receiver, and allow a few seconds for model discovery and a subsequent Spotify Connect update. Missing or unknown model metadata leaves the friendly name visible. Diagnostics distinguish model discovery failures from Connect publication responses.

## Lyrics are missing or mistimed

Check enabled lyrics sources and their priority. A provider may have no lyrics for a track or require its own token. Adjust the lyrics offset for the current audio output; the setting is saved separately for each output.

## An upstream feature does not work

Spotify changes its native interfaces between versions, and server-side features depend on the account. A successful injection or a changed label does not establish that every feature is compatible. Record the Spotify version and retrieve device logs before changing hooks.

## Getting device logs

With the phone paired over USB and available to Xcode's device tools:

```sh
python3 Scripts/pull-lyrics-log.py
```

The script saves diagnostics locally under `Outputs/Diagnostics`. Review logs before sharing them; they can contain account, playback, and local-device details.

## Builds and releases

This is a personal project. Build instructions are in [README.md](README.md); there is no formal release process for local iterations. Existing upstream issue trackers and release packages describe their own project rather than the current Lyssna customization.
