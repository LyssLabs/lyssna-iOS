import AVFoundation
import CommonCrypto
import Foundation
import ObjectiveC.runtime
import Orion
import UIKit

struct SpotifyConnectPublicationGroup: HookGroup {}
struct SpotifyConnectCoreNameGroup: HookGroup {}
struct SpotifyConnectPublicationResponseGroup: HookGroup {}

/// Rewrites the phone's own published descriptor, never its Connect ID or commands.
/// Field numbers and enum values are verified against the 9.2.0 IPA descriptors.
/// Reference: librespot-org/librespot/protocol/proto/{connect,devices}.proto.
enum SpotifyConnectPublication {
    private static let lock = NSLock()
    private static var physicalTypes: [String: Field] = [:]
    private static var notices = Set<String>()
    private static var lastPublishedRoute: String?

    static func activate() {
        let cls = type(of: URLSession.shared)
        let selectors = ["dataTaskWithRequest:", "dataTaskWithRequest:completionHandler:",
                         "uploadTaskWithRequest:fromData:", "uploadTaskWithRequest:fromData:completionHandler:"]
        if selectors.allSatisfy({ class_getInstanceMethod(cls, NSSelectorFromString($0)) != nil }) {
            SpotifyConnectPublicationGroup().activate()
            writeDebugLog("[Connect][publish] Attached request hooks to \(NSStringFromClass(cls))")
        }
        if let config = NSClassFromString("SPTCoreFullAuthenticatedScopeConfiguration"),
           class_getInstanceMethod(config, NSSelectorFromString("deviceName")) != nil {
            SpotifyConnectCoreNameGroup().activate()
        }
        if let delegate = NSClassFromString("SPTCoreURLSessionDataDelegate"),
           class_getInstanceMethod(delegate, NSSelectorFromString("URLSession:dataTask:didReceiveResponse:completionHandler:")) != nil,
           class_getInstanceMethod(delegate, NSSelectorFromString("URLSession:task:didCompleteWithError:")) != nil {
            SpotifyConnectPublicationResponseGroup().activate()
        }
    }

    private static func notice(_ key: String, _ message: String) {
        lock.lock()
        let first = notices.insert(key).inserted
        lock.unlock()
        if first { writeDebugLog("[Connect][publish] \(message)") }
    }

    private static func eligible(_ request: URLRequest) -> Bool {
        guard let url = request.url, url.scheme == "https", request.httpMethod == "PUT",
              let host = url.host?.lowercased(),
              host == "spclient.wg.spotify.com" || host.hasSuffix("-spclient.spotify.com") else { return false }
        let parts = url.pathComponents
        return parts.count == 5 && parts[1...3].elementsEqual(["connect-state", "v1", "devices"])
    }

    static func request(_ original: URLRequest) -> URLRequest {
        guard eligible(original) else { return original }
        guard let body = original.httpBody else {
            notice("no-body", "Request has no inline body; waiting for a data upload or full state update")
            return original
        }
        guard let changed = rewrite(body, request: original) else { return original }
        var result = original
        result.httpBody = changed
        updateBodyHeaders(&result, body: changed)
        return result
    }

    static func upload(_ original: URLRequest, data: Data?) -> (URLRequest, Data?) {
        guard eligible(original), let data, let changed = rewrite(data, request: original) else { return (original, data) }
        var result = original
        updateBodyHeaders(&result, body: changed)
        return (result, changed)
    }

    private static func updateBodyHeaders(_ request: inout URLRequest, body: Data) {
        if request.value(forHTTPHeaderField: "Content-Length") != nil {
            request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
        }
        if request.value(forHTTPHeaderField: "Content-MD5") != nil {
            // Legacy HTTP Content-MD5 covers the encoded entity, not decoded protobuf.
            var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
            body.withUnsafeBytes { _ = CC_MD5($0.baseAddress, CC_LONG(body.count), &digest) }
            request.setValue(Data(digest).base64EncodedString(), forHTTPHeaderField: "Content-MD5")
        }
    }

    static func recordResponse(for request: URLRequest?, response: URLResponse? = nil, error: Error? = nil) {
        guard let request, eligible(request) else { return }
        if let response = response as? HTTPURLResponse {
            writeDebugLog("[Connect][publish] Server response HTTP \(response.statusCode)")
        }
        if let error = error as NSError? {
            writeDebugLog("[Connect][publish] Request failed: \(error.domain) \(error.code)")
        }
    }

    private static func rewrite(_ body: Data, request: URLRequest) -> Data? {
        let encoding = request.value(forHTTPHeaderField: "Content-Encoding")?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "identity"
        let supported = ["", "identity", "gzip", "x-gzip", "deflate"].contains(encoding)
        let hasMD5 = request.value(forHTTPHeaderField: "Content-MD5") != nil
        let hasDigest = request.value(forHTTPHeaderField: "Digest") != nil
            || request.value(forHTTPHeaderField: "Content-Digest") != nil
            || request.value(forHTTPHeaderField: "Repr-Digest") != nil
        let coding = supported ? encoding : "unsupported"
        notice("coding:\(coding):\(hasMD5):\(hasDigest)", "Request coding=\(coding), Content-MD5=\(hasMD5), other digest=\(hasDigest)")
        guard supported, !hasDigest else {
            notice("coding-skip", "Skipped unsupported coding or non-MD5 digest header")
            return nil
        }
        let compressed = !encoding.isEmpty && encoding != "identity"
        let gzip = encoding == "gzip" || encoding == "x-gzip"
        let decoded: Data
        if compressed {
            guard let expanded = SpotifyConnectContentCoding.decode(body, gzip: gzip) else {
                notice("decode", "Content decoding failed; kept original publication")
                return nil
            }
            decoded = expanded
        } else { decoded = body }
        guard let changed = rewriteState(decoded, request: request) else { return nil }
        guard compressed else { return changed }
        guard let encoded = SpotifyConnectContentCoding.encode(changed, gzip: gzip) else {
            notice("encode", "Content re-encoding failed; kept original publication")
            return nil
        }
        notice("reencoded", "Re-encoded modified Connect publication successfully")
        return encoded
    }

    private static func rewriteState(_ body: Data, request: URLRequest) -> Data? {
        // PutStateRequest.device(2).device_info(1), not the similarly named ads message.
        guard body.count <= 4 * 1024 * 1024, let state = fields(body),
              let deviceData = unique(2, in: state)?.bytes, let device = fields(deviceData),
              let infoData = unique(1, in: device)?.bytes, let info = fields(infoData),
              let idData = unique(10, in: info)?.bytes, let id = String(data: idData, encoding: .utf8),
              !id.isEmpty, id == request.url?.lastPathComponent,
              let advertisedType = unique(7, in: info), let type = advertisedType.integer else {
            notice("shape", "Skipped publication without matching full phone DeviceInfo")
            return nil
        }
        lock.lock()
        // Only smartphone/tablet descriptors seed this cache. Re-entrant factory
        // calls and retries can already contain our SPEAKER (4) replacement.
        if physicalTypes[id] == nil, type == 2 || type == 3 {
            if physicalTypes.count >= 16 { physicalTypes.removeAll() }
            physicalTypes[id] = advertisedType
        }
        let physicalType = physicalTypes[id]
        lock.unlock()
        guard let physicalType else {
            notice("type", "Skipped descriptor that is not a known phone or tablet")
            return nil
        }

        let airPlayName = PlaybackAudioRoute.airPlayName
        let name = airPlayName ?? (SpotifyConnectDeviceName.launchName.isEmpty
            ? UIDevice.current.name : SpotifyConnectDeviceName.launchName)
        let ports = AVAudioSession.sharedInstance().currentRoute.outputs
        let bluetooth: Set<AVAudioSession.Port> = [.bluetoothA2DP, .bluetoothHFP, .bluetoothLE]
        let outputType: UInt64
        if airPlayName != nil { outputType = 4 } // AudioOutputDeviceType.AIRPLAY
        else if ports.contains(where: { bluetooth.contains($0.portType) }) { outputType = 3 }
        else if ports.contains(where: { $0.portType == .carAudio }) { outputType = 5 }
        else if ports.allSatisfy({ $0.portType == .builtInSpeaker || $0.portType == .builtInReceiver }) { outputType = 1 }
        else { outputType = 2 }
        let outputName = airPlayName ?? ports.map(\.portName).sorted().joined(separator: ", ")
        let previousOutput: [Field]
        if let previous = unique(24, in: info)?.bytes {
            guard let parsed = fields(previous) else { return nil }
            previousOutput = parsed
        } else { previousOutput = [] }
        let output = excluding([1, 2], in: previousOutput) + integer(1, outputType) + bytes(2, Data(outputName.utf8))
        // DeviceType.SPEAKER is 4, whereas DeviceType.SMARTPHONE is 3.
        let changedInfo = excluding([3, 7, 24], in: info) + bytes(3, Data(name.utf8))
            + (airPlayName == nil ? physicalType.raw : integer(7, 4))
            + (ports.isEmpty ? (unique(24, in: info)?.raw ?? Data()) : bytes(24, output))
        let changedDevice = replacing(1, in: device, with: bytes(1, changedInfo))
        // Otherwise Spotify's server can ignore the updated device descriptor.
        let changedState = excluding([2, 13], in: state) + bytes(2, changedDevice)

        let route = airPlayName.map { "airplay:" + $0 } ?? "phone"
        lock.lock()
        let report = lastPublishedRoute != route
        lastPublishedRoute = route
        lock.unlock()
        if report {
            writeDebugLog(airPlayName == nil
                ? "[Connect][publish] Rewrote outgoing phone/tablet name and original type"
                : "[Connect][publish] Rewrote outgoing AirPlay receiver name and SPEAKER type (4)")
        }
        return changedState
    }

    private struct Field {
        let number: Int
        let integer: UInt64?
        let bytes: Data?
        let raw: Data
    }

    /// Preserve unknown fields verbatim. Reject malformed/unsupported messages.
    private static func fields(_ data: Data) -> [Field]? {
        let input = [UInt8](data)
        var index = 0, result: [Field] = []
        func read() -> UInt64? {
            var value: UInt64 = 0
            for shift in stride(from: 0, through: 63, by: 7) {
                guard index < input.count else { return nil }
                let byte = input[index]; index += 1
                guard shift != 63 || byte <= 1 else { return nil }
                value |= UInt64(byte & 127) << shift
                if byte < 128 { return value }
            }
            return nil
        }
        while index < input.count {
            let start = index
            guard result.count < 8192, let tag = read(), tag >> 3 > 0, tag >> 3 <= 536870911 else { return nil }
            var value: UInt64?, payload: Data?
            switch tag & 7 {
            case 0:
                guard let number = read() else { return nil }
                value = number
            case 1:
                guard input.count - index >= 8 else { return nil }; index += 8
            case 2:
                guard let count = read(), count <= UInt64(input.count - index) else { return nil }
                payload = Data(input[index..<(index + Int(count))]); index += Int(count)
            case 5:
                guard input.count - index >= 4 else { return nil }; index += 4
            default: return nil
            }
            result.append(Field(number: Int(tag >> 3), integer: value, bytes: payload, raw: Data(input[start..<index])))
        }
        return result
    }

    private static func unique(_ number: Int, in fields: [Field]) -> Field? {
        let matches = fields.filter { $0.number == number }
        return matches.count == 1 ? matches[0] : nil
    }

    private static func varint(_ number: UInt64) -> Data {
        var number = number, data = Data()
        repeat {
            let byte = UInt8(number & 127); number >>= 7
            data.append(number == 0 ? byte : byte | 128)
        } while number != 0
        return data
    }

    private static func bytes(_ field: Int, _ value: Data) -> Data {
        varint(UInt64(field << 3 | 2)) + varint(UInt64(value.count)) + value
    }

    private static func integer(_ field: Int, _ value: UInt64) -> Data { varint(UInt64(field << 3)) + varint(value) }

    private static func replacing(_ number: Int, in fields: [Field], with value: Data?) -> Data {
        excluding([number], in: fields) + (value ?? Data())
    }

    private static func excluding(_ numbers: Set<Int>, in fields: [Field]) -> Data {
        fields.filter { !numbers.contains($0.number) }.reduce(into: Data()) { $0.append($1.raw) }
    }
}

class SpotifyConnectCoreNameHook: ClassHook<NSObject> {
    typealias Group = SpotifyConnectCoreNameGroup
    static let targetName = "SPTCoreFullAuthenticatedScopeConfiguration"
    func deviceName() -> String { SpotifyConnectDeviceName.reportedName ?? UIDevice.current.name }
}

class SpotifyConnectPublicationResponseHook: ClassHook<NSObject> {
    typealias Group = SpotifyConnectPublicationResponseGroup
    static let targetName = "SPTCoreURLSessionDataDelegate"

    @objc(URLSession:dataTask:didReceiveResponse:completionHandler:)
    func URLSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        SpotifyConnectPublication.recordResponse(for: dataTask.currentRequest ?? dataTask.originalRequest, response: response)
        orig.URLSession(session, dataTask: dataTask, didReceive: response, completionHandler: completionHandler)
    }

    @objc(URLSession:task:didCompleteWithError:)
    func URLSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        SpotifyConnectPublication.recordResponse(for: task.currentRequest ?? task.originalRequest, error: error)
        orig.URLSession(session, task: task, didCompleteWithError: error)
    }
}

class SpotifyConnectPublicationHook: ClassHook<URLSession> {
    typealias Group = SpotifyConnectPublicationGroup
    static let targetName = NSStringFromClass(type(of: URLSession.shared))

    @objc(dataTaskWithRequest:)
    func dataTask(with request: URLRequest) -> URLSessionDataTask {
        orig.dataTask(with: SpotifyConnectPublication.request(request))
    }

    @objc(dataTaskWithRequest:completionHandler:)
    func dataTask(with request: URLRequest, completionHandler: ((Data?, URLResponse?, Error?) -> Void)?) -> URLSessionDataTask {
        orig.dataTask(with: SpotifyConnectPublication.request(request), completionHandler: completionHandler)
    }

    @objc(uploadTaskWithRequest:fromData:)
    func uploadTask(with request: URLRequest, from bodyData: Data?) -> URLSessionUploadTask {
        let (request, data) = SpotifyConnectPublication.upload(request, data: bodyData)
        return orig.uploadTask(with: request, from: data)
    }

    @objc(uploadTaskWithRequest:fromData:completionHandler:)
    func uploadTask(with request: URLRequest, from bodyData: Data?, completionHandler: ((Data?, URLResponse?, Error?) -> Void)?) -> URLSessionUploadTask {
        let (request, data) = SpotifyConnectPublication.upload(request, data: bodyData)
        return orig.uploadTask(with: request, from: data, completionHandler: completionHandler)
    }
}
