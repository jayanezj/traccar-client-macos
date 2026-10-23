import AppKit
import SwiftUI

@main
struct TraccarClientApp: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            TrackingMenu()
        } label: {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .accessibilityLabel("Traccar Client — Paused")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
        }
    }
}

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
