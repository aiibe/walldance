import AVFoundation
import Foundation

public struct LibraryVideo: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID { wallpaper.assetID }
    public let name: String
    public let sourceSHA256: String
    public let wallpaper: PreparedWallpaper

    public init(name: String, sourceSHA256: String, wallpaper: PreparedWallpaper) {
        self.name = name
        self.sourceSHA256 = sourceSHA256
        self.wallpaper = wallpaper
    }

    fileprivate var hasValidStorageMetadata: Bool {
        let hashes = [sourceSHA256, wallpaper.videoSHA256, wallpaper.thumbnailSHA256]
        return !name.isEmpty && hashes.allSatisfy { hash in
            hash.utf8.count == 64 && hash.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
        }
    }
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

/// Owns one prepared file per wallpaper, shared by shelf previews and macOS.
public actor VideoLibrary {
    public nonisolated let directory: URL
    private let paths: WallpaperPaths
    private let manifest: URL
    private var imports: [String: Task<LibraryVideo, Error>] = [:]
    private var catalog: WallpaperCatalog { WallpaperCatalog(paths: paths) }

    public init(paths: WallpaperPaths) {
        self.paths = paths
        directory = paths.state.appendingPathComponent("Videos", isDirectory: true)
        manifest = directory.appendingPathComponent("library.json")
    }

    public func load() throws -> [LibraryVideo] {
        guard FileManager.default.fileExists(atPath: manifest.path) else { return [] }
        do {
            let videos = try JSONDecoder().decode([LibraryVideo].self, from: Data(contentsOf: manifest))
            guard Set(videos.map(\.id)).count == videos.count,
                  videos.allSatisfy(\.hasValidStorageMetadata) else {
                throw VideoLibraryError.invalidLibrary
            }
            return videos
        } catch {
            throw VideoLibraryError.invalidLibrary
        }
    }

    public func importVideo(from source: URL,
                            progress: @escaping @Sendable (WallpaperProgress) -> Void = { _ in }) async throws -> LibraryVideo {
        let key = source.standardizedFileURL.path
        if let existing = imports[key] { return try await existing.value }
        let task = Task { try await self.performImport(from: source, progress: progress) }
        imports[key] = task
        defer { imports.removeValue(forKey: key) }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    private func performImport(from source: URL,
                               progress: @escaping @Sendable (WallpaperProgress) -> Void) async throws -> LibraryVideo {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        try Task.checkCancellation()
        _ = try load() // Never overwrite an unreadable manifest.
        progress(WallpaperProgress(fraction: 0, message: "Checking video…"))
        let asset = AVURLAsset(url: source)
        do {
            guard try await asset.load(.isPlayable),
                  !(try await asset.loadTracks(withMediaType: .video)).isEmpty else {
                throw VideoLibraryError.notAVideo(source.lastPathComponent)
            }
        } catch {
            try Task.checkCancellation()
            throw VideoLibraryError.notAVideo(source.lastPathComponent)
        }
        try catalog.checkAvailable()
        let sourceHash = try await WallpaperEncoder.fingerprintAsync(source)
        try Task.checkCancellation()
        if let existing = try load().first(where: { $0.sourceSHA256 == sourceHash }) {
            try ensureRegistered(existing)
            return existing
        }
        let staging = paths.state.appendingPathComponent("Staging/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        let movie = staging.appendingPathComponent("video.mov")
        let thumbnail = staging.appendingPathComponent("thumbnail.png")
        try await WallpaperEncoder.prepare(source: source, destination: movie, thumbnail: thumbnail, progress: progress)
        let videoHash = try await WallpaperEncoder.fingerprintAsync(movie)
        let thumbnailHash = try await WallpaperEncoder.fingerprintAsync(thumbnail)
        try Task.checkCancellation()
        let wallpaper = PreparedWallpaper(assetID: UUID(), subcategoryID: UUID(),
            videoSHA256: videoHash, thumbnailSHA256: thumbnailHash)
        let video = LibraryVideo(name: source.deletingPathExtension().lastPathComponent,
            sourceSHA256: sourceHash, wallpaper: wallpaper)
        progress(WallpaperProgress(fraction: 0.99, message: "Finishing…"))
        return try catalog.withLock {
            // Encoding suspends the actor; retain other imports committed while it ran.
            var videos = try load()
            if let existing = videos.first(where: { $0.sourceSHA256 == sourceHash }) { return existing }
            try FileManager.default.createDirectory(at: paths.video(video.id).deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: paths.thumbnail(video.id).deletingLastPathComponent(), withIntermediateDirectories: true)
            do {
                try FileManager.default.moveItem(at: movie, to: paths.video(video.id))
                try FileManager.default.moveItem(at: thumbnail, to: paths.thumbnail(video.id))
                videos.append(video)
                try catalog.register(video) { try save(videos) }
            } catch {
                try? FileManager.default.removeItem(at: paths.video(video.id))
                try? FileManager.default.removeItem(at: paths.thumbnail(video.id))
                throw error
            }
            return video
        }
    }

    public nonisolated func url(for video: LibraryVideo) -> URL { paths.video(video.id) }

    /// Apple can refresh its catalogue independently of our library.
    public func ensureRegistered(_ video: LibraryVideo) throws {
        guard let current = try load().first(where: { $0.id == video.id }) else {
            throw WallpaperError.unavailable("This video is no longer in your shelf.")
        }
        try verify(current)
        try catalog.withLock { try catalog.register(current) }
    }

    public func apply(_ video: LibraryVideo) throws {
        let videos = try load()
        guard let current = videos.first(where: { $0.id == video.id }) else {
            throw WallpaperError.unavailable("This video is no longer in your shelf.")
        }
        try verify(current)
        try catalog.withLock {
            try catalog.register(current)
            try catalog.apply(current.wallpaper, managedIDs: Set(videos.map(\.id)))
        }
    }

    public func currentWallpaperID() throws -> UUID? {
        let selected = try catalog.selectedIDs()
        return try load().first(where: { selected.contains($0.id) })?.id
    }

    public func remove(_ video: LibraryVideo) throws {
        var videos = try load()
        guard let current = videos.first(where: { $0.id == video.id }) else { return }
        try verify(current)
        try catalog.withLock {
            if try catalog.selectedIDs().contains(current.id) {
                if let next = videos.first(where: { $0.id != current.id }) {
                    try verify(next)
                    try catalog.register(next)
                    try catalog.apply(next.wallpaper, managedIDs: Set(videos.map(\.id)))
                } else { try catalog.restoreSelection(removing: current.id) }
            }
            videos.removeAll { $0.id == current.id }
            try catalog.unregister(current) { try save(videos) }
            try? FileManager.default.removeItem(at: paths.video(current.id))
            try? FileManager.default.removeItem(at: paths.thumbnail(current.id))
            catalog.reload()
        }
    }

    private func verify(_ video: LibraryVideo) throws {
        guard (try? WallpaperEncoder.fingerprint(paths.video(video.id))) == video.wallpaper.videoSHA256,
              (try? WallpaperEncoder.fingerprint(paths.thumbnail(video.id))) == video.wallpaper.thumbnailSHA256 else {
            throw WallpaperError.mediaChanged
        }
    }

    private func save(_ videos: [LibraryVideo]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(videos).write(to: manifest, options: .atomic)
    }
}
