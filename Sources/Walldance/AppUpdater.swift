import AppKit
import Combine
import Sparkle
import SwiftUI

@MainActor
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var automaticallyDownloadsUpdates = false

    weak var library: LibraryModel?
    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    override init() {
        super.init()
        let updater = controller.updater
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
        updater.publisher(for: \.automaticallyChecksForUpdates)
            .assign(to: &$automaticallyChecksForUpdates)
        updater.publisher(for: \.automaticallyDownloadsUpdates)
            .assign(to: &$automaticallyDownloadsUpdates)

        // A bare SwiftPM executable has no update feed or app bundle to replace.
        if Bundle.main.bundleURL.pathExtension == "app" {
            controller.startUpdater()
        }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    func setAutomaticChecks(_ enabled: Bool) {
        controller.updater.automaticallyChecksForUpdates = enabled
    }

    func setAutomaticDownloads(_ enabled: Bool) {
        controller.updater.automaticallyDownloadsUpdates = enabled
    }

    func updaterShouldRelaunchApplication(_ updater: SPUUpdater) -> Bool {
        guard library?.canRestartForUpdate == true else {
            let alert = NSAlert()
            alert.messageText = "Walldance Can’t Restart Yet"
            alert.informativeText = "Wait for video preparation and wallpaper changes to finish, then install the update again."
            alert.runModal()
            return false
        }
        return true
    }
}

struct UpdaterSettingsView: View {
    @ObservedObject var updater: AppUpdater

    var body: some View {
        Form {
            Toggle("Check for updates automatically", isOn: Binding(
                get: { updater.automaticallyChecksForUpdates },
                set: { updater.setAutomaticChecks($0) }
            ))
            Toggle("Download and install updates automatically", isOn: Binding(
                get: { updater.automaticallyDownloadsUpdates },
                set: { updater.setAutomaticDownloads($0) }
            ))
            .disabled(!updater.automaticallyChecksForUpdates)
            Button("Check for Updates…") {
                updater.checkForUpdates()
            }
            .disabled(!updater.canCheckForUpdates)
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
