import Foundation
import Security
import Testing

@Suite @MainActor
struct ConfigurationTests {
    @Test func defaultsDoNotGenerateIdentity() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        var generated = 0
        let model = ConfigurationModel(storage: fixture.storage, generateIdentifier: {
            generated += 1
            return "12345678"
        })
        model.loadIfNeeded()
        model.loadIfNeeded()
        #expect(model.draft == AppConfiguration())
        #expect(model.draft.connection.serverURL == "http://demo.traccar.org:5055")
        #expect(model.draft.tracking.intervalSeconds == 300)
        #expect(model.draft.tracking.distanceMetres == 75)
        #expect(model.draft.tracking.accuracy == .medium)
        #expect(!model.draft.tracking.launchAtLogin && !model.draft.tracking.restoreTracking)
        #expect(generated == 0 && fixture.connection.writes == 0)
        #expect(model.save())
        #expect(generated == 1)
        #expect(model.save())
        #expect(generated == 1)
        #expect(try fixture.storage.load().connection.deviceIdentifier == "12345678")
    }

    @Test func randomIdentityHasEightDigitsAndSurvivesModelRecreation() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let model = ConfigurationModel(storage: fixture.storage)
        model.loadIfNeeded()
        #expect(model.save())
        let identifier = model.draft.connection.deviceIdentifier
        #expect(identifier.count == 8 && identifier.utf8.allSatisfy { (48...57).contains($0) })
        let reopened = ConfigurationModel(storage: fixture.storage, generateIdentifier: {
            Issue.record("Loading an existing identity must never generate another one")
            return "unexpected"
        })
        reopened.loadIfNeeded()
        #expect(reopened.draft.connection.deviceIdentifier == identifier)
    }

    @Test func roundTripPreservesSettingsAndExactIdentifier() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        var configuration = AppConfiguration()
        configuration.connection = ReceiverConnection(
            serverURL: "https://tracker.example:8443/OsmAnd?token=synthetic", deviceIdentifier: "000123-AbC"
        )
        configuration.tracking.intervalSeconds = 42
        configuration.tracking.distanceMetres = 12.5
        configuration.tracking.accuracy = .high
        configuration.tracking.angleDegrees = 30
        configuration.tracking.heartbeatSeconds = 60
        configuration.tracking.bufferingEnabled = false
        configuration.tracking.stationaryDetectionEnabled = false
        try fixture.storage.save(configuration)
        let reopened = PreferencesConfigurationStorage(
            preferences: fixture.preferences, connectionStorage: fixture.connection
        )
        #expect(try reopened.load() == configuration)
        let data = try #require(fixture.preferences.data(forKey: PreferencesConfigurationStorage.preferencesKey))
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(!text.contains("000123") && !text.contains("tracker.example") && !text.contains("synthetic"))
    }

    @Test(arguments: [
        "", "ftp://example.com", "https:///", "example.com:5055", "http://host:0", "http://host:65536",
        "http://host:abc", "http://host:", "https://host/a%xx", " https://host", "https://host/a b",
        "https://user:password@host", "https://host/#fragment",
    ])
    func invalidURLsAreRejected(value: String) {
        #expect(throws: ConfigurationError.invalidURL) { try ReceiverConnection.canonicalURL(value) }
    }

    @Test(arguments: [
        "http://192.0.2.1:5055", "https://tracker.example:8443/OsmAnd?key=synthetic",
        "http://[2001:db8::1]:5055/receiver", "https://tracker.example/a%20b",
        "https://tracker.example/receiver?next=http://synthetic:",
    ])
    func supportedURLsRoundTrip(value: String) throws {
        #expect(try ReceiverConnection.canonicalURL(value) == value)
    }

    @Test func URLNormalizationPreservesPathAndQueryCase() throws {
        #expect(try ReceiverConnection.canonicalURL("HTTPS://TRACKER.EXAMPLE:443/") == "https://tracker.example")
        #expect(try ReceiverConnection.canonicalURL("http://TRACKER.EXAMPLE:80/Path?Key=Value")
                == "http://tracker.example/Path?Key=Value")
    }

    @Test func invalidTrackingAndIdentifierDoNotWrite() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let model = ConfigurationModel(storage: fixture.storage)
        model.loadIfNeeded()
        model.draft.tracking.intervalSeconds = -.infinity
        #expect(!model.save())
        model.draft.tracking = TrackingPreferences()
        model.draft.connection.deviceIdentifier = "\n"
        #expect(!model.save())
        #expect(fixture.connection.writes == 0)
        #expect(model.saved == AppConfiguration())
        for value in [Double.nan, .infinity, -1] {
            var tracking = TrackingPreferences()
            tracking.distanceMetres = value
            #expect(throws: ConfigurationError.invalidTracking) { try tracking.validate() }
        }
        var tracking = TrackingPreferences()
        tracking.angleDegrees = 181
        #expect(throws: ConfigurationError.invalidTracking) { try tracking.validate() }
    }

    @Test func failedSaveRetainsGeneratedIdentityAndPreferences() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        var generated = 0
        let model = ConfigurationModel(storage: fixture.storage, generateIdentifier: {
            generated += 1
            return "87654321"
        })
        model.loadIfNeeded()
        fixture.connection.writeError = .keychain(errSecAuthFailed)
        #expect(!model.save())
        #expect(model.draft.connection.deviceIdentifier == "87654321")
        #expect(model.saved == AppConfiguration())
        #expect(fixture.preferences.object(forKey: PreferencesConfigurationStorage.preferencesKey) == nil)
        fixture.connection.writeError = nil
        #expect(model.save())
        #expect(generated == 1)
    }

    @Test func unavailableKeychainBlocksSaveUntilReload() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.connection.readError = .keychain(errSecInteractionNotAllowed)
        let model = ConfigurationModel(storage: fixture.storage)
        model.loadIfNeeded()
        #expect(!model.hasLoaded && model.needsKeychainAuthorization)
        #expect(!model.save())
        #expect(fixture.connection.writes == 0)
        fixture.connection.readError = nil
        model.reload()
        #expect(model.hasLoaded)
    }

    @Test func missingIdentityDoesNotSilentlyReplaceDevice() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        var configuration = AppConfiguration()
        configuration.connection.deviceIdentifier = "00123"
        try fixture.storage.save(configuration)
        fixture.connection.value = nil
        #expect(throws: ConfigurationError.missingIdentity) { try fixture.storage.load() }
    }

    @Test func corruptOrFuturePreferencesAreNotReset() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let key = PreferencesConfigurationStorage.preferencesKey
        fixture.preferences.set(Data("invalid".utf8), forKey: key)
        #expect(throws: ConfigurationError.unreadableStorage) { try fixture.storage.load() }
        let encoded = try JSONEncoder().encode(TrackingPreferences())
        let tracking = try #require(String(data: encoded, encoding: .utf8))
        fixture.preferences.set(Data("{\"version\":2,\"tracking\":\(tracking)}".utf8), forKey: key)
        #expect(throws: ConfigurationError.unsupportedStorageVersion) { try fixture.storage.load() }
        fixture.preferences.set("unexpected type", forKey: key)
        #expect(throws: ConfigurationError.unreadableStorage) { try fixture.storage.load() }
        #expect(fixture.connection.writes == 0)
    }

    @Test func connectionGuardRunsBeforeMutationAndSkipsTrackingOnlyChanges() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.connection.value = ReceiverConnection(serverURL: "https://tracker.example", deviceIdentifier: "00123")
        var guarded = 0
        let model = ConfigurationModel(storage: fixture.storage, beforeConnectionChange: { _, _ in
            guarded += 1
            throw ConfigurationError.notLoaded
        })
        model.loadIfNeeded()
        model.draft.connection.serverURL = "HTTPS://TRACKER.EXAMPLE:443/"
        model.draft.tracking.intervalSeconds = 90
        #expect(model.save())
        #expect(guarded == 0)
        model.draft.connection.deviceIdentifier = "other-device"
        #expect(!model.save())
        #expect(guarded == 1 && fixture.connection.writes == 1)
        #expect(fixture.connection.value?.deviceIdentifier == "00123")
        model.draft.connection.deviceIdentifier = "00123"
        model.draft.connection.serverURL = "https://other.example"
        #expect(!model.save())
        #expect(guarded == 2 && fixture.connection.writes == 1)
    }

    @Test func keychainUsesUpdateThenAddOnlyWhenMissing() throws {
        let operations = FakeKeychainOperations()
        let storage = KeychainConnectionStorage(service: "test.synthetic", operations: operations)
        let connection = ReceiverConnection(deviceIdentifier: "000123")
        #expect(try storage.read() == nil)
        try storage.write(connection)
        #expect(operations.adds == 1)
        operations.updateStatus = errSecSuccess
        try storage.write(connection)
        #expect(operations.adds == 1)
        operations.readStatus = errSecSuccess
        #expect(try storage.read() == connection)
        operations.updateStatus = errSecAuthFailed
        #expect(throws: ConfigurationError.keychain(errSecAuthFailed)) { try storage.write(connection) }
        #expect(operations.adds == 1)
        operations.readStatus = errSecInteractionNotAllowed
        #expect(throws: ConfigurationError.keychain(errSecInteractionNotAllowed)) { try storage.read() }
        operations.readStatus = errSecSuccess
        operations.data = Data("broken".utf8)
        #expect(throws: ConfigurationError.unreadableStorage) { try storage.read() }
    }
}

@MainActor
struct Fixture {
    let suite = "TraccarConfigurationTests.\(UUID().uuidString)"
    let preferences: UserDefaults
    let connection = FakeConnectionStorage()
    let storage: PreferencesConfigurationStorage

    init() throws {
        preferences = try #require(UserDefaults(suiteName: suite))
        storage = PreferencesConfigurationStorage(preferences: preferences, connectionStorage: connection)
    }

    func cleanUp() { preferences.removePersistentDomain(forName: suite) }
}

@MainActor
final class FakeConnectionStorage: ConnectionStorage {
    var value: ReceiverConnection?
    var readError: ConfigurationError?
    var writeError: ConfigurationError?
    var writes = 0
    var reads = 0
    var readModes: [Bool] = []

    func read(allowInteraction: Bool) throws -> ReceiverConnection? {
        reads += 1
        readModes.append(allowInteraction)
        if let readError { throw readError }
        return value
    }

    func write(_ connection: ReceiverConnection) throws {
        if let writeError { throw writeError }
        writes += 1
        value = connection
    }
}

@MainActor
final class FakeKeychainOperations: KeychainOperations {
    var readStatus = errSecItemNotFound
    var updateStatus = errSecItemNotFound
    var adds = 0
    var data: Data?
    var readModes: [Bool] = []

    func copyMatching(
        _ query: CFDictionary, allowInteraction: Bool, result: UnsafeMutablePointer<CFTypeRef?>
    ) -> OSStatus {
        readModes.append(allowInteraction)
        let attributes = query as NSDictionary
        #expect(attributes[kSecAttrService] as? String == "test.synthetic")
        #expect(attributes[kSecAttrSynchronizable] as? Bool == false)
        result.pointee = data as CFData?
        return readStatus
    }

    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus {
        if updateStatus == errSecSuccess { data = (attributes as NSDictionary)[kSecValueData] as? Data }
        return updateStatus
    }

    func add(_ attributes: CFDictionary) -> OSStatus {
        adds += 1
        data = (attributes as NSDictionary)[kSecValueData] as? Data
        return errSecSuccess
    }
}

@MainActor
private final class ControlledStatusDelay {
    private var continuations: [CheckedContinuation<Void, Never>?] = []
    private var returned: Set<Int> = []

    func wait() async {
        let index = continuations.count
        await withCheckedContinuation { continuations.append($0) }
        returned.insert(index)
    }

    func waitUntilScheduled(_ count: Int) async {
        while continuations.count < count { await Task.yield() }
    }

    func finish(_ index: Int) {
        continuations[index]?.resume()
        continuations[index] = nil
    }

    func waitUntilReturned(_ index: Int) async {
        while !returned.contains(index) { await Task.yield() }
    }
}

extension ConfigurationTests {
    @Test func informationalStatusExpiresAfterDelay() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let delay = ControlledStatusDelay()
        let model = ConfigurationModel(storage: fixture.storage, statusDelay: { await delay.wait() })
        model.loadIfNeeded()
        #expect(model.save())
        #expect(model.statusMessage != nil)
        await delay.waitUntilScheduled(1)
        delay.finish(0)
        await delay.waitUntilReturned(0)
        #expect(model.statusMessage == nil)
        model.reload()
        #expect(model.statusMessage == "Configuration loaded.")
        await delay.waitUntilScheduled(2)
        delay.finish(1)
        await delay.waitUntilReturned(1)
        #expect(model.statusMessage == nil)
    }

    @Test func olderTimerCannotDismissNewerStatus() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let delay = ControlledStatusDelay()
        let model = ConfigurationModel(storage: fixture.storage, statusDelay: { await delay.wait() })
        model.loadIfNeeded()
        #expect(model.save())
        await delay.waitUntilScheduled(1)
        #expect(model.save())
        await delay.waitUntilScheduled(2)
        delay.finish(0)
        await delay.waitUntilReturned(0)
        #expect(model.statusMessage != nil)
        delay.finish(1)
        await delay.waitUntilReturned(1)
        #expect(model.statusMessage == nil)
    }

    @Test func errorsRemainVisibleWhenOldTimerFinishes() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let delay = ControlledStatusDelay()
        let model = ConfigurationModel(storage: fixture.storage, statusDelay: { await delay.wait() })
        model.loadIfNeeded()
        #expect(model.save())
        await delay.waitUntilScheduled(1)
        model.draft.connection.serverURL = "invalid"
        #expect(!model.save())
        let error = model.errorMessage
        delay.finish(0)
        await delay.waitUntilReturned(0)
        #expect(model.statusMessage == nil && model.errorMessage == error && error != nil)
    }

}
