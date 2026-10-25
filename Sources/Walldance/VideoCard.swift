import SwiftUI
import WalldanceCore

struct VideoCard: View {
    let video: LibraryVideo
    let url: URL
    @Binding var playingID: UUID?
    let selectedID: UUID?
    var isCheckingRegistration = false
    var registrationFailed = false
    var isApplying = false
    var selectionEnabled = true
    let select: () -> Void
    let retryRegistration: () -> Void
    let remove: () -> Void
    @State private var playback: VideoPlayback?

    private var isPlaying: Bool { playingID == video.id }
    private var isSelected: Bool { selectedID == video.id }

    var body: some View {
        Button(action: selectIfReady) {
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
                if isCheckingRegistration {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Checking wallpaper…")
                            .font(.callout)
                    }
                    .foregroundStyle(.white)
                    .padding(18)
                    .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 16))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if registrationFailed {
                    Label("Wallpaper unavailable", systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.white)
                        .padding(14)
                        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 16))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if isApplying {
                    ProgressView()
                        .colorScheme(.dark)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .buttonStyle(.plain)
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.08),
                              lineWidth: isSelected ? 3 : 1)
                .allowsHitTesting(false)
        }
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .accessibilityLabel(video.name)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityAction(named: Text("Use Wallpaper")) {
            selectIfReady()
        }
        .overlay(alignment: .topTrailing) {
            Menu {
                cardActions
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 28)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .colorScheme(.dark)
            .fixedSize()
            .padding(16)
            .accessibilityLabel("Options for \(video.name)")
        }
        .contextMenu { cardActions }
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

    private func selectIfReady() {
        if selectionEnabled && !isCheckingRegistration && !registrationFailed { select() }
    }

    @ViewBuilder
    private var cardActions: some View {
        if registrationFailed { Button("Retry", action: retryRegistration) }
        Button("Remove Video", role: .destructive, action: remove)
            .disabled(isCheckingRegistration || !selectionEnabled)
    }
}
