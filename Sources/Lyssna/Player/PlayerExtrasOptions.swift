import Foundation

enum PlayerDoubleTap: String, Codable, CaseIterable {
    case off, seek, skip
}

struct PlayerExtrasOptions: Codable, Equatable {
    var doubleTap = PlayerDoubleTap.off
    var threeZones = true
    var haptics = false
}

extension UserDefaults {
    @UserDefault(key: "lyssnaPlayerExtrasOptions", defaultValue: PlayerExtrasOptions())
    static var playerExtrasOptions
}
