import AVFoundation
import Foundation
import ObjectiveC.runtime
import UIKit

/// Public audio ports can omit the receiver's model and even its name. WebKit
/// uses AVOutputContext for selected receivers; resolve private SPI only when present.
/// https://github.com/WebKit/WebKit/blob/main/Source/WebCore/PAL/pal/avfoundation/OutputContext.mm
enum AirPlayReceiverName {
    private static let lock = NSLock()
    private static var lastResolution: String?
    private static var reportedModels = Set<String>()
    private static let lookupKey = "com.eevee.airplayReceiverLookup"
    // Hardware identifiers, not room-name guesses. Mapping reference:
    // https://github.com/postlund/pyatv/blob/master/pyatv/support/device_info.py
    private static let modelNames: [String: String] = [
        "audioaccessory1,1": "HomePod",
        "audioaccessory1,2": "HomePod",
        "audioaccessory5,1": "HomePod mini",
        "audioaccessorysingle5,1": "HomePod mini",
        "audioaccessory6,1": "HomePod",
        "appletv2,1": "Apple TV",
        "appletv3,1": "Apple TV",
        "appletv3,2": "Apple TV",
        "appletv5,3": "Apple TV HD",
        "appletv6,2": "Apple TV 4K",
        "appletv11,1": "Apple TV 4K",
        "appletv14,1": "Apple TV 4K",
        "airport4,107": "AirPort Express",
        "airport10,115": "AirPort Express"
    ]

    static func name(for ports: [AVAudioSessionPortDescription]) -> String? {
        guard !ports.isEmpty, ports.allSatisfy({ $0.portType == .airPlay }) else { return nil }
        let publicNames = ports.map { $0.portName.trimmingCharacters(in: .whitespacesAndNewlines) }
        let fallback = publicNames.count == 1 ? useful(publicNames[0]) : nil
        // A framework lookup can itself ask UIDevice for a name. Do not recurse
        // through our UIDevice.name hook while resolving the output context.
        let thread = Thread.current.threadDictionary
        guard thread[lookupKey] as? Bool != true else { return nil }
        thread[lookupKey] = true
        defer { thread.removeObject(forKey: lookupKey) }
        if let name = contextName(fallback: fallback) {
            note("context:" + name, "Resolved selected AirPlay receiver label from AVOutputContext")
            return name
        }
        note("fallback", "AirPlay receiver metadata unavailable; using public port name")
        return joined(publicNames.filter { !$0.isEmpty })
    }

    private static func contextName(fallback: String?) -> String? {
        let selector = NSSelectorFromString("sharedAudioPresentationOutputContext")
        guard let cls = NSClassFromString("AVOutputContext"),
              let method = class_getClassMethod(cls, selector), returnsObject(method) else { return nil }
        typealias ContextGetter = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
        let getter = unsafeBitCast(method_getImplementation(method), to: ContextGetter.self)
        guard let context = getter(cls as AnyObject, selector)?.takeUnretainedValue() as? NSObject else { return nil }

        if let devices = object(context, "outputDevices") as? [NSObject], !devices.isEmpty {
            let names = devices.map { device -> String? in
                receiverLabel(device, fallback: devices.count == 1 ? fallback : nil)
            }
            // Do not drop unnamed members from a multi-room output.
            if names.allSatisfy({ $0 != nil }) { return joined(names.compactMap { $0 }) }
            if devices.count > 1 { return useful(object(context, "deviceName") as? String) }
        }
        if let device = object(context, "outputDevice") as? NSObject,
           let name = receiverLabel(device, fallback: fallback) {
            return name
        }
        return useful(object(context, "deviceName") as? String)
    }

    private static func receiverLabel(_ device: NSObject, fallback: String?) -> String? {
        guard let name = useful(object(device, "name") as? String)
                ?? useful(object(device, "deviceName") as? String) ?? fallback else { return nil }
        let identifier = (object(device, "modelID") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = identifier.flatMap { modelNames[$0.lowercased()] }
        noteModel(identifier, model: model)
        guard let model else { return name }
        // Preserve existing user labels without adding the model twice.
        if name.range(of: model, options: .caseInsensitive) != nil { return name }
        return "\(name) (\(model))"
    }

    private static func noteModel(_ identifier: String?, model: String?) {
        let identifier = String((identifier?.isEmpty == false ? identifier! : "unavailable").prefix(64))
        lock.lock()
        if reportedModels.count >= 32 { reportedModels.removeAll() }
        let first = reportedModels.insert(identifier).inserted
        lock.unlock()
        if first { writeDebugLog("[Connect][receiver] Model identifier=\(identifier); label=\(model ?? "unknown")") }
    }

    private static func object(_ receiver: NSObject, _ name: String) -> AnyObject? {
        let selector = NSSelectorFromString(name)
        guard let method = class_getInstanceMethod(type(of: receiver), selector), returnsObject(method) else { return nil }
        return receiver.perform(selector)?.takeUnretainedValue()
    }

    private static func returnsObject(_ method: Method) -> Bool {
        guard method_getNumberOfArguments(method) == 2 else { return false }
        let type = method_copyReturnType(method)
        defer { free(type) }
        return type.pointee == 64 // Objective-C object return type '@'.
    }

    private static func useful(_ value: String?) -> String? {
        guard let name = value?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        var generic: Set<String> = ["airplay", "airplay audio", "airplay device", "iphone", "ipad", "ipod touch"]
        generic.insert(UIDevice.current.model.lowercased())
        let phoneName = SpotifyConnectDeviceName.launchName.lowercased()
        if !phoneName.isEmpty { generic.insert(phoneName) }
        return generic.contains(name.lowercased()) ? nil : name
    }

    private static func joined(_ names: [String]) -> String? {
        let names = Array(Set(names)).sorted()
        return names.isEmpty ? nil : names.joined(separator: " + ")
    }

    private static func note(_ key: String, _ message: String) {
        lock.lock()
        let changed = lastResolution != key
        lastResolution = key
        lock.unlock()
        if changed { writeDebugLog("[Connect][receiver] \(message)") }
    }
}
