import AVFoundation
import Foundation
import Testing
@testable import WalldanceCore

struct WallpaperTests {
    @Test func dropPreparesOneSharedFileAndSelectionAppliesIt() async throws {
        let fixture = try VideoLibraryFixture()
        defer { fixture.cleanUp() }
        let source = fixture.root.appendingPathComponent("Ocean.mov")
        try await makeVideo(at: source)
        let original = try Data(contentsOf: source)
        let initialIndex = try Data(contentsOf: fixture.paths.index)
        let library = VideoLibrary(paths: fixture.paths)
        let video = try await library.importVideo(from: source)
        let wallpaper = video.wallpaper
        #expect(try Data(contentsOf: fixture.paths.index) == initialIndex) // Import never selects.
        #expect(library.url(for: video) == fixture.paths.video(wallpaper.assetID))
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.library.path) == ["library.json"])
        #expect(try WallpaperEncoder.hasTemporalMetadata(library.url(for: video)))
        let asset = AVURLAsset(url: library.url(for: video))
        #expect(try await asset.load(.duration).seconds >= 60)
        #expect(try await asset.loadTracks(withMediaType: .audio).isEmpty)
        #expect(try Data(contentsOf: source) == original)
        let duplicate = fixture.root.appendingPathComponent("Renamed.mov")
        try original.write(to: duplicate)
        #expect(try await library.importVideo(from: duplicate) == video)
        let reopened = VideoLibrary(paths: fixture.paths)
        #expect(try await reopened.load() == [video])

        try await reopened.apply(video)
        #expect(try await reopened.currentWallpaperID() == video.id)
        let index = try fixture.index()
        #expect(index["Unrelated"] as? String == "keep")
        #expect((index["Displays"] as? [String: Any])?["display-one"] != nil)
        #expect(WallpaperCatalog.selectedIDs(in: index["Spaces"]!) == [wallpaper.assetID])
        let catalog = try fixture.catalog()
        #expect(catalog["UnknownAppleField"] as? String == "keep")
        #expect((catalog["assets"] as? [[String: Any]])?.contains { $0["id"] as? String == "APPLE" } == true)

        try await reopened.remove(video)
        #expect(try await reopened.load().isEmpty)
        #expect(try await reopened.currentWallpaperID() == nil)
        #expect(try WallpaperCatalog(paths: fixture.paths).selectedIDs().isEmpty)
        let restored = try PropertyListSerialization.propertyList(from: Data(contentsOf: fixture.paths.index), format: nil) as! NSDictionary
        let initial = try PropertyListSerialization.propertyList(from: initialIndex, format: nil) as! NSDictionary
        #expect(restored == initial)
        #expect(!FileManager.default.fileExists(atPath: library.url(for: video).path))
        #expect(try Data(contentsOf: source) == original)
        #expect((try fixture.catalog()["assets"] as? [[String: Any]])?.count == 1)
    }

    @Test func normalizesPortraitVideoAndRepairsRegistrationWithoutEncodingAgain() async throws {
        let fixture = try VideoLibraryFixture()
        defer { fixture.cleanUp() }
        let source = fixture.root.appendingPathComponent("Portrait.mov")
        try await makeVideo(at: source, rotated: true)
        let library = VideoLibrary(paths: fixture.paths)
        let video = try await library.importVideo(from: source)
        #expect(FileManager.default.fileExists(atPath: source.path))
        let track = try #require(try await AVURLAsset(url: library.url(for: video)).loadTracks(withMediaType: .video).first)
        let size = try await track.load(.naturalSize)
        #expect(size.width == 180 && size.height == 320)
        #expect(try await track.load(.preferredTransform) == .identity)
        let bytes = try Data(contentsOf: library.url(for: video))
        try JSONSerialization.data(withJSONObject: ["assets": [["id": "APPLE"]], "categories": []])
            .write(to: fixture.paths.manifest, options: .atomic)
        try await library.ensureRegistered(video)
        #expect(try Data(contentsOf: library.url(for: video)) == bytes)
        #expect(try await library.load() == [video])

        try Data("changed".utf8).write(to: library.url(for: video))
        await #expect(throws: WallpaperError.self) { try await library.apply(video) }
        await #expect(throws: WallpaperError.self) { try await library.remove(video) }
        #expect(try await library.load() == [video])
    }

    @Test func compatibleInputIsReusedAndCancellationLeavesNoLibraryEntry() async throws {
        let fixture = try VideoLibraryFixture()
        defer { fixture.cleanUp() }
        let source = fixture.root.appendingPathComponent("Source.mov")
        let encoded = fixture.root.appendingPathComponent("Ready.mov")
        let thumbnail = fixture.root.appendingPathComponent("Preview.png")
        try await makeVideo(at: source)
        try await WallpaperEncoder.prepare(source: source, destination: encoded, thumbnail: thumbnail,
            minimumDuration: 1, progress: { _ in })
        let reused = fixture.root.appendingPathComponent("Reused.mov")
        try await WallpaperEncoder.prepare(source: encoded, destination: reused,
            thumbnail: fixture.root.appendingPathComponent("Reused.png"), minimumDuration: 1, progress: { _ in })
        #expect(try Data(contentsOf: encoded) == Data(contentsOf: reused))
        let library = VideoLibrary(paths: fixture.paths)
        let task = Task { try await library.importVideo(from: source) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try await library.load().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.library.appendingPathComponent("library.json").path))
        #expect((try fixture.catalog()["assets"] as? [[String: Any]])?.count == 1)

        let (updates, continuation) = AsyncStream<Void>.makeStream()
        let running = Task {
            defer { continuation.finish() }
            return try await library.importVideo(from: source) { progress in
                if progress.fraction > 0.1 { continuation.yield(()) }
            }
        }
        for await _ in updates { break }
        running.cancel()
        await #expect(throws: CancellationError.self) { try await running.value }
        continuation.finish()
        #expect(try await library.load().isEmpty)
        #expect((try fixture.catalog()["assets"] as? [[String: Any]])?.count == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.paths.state.appendingPathComponent("Staging").path).isEmpty)
    }

    @Test func concurrentPreparationsPersistAndRemovingActiveVideoSelectsAnother() async throws {
        let fixture = try VideoLibraryFixture()
        defer { fixture.cleanUp() }
        let firstSource = fixture.root.appendingPathComponent("First.mov")
        let secondSource = fixture.root.appendingPathComponent("Second.mov")
        try await makeVideo(at: firstSource)
        try await makeVideo(at: secondSource, color: 140)
        let library = VideoLibrary(paths: fixture.paths)
        async let firstImport = library.importVideo(from: firstSource)
        async let secondImport = library.importVideo(from: secondSource)
        let (first, second) = try await (firstImport, secondImport)
        #expect(try await library.load().count == 2)
        let registered = try Data(contentsOf: fixture.paths.manifest)
        try await library.apply(first)
        #expect(try Data(contentsOf: fixture.paths.manifest) == registered)
        try await library.remove(first)
        #expect(try await library.currentWallpaperID() == second.id)
        #expect(try await library.load() == [second])
        try await library.remove(second)
        #expect(try WallpaperCatalog(paths: fixture.paths).selectedIDs().isEmpty)
        #expect(try await library.load().isEmpty)
    }

    @Test func catalogCommitFailureRollsBackAndCorruptCatalogIsPreserved() throws {
        let fixture = try VideoLibraryFixture()
        defer { fixture.cleanUp() }
        let catalog = WallpaperCatalog(paths: fixture.paths)
        let video = LibraryVideo(name: "Test", sourceSHA256: "",
            wallpaper: PreparedWallpaper(assetID: UUID(), subcategoryID: UUID(), videoSHA256: "", thumbnailSHA256: ""))
        let before = try Data(contentsOf: fixture.paths.manifest)
        #expect(throws: CancellationError.self) {
            try catalog.withLock { try catalog.register(video) { throw CancellationError() } }
        }
        #expect(try Data(contentsOf: fixture.paths.manifest) == before)
        let corrupt = Data("{broken".utf8)
        try corrupt.write(to: fixture.paths.manifest)
        #expect(throws: WallpaperError.self) { try catalog.register(video) }
        #expect(try Data(contentsOf: fixture.paths.manifest) == corrupt)
    }

    @Test func unknownSelectionAndForeignAssetIDsAreNeverOverwritten() throws {
        let fixture = try VideoLibraryFixture()
        defer { fixture.cleanUp() }
        let wallpaper = PreparedWallpaper(assetID: UUID(), subcategoryID: UUID(), videoSHA256: "", thumbnailSHA256: "")
        let catalog = WallpaperCatalog(paths: fixture.paths)
        let foreign = try JSONSerialization.data(withJSONObject: ["categories": [],
            "assets": [["id": wallpaper.assetID.uuidString, "url-4K-SDR-240FPS": "file:///other.mov"]]])
        try foreign.write(to: fixture.paths.manifest)
        let video = LibraryVideo(name: "Foreign", sourceSHA256: "", wallpaper: wallpaper)
        #expect(throws: WallpaperError.self) { try catalog.register(video) }
        #expect(throws: WallpaperError.self) { try catalog.unregister(video) }
        #expect(try Data(contentsOf: fixture.paths.manifest) == foreign)
        let unknown = try PropertyListSerialization.data(fromPropertyList: ["AllSpacesAndDisplays": ["Type": "future-format"]],
            format: .binary, options: 0)
        try unknown.write(to: fixture.paths.index)
        #expect(throws: WallpaperError.self) { try catalog.apply(wallpaper, managedIDs: []) }
        #expect(try Data(contentsOf: fixture.paths.index) == unknown)
    }

    @Test func temporalMetadataCheckDoesNotMatchVideoDataOrMalformedAtoms() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let movie = root.appendingPathComponent("Movie.mov")
        let payload = Data("tscltsassgpdcsgm".utf8)
        var data = Data([0, 0, 0, UInt8(8 + payload.count)])
        data.append(Data("mdat".utf8))
        data.append(payload)
        try data.write(to: movie)
        #expect(try !WallpaperEncoder.hasTemporalMetadata(movie))
        try Data([0xff, 0xff, 0xff, 0xff, 109, 111, 111, 118]).write(to: movie)
        #expect(try !WallpaperEncoder.hasTemporalMetadata(movie))
    }
}
