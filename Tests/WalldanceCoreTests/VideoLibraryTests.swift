import Foundation
import Testing
@testable import WalldanceCore

struct VideoLibraryTests {
    @Test func importsPersistDeduplicateAndRemoveWithoutTouchingOriginal() async throws {
        let fixture = try VideoLibraryFixture()
        defer { fixture.cleanUp() }
        let source = fixture.root.appendingPathComponent("A little motion.mov")
        try await makeVideo(at: source)
        let original = try Data(contentsOf: source)
        let library = VideoLibrary(paths: fixture.paths)
        let imported = try await library.importVideo(from: source)
        #expect(imported.name == "A little motion")
        #expect(library.url(for: imported) == fixture.paths.video(imported.id))
        #expect(FileManager.default.fileExists(atPath: library.url(for: imported).path))
        #expect(try Data(contentsOf: source) == original)
        #expect(try await library.importVideo(from: source) == imported)

        let renamed = fixture.root.appendingPathComponent("Renamed.mov")
        try original.write(to: renamed)
        #expect(try await library.importVideo(from: renamed) == imported)
        let reopened = VideoLibrary(paths: fixture.paths)
        #expect(try await reopened.load() == [imported])
        #expect(try FileManager.default.contentsOfDirectory(atPath: library.directory.path) == ["library.json"])
        try await reopened.remove(imported)
        #expect(try await reopened.load().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: library.url(for: imported).path))
        #expect(try Data(contentsOf: source) == original)
        #expect(try Data(contentsOf: renamed) == original)
    }

    @Test func concurrentImportsDoNotDuplicateEntries() async throws {
        let fixture = try VideoLibraryFixture()
        defer { fixture.cleanUp() }
        let source = fixture.root.appendingPathComponent("Motion.mov")
        let duplicate = fixture.root.appendingPathComponent("Same content.mov")
        try await makeVideo(at: source)
        try FileManager.default.copyItem(at: source, to: duplicate)
        let library = VideoLibrary(paths: fixture.paths)
        async let first = library.importVideo(from: source)
        async let second = library.importVideo(from: source)
        async let third = library.importVideo(from: duplicate)
        let results = try await [first, second, third]
        #expect(results.allSatisfy { $0 == results[0] })
        #expect(try await library.load().count == 1)
        let media = fixture.paths.aerials.appendingPathComponent("videos")
        #expect(try FileManager.default.contentsOfDirectory(atPath: media.path).count == 1)
    }

    @Test func changedContentAtTheSameSourcePathCreatesANewWallpaper() async throws {
        let fixture = try VideoLibraryFixture()
        defer { fixture.cleanUp() }
        let source = fixture.root.appendingPathComponent("Motion.mov")
        try await makeVideo(at: source)
        let library = VideoLibrary(paths: fixture.paths)
        let first = try await library.importVideo(from: source)
        let prepared = try Data(contentsOf: library.url(for: first))
        try FileManager.default.removeItem(at: source)
        try await makeVideo(at: source, color: 140)
        let second = try await library.importVideo(from: source)
        #expect(first.id != second.id)
        #expect(first.sourceSHA256 != second.sourceSHA256)
        #expect(try await library.load() == [first, second])
        #expect(try Data(contentsOf: library.url(for: first)) == prepared)
    }

    @Test func rejectsInvalidVideoWithoutCreatingLibrary() async throws {
        let fixture = try VideoLibraryFixture()
        defer { fixture.cleanUp() }
        let source = fixture.root.appendingPathComponent("Broken.mp4")
        try Data("This is not a movie".utf8).write(to: source)
        let library = VideoLibrary(paths: fixture.paths)
        let catalog = try Data(contentsOf: fixture.paths.manifest)
        await #expect(throws: VideoLibraryError.self) { try await library.importVideo(from: source) }
        #expect(try await library.load().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: library.directory.path))
        #expect(try Data(contentsOf: fixture.paths.manifest) == catalog)
    }

    @Test func corruptOrIncompleteManifestIsPreserved() async throws {
        let fixture = try VideoLibraryFixture()
        defer { fixture.cleanUp() }
        try FileManager.default.createDirectory(at: fixture.library, withIntermediateDirectories: true)
        let manifest = fixture.library.appendingPathComponent("library.json")
        let library = VideoLibrary(paths: fixture.paths)
        let hash = String(repeating: "a", count: 64)
        let video = LibraryVideo(name: "Duplicate", sourceSHA256: hash,
            wallpaper: PreparedWallpaper(assetID: UUID(), subcategoryID: UUID(), videoSHA256: hash, thumbnailSHA256: hash))
        let invalidRecords = [
            Data("{ damaged library".utf8),
            Data("[{\"name\":\"Incomplete\",\"sourceSHA256\":\"abc\"}]".utf8),
            try JSONEncoder().encode([video, video])
        ]
        for damaged in invalidRecords {
            try damaged.write(to: manifest)
            await #expect(throws: VideoLibraryError.self) { try await library.load() }
            await #expect(throws: VideoLibraryError.self) {
                try await library.importVideo(from: fixture.root.appendingPathComponent("Any.mov"))
            }
            #expect(try Data(contentsOf: manifest) == damaged)
        }
    }
}
