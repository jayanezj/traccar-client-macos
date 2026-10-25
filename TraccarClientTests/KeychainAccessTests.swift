import Foundation
import Security
import Testing

extension ConfigurationTests {
    @Test func keychainIsNotReadUntilExplicitLoadAndCancellationDoesNotReplaceIdentity() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let existing = ReceiverConnection(serverURL: "https://tracker.example", deviceIdentifier: "000123-test")
        fixture.connection.value = existing
        fixture.connection.readError = .keychain(errSecUserCanceled)
        var generated = 0
        let model = ConfigurationModel(storage: fixture.storage, generateIdentifier: {
            generated += 1
            return "12345678"
        })
        #expect(fixture.connection.reads == 0 && !model.hasLoaded)
        model.reload()
        #expect(!model.hasLoaded)
        #expect(model.errorMessage?.contains("cancelled") == true)
        #expect(model.errorMessage?.contains("not saved") == false)
        #expect(model.statusMessage == nil)
        #expect(fixture.connection.reads == 1 && fixture.connection.writes == 0)
        #expect(fixture.connection.value == existing && generated == 0)
        #expect(!model.save())
        #expect(fixture.connection.reads == 1 && fixture.connection.writes == 0)
        fixture.connection.readError = nil
        model.reload()
        #expect(model.hasLoaded && model.errorMessage == nil)
        #expect(model.draft.connection == existing && generated == 0)
        #expect(fixture.connection.reads == 2 && fixture.connection.writes == 0)
    }

    @Test func cancelledWritePreservesLoadedConfigurationAndCanBeRetried() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let existing = ReceiverConnection(deviceIdentifier: "000123-test")
        fixture.connection.value = existing
        let model = ConfigurationModel(storage: fixture.storage)
        model.reload()
        let original = model.saved
        model.draft.connection.serverURL = "https://new.example"
        fixture.connection.writeError = .keychain(errSecUserCanceled)
        #expect(!model.save())
        #expect(model.errorMessage?.contains("cancelled") == true)
        #expect(model.hasLoaded && model.saved == original)
        #expect(fixture.connection.value == existing)
        #expect(fixture.preferences.object(forKey: PreferencesConfigurationStorage.preferencesKey) == nil)
        fixture.connection.writeError = nil
        #expect(model.save())
        #expect(model.errorMessage == nil)
        #expect(try fixture.storage.load().connection.serverURL == "https://new.example")
        #expect(try fixture.storage.load().connection.deviceIdentifier == "000123-test")
    }
}

extension ConfigurationTests {
    @Test func trustedAndEmptyStoresLoadAutomaticallyWithoutAuthorizationStep() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let initial = ConfigurationModel(storage: fixture.storage)
        initial.loadIfNeeded()
        #expect(initial.hasLoaded && !initial.needsKeychainAuthorization)
        #expect(initial.draft.connection.deviceIdentifier.isEmpty)
        #expect(fixture.connection.readModes == [false])
        fixture.connection.value = ReceiverConnection(deviceIdentifier: "000123-test")
        let reopened = ConfigurationModel(storage: fixture.storage)
        reopened.loadIfNeeded()
        reopened.loadIfNeeded()
        #expect(reopened.hasLoaded && !reopened.needsKeychainAuthorization)
        #expect(reopened.draft.connection.deviceIdentifier == "000123-test")
        #expect(fixture.connection.readModes == [false, false])
    }

    @Test func authorizationRequiredExplainsBeforeExplicitRetryWithoutAutomaticLoop() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.connection.readError = .keychain(errSecInteractionNotAllowed)
        let model = ConfigurationModel(storage: fixture.storage)
        model.loadIfNeeded()
        #expect(!model.hasLoaded && model.needsKeychainAuthorization)
        #expect(model.errorMessage == nil)
        model.loadIfNeeded()
        #expect(fixture.connection.readModes == [false])
        fixture.connection.readError = .keychain(errSecUserCanceled)
        model.reload()
        model.loadIfNeeded()
        #expect(model.errorMessage?.contains("cancelled") == true)
        #expect(fixture.connection.readModes == [false, true])
        fixture.connection.readError = nil
        model.reload()
        #expect(model.hasLoaded && !model.needsKeychainAuthorization && model.errorMessage == nil)
        #expect(fixture.connection.readModes == [false, true, true])
    }

    @Test func keychainBackendReceivesNoninteractiveReadMode() throws {
        let operations = FakeKeychainOperations()
        let storage = KeychainConnectionStorage(service: "test.synthetic", operations: operations)
        #expect(try storage.read(allowInteraction: false) == nil)
        operations.readStatus = errSecInteractionNotAllowed
        #expect(throws: ConfigurationError.keychain(errSecInteractionNotAllowed)) {
            try storage.read(allowInteraction: false)
        }
        #expect(operations.readModes == [false, false])
    }
}
