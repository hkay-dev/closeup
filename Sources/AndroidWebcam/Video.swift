import Foundation
import CoreMedia
import CoreVideo
import VideoToolbox

struct WebcamError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

func checkStatus(_ status: OSStatus, _ operation: String) throws {
    if status != noErr { throw WebcamError(message: "\(operation) failed (\(status)).") }
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
        guard data.count == 12 else { throw WebcamError(message: "Incomplete scrcpy packet header.") }
        let bytes = [UInt8](data)
        let flags = bytes[0..<8].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        if flags & (1 << 63) != 0 {
            let width = bytes[4..<8].reduce(0) { ($0 << 8) | Int($1) }
            let height = bytes[8..<12].reduce(0) { ($0 << 8) | Int($1) }
            guard width > 0, height > 0, width <= 8192, height <= 8192 else {
                throw WebcamError(message: "Invalid capture dimensions in scrcpy session.")
            }
            self = .session(width: width, height: height)
        } else {
            let size = bytes[8..<12].reduce(0) { ($0 << 8) | Int($1) }
            guard size > 0, size <= 32 * 1024 * 1024 else {
                throw WebcamError(message: "Invalid scrcpy packet size.")
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
    let onFrame: (CVPixelBuffer) -> Void
    let onError: (Error) -> Void
    private(set) var hardwareAccelerated = false

    init(onFrame: @escaping (CVPixelBuffer) -> Void, onError: @escaping (Error) -> Void) {
        self.onFrame = onFrame
        self.onError = onError
    }

    func decode(_ payload: Data, pts: Int64) throws {
        let units = AnnexB.units(payload)
        guard !units.isEmpty else { throw WebcamError(message: "Expected Annex B HEVC data from the phone.") }
        for unit in units where (32...34).contains(AnnexB.nalType(unit)) {
            parameterSets[AnnexB.nalType(unit)] = unit
        }
        if session == nil, parameterSets.count == 3 { try createSession() }
        let pictures = units.filter { AnnexB.nalType($0) < 32 }
        guard !pictures.isEmpty else { return }
        guard let session, let format else { throw WebcamError(message: "HEVC picture arrived before its configuration.") }
        let bytes = AnnexB.lengthPrefixed(pictures)
        var block: CMBlockBuffer?
        try checkStatus(CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: bytes.count,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
            offsetToData: 0, dataLength: bytes.count, flags: 0, blockBufferOut: &block
        ), "Creating a video packet buffer")
        try bytes.withUnsafeBytes {
            try checkStatus(CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block!,
                                                       offsetIntoDestination: 0, dataLength: bytes.count), "Copying a video packet")
        }
        var timing = CMSampleTimingInfo(duration: .invalid,
            presentationTimeStamp: CMTime(value: pts, timescale: 1_000_000), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        var size = bytes.count
        try checkStatus(CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format, sampleCount: 1,
            sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample
        ), "Creating a HEVC sample")
        try checkStatus(VTDecompressionSessionDecodeFrame(session, sampleBuffer: sample!,
            flags: [._EnableAsynchronousDecompression], frameRefcon: nil, infoFlagsOut: nil), "Decoding HEVC")
    }

    private func createSession() throws {
        let vps = parameterSets[32]!, sps = parameterSets[33]!, pps = parameterSets[34]!
        try vps.withUnsafeBytes { v in try sps.withUnsafeBytes { s in try pps.withUnsafeBytes { p in
            var pointers = [v.bindMemory(to: UInt8.self).baseAddress!, s.bindMemory(to: UInt8.self).baseAddress!, p.bindMemory(to: UInt8.self).baseAddress!]
            var lengths = [vps.count, sps.count, pps.count]
            try checkStatus(CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                allocator: kCFAllocatorDefault, parameterSetCount: 3, parameterSetPointers: &pointers,
                parameterSetSizes: &lengths, nalUnitHeaderLength: 4, extensions: nil,
                formatDescriptionOut: &format), "Reading the HEVC configuration")
        } } }
        let specification = [kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder: true] as CFDictionary
        let attributes = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any]
        ] as CFDictionary
        var callback = VTDecompressionOutputCallbackRecord(decompressionOutputCallback: { ref, _, status, _, image, _, _ in
            guard let ref else { return }
            let decoder = Unmanaged<HEVCDecoder>.fromOpaque(ref).takeUnretainedValue()
            if status != noErr { decoder.onError(WebcamError(message: "VideoToolbox returned error \(status).")) }
            else if let image { decoder.onFrame(image) }
        }, decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque())
        try checkStatus(VTDecompressionSessionCreate(allocator: kCFAllocatorDefault, formatDescription: format!,
            decoderSpecification: specification, imageBufferAttributes: attributes,
            outputCallback: &callback, decompressionSessionOut: &session), "Starting the hardware decoder")
        var value: Unmanaged<CFTypeRef>?
        try checkStatus(VTSessionCopyProperty(session!, key: kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder,
            allocator: kCFAllocatorDefault, valueOut: &value), "Checking hardware decoding")
        hardwareAccelerated = (value?.takeRetainedValue() as? Bool) == true
        guard hardwareAccelerated else { throw WebcamError(message: "Hardware HEVC decoding is unavailable.") }
    }

    func finish() {
        if let session {
            VTDecompressionSessionWaitForAsynchronousFrames(session)
            VTDecompressionSessionInvalidate(session)
        }
        session = nil
        format = nil
    }
    deinit { finish() }
}

func makeVideoSample(_ frame: CVPixelBuffer, fps: Int32) throws -> CMSampleBuffer {
    var format: CMVideoFormatDescription?
    try checkStatus(CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
        imageBuffer: frame, formatDescriptionOut: &format), "Describing a decoded frame")
    var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: fps),
        presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()), decodeTimeStamp: .invalid)
    var sample: CMSampleBuffer?
    try checkStatus(CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault,
        imageBuffer: frame, formatDescription: format!, sampleTiming: &timing, sampleBufferOut: &sample), "Preparing a decoded frame")
    return sample!
}
