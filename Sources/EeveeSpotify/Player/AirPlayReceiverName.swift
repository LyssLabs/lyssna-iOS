import AVFoundation
import Foundation
import ObjectiveC.runtime
import UIKit

/// Public audio ports can be named only "AirPlay". WebKit uses AVOutputContext
/// for richer selected-receiver names; resolve this private SPI only when present.
/// https://github.com/WebKit/WebKit/blob/main/Source/WebCore/PAL/pal/avfoundation/OutputContext.mm
enum AirPlayReceiverName {
    private static let lock = NSLock()
    private static var lastResolution: String?
    private static let lookupKey = "com.eevee.airplayReceiverLookup"

    static func name(for ports: [AVAudioSessionPortDescription]) -> String? {
        guard !ports.isEmpty, ports.allSatisfy({ $0.portType == .airPlay }) else { return nil }
        let publicNames = ports.map { $0.portName.trimmingCharacters(in: .whitespacesAndNewlines) }
        if publicNames.allSatisfy({ useful($0) != nil }) {
            return joined(publicNames)
        }
        // A framework lookup can itself ask UIDevice for a name. Do not recurse
        // through our UIDevice.name hook while resolving the output context.
        let thread = Thread.current.threadDictionary
        guard thread[lookupKey] as? Bool != true else { return nil }
        thread[lookupKey] = true
        defer { thread.removeObject(forKey: lookupKey) }
        if let name = contextName() {
            note("context:" + name, "Resolved selected AirPlay receiver name from AVOutputContext")
            return name
        }
        note("fallback", "AirPlay receiver metadata unavailable; using public port name")
        return joined(publicNames.filter { !$0.isEmpty })
    }

    private static func contextName() -> String? {
        let selector = NSSelectorFromString("sharedAudioPresentationOutputContext")
        guard let cls = NSClassFromString("AVOutputContext"),
              let method = class_getClassMethod(cls, selector), returnsObject(method) else { return nil }
        typealias ContextGetter = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
        let getter = unsafeBitCast(method_getImplementation(method), to: ContextGetter.self)
        guard let context = getter(cls as AnyObject, selector)?.takeUnretainedValue() as? NSObject else { return nil }

        if let devices = object(context, "outputDevices") as? [NSObject], !devices.isEmpty {
            let names = devices.map { device -> String? in
                useful(object(device, "name") as? String) ?? useful(object(device, "deviceName") as? String)
            }
            // Do not drop unnamed members from a multi-room output.
            if names.allSatisfy({ $0 != nil }) { return joined(names.compactMap { $0 }) }
            if devices.count > 1 { return useful(object(context, "deviceName") as? String) }
        }
        if let device = object(context, "outputDevice") as? NSObject,
           let name = useful(object(device, "name") as? String) ?? useful(object(device, "deviceName") as? String) {
            return name
        }
        return useful(object(context, "deviceName") as? String)
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
