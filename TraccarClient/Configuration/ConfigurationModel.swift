import Foundation
import Observation
import Security

@MainActor
@Observable
final class ConfigurationModel {
    var draft = AppConfiguration()
    private(set) var saved: AppConfiguration?
    private(set) var hasLoaded = false
    private(set) var needsKeychainAuthorization = false
    @ObservationIgnored private var attemptedAutomaticLoad = false
    private(set) var errorMessage: String?
    private(set) var statusMessage: String?

    @ObservationIgnored private var statusTask: Task<Void, Never>?
    @ObservationIgnored private let statusDelay: @MainActor () async throws -> Void
    @ObservationIgnored private let storage: any ConfigurationStorage
    @ObservationIgnored private let generateIdentifier: () -> String
    @ObservationIgnored private let beforeConnectionChange: (ReceiverConnection, ReceiverConnection) throws -> Void

    init(
        storage: any ConfigurationStorage,
        generateIdentifier: @escaping () -> String = { String(Int.random(in: 10_000_000...99_999_999)) },
        statusDelay: @escaping @MainActor () async throws -> Void = { try await Task.sleep(for: .seconds(10)) },
        beforeConnectionChange: @escaping (ReceiverConnection, ReceiverConnection) throws -> Void = { _, _ in }
    ) {
        self.statusDelay = statusDelay
        self.storage = storage
        self.generateIdentifier = generateIdentifier
        self.beforeConnectionChange = beforeConnectionChange
    }

    static func live() -> ConfigurationModel {
        ConfigurationModel(storage: PreferencesConfigurationStorage(
            preferences: .standard, connectionStorage: KeychainConnectionStorage(
                service: "\(Bundle.main.bundleIdentifier ?? "com.codigojose.traccar-client-macos").configuration"
            )
        ))
    }

    func loadIfNeeded() {
        guard !hasLoaded, !attemptedAutomaticLoad else { return }
        reload(allowInteraction: false)
    }

    func reload(allowInteraction: Bool = true) {
        attemptedAutomaticLoad = true
        do {
            let configuration = try storage.load(allowInteraction: allowInteraction)
            draft = configuration
            saved = configuration
            hasLoaded = true
            needsKeychainAuthorization = false
            errorMessage = nil
            showStatus(configuration.connection.deviceIdentifier.isEmpty ? nil : "Configuration loaded.")
        } catch {
            hasLoaded = false
            needsKeychainAuthorization = Self.requiresAuthorization(error)
            errorMessage = !allowInteraction && needsKeychainAuthorization ? nil : message(for: error)
            showStatus(nil)
        }
    }

    @discardableResult
    func save() -> Bool {
        do {
            guard hasLoaded, let saved else { throw ConfigurationError.notLoaded }
            var candidate = draft
            candidate.connection = try candidate.connection.validated()
            try candidate.tracking.validate()
            if candidate.connection.deviceIdentifier.isEmpty {
                candidate.connection.deviceIdentifier = generateIdentifier()
                // Retain the generated value on failure so an explicit retry does not generate another identity.
                draft.connection.deviceIdentifier = candidate.connection.deviceIdentifier
            }
            guard !candidate.connection.deviceIdentifier.isEmpty else { throw ConfigurationError.invalidIdentifier }
            if saved.connection != candidate.connection {
                // Queue/tracking coordination will supply this guard before changing the active destination.
                try beforeConnectionChange(saved.connection, candidate.connection)
            }
            try storage.save(candidate)
            self.saved = candidate
            draft = candidate
            errorMessage = nil
            showStatus("Configuration saved locally. Tracking remains paused.")
            return true
        } catch {
            errorMessage = message(for: error)
            showStatus(nil)
            return false
        }
    }

    private static func requiresAuthorization(_ error: Error) -> Bool {
        guard case ConfigurationError.keychain(let status) = error else { return false }
        return [errSecInteractionNotAllowed, errSecInteractionRequired, errSecAuthFailed, errSecUserCanceled]
            .contains(status)
    }

    private func showStatus(_ message: String?) {
        statusTask?.cancel()
        statusMessage = message
        guard message != nil else { return }
        let delay = statusDelay
        statusTask = Task { [weak self] in
            do {
                try await delay()
                try Task.checkCancellation()
                self?.statusMessage = nil
            } catch {
                // Cancellation leaves the newer message or persistent error in control.
            }
        }
    }

    private func message(for error: Error) -> String {
        if let error = error as? ConfigurationError { return error.localizedDescription }
        return "Configuration could not be saved or loaded. Check storage and try again."
    }
}
