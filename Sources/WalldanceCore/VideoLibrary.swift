import AVFoundation
import Foundation

public struct LibraryVideo: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let filename: String
    public let sourcePath: String
}

public enum VideoLibraryError: LocalizedError {
    case notAVideo(String)
    case invalidLibrary

    public var errorDescription: String? {
        switch self {
        case .notAVideo(let name): "“\(name)” doesn’t contain a playable video. Try a MOV, MP4, or M4V file."
        case .invalidLibrary: "The saved video library couldn’t be read. Your video files are still on disk."
        }
    }
}

/// Owns imported copies so videos remain available when their originals move.
public actor VideoLibrary {
    public nonisolated let directory: URL
    private let manifest: URL

    public init(directory: URL) {
        self.directory = directory
        self.manifest = directory.appendingPathComponent("library.json")
    }

    public func load() throws -> [LibraryVideo] {
        guard FileManager.default.fileExists(atPath: manifest.path) else { return [] }
        do {
            let videos = try JSONDecoder().decode([LibraryVideo].self, from: Data(contentsOf: manifest))
            guard videos.allSatisfy({ $0.filename == URL(fileURLWithPath: $0.filename).lastPathComponent }) else {
                throw VideoLibraryError.invalidLibrary
            }
            return videos
        } catch {
            throw VideoLibraryError.invalidLibrary
        }
    }

    public func importVideo(from source: URL) async throws -> LibraryVideo {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }

        let sourcePath = source.standardizedFileURL.path
        // Loading before writing also prevents overwriting an unreadable manifest.
        if let existing = try load().first(where: { $0.sourcePath == sourcePath }) {
            if FileManager.default.fileExists(atPath: url(for: existing).path) { return existing }
        }
        let asset = AVURLAsset(url: source)
        do {
            guard try await asset.load(.isPlayable),
                  !(try await asset.loadTracks(withMediaType: .video)).isEmpty else {
                throw VideoLibraryError.notAVideo(source.lastPathComponent)
            }
        } catch {
            throw VideoLibraryError.notAVideo(source.lastPathComponent)
        }

        let id = UUID()
        let filename = id.uuidString + (source.pathExtension.isEmpty ? "" : "." + source.pathExtension)
        let video = LibraryVideo(id: id, name: source.deletingPathExtension().lastPathComponent,
                                 filename: filename, sourcePath: sourcePath)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = url(for: video)
        try FileManager.default.copyItem(at: source, to: destination)
        do {
            // Re-read after AVFoundation's suspension points: concurrent imports must not lose entries.
            var videos = try load()
            if let existing = videos.first(where: { $0.sourcePath == sourcePath }),
               FileManager.default.fileExists(atPath: url(for: existing).path) {
                try FileManager.default.removeItem(at: destination)
                return existing
            }
            videos.removeAll { $0.sourcePath == sourcePath }
            videos.append(video)
            try save(videos)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        return video
    }

    public func remove(_ video: LibraryVideo) throws {
        var videos = try load()
        guard videos.contains(where: { $0.id == video.id }) else { return }
        // Commit metadata first; a failure must leave the visible library intact.
        videos.removeAll { $0.id == video.id }
        try save(videos)
        try? FileManager.default.removeItem(at: url(for: video))
    }

    public nonisolated func url(for video: LibraryVideo) -> URL {
        directory.appendingPathComponent(video.filename)
    }

    private func save(_ videos: [LibraryVideo]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(videos).write(to: manifest, options: .atomic)
    }
}
