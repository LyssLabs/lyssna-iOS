import AVFoundation
import Combine
import UIKit

/// One calibration per audio output, independent of the current song.
final class PlaybackAudioRoute: ObservableObject {
    struct Output: Equatable {
        let id: String
        let name: String
    }

    static let shared = PlaybackAudioRoute()
    private static let offsetsKey = "lyssnaLyricsOffsetsByOutput"
    @Published private(set) var output: Output
    @Published private(set) var timingOffsetMs: Double
    private var offsets: [String: Double]
    private var remoteOutput: Output?
    private var routeObserver: NSObjectProtocol?
    private var modelObserver: NSObjectProtocol?

    private init() {
        let current = Self.localOutput()
        output = current
        if let saved = UserDefaults.container.dictionary(forKey: Self.offsetsKey) as? [String: Double] {
            offsets = saved.mapValues(Self.clamped)
        } else {
            // The old global value has no output identity. Keep it in the old
            // settings so the user can explicitly apply it to the right output.
            offsets = [:]
            UserDefaults.container.set(offsets, forKey: Self.offsetsKey)
        }
        timingOffsetMs = offsets[current.id] ?? 0
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }
        modelObserver = NotificationCenter.default.addObserver(
            forName: .lyssnaAirPlayModelChanged, object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }
    }

    deinit {
        if let routeObserver { NotificationCenter.default.removeObserver(routeObserver) }
        if let modelObserver { NotificationCenter.default.removeObserver(modelObserver) }
    }

    private static func clamped(_ value: Double) -> Double {
        value.isFinite ? min(3000, max(-3000, value)) : 0
    }

    private static func localOutput() -> Output {
        let ports = AVAudioSession.sharedInstance().currentRoute.outputs
        let external = ports.filter { $0.portType != .builtInSpeaker && $0.portType != .builtInReceiver }
        guard !external.isEmpty else {
            return Output(id: "local", name: "lyrics_output_this_device".localized)
        }
        // Sorting keeps a multi-speaker route stable when iOS changes port order.
        let identifiers = external.map { $0.uid.isEmpty ? $0.portName : $0.uid }.sorted()
        let encoded = (try? JSONEncoder().encode(identifiers)).flatMap { String(data: $0, encoding: .utf8) }
        return Output(id: "audio:" + (encoded ?? identifiers.joined(separator: "|")),
                      name: AirPlayReceiverName.name(for: ports) ?? external.map(\.portName).sorted().joined(separator: ", "))
    }

    /// Only AirPlay receivers replace the phone's name. Bluetooth headphones
    /// (including AirPods), wired headphones and the built-in output do not.
    static var airPlayName: String? {
        AirPlayReceiverName.name(for: AVAudioSession.sharedInstance().currentRoute.outputs)
    }

    var hasSavedOffsets: Bool { offsets.values.contains { $0 != 0 } }
    var previousGlobalOffsetMs: Double { Self.clamped(UserDefaults.karaokeOptions.timingOffsetMs) }

    func setTimingOffset(_ value: Double) {
        let value = Self.clamped(value)
        if value == 0 { offsets.removeValue(forKey: output.id) }
        else { offsets[output.id] = value }
        UserDefaults.container.set(offsets, forKey: Self.offsetsKey)
        timingOffsetMs = value
    }

    func resetTimingOffsets() {
        offsets = [:]
        UserDefaults.container.set(offsets, forKey: Self.offsetsKey)
        timingOffsetMs = 0
    }

    private func refresh() {
        let next = remoteOutput ?? Self.localOutput()
        if output != next { output = next }
        let offset = offsets[next.id] ?? 0
        if timingOffsetMs != offset { timingOffsetMs = offset }
    }

    /// The Connect state supplies a stable destination ID when playback runs
    /// on another Spotify device rather than through this phone's audio session.
    func updateConnectOutput(_ destination: Output?) {
        let update = { [weak self] in
            guard let self, self.remoteOutput != destination else { return }
            self.remoteOutput = destination
            self.refresh()
        }
        if Thread.isMainThread { update() }
        else { DispatchQueue.main.async(execute: update) }
    }
}
