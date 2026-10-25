import AppKit
import Observation
import UniformTypeIdentifiers
import WalldanceCore

@Observable @MainActor
final class LibraryModel {
    struct PendingVideo: Identifiable {
        let id = UUID()
        let url: URL
        var progress = WallpaperProgress(fraction: 0, message: "Waiting…")

        var name: String { url.deletingPathExtension().lastPathComponent }
    }

    private(set) var videos: [LibraryVideo] = []
    private(set) var isLoading = true
    var importCount: Int { pendingVideos.count }
    var errorMessage: String?
    var playingID: UUID?
    var selectedID: UUID?
    private(set) var pendingVideos: [PendingVideo] = []
    private(set) var checkingIDs: Set<UUID> = []
    private(set) var registrationErrors: [UUID: String] = [:]
    private(set) var applyingID: UUID?
    private var activeImport: Task<Void, Never>?
    private var openPanel: NSOpenPanel?
    private var removalCount = 0
    let repository: VideoLibrary

    var canRestartForUpdate: Bool {
        !isLoading && pendingVideos.isEmpty && checkingIDs.isEmpty
            && applyingID == nil && removalCount == 0 && openPanel == nil
    }

    init(applicationSupport support: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
         controlsWallpaperProcesses: Bool = true) {
        let state = support.appendingPathComponent("Walldance", isDirectory: true)
        repository = VideoLibrary(paths: WallpaperPaths(applicationSupport: support, state: state,
            controlsWallpaperProcesses: controlsWallpaperProcesses))
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            videos = try await repository.load()
            checkingIDs = Set(videos.map(\.id))
            for video in videos { await checkRegistration(video) }
            await refreshSelection()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func chooseVideos() {
        guard openPanel == nil else { return }
        let panel = NSOpenPanel()
        openPanel = panel
        panel.title = "Add videos to Walldance"
        panel.prompt = "Add Videos"
        panel.allowedContentTypes = [.movie]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            self?.openPanel = nil
            guard response == .OK else { return }
            self?.importVideos(panel.urls)
        }
    }

    func importVideos(_ urls: [URL]) {
        pendingVideos.append(contentsOf: urls.map { PendingVideo(url: $0) })
        startNextImport()
    }

    private func startNextImport() {
        guard activeImport == nil, let pending = pendingVideos.first else { return }
        let id = pending.id
        updateProgress(WallpaperProgress(fraction: 0, message: "Checking video…"), for: id)
        activeImport = Task {
            defer {
                pendingVideos.removeAll { $0.id == id }
                activeImport = nil
                startNextImport()
            }
            do {
                let video = try await repository.importVideo(from: pending.url) { [weak self] progress in
                    Task { @MainActor in self?.updateProgress(progress, for: id) }
                }
                if !videos.contains(where: { $0.id == video.id }) { videos.append(video) }
            } catch is CancellationError {
                // A cancelled import never becomes a shelf entry.
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func cancelImport(_ id: UUID) {
        if pendingVideos.first?.id == id { activeImport?.cancel() }
        else { pendingVideos.removeAll { $0.id == id } }
    }

    private func updateProgress(_ progress: WallpaperProgress, for id: UUID) {
        guard let index = pendingVideos.firstIndex(where: { $0.id == id }) else { return }
        pendingVideos[index].progress = progress
    }

    private func checkRegistration(_ video: LibraryVideo) async {
        checkingIDs.insert(video.id)
        registrationErrors.removeValue(forKey: video.id)
        defer { checkingIDs.remove(video.id) }
        do {
            try await repository.ensureRegistered(video)
        } catch {
            registrationErrors[video.id] = error.localizedDescription
            if !(error is CancellationError) { errorMessage = error.localizedDescription }
        }
    }

    func retryRegistration(_ video: LibraryVideo) {
        guard !checkingIDs.contains(video.id) else { return }
        Task { await checkRegistration(video) }
    }

    func select(_ video: LibraryVideo) {
        guard !checkingIDs.contains(video.id), registrationErrors[video.id] == nil, applyingID == nil else { return }
        applyingID = video.id
        Task {
            defer { applyingID = nil }
            do {
                try await repository.apply(video)
                selectedID = video.id
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func refreshSelection() async {
        guard applyingID == nil else { return }
        do { selectedID = try await repository.currentWallpaperID() }
        catch { /* An unavailable system store must not block browsing the shelf. */ }
    }

    func remove(_ video: LibraryVideo) {
        removalCount += 1
        Task {
            defer { removalCount -= 1 }
            do {
                try await repository.remove(video)
                if playingID == video.id { playingID = nil }
                if selectedID == video.id { selectedID = nil }
                videos.removeAll { $0.id == video.id }
                registrationErrors.removeValue(forKey: video.id)
                await refreshSelection()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
