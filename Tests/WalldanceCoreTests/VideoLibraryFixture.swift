import AVFoundation
import CoreVideo
import Foundation
import Testing
@testable import WalldanceCore

struct VideoLibraryFixture {
    let root: URL
    let library: URL
    let paths: WallpaperPaths

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("WalldanceWallpaperTests-\(UUID())")
        library = root.appendingPathComponent("Walldance/Videos")
        paths = WallpaperPaths(applicationSupport: root, state: root.appendingPathComponent("Walldance"))
        try FileManager.default.createDirectory(at: paths.manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.index.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["assets": [["id": "APPLE", "unknown": "keep"]],
            "categories": [], "UnknownAppleField": "keep"]).write(to: paths.manifest)
        let choice: [String: Any] = ["Provider": "default", "Configuration": Data(), "Files": [String]()]
        let container: [String: Any] = ["Type": "linked", "Linked": ["Content": ["Choices": [choice]], "OtherSetting": "keep"]]
        let display: [String: Any] = ["Type": "individual", "Desktop": ["Content": ["Choices": [[
            "Provider": "com.apple.wallpaper.choice.image", "Files": ["file:///display.jpg"], "Configuration": Data()]]]],
            "Idle": ["Content": ["Choices": [choice]]], "DisplayOption": "preserve"]
        try PropertyListSerialization.data(fromPropertyList: ["AllSpacesAndDisplays": container, "SystemDefault": container,
            "Displays": ["display-one": display], "Spaces": ["space-one": ["Default": container]], "Unrelated": "keep"],
            format: .binary, options: 0).write(to: paths.index)
    }

    func catalog() throws -> [String: Any] { try JSONSerialization.jsonObject(with: Data(contentsOf: paths.manifest)) as! [String: Any] }
    func index() throws -> [String: Any] {
        try PropertyListSerialization.propertyList(from: Data(contentsOf: paths.index), format: nil) as! [String: Any]
    }
    func cleanUp() { try? FileManager.default.removeItem(at: root) }
}

func makeVideo(at url: URL, rotated: Bool = false, color: Int32 = 80) async throws {
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: 320, AVVideoHeightKey: 180])
    if rotated { input.transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 180, ty: 0) }
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
        sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 180])
    writer.add(input)
    #expect(writer.startWriting())
    writer.startSession(atSourceTime: .zero)
    var buffer: CVPixelBuffer?
    #expect(CVPixelBufferCreate(kCFAllocatorDefault, 320, 180, kCVPixelFormatType_32ARGB, nil, &buffer) == kCVReturnSuccess)
    let pixelBuffer = try #require(buffer)
    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    memset(CVPixelBufferGetBaseAddress(pixelBuffer), color, CVPixelBufferGetDataSize(pixelBuffer))
    CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
    for frame in 0..<15 {
        while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
        #expect(adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)))
    }
    input.markAsFinished()
    await writer.finishWriting()
    #expect(writer.status == .completed)
}
