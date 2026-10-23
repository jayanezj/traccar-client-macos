import AppKit
import SwiftUI

struct TrackingMenu: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text("Paused")
        Text("Tracking is not available in this build.")

        Divider()

        Button("Start tracking") {}
            .disabled(true)
        Button("Send location now") {}
            .disabled(true)
        Button("Send SOS") {}
            .disabled(true)

        Divider()

        Button("Settings…") {
            NSApplication.shared.activate(ignoringOtherApps: true)
            openSettings()
        }
        .keyboardShortcut(",")

        Button("About Traccar Client for macOS") {
            NSApplication.shared.activate(ignoringOtherApps: true)
            NSApplication.shared.orderFrontStandardAboutPanel(options: [
                .applicationName: "Traccar Client for macOS",
                .credits: NSAttributedString(
                    string: "An independent, unofficial Traccar client.\nLicensed under Apache License 2.0."
                ),
            ])
        }

        Divider()

        Button("Quit Traccar Client macOS") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
