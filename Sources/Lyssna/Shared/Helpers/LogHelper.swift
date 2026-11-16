import Foundation
import os.log

// Public logging helper that makes strings visible in Console.app
struct LogHelper {
    private static let log = OSLog(subsystem: "com.lyssna.spotify", category: "Lyssna")

    static func log(_ message: String) {
        os_log("%{public}@", log: log, type: .default, "[Lyssna] \(message)")
    }

    static func logError(_ message: String) {
        os_log("%{public}@", log: log, type: .error, "[Lyssna] ERROR: \(message)")
    }

    static func logDebug(_ message: String) {
        os_log("%{public}@", log: log, type: .debug, "[Lyssna] \(message)")
    }
}
