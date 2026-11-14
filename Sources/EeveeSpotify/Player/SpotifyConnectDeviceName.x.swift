import Orion
import UIKit
import ObjectiveC.runtime

struct SpotifyConnectDeviceNameGroup: HookGroup {}
struct SpotifyConnectOutputGroup: HookGroup {}

enum SpotifyConnectDeviceName {
    static let launchName = UserDefaults.spotifyConnectDeviceName

    static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func activate() {
        _ = PlaybackAudioRoute.shared
        SpotifyConnectDeviceNameGroup().activate()
        if let cls = NSClassFromString("SPTGaiaConnectStateImpl"),
           class_getInstanceMethod(cls, NSSelectorFromString("activeDevice")) != nil {
            SpotifyConnectOutputGroup().activate()
        }
        if let cls = NSClassFromString("SPTGaiaConnectDevice"),
           class_getInstanceMethod(cls, NSSelectorFromString("name")) != nil,
           class_getInstanceMethod(cls, NSSelectorFromString("isSelf")) != nil {
            SpotifyConnectDestinationNameGroup().activate()
        }
    }

    static var reportedName: String? {
        PlaybackAudioRoute.airPlayName ?? (launchName.isEmpty ? nil : launchName)
    }
}

// Sideloaded apps cannot assume access to iOS's user-assigned-name entitlement.
// Supply the user's explicit override when Spotify asks UIKit for this device's name.
class SpotifyConnectDeviceNameHook: ClassHook<UIDevice> {
    typealias Group = SpotifyConnectDeviceNameGroup

    func name() -> String {
        SpotifyConnectDeviceName.reportedName ?? orig.name()
    }
}

struct SpotifyConnectDestinationNameGroup: HookGroup {}

// Refresh local Connect display names when Spotify reads an existing device
// model after an AirPlay route change. Remote Connect devices keep their names.
class SpotifyConnectDestinationNameHook: ClassHook<NSObject> {
    typealias Group = SpotifyConnectDestinationNameGroup
    static let targetName = "SPTGaiaConnectDevice"

    func name() -> String? {
        if (target.value(forKey: "isSelf") as? NSNumber)?.boolValue == true {
            return SpotifyConnectDeviceName.reportedName ?? orig.name()
        }
        return orig.name()
    }
}

class SpotifyConnectOutputHook: ClassHook<NSObject> {
    typealias Group = SpotifyConnectOutputGroup
    static let targetName = "SPTGaiaConnectStateImpl"

    func activeDevice() -> NSObject? {
        let device = orig.activeDevice()
        func value(_ key: String) -> Any? {
            guard let device, device.responds(to: NSSelectorFromString(key)) else { return nil }
            return device.value(forKey: key)
        }
        let isLocal = (value("isSelf") as? NSNumber)?.boolValue
        let id = (value("localIdentifier") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = value("name") as? String
        if isLocal == false, let id, !id.isEmpty, let name, !name.isEmpty {
            PlaybackAudioRoute.shared.updateConnectOutput(.init(id: "connect:" + id, name: name))
        } else if device == nil || isLocal == true {
            PlaybackAudioRoute.shared.updateConnectOutput(nil)
        }
        return device
    }
}
