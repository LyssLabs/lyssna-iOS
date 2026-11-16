import Foundation

extension Notification.Name {
    static let lyssnaAirPlayModelChanged = Notification.Name("lyssnaAirPlayModelChanged")
}

/// Resolve only a selected receiver's advertised service. This reads Bonjour
/// metadata without opening a connection or changing the playback route.
final class AirPlayReceiverModel: NSObject, NetServiceDelegate {
    static let shared = AirPlayReceiverModel()

    private struct Entry {
        let identifier: String?
        let expires: TimeInterval
    }

    private let lock = NSLock()
    private var cache: [String: Entry] = [:]
    private var pending = Set<String>()
    // NetService and its delegate callbacks run on the main run loop.
    private var services: [String: NetService] = [:]

    func identifier(for name: String) -> String? {
        guard !name.isEmpty, name.utf8.count <= 63 else { return nil }
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        if let entry = cache[name], entry.expires > now {
            lock.unlock()
            return entry.identifier
        }
        guard !pending.contains(name), pending.count < 8 else { lock.unlock(); return nil }
        pending.insert(name)
        lock.unlock()
        DispatchQueue.main.async { [weak self] in self?.resolve(name) }
        return nil
    }

    private func resolve(_ name: String) {
        let service = NetService(domain: "local.", type: "_airplay._tcp.", name: name)
        services[name] = service
        service.delegate = self
        service.includesPeerToPeer = true
        writeDebugLog("[Connect][receiver] Resolving selected AirPlay receiver model through Bonjour")
        service.resolve(withTimeout: 5)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        finish(sender, identifier: Self.identifier(from: sender.txtRecordData()))
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        // TXT metadata can be available even if address resolution failed.
        if let identifier = Self.identifier(from: sender.txtRecordData()) {
            finish(sender, identifier: identifier)
        } else {
            let code = errorDict["NSNetServicesErrorCode"]?.intValue ?? 0
            writeDebugLog("[Connect][receiver] Bonjour model resolution failed: \(code)")
            finish(sender, identifier: nil)
        }
    }

    func netServiceDidStop(_ sender: NetService) { finish(sender, identifier: nil) }

    private func finish(_ service: NetService, identifier: String?) {
        guard let name = services.first(where: { $0.value === service })?.key else { return }
        services.removeValue(forKey: name)
        service.delegate = nil
        service.stop()
        lock.lock()
        pending.remove(name)
        if cache.count >= 64 { cache.removeAll() }
        cache[name] = Entry(identifier: identifier,
                            expires: ProcessInfo.processInfo.systemUptime + (identifier == nil ? 30 : 300))
        lock.unlock()
        if let identifier {
            writeDebugLog("[Connect][receiver] Bonjour model identifier=\(identifier)")
            NotificationCenter.default.post(name: .lyssnaAirPlayModelChanged, object: nil)
        } else {
            writeDebugLog("[Connect][receiver] Bonjour model unavailable; keeping receiver name")
        }
    }

    private static func identifier(from data: Data?) -> String? {
        guard let data, !data.isEmpty, data.count <= 8192 else { return nil }
        // Foundation asserts on malformed TXT data. Validate its length-prefixed
        // strings before handing the advertised record to the system parser.
        let bytes = [UInt8](data)
        var offset = 0
        while offset < bytes.count {
            let length = Int(bytes[offset]); offset += 1
            guard length <= bytes.count - offset else { return nil }
            offset += length
        }
        let record = NetService.dictionary(fromTXTRecord: data)
        for key in ["model", "am"] {
            guard let value = record[key], let text = String(data: value, encoding: .utf8) else { continue }
            let identifier = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !identifier.isEmpty, identifier.utf8.count <= 64 { return identifier }
        }
        return nil
    }
}
