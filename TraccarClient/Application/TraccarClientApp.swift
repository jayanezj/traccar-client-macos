import AppKit
import SwiftUI

@main
struct TraccarClientApp: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var delegate

    @State private var configuration: ConfigurationModel
    @State private var location: LocationModel

    init() {
        let storage = PreferencesConfigurationStorage.live()
        let capture = LocationModel(provider: CoreLocationProvider(), readAccuracy: {
            try storage.loadTrackingPreferences().accuracy
        })
        _location = State(initialValue: capture)
        _configuration = State(initialValue: ConfigurationModel(storage: storage, beforeConnectionChange: { _, _ in
            capture.shutdown()
        }))
    }

    var body: some Scene {
        MenuBarExtra {
            TrackingMenu(location: location)
        } label: {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .accessibilityLabel("Traccar Client — \(location.status)")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(model: configuration, location: location)
        }

        Window("Location capture", id: "location-capture") {
            LocationStatusView(location: location)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }
}

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    private let openWindows = NSHashTable<NSWindow>.weakObjects()
    private var closingWindows: Set<ObjectIdentifier> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = NotificationCenter.default
        let notifications = [
            NSWindow.didBecomeKeyNotification, NSWindow.didUpdateNotification, NSWindow.willCloseNotification,
        ]
        for name in notifications {
            center.addObserver(self, selector: #selector(windowChanged(_:)), name: name, object: nil)
        }
    }

    @objc private func windowChanged(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.level == .normal, window.canBecomeKey else { return }
        let identity = ObjectIdentifier(window)
        if notification.name == NSWindow.willCloseNotification {
            closingWindows.insert(identity)
            openWindows.remove(window)
        } else {
            if notification.name == NSWindow.didBecomeKeyNotification { closingWindows.remove(identity) }
            guard !closingWindows.contains(identity), window.isVisible || window.isMiniaturized else { return }
            openWindows.add(window)
        }
        let policy: NSApplication.ActivationPolicy = openWindows.allObjects.isEmpty ? .accessory : .regular
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
            if policy == .regular { NSApp.activate() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard WindowFocusController.pendingActivations == 0 else { return false }
        if let window = sender.windows.first(where: { openWindows.contains($0) }) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        }
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
