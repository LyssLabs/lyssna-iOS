import Foundation

/// Keep existing preferences when moving the app-owned namespaces to Lyssna.
/// Legacy names appear only here for upgrade compatibility and in attribution.
enum LyssnaPreferencesMigration {
    static func migrate(_ defaults: UserDefaults) {
        migrateStorage()
        let marker = "lyssnaBrandingMigrationV1"
        guard !defaults.bool(forKey: marker) else { return }
        let replacements = [
            ("EeveeSpotify", "Lyssna"), ("eeveespotify", "lyssna"),
            ("Eevee", "Lyssna"), ("eevee", "lyssna"),
            ("Pixie", "LyssnaOffline"), ("pixie", "lyssnaOffline")
        ]
        for (key, value) in defaults.dictionaryRepresentation() {
            let migrated = replacements.reduce(key) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
            if migrated != key, defaults.object(forKey: migrated) == nil {
                defaults.set(value, forKey: migrated)
            }
        }
        // Removed alternate icons must not leave the picker pointing to an old key.
        defaults.set("__primary__", forKey: "LyssnaSelectedAppIconName")
        defaults.set(true, forKey: marker)
    }

    private static func migrateStorage() {
        let manager = FileManager.default
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let directories = [
            ("Library/Caches/EeveeSpotify", "Library/Caches/Lyssna"),
            ("Library/Caches/EeveeLyricsFonts", "Library/Caches/LyssnaLyricsFonts"),
            ("Library/Application Support/EeveeSpotify", "Library/Application Support/Lyssna"),
            ("Library/Application Support/Pixie", "Library/Application Support/LyssnaOffline"),
            ("Library/Application Support/PixieExport", "Library/Application Support/LyssnaOfflineExport"),
            ("Documents/Pixie Exports", "Documents/LyssnaOffline Exports"),
            ("Documents/Pixie Research", "Documents/LyssnaOffline Research")
        ]
        for (old, new) in directories {
            let source = home.appendingPathComponent(old)
            let destination = home.appendingPathComponent(new)
            guard manager.fileExists(atPath: source.path), !manager.fileExists(atPath: destination.path) else { continue }
            do {
                try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try manager.moveItem(at: source, to: destination)
            } catch {
                // Leave the existing directory intact if migration cannot complete.
                NSLog("[Lyssna] Existing storage migration failed: %@", error.localizedDescription)
            }
        }
    }
}
