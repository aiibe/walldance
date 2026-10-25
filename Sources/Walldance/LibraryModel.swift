import AppKit
import Observation
import UniformTypeIdentifiers
import WalldanceCore

@Observable @MainActor
final class LibraryModel {
    private(set) var videos: [LibraryVideo] = []
    private(set) var isLoading = true
    private(set) var importCount = 0
    var errorMessage: String?
    var playingID: UUID?
    var selectedID: UUID?
    let repository: VideoLibrary

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        repository = VideoLibrary(directory: support.appendingPathComponent("Walldance/Videos", isDirectory: true))
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            videos = try await repository.load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func chooseVideos() {
        let panel = NSOpenPanel()
        panel.title = "Add videos to Walldance"
        panel.prompt = "Add Videos"
        panel.allowedContentTypes = [.movie]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            self?.importVideos(panel.urls)
        }
    }

    func importVideos(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        importCount += urls.count
        Task {
            var failures: [String] = []
            for url in urls {
                do {
                    let video = try await repository.importVideo(from: url)
                    if !videos.contains(where: { $0.id == video.id }) {
                        videos.append(video)
                    }
                } catch {
                    failures.append(error.localizedDescription)
                }
                importCount -= 1
            }
            if !failures.isEmpty {
                errorMessage = failures.joined(separator: "\n\n")
            }
        }
    }

    func remove(_ video: LibraryVideo) {
        Task {
            do {
                try await repository.remove(video)
                if playingID == video.id { playingID = nil }
                if selectedID == video.id { selectedID = nil }
                videos.removeAll { $0.id == video.id }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
