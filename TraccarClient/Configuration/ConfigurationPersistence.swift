import Foundation
import Security

@MainActor
protocol ConnectionStorage {
    func read(allowInteraction: Bool) throws -> ReceiverConnection?
    func write(_ connection: ReceiverConnection) throws
}

@MainActor
protocol ConfigurationStorage {
    func load(allowInteraction: Bool) throws -> AppConfiguration
    func save(_ configuration: AppConfiguration) throws
}

extension ConnectionStorage {
    func read() throws -> ReceiverConnection? { try read(allowInteraction: true) }
}

extension ConfigurationStorage {
    func load() throws -> AppConfiguration { try load(allowInteraction: true) }
}

@MainActor
final class PreferencesConfigurationStorage: ConfigurationStorage {
    private struct Record: Codable {
        var version = 1
        var tracking: TrackingPreferences
    }

    static let preferencesKey = "configuration.v1"
    private let preferences: UserDefaults
    private let connectionStorage: any ConnectionStorage

    init(preferences: UserDefaults, connectionStorage: any ConnectionStorage) {
        self.preferences = preferences
        self.connectionStorage = connectionStorage
    }

    func load(allowInteraction: Bool) throws -> AppConfiguration {
        let data = preferences.data(forKey: Self.preferencesKey)
        let record: Record?
        if let data {
            do {
                record = try JSONDecoder().decode(Record.self, from: data)
            } catch {
                throw ConfigurationError.unreadableStorage
            }
            guard record?.version == 1 else { throw ConfigurationError.unsupportedStorageVersion }
        } else if preferences.object(forKey: Self.preferencesKey) != nil {
            throw ConfigurationError.unreadableStorage
        } else {
            record = nil
        }
        let connection = try connectionStorage.read(allowInteraction: allowInteraction)
        if record != nil && connection == nil { throw ConfigurationError.missingIdentity }
        var configuration = AppConfiguration()
        if let connection {
            guard !connection.deviceIdentifier.isEmpty else { throw ConfigurationError.missingIdentity }
            configuration.connection = try connection.validated()
        }
        if let record { configuration.tracking = record.tracking }
        try configuration.tracking.validate()
        return configuration
    }

    func save(_ configuration: AppConfiguration) throws {
        let connection = try configuration.connection.validated()
        guard !connection.deviceIdentifier.isEmpty else { throw ConfigurationError.invalidIdentifier }
        try configuration.tracking.validate()
        let data = try JSONEncoder().encode(Record(tracking: configuration.tracking))
        // Keychain errors leave UserDefaults untouched. Connection and identity share one secure item.
        try connectionStorage.write(connection)
        preferences.set(data, forKey: Self.preferencesKey)
    }
}

@MainActor
protocol KeychainOperations {
    func copyMatching(
        _ query: CFDictionary, allowInteraction: Bool, result: UnsafeMutablePointer<CFTypeRef?>
    ) -> OSStatus
    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus
    func add(_ attributes: CFDictionary) -> OSStatus
}

@MainActor
struct SystemKeychainOperations: KeychainOperations {
    func copyMatching(
        _ query: CFDictionary, allowInteraction: Bool, result: UnsafeMutablePointer<CFTypeRef?>
    ) -> OSStatus {
        if allowInteraction { return SecItemCopyMatching(query, result) }
        // SecItem's LAContext/UI flags do not suppress dialogs for file-based keychains.
        // Keep this synchronous and on MainActor with every other Keychain operation.
        var previous: DarwinBoolean = false
        var status = SecKeychainGetUserInteractionAllowed(&previous)
        guard status == errSecSuccess else { return status }
        status = SecKeychainSetUserInteractionAllowed(false)
        guard status == errSecSuccess else { return status }
        let readStatus = SecItemCopyMatching(query, result)
        let restoreStatus = SecKeychainSetUserInteractionAllowed(previous.boolValue)
        return restoreStatus == errSecSuccess ? readStatus : restoreStatus
    }

    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus {
        SecItemUpdate(query, attributes)
    }

    func add(_ attributes: CFDictionary) -> OSStatus {
        SecItemAdd(attributes, nil)
    }
}

@MainActor
final class KeychainConnectionStorage: ConnectionStorage {
    private let service: String
    private let operations: any KeychainOperations
    private let account = "receiver-identity.v1"

    init(
        service: String = "com.codigojose.traccar-client-macos.configuration",
        operations: any KeychainOperations = SystemKeychainOperations()
    ) {
        self.service = service
        self.operations = operations
    }

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
    }

    func read(allowInteraction: Bool) throws -> ReceiverConnection? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = operations.copyMatching(
            request as CFDictionary, allowInteraction: allowInteraction, result: &result
        )
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw ConfigurationError.keychain(status) }
        guard let data = result as? Data,
              let connection = try? JSONDecoder().decode(ReceiverConnection.self, from: data) else {
            throw ConfigurationError.unreadableStorage
        }
        return connection
    }

    func write(_ connection: ReceiverConnection) throws {
        let data = try JSONEncoder().encode(connection)
        var status = operations.update(query as CFDictionary, attributes: [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = query
            attributes[kSecValueData as String] = data
            status = operations.add(attributes as CFDictionary)
        }
        guard status == errSecSuccess else { throw ConfigurationError.keychain(status) }
    }
}
