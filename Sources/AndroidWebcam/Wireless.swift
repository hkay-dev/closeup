import Foundation
import os

/// The hidden switch for phones on wireless debugging (kata:android-webcam#wnmp). Off by default, so the app
/// stays USB only. Turn it on before launching: `defaults write com.harsha.android-webcam wirelessAdb -bool true`,
/// or start the binary with `ANDROID_WEBCAM_WIRELESS=1` (the environment wins, and `0` turns it off).
/// Read once per launch, so every part of the app sees the same answer.
enum Wireless {
    static let defaultsKey = "wirelessAdb"
    static let environmentKey = "ANDROID_WEBCAM_WIRELESS"

    static let enabled: Bool = {
        if let value = ProcessInfo.processInfo.environment[environmentKey] {
            return ["1", "true", "yes", "on"].contains(value.lowercased())
        }
        return UserDefaults.standard.bool(forKey: defaultsKey)
    }()
}

/// One log line per second while capturing, for the wireless latency session. Frames and bytes received, the
/// longest gap between packets, and how far arrival has drifted behind the phone's clock.
///
/// Watch it with `log stream --level info --predicate 'subsystem == "com.harsha.android-webcam" AND category == "wireless-latency"'`.
///
/// The phone and Mac clocks differ, so `behind_ms` is arrival minus pts measured from the least delayed packet
/// seen since capture started. It sits near 0 on a link that keeps up and grows while frames queue. The two
/// clocks also drift a few ms in five minutes, so read the trend, not a single digit.
final class PacketLog {
    private static let log = Logger(subsystem: "com.harsha.android-webcam", category: "wireless-latency")
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "android-webcam.packet-log", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var frames = 0, bytes = 0
    private var longestGap: UInt64 = 0
    private var lastArrival: UInt64?
    private var packetsThisSecond = 0
    private var floorOffset: Int64?
    private var behindLast: Int64?, behindMax: Int64?

    init(label: String) {
        Self.log.info("capture started \(label, privacy: .public)")
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in self?.flush() }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        lock.lock(); let running = timer; timer = nil; lock.unlock()
        running?.cancel()
    }

    /// Called once the whole packet has been read. pts is the phone's capture time in microseconds.
    func record(size: Int, pts: Int64, configuration: Bool) {
        let arrival = DispatchTime.now().uptimeNanoseconds
        lock.lock(); defer { lock.unlock() }
        if let lastArrival { longestGap = max(longestGap, arrival - lastArrival) }
        lastArrival = arrival
        packetsThisSecond += 1
        bytes += size
        guard !configuration else { return }
        frames += 1
        let offset = Int64(arrival / 1000) - pts
        let floor = min(floorOffset ?? offset, offset)
        floorOffset = floor
        let behind = offset - floor
        behindLast = behind
        behindMax = max(behindMax ?? behind, behind)
    }

    private func flush() {
        let now = DispatchTime.now().uptimeNanoseconds
        lock.lock()
        guard let lastArrival else { lock.unlock(); return }    // the camera is still opening
        // A second with no packet at all is one long gap that hasn't ended yet.
        let gap = packetsThisSecond == 0 ? now - lastArrival : longestGap
        let line = "frames=\(frames) bytes=\(bytes) max_gap_ms=\(gap / 1_000_000) "
            + "behind_ms=\(behindLast.map { String($0 / 1000) } ?? "-") behind_max_ms=\(behindMax.map { String($0 / 1000) } ?? "-")"
        frames = 0; bytes = 0; longestGap = 0; packetsThisSecond = 0; behindLast = nil; behindMax = nil
        lock.unlock()
        Self.log.info("\(line, privacy: .public)")
    }
}
