import Foundation

/// The library manifest owns our records; the Apple catalogue is a rebuildable projection.
public struct WallpaperPaths: Sendable {
    public let aerials: URL
    public let index: URL
    public let state: URL
    let controlsWallpaperProcesses: Bool

    public init(applicationSupport: URL, state: URL, controlsWallpaperProcesses: Bool = false) {
        aerials = applicationSupport.appendingPathComponent("com.apple.wallpaper/aerials", isDirectory: true)
        index = applicationSupport.appendingPathComponent("com.apple.wallpaper/Store/Index.plist")
        self.state = state
        self.controlsWallpaperProcesses = controlsWallpaperProcesses
    }

    var manifest: URL { aerials.appendingPathComponent("manifest/entries.json") }
    func video(_ id: UUID) -> URL { aerials.appendingPathComponent("videos/\(id.uuidString).mov") }
    func thumbnail(_ id: UUID) -> URL { aerials.appendingPathComponent("thumbnails/\(id.uuidString).png") }
}

public struct PreparedWallpaper: Codable, Equatable, Sendable {
    public let assetID: UUID
    public let subcategoryID: UUID
    public let videoSHA256: String
    public let thumbnailSHA256: String
}

public struct WallpaperProgress: Sendable {
    public let fraction: Double
    public let message: String

    public init(fraction: Double, message: String) {
        self.fraction = fraction
        self.message = message
    }
}

public enum WallpaperError: LocalizedError {
    case unavailable(String)
    case invalidCatalog
    case invalidSelection
    case changedDuringWrite
    case mediaChanged
    case encoding(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let message): message
        case .invalidCatalog: "The macOS wallpaper catalogue couldn’t be read safely. Download an aerial in System Settings → Wallpaper, then try again."
        case .invalidSelection: "The macOS wallpaper settings use an unrecognized format. Your settings haven’t been replaced."
        case .changedDuringWrite: "macOS changed its wallpaper settings during this operation. Please try again."
        case .mediaChanged: "A prepared wallpaper file is missing or has changed. Your original video is untouched."
        case .encoding(let message): "Couldn’t prepare the wallpaper: \(message)"
        }
    }
}
