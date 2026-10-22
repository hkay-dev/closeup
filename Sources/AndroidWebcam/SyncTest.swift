import AVFoundation
import CoreVideo
import Foundation

struct SyncTestResult { let videoLagMs: Double }   // positive: video reaches the Mac later than sound does

enum SyncTestError: LocalizedError {
    case microphoneDenied, noClapHeard, noMotionSeen

    var errorDescription: String? {
        switch self {
        case .microphoneDenied: return "Microphone access is off for \(appName). Turn it on in Microphone settings, then test again."
        case .noClapHeard: return "No clap was heard. Clap once, sharply, near the microphone."
        case .noMotionSeen: return "The clap wasn't seen. Keep the webcam live and clap in the middle of the picture."
        }
    }
}

/// Clap test (zt1n): records the default mic and the webcam frames, finds the clap in each,
/// and reports how much later the video arrives than the sound. Call start and cancel on main.
final class SyncTest {
    private struct Sample { let hostTime: UInt64; let value: Float }

    private static let gridColumns = 48, gridRows = 27
    /// Audio is measured in hops of this length.
    private static let hopSeconds = 0.0025
    /// The first sharp sound must be this loud (RMS of one hop, about -30 dBFS)...
    private static let minClapPower: Float = 0.03 * 0.03
    /// ...and at least this many times the mean power of the 100 ms before it (15 dB).
    private static let clapRise: Float = 31.6
    private static let clapHistoryHops = 40

    /// What the window shows while the test listens.
    struct Meter: Equatable {
        var level: Float = 0        // 0 (-60 dBFS or quieter) to 1 (full scale), loudest hop of the last 100 ms
        var progress: Double = 0    // share of the listening time used
        var heard = false           // the clap was heard; the test is waiting for the video around it
    }

    /// The microphone the test listens to, as macOS names it.
    static var microphoneName: String? { AVCaptureDevice.default(for: .audio)?.localizedName }

    /// Called on main about 20 times a second while recording.
    var onMeter: ((Meter) -> Void)?

    /// The longest it listens for the clap.
    private let duration: TimeInterval
    /// Video after the clap that motionPeak looks at, plus a little for the last frames to arrive.
    private static let afterClap = 1.6
    private let lock = NSLock()
    private var engine: AVAudioEngine?
    private var meterTimer: Timer?
    private var completion: ((Result<SyncTestResult, Error>) -> Void)?
    private var configObserver: NSObjectProtocol?
    private var generation = 0
    // Guarded by lock.
    private var recording = false
    private var startTime: UInt64 = 0
    private var sound: [Sample] = []      // power of each hop, stamped with the time it reached the mic
    private var motion: [Sample] = []     // mean absolute luma difference from the previous frame
    private var grid = [UInt8](repeating: 0, count: SyncTest.gridColumns * SyncTest.gridRows)
    private var gridWidth = 0, gridHeight = 0
    private var clap: UInt64?             // when the clap reached the mic, once heard

    init(duration: TimeInterval = 8) { self.duration = duration }

    /// Listens until the clap and the video after it are in, or `duration` passes. Completion on main;
    /// cancel() ends the test without calling it.
    func start(completion: @escaping (Result<SyncTestResult, Error>) -> Void) {
        cancel()
        let generation = self.generation
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            DispatchQueue.main.async { self.record(generation, completion) }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    guard generation == self.generation else { return }
                    if granted { self.record(generation, completion) } else { completion(.failure(SyncTestError.microphoneDenied)) }
                }
            }
        default:
            DispatchQueue.main.async { completion(.failure(SyncTestError.microphoneDenied)) }
        }
    }

    /// Any thread; hostTime is mach_absolute_time() when the frame arrived.
    func addFrame(_ frame: CVPixelBuffer, hostTime: UInt64) {
        lock.lock(); defer { lock.unlock() }
        guard recording, CVPixelBufferGetPlaneCount(frame) >= 1 else { return }
        CVPixelBufferLockBaseAddress(frame, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(frame, .readOnly) }
        guard let luma = CVPixelBufferGetBaseAddressOfPlane(frame, 0)?.assumingMemoryBound(to: UInt8.self) else { return }
        let width = CVPixelBufferGetWidthOfPlane(frame, 0), height = CVPixelBufferGetHeightOfPlane(frame, 0)
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(frame, 0)
        let fresh = width != gridWidth || height != gridHeight
        gridWidth = width; gridHeight = height
        // One luma sample at the center of each grid cell over the middle 60% of the picture.
        var total = 0, index = 0
        for row in 0..<Self.gridRows {
            let y = height / 5 + (row * 2 + 1) * height * 3 / (10 * Self.gridRows)
            for column in 0..<Self.gridColumns {
                let x = width / 5 + (column * 2 + 1) * width * 3 / (10 * Self.gridColumns)
                let value = luma[y * rowBytes + x]
                total += abs(Int(value) - Int(grid[index]))
                grid[index] = value
                index += 1
            }
        }
        if !fresh { motion.append(Sample(hostTime: hostTime, value: Float(total) / Float(index))) }
    }

    func cancel() {
        meterTimer?.invalidate()
        meterTimer = nil
        completion = nil
        generation += 1
        stopEngine()
        lock.lock(); recording = false; sound = []; motion = []; clap = nil; lock.unlock()
    }

    private func record(_ generation: Int, _ completion: @escaping (Result<SyncTestResult, Error>) -> Void) {
        guard generation == self.generation else { return }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            completion(.failure(WebcamError(message: "No microphone is available.")))
            return
        }
        let sampleRate = format.sampleRate
        let hop = max(1, Int(sampleRate * Self.hopSeconds))
        // Buffer times are when the IO cycle ran; the sound reached the mic one input latency earlier.
        let latency = AVAudioTime.hostTime(forSeconds: max(0, input.presentationLatency))
        lock.lock()
        sound = []; motion = []; gridWidth = 0; gridHeight = 0; clap = nil
        sound.reserveCapacity(Int(duration / Self.hopSeconds) + 1000)
        motion.reserveCapacity(Int((duration + Self.afterClap) * 120))
        lock.unlock()
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, when in
            self?.addAudio(buffer, when: when, hop: hop, sampleRate: sampleRate, latency: latency)
        }
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            completion(.failure(error))
            return
        }
        self.engine = engine
        self.completion = completion
        // The engine stops by itself when the input device or its format changes, and only says so here.
        configObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            guard let self, let completion = self.completion else { return }
            self.cancel()
            completion(.failure(WebcamError(message: "The microphone changed during the test. Test again.")))
        }
        lock.lock(); recording = true; startTime = mach_absolute_time(); lock.unlock()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        meterTimer = timer
    }

    /// Updates the meter, looks for the clap, and ends the test once the video after the clap is in.
    private func tick() {
        let now = mach_absolute_time()
        lock.lock()
        // Audio arrives in IO buffers stamped a buffer and an input latency back, so look further than one tick.
        let window = AVAudioTime.hostTime(forSeconds: 0.1)
        var peak: Float = 0
        for sample in sound.reversed() {
            guard sample.hostTime &+ window >= now else { break }
            peak = max(peak, sample.value)
        }
        if clap == nil {
            // Skip the first 200 ms, where starting the mic can click.
            clap = Self.soundOnset(sound, after: startTime &+ AVAudioTime.hostTime(forSeconds: 0.2))
        }
        let heard = clap, start = startTime
        lock.unlock()
        let elapsed = AVAudioTime.seconds(forHostTime: now &- start)
        let decibels = peak > 0 ? 10 * log10(peak) : -60
        onMeter?(Meter(level: max(0, min(1, (decibels + 60) / 60)),
                       progress: min(1, elapsed / duration), heard: heard != nil))
        if let heard {
            if now >= heard &+ AVAudioTime.hostTime(forSeconds: Self.afterClap) { finish() }
        } else if elapsed >= duration {
            finish()
        }
    }

    private func addAudio(_ buffer: AVAudioPCMBuffer, when: AVAudioTime, hop: Int, sampleRate: Double, latency: UInt64) {
        guard let samples = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        let base = (when.isHostTimeValid ? when.hostTime : mach_absolute_time()) &- latency
        lock.lock(); defer { lock.unlock() }
        guard recording else { return }
        var offset = 0
        while offset < count {
            let end = min(offset + hop, count)
            var power: Float = 0
            for i in offset..<end { power += samples[i] * samples[i] }
            let time = base &+ AVAudioTime.hostTime(forSeconds: Double(offset) / sampleRate)
            sound.append(Sample(hostTime: time, value: power / Float(end - offset)))
            offset = end
        }
    }

    private func stopEngine() {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver); self.configObserver = nil }
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
    }

    private func finish() {
        meterTimer?.invalidate()
        meterTimer = nil
        stopEngine()
        guard let completion else { return }
        self.completion = nil
        lock.lock()
        recording = false
        let sound = self.sound, motion = self.motion, start = startTime, heard = clap
        self.sound = []; self.motion = []; clap = nil
        lock.unlock()
        // Skip the first 200 ms, where starting the mic can click.
        guard let clap = heard ?? Self.soundOnset(sound, after: start &+ AVAudioTime.hostTime(forSeconds: 0.2)) else {
            completion(.failure(SyncTestError.noClapHeard))
            return
        }
        guard let seen = Self.motionPeak(motion, near: clap) else {
            completion(.failure(SyncTestError.noMotionSeen))
            return
        }
        let lag = (AVAudioTime.seconds(forHostTime: seen) - AVAudioTime.seconds(forHostTime: clap)) * 1000
        completion(.success(SyncTestResult(videoLagMs: lag)))
    }

    /// The first hop that is loud and far louder than the 100 ms before it.
    private static func soundOnset(_ sound: [Sample], after start: UInt64) -> UInt64? {
        for i in sound.indices where sound[i].hostTime >= start && sound[i].value >= minClapPower {
            let from = max(0, i - clapHistoryHops)
            guard i - from >= clapHistoryHops / 4 else { continue }
            let before = sound[from..<i].reduce(Float(0)) { $0 + $1.value } / Float(i - from)
            if sound[i].value >= before * clapRise { return sound[i].hostTime }
        }
        return nil
    }

    /// The frame where the hands meet: the first sharp rise in motion from 0.5 s before the sound to 1.5 s
    /// after it, followed up to the top of that rise. Hands move fastest just before they meet and stop
    /// when they touch, so the top of the first burst is the contact, not the start of the swing.
    private static func motionPeak(_ motion: [Sample], near clap: UInt64) -> UInt64? {
        guard motion.count >= 3 else { return nil }
        let median = motion.map(\.value).sorted()[motion.count / 2]
        let threshold = max(median * 3, median + 2)
        let before = AVAudioTime.hostTime(forSeconds: 0.5)
        let from = clap > before ? clap - before : 0
        let to = clap &+ AVAudioTime.hostTime(forSeconds: 1.5)
        guard var peak = motion.firstIndex(where: { $0.hostTime >= from && $0.hostTime <= to && $0.value > threshold })
        else { return nil }
        while peak + 1 < motion.count && motion[peak + 1].value > motion[peak].value { peak += 1 }
        return motion[peak].hostTime
    }
}
