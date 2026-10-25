import AppKit
import SwiftUI

@main
struct WalldanceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var library = LibraryModel()
    @StateObject private var updater = AppUpdater()

    var body: some Scene {
        Window("Walldance", id: "library") {
            LibraryView(model: library)
                .frame(minWidth: 380, idealWidth: 460, minHeight: 460, idealHeight: 650)
                .onAppear { updater.library = library }
        }
        .defaultSize(width: 460, height: 650)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…", action: updater.checkForUpdates)
                    .disabled(!updater.canCheckForUpdates)
            }
            CommandGroup(replacing: .newItem) {
                Button("Add Videos…", action: library.chooseVideos)
                    .keyboardShortcut("o")
            }
        }

        Settings {
            UpdaterSettingsView(updater: updater)
        }
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
            ?? Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
    }
}
