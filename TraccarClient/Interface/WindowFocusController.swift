import AppKit

@MainActor
protocol FocusRestorationWindow: AnyObject {
    var isVisible: Bool { get }
    var isMiniaturized: Bool { get }
    func restoreKeyWindow()
}

extension NSWindow: FocusRestorationWindow {
    func restoreKeyWindow() { makeKeyAndOrderFront(nil) }
}

@MainActor
final class WindowFocusController {
    // A workspace activation sends a reopen event. Its window is selected only after activation finishes.
    private(set) static var pendingActivations = 0

    weak var window: (any FocusRestorationWindow)?
    private var restoration: Task<Void, Never>?
    private let activate: @MainActor () async -> Bool

    init(activate: @escaping @MainActor () async -> Bool = activateCurrentApplication) {
        self.activate = activate
    }

    @discardableResult
    func perform(_ action: () -> Void) -> Task<Void, Never>? {
        restoration?.cancel()
        let initiatingWindow = window
        action()
        guard let initiatingWindow, initiatingWindow.isVisible, !initiatingWindow.isMiniaturized else { return nil }
        let activate = activate
        restoration = Task { [weak initiatingWindow] in
            guard !Task.isCancelled, let initiatingWindow,
                  initiatingWindow.isVisible, !initiatingWindow.isMiniaturized else { return }
            Self.pendingActivations += 1
            defer { Self.pendingActivations -= 1 }
            guard await activate(), !Task.isCancelled,
                  initiatingWindow.isVisible, !initiatingWindow.isMiniaturized else { return }
            initiatingWindow.restoreKeyWindow()
        }
        return restoration
    }

    private static func activateCurrentApplication() async -> Bool {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        configuration.allowsRunningApplicationSubstitution = false
        configuration.addsToRecentItems = false
        configuration.promptsUserIfNeeded = false
        do {
            // Launch Services supplies activation context that a plain NSApp.activate() cannot guarantee.
            let application = try await NSWorkspace.shared.openApplication(
                at: Bundle.main.bundleURL, configuration: configuration
            )
            return application.processIdentifier == ProcessInfo.processInfo.processIdentifier
        } catch {
            return false
        }
    }
}
