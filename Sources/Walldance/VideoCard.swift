import SwiftUI
import WalldanceCore

struct VideoCard: View {
    let video: LibraryVideo
    let url: URL
    @Binding var playingID: UUID?
    @Binding var selectedID: UUID?
    let remove: () -> Void
    @State private var playback: VideoPlayback?

    private var isPlaying: Bool { playingID == video.id }
    private var isSelected: Bool { selectedID == video.id }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.black
            if let playback {
                PlayerSurface(player: playback.player)
                    .allowsHitTesting(false)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.3)], startPoint: .center, endPoint: .bottom)
            if playback?.failed == true {
                Text("This video is unavailable")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.08),
                              lineWidth: isSelected ? 3 : 1)
                .allowsHitTesting(false)
        }
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .onTapGesture { selectedID = video.id }
        .accessibilityLabel(video.name)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityAction(named: Text("Select")) { selectedID = video.id }
        .overlay(alignment: .topTrailing) {
            Menu {
                Button("Remove Video", role: .destructive, action: remove)
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 28)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .modifier(VideoControlStyle())
            .fixedSize()
            .padding(16)
            .accessibilityLabel("Options for \(video.name)")
        }
        .contextMenu { Button("Remove Video", role: .destructive, action: remove) }
        .onHover { hovering in
            if hovering {
                playingID = video.id
            } else if isPlaying {
                playingID = nil
            }
        }
        .onAppear {
            if playback == nil { playback = VideoPlayback(url: url) }
        }
        .onChange(of: isPlaying) { _, playing in
            if playing { playback?.player.play() } else { playback?.player.pause() }
        }
        .onDisappear {
            playback?.player.pause()
            if isPlaying { playingID = nil }
        }
    }
}

/// Use the system's Liquid Glass controls on Tahoe, with a native material fallback.
private struct VideoControlStyle: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .colorScheme(.dark)
        } else {
            content
                .buttonStyle(.plain)
                .padding(8)
                .background(.thinMaterial, in: Circle())
                .colorScheme(.dark)
        }
    }
}
