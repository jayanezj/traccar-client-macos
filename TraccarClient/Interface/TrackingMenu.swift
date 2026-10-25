import AppKit
import SwiftUI

struct TrackingMenu: View {
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    let location: LocationModel

    var body: some View {
        Text(location.continuousRequested ? "Location capture active" : "Paused")
        Text(location.status)
        Text("Local capture only. No positions are sent.")
        if let fix = location.lastFix {
            Text("Last fix: \(fix.timestamp.formatted(date: .numeric, time: .standard))")
            Text("Reported accuracy: \(fix.horizontalAccuracy.formatted()) m")
        }

        Divider()

        Button(location.continuousRequested ? "Pause location capture" : "Start location capture") {
            if location.continuousRequested { location.pause() } else if location.availability.canCapture {
                location.startContinuous()
            } else {
                showCaptureWindow()
            }
        }
        Button("Capture location once") {
            if location.availability.canCapture {
                location.captureOnce()
            }
            showCaptureWindow()
        }
        .disabled(location.singleStatus == .waiting)
        Button("Location status…") { showCaptureWindow() }
        Button("Send location now") {}
            .disabled(true)
        Button("Send SOS") {}
            .disabled(true)

        Divider()

        Button("Settings…") {
            NSApplication.shared.activate()
            openSettings()
        }
        .keyboardShortcut(",")

        Button("About Traccar Client for macOS") {
            NSApplication.shared.activate()
            NSApplication.shared.orderFrontStandardAboutPanel(options: [
                .applicationName: "Traccar Client for macOS",
                .credits: NSAttributedString(
                    string: "An independent, unofficial Traccar client.\nLicensed under Apache License 2.0."
                ),
            ])
        }

        Divider()

        Button("Quit Traccar Client macOS") {
            location.shutdown()
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func showCaptureWindow() {
        NSApplication.shared.activate()
        openWindow(id: "location-capture")
    }
}
