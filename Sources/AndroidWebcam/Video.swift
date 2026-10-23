import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import CoreMedia
import CoreVideo
import VideoToolbox

/// `message` is what the user reads; `detail` keeps the exact failure for the log.
struct WebcamError: LocalizedError {
    let message: String
    var detail: String? = nil
    var errorDescription: String? { message }
}

/// What the user reads when a step they can't see fails.
enum Plain {
    static let decode = "The Mac couldn't decode the phone's video. Start again, and pick a lower capture mode if it keeps happening."
    static let garbled = "The phone's video arrived damaged. Start again, and check the cable if it keeps happening."
    static let obs = "OBS's camera extension isn't taking video. Open OBS, click Start Virtual Camera and then Stop, quit OBS and start again."
    static let frame = "A frame couldn't be prepared for the camera. Start again."
    static let process = "Mac picture processing failed."
}

func checkStatus(_ status: OSStatus, _ operation: String, _ plain: String) throws {
    if status != noErr { throw WebcamError(message: plain, detail: "\(operation) failed (\(status)).") }
}

extension Error {
    /// The exact failure for the log, with the plain message in front when there is a detail behind it.
    var logText: String {
        switch self {
        case let error as WebcamError: return error.detail.map { "\(error.message) [\($0)]" } ?? error.message
        case let error as TransportError: return error.detail.map { "\(error.message) [\($0)]" } ?? error.message
        default: return localizedDescription
        }
    }
}

struct CaptureMode: Equatable {
    let title: String
    let width: Int
    let height: Int
    let fps: Int32
    let bitrate: Int
    static let all = [
        CaptureMode(title: "4K / 60 fps", width: 3840, height: 2160, fps: 60, bitrate: 40_000_000),
        CaptureMode(title: "1080p / 60 fps", width: 1920, height: 1080, fps: 60, bitrate: 20_000_000),
        CaptureMode(title: "1080p / 30 fps", width: 1920, height: 1080, fps: 30, bitrate: 12_000_000),
        CaptureMode(title: "1080p / 120 fps (experimental)", width: 1920, height: 1080, fps: 120, bitrate: 40_000_000)
    ]
}

enum ScrcpyHeader {
    case session(width: Int, height: Int)
    case packet(size: Int, pts: Int64, configuration: Bool)

    init(_ data: Data) throws {
        guard data.count == 12 else { throw WebcamError(message: Plain.garbled, detail: "Incomplete scrcpy packet header.") }
        let bytes = [UInt8](data)
        let flags = bytes[0..<8].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        if flags & (1 << 63) != 0 {
            let width = bytes[4..<8].reduce(0) { ($0 << 8) | Int($1) }
            let height = bytes[8..<12].reduce(0) { ($0 << 8) | Int($1) }
            guard width > 0, height > 0, width <= 8192, height <= 8192 else {
                throw WebcamError(message: Plain.garbled, detail: "Invalid capture dimensions \(width)x\(height) in scrcpy session.")
            }
            self = .session(width: width, height: height)
        } else {
            let size = bytes[8..<12].reduce(0) { ($0 << 8) | Int($1) }
            guard size > 0, size <= 32 * 1024 * 1024 else {
                throw WebcamError(message: Plain.garbled, detail: "Invalid scrcpy packet size \(size).")
            }
            self = .packet(size: size, pts: Int64(flags & ((1 << 61) - 1)), configuration: flags & (1 << 62) != 0)
        }
    }
}

enum AnnexB {
    static func units(_ data: Data) -> [Data] {
        let bytes = [UInt8](data)
        var starts: [(prefix: Int, payload: Int)] = []
        var i = 0
        while i + 2 < bytes.count {
            if bytes[i] == 0, bytes[i + 1] == 0 {
                if bytes[i + 2] == 1 { starts.append((i, i + 3)); i += 3; continue }
                if i + 3 < bytes.count, bytes[i + 2] == 0, bytes[i + 3] == 1 {
                    starts.append((i, i + 4)); i += 4; continue
                }
            }
            i += 1
        }
        return starts.enumerated().compactMap { index, start in
            let end = index + 1 < starts.count ? starts[index + 1].prefix : bytes.count
            return end > start.payload ? Data(bytes[start.payload..<end]) : nil
        }
    }

    static func nalType(_ data: Data) -> Int { Int((data.first ?? 0) >> 1) & 0x3f }

    static func lengthPrefixed(_ units: [Data]) -> Data {
        var result = Data()
        for unit in units {
            var length = UInt32(unit.count).bigEndian
            withUnsafeBytes(of: &length) { result.append(contentsOf: $0) }
            result.append(unit)
        }
        return result
    }
}

final class HEVCDecoder {
    private var format: CMVideoFormatDescription?
    private var session: VTDecompressionSession?
    private var parameterSets: [Int: Data] = [:]
    /// The VPS, SPS and PPS that `format` was built from.
    private var formatParameterSets: [Int: Data] = [:]
    private var firstFrameLogged = false
    let onFrame: (CVPixelBuffer) -> Void
    let onError: (Error) -> Void
    private(set) var hardwareAccelerated = false

    init(onFrame: @escaping (CVPixelBuffer) -> Void, onError: @escaping (Error) -> Void) {
        self.onFrame = onFrame
        self.onError = onError
    }

    func decode(_ payload: Data, pts: Int64) throws {
        let units = AnnexB.units(payload)
        guard !units.isEmpty else { throw WebcamError(message: Plain.garbled, detail: "Expected Annex B HEVC data from the phone.") }
        for unit in units where (32...34).contains(AnnexB.nalType(unit)) {
            parameterSets[AnnexB.nalType(unit)] = unit
        }
        if parameterSets.count == 3, parameterSets != formatParameterSets { try updateFormat() }
        let pictures = units.filter { AnnexB.nalType($0) < 32 }
        guard !pictures.isEmpty else { return }
        guard let session, let format else {
            throw WebcamError(message: Plain.garbled, detail: "HEVC picture arrived before its configuration.")
        }
        let bytes = AnnexB.lengthPrefixed(pictures)
        var block: CMBlockBuffer?
        try checkStatus(CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: bytes.count,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
            offsetToData: 0, dataLength: bytes.count, flags: 0, blockBufferOut: &block
        ), "Creating a video packet buffer", Plain.decode)
        try bytes.withUnsafeBytes {
            try checkStatus(CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block!,
                                                       offsetIntoDestination: 0, dataLength: bytes.count), "Copying a video packet", Plain.decode)
        }
        var timing = CMSampleTimingInfo(duration: .invalid,
            presentationTimeStamp: CMTime(value: pts, timescale: 1_000_000), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        var size = bytes.count
        try checkStatus(CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format, sampleCount: 1,
            sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample
        ), "Creating a HEVC sample", Plain.decode)
        try checkStatus(VTDecompressionSessionDecodeFrame(session, sampleBuffer: sample!,
            flags: [._EnableAsynchronousDecompression], frameRefcon: nil, infoFlagsOut: nil), "Decoding HEVC", Plain.decode)
    }

    /// Builds the format from the latest VPS, SPS and PPS, and replaces the session
    /// when the current one can't decode that format (for example after the phone's encoder restarts).
    private func updateFormat() throws {
        let vps = parameterSets[32]!, sps = parameterSets[33]!, pps = parameterSets[34]!
        var newFormat: CMVideoFormatDescription?
        try vps.withUnsafeBytes { v in try sps.withUnsafeBytes { s in try pps.withUnsafeBytes { p in
            var pointers = [v.bindMemory(to: UInt8.self).baseAddress!, s.bindMemory(to: UInt8.self).baseAddress!, p.bindMemory(to: UInt8.self).baseAddress!]
            var lengths = [vps.count, sps.count, pps.count]
            try checkStatus(CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                allocator: kCFAllocatorDefault, parameterSetCount: 3, parameterSetPointers: &pointers,
                parameterSetSizes: &lengths, nalUnitHeaderLength: 4, extensions: nil,
                formatDescriptionOut: &newFormat), "Reading the HEVC configuration", Plain.garbled)
        } } }
        if session == nil || !VTDecompressionSessionCanAcceptFormatDescription(session!, formatDescription: newFormat!) {
            endSession()
            session = try makeSession(newFormat!)
            firstFrameLogged = false
        }
        format = newFormat
        formatParameterSets = parameterSets
    }

    private func makeSession(_ format: CMVideoFormatDescription) throws -> VTDecompressionSession {
        let specification = [kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder: true] as CFDictionary
        let attributes = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any]
        ] as CFDictionary
        var callback = VTDecompressionOutputCallbackRecord(decompressionOutputCallback: { ref, _, status, _, image, _, _ in
            guard let ref else { return }
            let decoder = Unmanaged<HEVCDecoder>.fromOpaque(ref).takeUnretainedValue()
            if status != noErr { decoder.onError(WebcamError(message: Plain.decode, detail: "VideoToolbox returned error \(status).")) }
            else if let image { decoder.logFirstFrame(image); HEVCDecoder.tagStandardMatrix(image); decoder.onFrame(image) }
        }, decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque())
        var created: VTDecompressionSession?
        try checkStatus(VTDecompressionSessionCreate(allocator: kCFAllocatorDefault, formatDescription: format,
            decoderSpecification: specification, imageBufferAttributes: attributes,
            outputCallback: &callback, decompressionSessionOut: &created), "Starting the hardware decoder", Plain.decode)
        var value: Unmanaged<CFTypeRef>?
        let status = VTSessionCopyProperty(created!, key: kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder,
            allocator: kCFAllocatorDefault, valueOut: &value)
        hardwareAccelerated = status == noErr && (value?.takeRetainedValue() as? Bool) == true
        guard hardwareAccelerated else {
            VTDecompressionSessionInvalidate(created!)
            throw WebcamError(message: "This Mac can't decode HEVC video in hardware, which the webcam needs.")
        }
        return created!
    }

    /// Writes the first decoded frame's size, pixel format and color tags to stderr, once per session,
    /// so color tags that recorders reject can be read from the log.
    private func logFirstFrame(_ image: CVImageBuffer) {
        guard !firstFrameLogged else { return }
        firstFrameLogged = true
        func tag(_ key: CFString) -> String {
            CVBufferCopyAttachment(image, key, nil).map { "\($0)" } ?? "none"
        }
        let pixelFormat = CVPixelBufferGetPixelFormatType(image)
        let fourCC = String(decoding: [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: pixelFormat >> $0) }, as: UTF8.self)
        fputs("First frame \(CVPixelBufferGetWidth(image))x\(CVPixelBufferGetHeight(image)) \(fourCC)"
            + " matrix=\(tag(kCVImageBufferYCbCrMatrixKey)) primaries=\(tag(kCVImageBufferColorPrimariesKey))"
            + " transfer=\(tag(kCVImageBufferTransferFunctionKey))\n", stderr)
    }

    private static let namedMatrices = Set([kCVImageBufferYCbCrMatrix_ITU_R_709_2, kCVImageBufferYCbCrMatrix_ITU_R_601_4,
        kCVImageBufferYCbCrMatrix_SMPTE_240M_1995, kCVImageBufferYCbCrMatrix_ITU_R_2020].map { $0 as String })

    /// The S25 Ultra tags its video BT.470BG (matrix 5), which VideoToolbox passes on as "YCbCrMatrix#5". Recorders
    /// (QuickTime, AVCaptureMovieFileOutput) copy the tag to their encoder, which refuses it with -12902 and stops
    /// with "Cannot Record". BT.470BG uses the BT.601 coefficients, so the frame is tagged with that name instead.
    static func tagStandardMatrix(_ image: CVImageBuffer) {
        guard let matrix = CVBufferCopyAttachment(image, kCVImageBufferYCbCrMatrixKey, nil) as? String,
              !namedMatrices.contains(matrix) else { return }
        CVBufferSetAttachment(image, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_601_4, .shouldPropagate)
    }

    private func endSession() {
        guard let session else { return }
        VTDecompressionSessionWaitForAsynchronousFrames(session)
        VTDecompressionSessionInvalidate(session)
        self.session = nil
    }

    func finish() {
        endSession()
        format = nil
        formatParameterSets = [:]
    }
    deinit { finish() }
}

/// Wraps decoded frames in samples stamped with the host clock, reusing one format
/// description until a frame's size, pixel format or color tags change.
final class FrameSampler {
    private let duration: CMTime
    private var format: CMVideoFormatDescription?

    init(fps: Int32) {
        duration = CMTime(value: 1, timescale: fps)
    }

    /// Not thread-safe: give each consumer its own sampler.
    func sample(_ frame: CVPixelBuffer) throws -> CMSampleBuffer {
        if format == nil || !CMVideoFormatDescriptionMatchesImageBuffer(format!, imageBuffer: frame) {
            format = nil
            try checkStatus(CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                imageBuffer: frame, formatDescriptionOut: &format), "Describing a decoded frame", Plain.frame)
        }
        var timing = CMSampleTimingInfo(duration: duration,
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        try checkStatus(CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault,
            imageBuffer: frame, formatDescription: format!, sampleTiming: &timing, sampleBufferOut: &sample), "Preparing a decoded frame", Plain.frame)
        return sample!
    }
}

/// Sharpens and turns NV12 frames with Core Image on the GPU, keeping their size. A sideways (tall) picture is fitted
/// between black bars. Thread-safe settings; with neither set, the input passes through.
final class FrameProcessor {
    private let context: CIContext
    private let sharpen = CIFilter.sharpenLuminance()
    private let scale = CIFilter.lanczosScaleTransform()
    private let settingsLock = NSLock()
    private let renderLock = NSLock()
    private var storedAmount: Float = 0
    private var storedTurns = 0
    private var pool: CVPixelBufferPool?
    private var poolWidth = 0, poolHeight = 0
    private var poolFormat: OSType = 0
    private var failureLogged = false
    /// What Core Image does to show a picture turned this many quarter turns clockwise.
    private static let orientations: [CGImagePropertyOrientation] = [.up, .right, .down, .left]

    init() {
        // No color management: Core Image converts YCbCr to RGB with the frame's matrix, sharpens,
        // and converts back with the same matrix, so colors don't shift.
        context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull(),
                                      .cacheIntermediates: false, .useSoftwareRenderer: false])
        sharpen.radius = 1.5
        scale.aspectRatio = 1
    }

    /// 0 = off ... 1 = strong.
    var amount: Float {
        get { settingsLock.lock(); defer { settingsLock.unlock() }; return storedAmount }
        set { settingsLock.lock(); storedAmount = min(max(newValue, 0), 1); settingsLock.unlock() }
    }

    /// Clockwise quarter turns, 0...3.
    var turns: Int {
        get { settingsLock.lock(); defer { settingsLock.unlock() }; return storedTurns }
        set { settingsLock.lock(); storedTurns = ((newValue % 4) + 4) % 4; settingsLock.unlock() }
    }

    func process(_ frame: CVPixelBuffer) -> CVPixelBuffer {
        settingsLock.lock(); let amount = storedAmount, turns = storedTurns; settingsLock.unlock()
        guard amount > 0 || turns != 0 else { return frame }
        renderLock.lock(); defer { renderLock.unlock() }
        do {
            let output = try outputBuffer(like: frame)
            // Copy the color tags first: Core Image picks the RGB to YCbCr matrix from the destination's tags.
            CVBufferPropagateAttachments(frame, output)
            var image = CIImage(cvPixelBuffer: frame, options: [.colorSpace: NSNull()])
            defer { sharpen.inputImage = nil; scale.inputImage = nil }
            if amount > 0 {
                sharpen.inputImage = image
                sharpen.sharpness = amount
                guard let sharpened = sharpen.outputImage else { throw WebcamError(message: Plain.process, detail: "The sharpen filter gave no image.") }
                image = sharpened
            }
            if turns != 0 { image = try turn(image, by: turns, into: CGSize(width: CVPixelBufferGetWidth(frame), height: CVPixelBufferGetHeight(frame))) }
            let destination = CIRenderDestination(pixelBuffer: output)
            destination.colorSpace = nil
            _ = try context.startTask(toRender: image, to: destination).waitUntilCompleted()
            return output
        } catch {
            if !failureLogged {
                failureLogged = true
                fputs("Mac picture processing failed, sending frames as they came. \(error.logText)\n", stderr)
            }
            return frame
        }
    }

    /// Turns the picture and fits it into size, centered on black.
    private func turn(_ image: CIImage, by turns: Int, into size: CGSize) throws -> CIImage {
        var turned = image.oriented(Self.orientations[turns])
        turned = turned.transformed(by: CGAffineTransform(translationX: -turned.extent.minX, y: -turned.extent.minY))
        guard turns % 2 == 1 else { return turned }
        scale.inputImage = turned
        scale.scale = Float(min(size.width / turned.extent.width, size.height / turned.extent.height))
        guard let fitted = scale.outputImage else { throw WebcamError(message: Plain.process, detail: "The scale filter gave no image.") }
        let centered = fitted.transformed(by: CGAffineTransform(translationX: ((size.width - fitted.extent.width) / 2).rounded(),
                                                                 y: ((size.height - fitted.extent.height) / 2).rounded()))
        return centered.composited(over: CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: size)))
    }

    /// A buffer from a pool of IOSurface-backed NV12 buffers matching the frame, rebuilt when its size or format changes.
    private func outputBuffer(like frame: CVPixelBuffer) throws -> CVPixelBuffer {
        let width = CVPixelBufferGetWidth(frame), height = CVPixelBufferGetHeight(frame)
        let format = CVPixelBufferGetPixelFormatType(frame)
        guard format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange || format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        else { throw WebcamError(message: Plain.process, detail: "Processing needs NV12 frames.") }
        if pool == nil || width != poolWidth || height != poolHeight || format != poolFormat {
            pool = nil
            let attributes = [
                kCVPixelBufferPixelFormatTypeKey: format,
                kCVPixelBufferWidthKey: width,
                kCVPixelBufferHeightKey: height,
                kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any],
                kCVPixelBufferMetalCompatibilityKey: true
            ] as CFDictionary
            let poolAttributes = [kCVPixelBufferPoolMinimumBufferCountKey: 4] as CFDictionary
            try checkStatus(CVPixelBufferPoolCreate(kCFAllocatorDefault, poolAttributes, attributes, &pool), "Creating processing buffers", Plain.process)
            poolWidth = width; poolHeight = height; poolFormat = format
        }
        var output: CVPixelBuffer?
        try checkStatus(CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool!, &output), "Getting a processing buffer", Plain.process)
        return output!
    }
}
