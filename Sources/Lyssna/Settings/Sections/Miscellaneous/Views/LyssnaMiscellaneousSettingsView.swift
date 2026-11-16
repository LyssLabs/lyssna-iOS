import SwiftUI
import UIKit

struct LyssnaMiscellaneousSettingsView: View {
    @State private var blockTelemetry = UserDefaults.blockTelemetry
    @State private var cleanShareLinks = UserDefaults.cleanShareLinks
    @State private var blockRatingPrompts = UserDefaults.blockRatingPrompts
    @State private var deviceName = UserDefaults.spotifyConnectDeviceName
    @State private var localPlaylistDownload = UserDefaults.localPlaylistDownloadEnabled

    var body: some View {
        List {
            Section(header: Text("spotify_connect_device_name".localized),
                    footer: Text("spotify_connect_device_name_footer".localized)) {
                TextField("spotify_connect_device_name_placeholder".localized, text: $deviceName)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            }

            Section(footer: Text("block_telemetry_footer".localized)) {
                Toggle("block_telemetry".localized, isOn: $blockTelemetry)
            }

            Section(footer: Text("block_rating_prompts_footer".localized)) {
                Toggle("block_rating_prompts".localized, isOn: $blockRatingPrompts)
            }

            Section(footer: Text("clean_share_links_description".localized)) {
                Toggle("clean_share_links".localized, isOn: $cleanShareLinks)
            }

            if UserDefaults.patchType.isPatching {
                Section {
                    Toggle("local_playlist_download_button".localized, isOn: $localPlaylistDownload)
                }
            }

            RestartSection(visible: blockTelemetry != TelemetryBlock.launchEnabled ||
                blockRatingPrompts != RatingPromptBlock.launchEnabled ||
                localPlaylistDownload != LocalPlaylistDownload.launchEnabled ||
                SpotifyConnectDeviceName.normalized(deviceName) != SpotifyConnectDeviceName.launchName)

            SpacerView()
        }
        .lyssnaSettingsStyle()
        .onChange(of: blockTelemetry) { UserDefaults.blockTelemetry = $0 }
        .onChange(of: cleanShareLinks) { UserDefaults.cleanShareLinks = $0 }
        .onChange(of: blockRatingPrompts) { UserDefaults.blockRatingPrompts = $0 }
        .onChange(of: deviceName) { UserDefaults.spotifyConnectDeviceName = $0 }
        .onChange(of: localPlaylistDownload) { UserDefaults.localPlaylistDownloadEnabled = $0 }
    }
}
