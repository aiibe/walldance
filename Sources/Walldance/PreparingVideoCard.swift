import SwiftUI
import WalldanceCore

struct PreparingVideoCard: View {
    let name: String
    let progress: WallpaperProgress
    let cancel: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text(name)
                .font(.headline)
                .lineLimit(1)
            ProgressView(value: progress.fraction)
                .frame(maxWidth: 180)
            Text(progress.message)
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Cancel", action: cancel)
                .buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(16 / 9, contentMode: .fit)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .contain)
    }
}
