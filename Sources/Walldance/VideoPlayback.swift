import AVKit
import Observation
import SwiftUI

@Observable @MainActor
final class VideoPlayback {
    let player: AVQueuePlayer
    private var looper: AVPlayerLooper?
    private var observation: NSKeyValueObservation?
    var failed = false

    init(url: URL) {
        player = AVQueuePlayer()
        player.isMuted = true
        let item = AVPlayerItem(url: url)
        looper = AVPlayerLooper(player: player, templateItem: item)
        observation = player.observe(\.status, options: [.initial, .new]) { [weak self] player, _ in
            let failed = player.status == .failed
            Task { @MainActor [weak self] in self?.failed = failed }
        }
    }
}

struct PlayerSurface: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.videoGravity = .resizeAspectFill
        view.player = player
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        view.player = player
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player = nil
    }
}
