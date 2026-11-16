import Foundation
import SwiftUI
import LyssnaC

class BundleHelper {
    private let bundleName = "Lyssna"
    
    // Make properties optional to prevent init crash
    private var bundle: Bundle?
    private var enBundle: Bundle?
    
    static let shared = BundleHelper()
    
    private init() {
        // Try locating in main bundle first
        if let path = Bundle.main.path(forResource: bundleName, ofType: "bundle"),
           let b = Bundle(path: path) {
            self.bundle = b
            lyssnaLog("[Lyssna] Loaded bundle from main bundle: \(path)")
        } 
        // If not found, try locating in file system (jailbreak path)
        else {
            let jbPath = LyssnaJBRootPath("/Library/Application Support/\(bundleName).bundle")
            if let b = Bundle(path: jbPath) {
                self.bundle = b
                lyssnaLog("[Lyssna] Loaded bundle from filesystem: \(jbPath)")
            } else {
                lyssnaLog("[Lyssna] ERROR: Could not find Lyssna.bundle!")
                self.bundle = nil
            }
        }
        
        // Load English localization if available
        if let b = self.bundle, let enPath = b.path(forResource: "en", ofType: "lproj"),
           let enB = Bundle(path: enPath) {
            self.enBundle = enB
        } else {
            lyssnaLog("[Lyssna] WARNING: Could not load en.lproj from bundle")
            self.enBundle = nil
        }
    }
    
    func resourceURL(_ name: String, extension fileExtension: String) -> URL? {
        bundle?.url(forResource: name, withExtension: fileExtension)
    }

    func uiImage(_ name: String) -> UIImage? {
        guard let bundle = self.bundle else { return nil }
        
        if let path = bundle.path(forResource: name, ofType: "png") {
            return UIImage(contentsOfFile: path)
        }
        return nil
    }
    
    func localizedString(_ key: String) -> String {
        guard let bundle = self.bundle else { return key }

        let value = bundle.localizedString(forKey: key, value: "No translation", table: nil)
        
        if value != "No translation" {
            return value
        }
        
        let fallback = enBundle?.localizedString(forKey: key, value: nil, table: nil) ?? key
        // An IPA that ships an older strings bundle than the dylib still gets readable text for new keys.
        return fallback == key ? (Self.builtInStrings[key] ?? key) : fallback
    }

    private static let builtInStrings: [String: String] = [
        "manage_downloads": "Manage downloads",
        "manage_downloads_subtitle": "Lyssna Offline downloads",
    ]
    
    func resolveConfiguration() throws -> ResolveConfiguration {
        let spotifyVersion = Lyssna.spotifyVersion
        let resourceName = BundledConfigurationPolicy.resourceName(for: spotifyVersion)

        guard let bundle = self.bundle,
              let url = bundle.url(forResource: resourceName, withExtension: "bnk") else {
            throw NSError(domain: "Lyssna", code: 404, userInfo: [NSLocalizedDescriptionKey: "Configuration not found"])
        }

        writeDebugLog("[CONFIG] Using \(resourceName).bnk for Spotify \(spotifyVersion)")
        
        return try ResolveConfiguration(
            serializedBytes: try Data(contentsOf: url)
        )
    }
}
