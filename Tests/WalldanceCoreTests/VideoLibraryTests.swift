import AVFoundation
import CoreVideo
import Foundation
import Testing
@testable import WalldanceCore

struct VideoLibraryTests {
    @Test func importsPersistDeduplicateAndRemoveWithoutTouchingOriginal() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("A little motion.mov")
        try await makeVideo(at: source)
        let directory = root.appendingPathComponent("Library")
        let library = VideoLibrary(directory: directory)

        let imported = try await library.importVideo(from: source)
        #expect(imported.name == "A little motion")
        #expect(FileManager.default.fileExists(atPath: library.url(for: imported).path))
        #expect(try Data(contentsOf: source) == Data(contentsOf: library.url(for: imported)))
        #expect(try await library.importVideo(from: source) == imported)

        let reopened = VideoLibrary(directory: directory)
        #expect(try await reopened.load() == [imported])
        try await reopened.remove(imported)
        #expect(try await reopened.load().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: library.url(for: imported).path))
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test func concurrentImportsDoNotDuplicateEntries() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Motion.mov")
        try await makeVideo(at: source)
        let library = VideoLibrary(directory: root.appendingPathComponent("Library"))
        async let first = library.importVideo(from: source)
        async let second = library.importVideo(from: source)
        let results = try await [first, second]
        #expect(results[0] == results[1])
        #expect(try await library.load().count == 1)
        let files = try FileManager.default.contentsOfDirectory(atPath: library.directory.path)
        #expect(files.count == 2) // One video and the manifest, with no orphaned copies.
    }

    @Test func rejectsInvalidVideoWithoutCreatingLibrary() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("Broken.mp4")
        try Data("This is not a movie".utf8).write(to: source)
        let library = VideoLibrary(directory: root.appendingPathComponent("Library"))
        await #expect(throws: VideoLibraryError.self) { try await library.importVideo(from: source) }
        #expect(try await library.load().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: library.directory.path))
    }

    @Test func corruptManifestIsPreserved() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let manifest = root.appendingPathComponent("library.json")
        let damaged = Data("{ damaged library".utf8)
        try damaged.write(to: manifest)
        let library = VideoLibrary(directory: root)
        await #expect(throws: VideoLibraryError.self) { try await library.load() }
        await #expect(throws: VideoLibraryError.self) {
            try await library.importVideo(from: root.appendingPathComponent("Any.mov"))
        }
        #expect(try Data(contentsOf: manifest) == damaged)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("WalldanceTests-\(UUID())")
    }

    private func makeVideo(at url: URL) async throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 320,
            AVVideoHeightKey: 180
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                                          kCVPixelBufferWidthKey as String: 320,
                                          kCVPixelBufferHeightKey as String: 180])
        writer.add(input)
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, 320, 180, kCVPixelFormatType_32ARGB, nil, &buffer)
        #expect(status == kCVReturnSuccess)
        let pixelBuffer = try #require(buffer)
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
            memset(base, 80, CVPixelBufferGetDataSize(pixelBuffer))
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        for frame in 0..<12 {
            while !input.isReadyForMoreMediaData {
                if let error = writer.error { throw error }
                try await Task.sleep(for: .milliseconds(5))
            }
            #expect(adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 24)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        #expect(writer.status == .completed)
    }
}
