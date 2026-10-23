import Foundation
import CoreMedia
import CoreMediaIO
import CoreVideo
import os

final class VirtualCamera {
    static let obsUID = "7626645E-4425-469E-9D8B-97E0FA59AC75"
    private let device: CMIODeviceID
    private let stream: CMIOStreamID
    private var queue: CMSimpleQueue?
    private var started = false
    private let sampler: FrameSampler
    private let lock = NSLock()

    private static func address(_ selector: Int) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(mSelector: UInt32(selector), mScope: UInt32(kCMIOObjectPropertyScopeGlobal),
                                  mElement: UInt32(kCMIOObjectPropertyElementMain))
    }

    private static func objectIDs(_ object: CMIOObjectID, selector: Int) throws -> [CMIOObjectID] {
        var property = address(selector)
        var size: UInt32 = 0, used: UInt32 = 0
        try checkStatus(CMIOObjectGetPropertyDataSize(object, &property, 0, nil, &size), "Reading camera device metadata", Plain.obs)
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        try ids.withUnsafeMutableBytes {
            try checkStatus(CMIOObjectGetPropertyData(object, &property, 0, nil, size, &used, $0.baseAddress), "Reading camera device identifiers", Plain.obs)
        }
        return ids
    }

    private static let lookupLog = Logger(subsystem: "com.harsha.closeup", category: "obs-lookup")
    private static let lookups = OSAllocatedUnfairLock(initialState: 0)

    /// Logs one line per lookup with a running count, so `log stream --level info` can show how often it runs.
    static func findDevice() throws -> CMIODeviceID {
        let count = lookups.withLock { n -> Int in n += 1; return n }
        lookupLog.info("CoreMediaIO device lookup #\(count)")
        for device in try objectIDs(CMIOObjectID(kCMIOObjectSystemObject), selector: kCMIOHardwarePropertyDevices) {
            var property = address(kCMIODevicePropertyDeviceUID)
            var uid: Unmanaged<CFString>?
            var used: UInt32 = 0
            let status = CMIOObjectGetPropertyData(device, &property, 0, nil,
                UInt32(MemoryLayout<Unmanaged<CFString>?>.size), &used, &uid)
            if status == noErr, let uid, uid.takeRetainedValue() as String == obsUID { return device }
        }
        throw WebcamError(message: "OBS's camera extension isn't installed or approved. Open Setup from the menu to finish it.")
    }

    static let obsExtensionBundleID = "com.obsproject.obs-studio.mac-camera-extension"

    enum ExtensionState {
        case missing
        case ready
        /// macOS has the extension on, but this process's CoreMediaIO device list was built before that and never updates.
        case staleInThisProcess
    }

    /// CoreMediaIO builds a process's device list when the process first asks, and a camera extension approved later
    /// never reaches it: not through a fresh lookup, an AVFoundation discovery session, a property listener, the
    /// DAL run loop property, nor waiting; CMIOHardwareUnload kills the list for good. Only a new process sees the
    /// device, so a miss is checked against what macOS says about the extension.
    static func extensionState() -> ExtensionState {
        if (try? findDevice()) != nil { return .ready }
        return systemExtensionEnabled() ? .staleInThisProcess : .missing
    }

    private static func systemExtensionEnabled() -> Bool {
        let count = lookups.withLock { n -> Int in n += 1; return n }
        lookupLog.info("System extension check (lookup #\(count))")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/systemextensionsctl")
        process.arguments = ["list"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: output, as: UTF8.self).split(separator: "\n")
            .contains { $0.contains(obsExtensionBundleID) && $0.contains("[activated enabled]") }
    }

    init(fps: Int32) throws {
        sampler = FrameSampler(fps: fps)
        device = try Self.findDevice()
        // OBS has a source stream that apps read (direction 1) and a sink stream this app writes (direction 0).
        guard let sink = try Self.objectIDs(device, selector: kCMIODevicePropertyStreams).first(where: { candidate in
            var property = VirtualCamera.address(kCMIOStreamPropertyDirection)
            var direction: UInt32 = 1
            var used: UInt32 = 0
            let status = CMIOObjectGetPropertyData(candidate, &property, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &direction)
            return status == noErr && direction == 0
        }) else { throw WebcamError(message: Plain.obs, detail: "The OBS camera sink stream is missing.") }
        stream = sink
        var copiedQueue: Unmanaged<CMSimpleQueue>?
        try checkStatus(CMIOStreamCopyBufferQueue(stream, { _, _, _ in }, nil, &copiedQueue), "Opening the camera buffer queue", Plain.obs)
        queue = copiedQueue?.takeRetainedValue()
        guard queue != nil else { throw WebcamError(message: Plain.obs, detail: "The OBS camera buffer queue is unavailable.") }
        try checkStatus(CMIODeviceStartStream(device, stream), "Starting the OBS camera sink", Plain.obs)
        started = true
    }

    func send(_ frame: CVPixelBuffer) throws {
        lock.lock(); defer { lock.unlock() }
        guard let queue, started else { return }
        // Keep latency bounded when the consumer is not draining its queue.
        guard CMSimpleQueueGetCount(queue) < CMSimpleQueueGetCapacity(queue) else { return }
        let sample = try sampler.sample(frame)
        let retained = Unmanaged.passRetained(sample)
        let status = CMSimpleQueueEnqueue(queue, element: UnsafeRawPointer(retained.toOpaque()))
        if status != noErr {
            retained.release()
            try checkStatus(status, "Publishing a webcam frame", Plain.obs)
        }
    }

    func stop() {
        lock.lock(); defer { lock.unlock() }
        if started { CMIODeviceStopStream(device, stream); started = false }
        queue = nil
    }
    deinit { stop() }
}
