import Orion
import UIKit

struct SpotifyConnectDeviceNameGroup: HookGroup {}

enum SpotifyConnectDeviceName {
    static let launchName = UserDefaults.spotifyConnectDeviceName

    static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func activate() {
        guard !launchName.isEmpty else { return }
        SpotifyConnectDeviceNameGroup().activate()
    }
}

// Sideloaded apps cannot assume access to iOS's user-assigned-name entitlement.
// Supply the user's explicit override when Spotify asks UIKit for this device's name.
class SpotifyConnectDeviceNameHook: ClassHook<UIDevice> {
    typealias Group = SpotifyConnectDeviceNameGroup

    func name() -> String {
        SpotifyConnectDeviceName.launchName.isEmpty ? orig.name() : SpotifyConnectDeviceName.launchName
    }
}
