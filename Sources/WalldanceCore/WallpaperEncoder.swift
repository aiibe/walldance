@preconcurrency import AVFoundation
import AppKit
import CryptoKit
import VideoToolbox

/// Native temporal HEVC encoding, adapted from AlexisBCD (MIT; LICENSES/VideoEncoder.txt).
enum WallpaperEncoder {
    private static let encodingQueue = DispatchQueue(label: "com.walldance.encoding", qos: .utility)

    static func prepare(source: URL, destination: URL, thumbnail: URL, minimumDuration: Double = 60,
                        progress: @escaping @Sendable (WallpaperProgress) -> Void) async throws {
        let task = Task.detached(priority: .utility) {
            try await encode(source: source, destination: destination, minimumDuration: minimumDuration, progress: progress)
            try Task.checkCancellation()
            progress(WallpaperProgress(fraction: 0.96, message: "Creating preview…"))
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: destination))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 512, height: 512)
            let image = try await generator.image(at: .zero).image
            guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                throw WallpaperError.encoding("The preview image couldn’t be created.")
            }
            try png.write(to: thumbnail, options: .atomic)
        }
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: { task.cancel() }
    }

    private static func encode(source: URL, destination: URL, minimumDuration: Double,
                               progress: @escaping @Sendable (WallpaperProgress) -> Void) async throws {
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw WallpaperError.encoding("The file has no video track.")
        }
        let range = try await track.load(.timeRange)
        let duration = range.duration.seconds
        guard duration.isFinite, duration > 0, duration * 30 < Double(Int32.max) else {
            throw WallpaperError.encoding("The video has an unsupported duration.")
        }
        let size = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        let descriptions = try await track.load(.formatDescriptions)
        guard let description = descriptions.first else { throw WallpaperError.encoding("The video format couldn’t be read.") }
        let extensions = (CMFormatDescriptionGetExtensions(description) as NSDictionary?) ?? [:]
        let primaries = extensions[kCMFormatDescriptionExtension_ColorPrimaries] as? String ?? ""
        let transfer = extensions[kCMFormatDescriptionExtension_TransferFunction] as? String ?? ""
        guard !["2020", "P3", "431", "432"].contains(where: primaries.contains),
              !["2084", "HLG", "2100"].contains(where: transfer.contains) else {
            throw WallpaperError.encoding("Export an SDR/Rec.709 video first. HDR and wide-gamut videos aren’t supported yet.")
        }
        let audio = try await asset.loadTracks(withMediaType: .audio)
        let presentation = CMVideoFormatDescriptionGetPresentationDimensions(description,
            usePixelAspectRatio: true, useCleanAperture: false)
        if source.pathExtension.lowercased() == "mov", duration >= minimumDuration, audio.isEmpty,
           size.width <= 3840, size.height <= 3840, preferredTransform == .identity,
           presentation == size,
           isMain10(description), try hasTemporalMetadata(source) {
            progress(WallpaperProgress(fraction: 0.5, message: "Using compatible video…"))
            try Task.checkCancellation()
            try FileManager.default.copyItem(at: source, to: destination)
            return
        }

        guard size.width > 0, size.height > 0, presentation.width > 0, presentation.height > 0 else {
            throw WallpaperError.encoding("The video has invalid dimensions.")
        }
        let aspect = CGAffineTransform(scaleX: presentation.width / size.width, y: presentation.height / size.height)
        let transform = aspect.concatenating(preferredTransform)
        let bounds = CGRect(origin: .zero, size: size).applying(transform).standardized
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else {
            throw WallpaperError.encoding("The video has an invalid display transform.")
        }
        let scale = min(1, 3840 / max(bounds.width, bounds.height))
        let width = max(2, Int((bounds.width * scale / 2).rounded(.down)) * 2)
        let height = max(2, Int((bounds.height * scale / 2).rounded(.down)) * 2)
        let displayTransform = transform.concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
            .concatenating(CGAffineTransform(scaleX: CGFloat(width) / bounds.width, y: CGFloat(height) / bounds.height))
        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid) else { throw WallpaperError.encoding("Couldn’t create a video track.") }
        try compositionTrack.insertTimeRange(range, of: track, at: .zero)
        var layer = AVVideoCompositionLayerInstruction.Configuration(assetTrack: compositionTrack)
        layer.setTransform(displayTransform, at: .zero)
        let instruction = AVVideoCompositionInstruction(configuration: .init(
            layerInstructions: [AVVideoCompositionLayerInstruction(configuration: layer)],
            timeRange: CMTimeRange(start: .zero, duration: range.duration)))
        let videoComposition = AVVideoComposition(configuration: .init(
            colorPrimaries: AVVideoColorPrimaries_ITU_R_709_2,
            colorTransferFunction: AVVideoTransferFunction_ITU_R_709_2,
            colorYCbCrMatrix: AVVideoYCbCrMatrix_ITU_R_709_2,
            frameDuration: CMTime(value: 1, timescale: 30), instructions: [instruction],
            renderSize: CGSize(width: width, height: height)))

        let framesPerLoop = max(1, Int(ceil(duration * 30)))
        let loopDuration = CMTime(value: Int64(framesPerLoop), timescale: 30)
        let loops = max(1, Int(ceil(minimumDuration / loopDuration.seconds)))
        guard loops <= 10000 else { throw WallpaperError.encoding("The input is too short. Export a longer clip first.") }
        let job = EncodingJob { job in
            let writer = TemporalMovieWriter(destination: destination)
            var session: VTCompressionSession?
            let status = VTCompressionSessionCreate(allocator: kCFAllocatorDefault, width: Int32(width), height: Int32(height),
                codecType: kCMVideoCodecType_HEVC,
                encoderSpecification: [kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: true] as CFDictionary,
                imageBufferAttributes: nil, compressedDataAllocator: nil,
                outputCallback: { context, _, status, _, sample in
                    guard let context else { return }
                    let writer = Unmanaged<TemporalMovieWriter>.fromOpaque(context).takeUnretainedValue()
                    writer.receive(sample, status: status)
                }, refcon: Unmanaged.passUnretained(writer).toOpaque(), compressionSessionOut: &session)
            guard status == noErr, let session else {
                throw WallpaperError.encoding("HEVC Main 10 encoding isn’t available on this Mac (\(status)).")
            }
            defer { VTCompressionSessionInvalidate(session) }
            func set(_ key: CFString, _ value: CFTypeRef) throws {
                let status = VTSessionSetProperty(session, key: key, value: value)
                guard status == noErr else { throw WallpaperError.encoding("The encoder doesn’t support \(key) (\(status)).") }
            }
            try set(kVTCompressionPropertyKey_RealTime, kCFBooleanFalse)
            try set(kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_HEVC_Main10_AutoLevel)
            try set(kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanTrue)
            try set(kVTCompressionPropertyKey_ExpectedFrameRate, 30 as CFNumber)
            try set(kVTCompressionPropertyKey_MaxKeyFrameInterval, 150 as CFNumber)
            try set(kVTCompressionPropertyKey_AverageBitRate, 12_000_000 as CFNumber)
            try set(kVTCompressionPropertyKey_ColorPrimaries, kCVImageBufferColorPrimaries_ITU_R_709_2)
            try set(kVTCompressionPropertyKey_TransferFunction, kCVImageBufferTransferFunction_ITU_R_709_2)
            try set(kVTCompressionPropertyKey_YCbCrMatrix, kCVImageBufferYCbCrMatrix_ITU_R_709_2)
            try set(kVTCompressionPropertyKey_AllowTemporalCompression, kCFBooleanTrue)
            try set(kVTCompressionPropertyKey_BaseLayerFrameRate, 15 as CFNumber)
            guard VTCompressionSessionPrepareToEncodeFrames(session) == noErr else {
                throw WallpaperError.encoding("The encoder couldn’t start.")
            }
            do {
                var frameCount = 0
                for loop in 0..<loops {
                    try job.checkCancellation()
                    let reader = try AVAssetReader(asset: composition)
                    let output = AVAssetReaderVideoCompositionOutput(videoTracks: [compositionTrack], videoSettings: [
                        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
                    ])
                    output.videoComposition = videoComposition
                    output.alwaysCopiesSampleData = false
                    guard reader.canAdd(output) else { throw WallpaperError.encoding("Couldn’t prepare the video reader.") }
                    reader.add(output)
                    guard reader.startReading() else { throw reader.error ?? WallpaperError.encoding("The video reader couldn’t start.") }
                    defer { reader.cancelReading() }
                    var loopFrames = 0
                    while let sample = output.copyNextSampleBuffer() {
                        try job.checkCancellation()
                        try writer.checkFailure()
                        guard let buffer = CMSampleBufferGetImageBuffer(sample) else {
                            throw WallpaperError.encoding("A video frame couldn’t be decoded.")
                        }
                        let time = CMTimeAdd(CMSampleBufferGetPresentationTimeStamp(sample),
                            CMTimeMultiply(loopDuration, multiplier: Int32(loop)))
                        let status = VTCompressionSessionEncodeFrame(session, imageBuffer: buffer, presentationTimeStamp: time,
                            duration: CMTime(value: 1, timescale: 30), frameProperties: nil,
                            sourceFrameRefcon: nil, infoFlagsOut: nil)
                        guard status == noErr else { throw WallpaperError.encoding("A frame couldn’t be encoded (\(status)).") }
                        loopFrames += 1
                        frameCount += 1
                        if frameCount % 15 == 0 {
                            let fraction = min(0.94, Double(frameCount) / Double(framesPerLoop * loops) * 0.94)
                            progress(WallpaperProgress(fraction: fraction, message: "Preparing wallpaper…"))
                        }
                    }
                    guard reader.status == .completed, loopFrames > 0 else {
                        throw reader.error ?? WallpaperError.encoding("The video reader stopped before completion.")
                    }
                }
                guard VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid) == noErr else {
                    throw WallpaperError.encoding("The encoder couldn’t finish.")
                }
                try job.checkCancellation()
                try writer.finish(end: CMTimeMultiply(loopDuration, multiplier: Int32(loops)))
            } catch {
                // Invalidate before releasing the callback context, including on cancellation.
                VTCompressionSessionInvalidate(session)
                writer.cancel()
                throw error
            }
        }
        try await run(job)
        let encoded = AVURLAsset(url: destination)
        guard let encodedTrack = try await encoded.loadTracks(withMediaType: .video).first,
              let format = try await encodedTrack.load(.formatDescriptions).first,
              isMain10(format), try hasTemporalMetadata(destination),
              abs((try await encoded.load(.duration)).seconds - loopDuration.seconds * Double(loops)) < 0.15 else {
            throw WallpaperError.encoding("The encoded video failed wallpaper compatibility checks.")
        }
    }

    private static func run(_ job: EncodingJob) async throws {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                encodingQueue.async {
                    do { try job.run(); continuation.resume() }
                    catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { job.cancel() }
    }

    private static func isMain10(_ format: CMFormatDescription) -> Bool {
        guard CMFormatDescriptionGetMediaSubType(format) == kCMVideoCodecType_HEVC,
              let atoms = CMFormatDescriptionGetExtension(format,
                extensionKey: kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms) as? [String: Any],
              let configuration = atoms["hvcC"] as? Data, configuration.count > 1 else { return false }
        return configuration[1] & 0x1f == 2
    }

    static func fingerprint(_ url: URL) throws -> String {
        let stream = try FileHandle(forReadingFrom: url)
        defer { try? stream.close() }
        var hash = SHA256()
        while let data = try stream.read(upToCount: 1024 * 1024), !data.isEmpty {
            try Task.checkCancellation()
            hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func fingerprintAsync(_ url: URL) async throws -> String {
        let task = Task.detached(priority: .utility) { try fingerprint(url) }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    static func hasTemporalMetadata(_ url: URL) throws -> Bool {
        let stream = try FileHandle(forReadingFrom: url)
        defer { try? stream.close() }
        let end = try stream.seekToEnd()
        try stream.seek(toOffset: 0)
        func integer(_ data: Data) -> UInt64 { data.reduce(0) { ($0 << 8) | UInt64($1) } }
        while try stream.offset() + 8 <= end {
            let start = try stream.offset()
            guard let header = try stream.read(upToCount: 8), header.count == 8 else { return false }
            var size = integer(header.prefix(4))
            var headerSize: UInt64 = 8
            if size == 1 {
                guard let extended = try stream.read(upToCount: 8), extended.count == 8 else { return false }
                size = integer(extended)
                headerSize = 16
            } else if size == 0 { size = end - start }
            guard size >= headerSize, size <= end - start else { return false }
            if header.suffix(4) == Data("moov".utf8) {
                guard size <= 64 * 1024 * 1024, let movie = try stream.read(upToCount: Int(size - headerSize)) else { return false }
                return ["tscl", "tsas", "sgpd", "csgm"].allSatisfy { movie.range(of: Data($0.utf8)) != nil }
            }
            try stream.seek(toOffset: start + size)
        }
        return false
    }
}

/// AVFoundation objects captured here are used only on the encoding queue.
/// Cancellation is the only cross-thread mutation and is protected by the lock.
private final class EncodingJob: @unchecked Sendable {
    private let operation: (EncodingJob) throws -> Void
    private let lock = NSLock()
    private var cancelled = false

    init(operation: @escaping (EncodingJob) throws -> Void) { self.operation = operation }

    func run() throws {
        try checkCancellation()
        try operation(self)
    }

    func cancel() { lock.withLock { cancelled = true } }

    func checkCancellation() throws {
        if lock.withLock({ cancelled }) { throw CancellationError() }
    }
}

/// VideoToolbox invokes this from its own threads. The lock guards every writer access.
private final class TemporalMovieWriter: @unchecked Sendable {
    private let destination: URL
    private let lock = NSLock()
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var failure: Error?

    init(destination: URL) { self.destination = destination }

    func receive(_ sample: CMSampleBuffer?, status: OSStatus) {
        lock.lock()
        defer { lock.unlock() }
        guard failure == nil else { return }
        do {
            guard status == noErr, let sample, CMSampleBufferDataIsReady(sample),
                  let format = CMSampleBufferGetFormatDescription(sample) else {
                throw WallpaperError.encoding("The encoder returned an invalid frame (\(status)).")
            }
            if writer == nil {
                let writer = try AVAssetWriter(outputURL: destination, fileType: .mov)
                let input = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: format)
                input.expectsMediaDataInRealTime = false
                guard writer.canAdd(input) else { throw WallpaperError.encoding("Couldn’t create the movie writer.") }
                writer.add(input)
                guard writer.startWriting() else { throw writer.error ?? WallpaperError.encoding("The movie writer couldn’t start.") }
                writer.startSession(atSourceTime: .zero)
                self.writer = writer
                self.input = input
            }
            guard let writer, let input else { return }
            let deadline = Date().addingTimeInterval(30)
            while !input.isReadyForMoreMediaData {
                guard writer.status == .writing, Date() < deadline else {
                    throw writer.error ?? WallpaperError.encoding("The movie writer stopped responding.")
                }
                Thread.sleep(forTimeInterval: 0.001)
            }
            guard input.append(sample) else { throw writer.error ?? WallpaperError.encoding("A frame couldn’t be saved.") }
        } catch { failure = error }
    }

    func checkFailure() throws {
        lock.lock()
        defer { lock.unlock() }
        if let failure { throw failure }
    }

    func finish(end: CMTime) throws {
        try checkFailure()
        guard let writer, let input else { throw WallpaperError.encoding("No video frames were written.") }
        writer.endSession(atSourceTime: end)
        input.markAsFinished()
        let completion = DispatchSemaphore(value: 0)
        writer.finishWriting { completion.signal() }
        guard completion.wait(timeout: .now() + 60) == .success, writer.status == .completed else {
            writer.cancelWriting()
            throw writer.error ?? WallpaperError.encoding("The movie couldn’t be completed.")
        }
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        writer?.cancelWriting()
    }
}
