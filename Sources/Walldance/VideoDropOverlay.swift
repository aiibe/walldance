import SwiftUI

struct VideoDropOverlay: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 24)

        VStack(spacing: 20) {
            Image(systemName: "arrow.down.document.fill")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 88, height: 88)
                .background(Color.accentColor.opacity(0.12), in: shape)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Drop videos here")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                Text("They’ll be copied to your library.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if reduceTransparency {
                shape.fill(.background)
            } else {
                shape.fill(.regularMaterial)
            }
        }
        .background(Color.accentColor.opacity(0.06), in: shape)
        .overlay {
            shape
                .strokeBorder(Color.accentColor.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
        }
        .accessibilityElement(children: .combine)
    }
}
