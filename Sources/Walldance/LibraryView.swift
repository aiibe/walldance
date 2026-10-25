import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Bindable var model: LibraryModel
    @State private var isDropTarget = false
    @State private var headerIsScrolled = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let headerHeight = geometry.safeAreaInsets.top

            ScrollView {
                LazyVStack(spacing: 20) {
                    if !model.isLoading && model.videos.isEmpty {
                        emptyState
                            .transition(.opacity)
                    }
                    ForEach(model.videos) { video in
                        VideoCard(video: video, url: model.repository.url(for: video),
                                  playingID: $model.playingID, selectedID: $model.selectedID) {
                            model.remove(video)
                        }
                        .transition(.asymmetric(
                            insertion: .opacity,
                            removal: .opacity.combined(with: .scale(scale: 0.96))
                        ))
                    }
                }
                .animation(reduceMotion ? nil : .smooth(duration: 0.32), value: model.videos.map(\.id))
                .padding(.horizontal, 20)
                .padding(.top, headerHeight)
                .padding(.bottom, 20)
                .onGeometryChange(for: Bool.self) { geometry in
                    geometry.frame(in: .named("videoLibraryScroll")).minY < -8
                } action: { isScrolled in
                    headerIsScrolled = isScrolled
                }
            }
            .coordinateSpace(name: "videoLibraryScroll")
            .allowsHitTesting(!isDropTarget)
            // Content scrolls behind the title bar; its glass stays fixed to the window.
            .ignoresSafeArea(.container, edges: .top)
            .overlay(alignment: .top) {
                GlassHeader()
                    .frame(height: headerHeight)
                    .opacity(headerIsScrolled ? 1 : 0)
                    .animation(.easeInOut(duration: 0.28), value: headerIsScrolled)
                    .offset(y: -headerHeight)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .contentShape(Rectangle())
        .toolbarBackground(.hidden, for: .windowToolbar)
        .toolbar {
            if #available(macOS 26.0, *) {
                ToolbarSpacer(.flexible, placement: .primaryAction)
            } else {
                ToolbarItem(placement: .primaryAction) {
                    Spacer()
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: model.chooseVideos) {
                    Label("Add Videos", systemImage: "plus")
                }
                .help("Add videos (⌘O)")
                .accessibilityLabel("Add videos")
            }
            if model.importCount > 0 {
                ToolbarItem(placement: .status) {
                    ProgressView()
                        .controlSize(.small)
                        .help("Adding videos…")
                        .accessibilityLabel("Adding videos")
                }
            }
        }
        .overlay {
            if isDropTarget {
                VideoDropOverlay()
                    // Keep the top flush with the first video's edge below the header.
                    .padding([.horizontal, .bottom], 12)
                    .allowsHitTesting(false)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isDropTarget)
        .onDrop(of: [.fileURL], isTargeted: $isDropTarget, perform: importDroppedVideos)
        .onChange(of: isDropTarget) { _, targeted in
            if targeted { model.playingID = nil }
        }
        .task { await model.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.playingID = nil }
        }
        .alert("Couldn’t add or update a video", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private func importDroppedVideos(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            Task { @MainActor in
                guard let item = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier),
                      let url = (item as? URL) ?? (item as? Data).flatMap({ URL(dataRepresentation: $0, relativeTo: nil) }) else {
                    return
                }
                model.importVideos([url])
            }
        }
        return !providers.isEmpty
    }

    private var emptyState: some View {
        Button(action: model.chooseVideos) {
            VStack(spacing: 20) {
                Image(systemName: "arrow.down.document")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.secondary)
                    .frame(width: 76, height: 76)
                    .background(.quaternary.opacity(0.4), in: Circle())
                VStack(spacing: 8) {
                    Text("Drop a video")
                        .font(.system(size: 22, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("or click to browse")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 260)
            .background(.quinary.opacity(0.5), in: RoundedRectangle(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Drop a video or choose a file")
    }
}

/// A single stationary glass surface behind the native traffic lights and toolbar.
private struct GlassHeader: View {
    var body: some View {
        if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }
}
