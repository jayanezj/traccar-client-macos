import CoreLocation
import Foundation
import Testing

@Suite @MainActor
struct LocationModelTests {
    @Test func passiveStatusChangesNeverRequestPermissionOrCapture() {
        let provider = FakeLocationProvider(permission: .notDetermined)
        let model = LocationModel(provider: provider)
        model.refreshAvailability()
        provider.publish(permission: .authorized)
        #expect(!model.continuousRequested && model.singleStatus == .idle)
        #expect(provider.authorizationRequests == 0 && provider.starts.isEmpty && provider.singles.isEmpty)
    }

    @Test func explicitStartRequestsPermissionOnceAndWaitsForGrant() {
        let provider = FakeLocationProvider(permission: .notDetermined)
        let model = LocationModel(provider: provider)
        model.startContinuous()
        model.startContinuous()
        provider.publish(permission: .notDetermined)
        #expect(provider.authorizationRequests == 1 && provider.starts.isEmpty)
        provider.publish(permission: .authorized)
        provider.publish(permission: .authorized)
        #expect(model.continuousRequested && provider.starts.count == 1)
        #expect(provider.startedAccuracies == [.medium])
    }

    @Test(arguments: [
        LocationAvailability(permission: .denied, services: .enabled),
        LocationAvailability(permission: .restricted, services: .enabled),
        LocationAvailability(permission: .notDetermined, services: .disabled),
    ])
    func blockedStatesDoNotPromptOrStart(availability: LocationAvailability) {
        let provider = FakeLocationProvider()
        provider.availability = availability
        let model = LocationModel(provider: provider)
        model.startContinuous()
        model.captureOnce()
        #expect(model.continuousRequested && model.singleStatus == .failed)
        #expect(model.errorMessage != nil)
        #expect(provider.authorizationRequests == 0 && provider.starts.isEmpty && provider.singles.isEmpty)
    }

    @Test func pauseBeforeAuthorizationPreventsDelayedStart() {
        let provider = FakeLocationProvider(permission: .notDetermined)
        let model = LocationModel(provider: provider)
        model.startContinuous()
        model.pause()
        provider.publish(permission: .authorized)
        #expect(!model.continuousRequested && provider.starts.isEmpty)
    }

    @Test func undeterminedPermissionCanBeRetriedOnlyByANewExplicitAttempt() {
        let provider = FakeLocationProvider(permission: .notDetermined)
        let model = LocationModel(provider: provider)
        model.captureOnce()
        model.cancelSingle()
        model.refreshAvailability()
        #expect(provider.authorizationRequests == 1)
        model.captureOnce()
        #expect(provider.authorizationRequests == 2)
        provider.publish(permission: .denied)
        model.captureOnce()
        #expect(provider.authorizationRequests == 2)
    }

    @Test func pauseRejectsLateFixAndResumeUsesNewSession() throws {
        let provider = FakeLocationProvider()
        let model = LocationModel(provider: provider)
        model.startContinuous(accuracy: .high)
        let old = try #require(provider.starts.last)
        let stops = provider.continuousStops
        model.pause()
        #expect(provider.continuousStops == stops + 1)
        provider.emit(.locations(.continuous, request: old, fixes: [try sampleFix()]))
        #expect(model.lastFix == nil)
        model.startContinuous(accuracy: .low)
        let current = try #require(provider.starts.last)
        #expect(old != current && provider.startedAccuracies == [.high, .low])
        provider.emit(.locations(.continuous, request: old, fixes: [try sampleFix()]))
        #expect(model.lastFix == nil)
        provider.emit(.locations(.continuous, request: current, fixes: [try sampleFix()]))
        #expect(model.lastFix != nil)
    }

    @Test func revokedPermissionStopsAcquisitionWithoutChangingUserIntent() throws {
        let provider = FakeLocationProvider()
        let model = LocationModel(provider: provider)
        model.startContinuous()
        let old = try #require(provider.starts.last)
        let stops = provider.continuousStops
        provider.publish(permission: .denied)
        #expect(provider.continuousStops > stops)
        provider.emit(.locations(.continuous, request: old, fixes: [try sampleFix()]))
        #expect(model.lastFix == nil && model.continuousRequested)
        #expect(model.status == "Location permission denied")
        provider.publish(permission: .authorized)
        #expect(provider.starts.count == 2 && provider.starts.last != old)
        model.pause()
        provider.publish(permission: .authorized)
        #expect(provider.starts.count == 2)
    }

    @Test func singleCaptureRemainsPausedAndDuplicatePressIsIgnored() throws {
        let provider = FakeLocationProvider()
        let model = LocationModel(provider: provider)
        model.captureOnce()
        model.captureOnce()
        let request = try #require(provider.singles.last)
        #expect(provider.singles.count == 1 && provider.starts.isEmpty)
        let fix = try sampleFix(age: 86_400, accuracy: 5_000)
        provider.emit(.locations(.single, request: request, fixes: [fix]))
        #expect(!model.continuousRequested && model.singleStatus == .received)
        #expect(model.lastFix == fix && model.lastFixOrigin == .single)
        #expect(model.status == "Paused")
    }

    @Test func singleCaptureSurvivesPausingContinuousCapture() throws {
        let provider = FakeLocationProvider()
        let model = LocationModel(provider: provider)
        model.startContinuous()
        model.captureOnce()
        let request = try #require(provider.singles.last)
        let cancels = provider.singleCancellations
        model.pause()
        #expect(provider.singleCancellations == cancels && model.singleStatus == .waiting)
        provider.emit(.locations(.single, request: request, fixes: [try sampleFix()]))
        #expect(model.singleStatus == .received && !model.continuousRequested)
    }

    @Test func cancelSingleRejectsItsCallbacksWithoutStoppingContinuousCapture() throws {
        let provider = FakeLocationProvider()
        let model = LocationModel(provider: provider)
        model.startContinuous()
        model.captureOnce()
        let old = try #require(provider.singles.last)
        model.cancelSingle()
        provider.emit(.locations(.single, request: old, fixes: [try sampleFix()]))
        #expect(model.lastFix == nil && model.continuousRequested && model.singleStatus == .cancelled)
        model.captureOnce()
        #expect(provider.singles.last != old)
        provider.emit(.failure(.single, request: old, reason: .unavailable, fallback: nil))
        #expect(model.singleStatus == .waiting && model.errorMessage == nil)
    }

    @Test func unavailableSingleUsesKnownFixWithoutInventingTimestamp() throws {
        let provider = FakeLocationProvider()
        let model = LocationModel(provider: provider)
        model.captureOnce()
        let request = try #require(provider.singles.last)
        let old = try sampleFix(age: 40 * 86_400, accuracy: 7_500)
        provider.emit(.failure(.single, request: request, reason: .unavailable, fallback: old))
        #expect(model.singleStatus == .lastKnown && model.lastFixOrigin == .lastKnown)
        #expect(model.lastFix == old && model.errorMessage != nil)
        #expect(!model.continuousRequested)
    }

    @Test func unavailableWithoutKnownFixDoesNotReportSuccess() throws {
        let provider = FakeLocationProvider()
        let model = LocationModel(provider: provider)
        model.captureOnce()
        let request = try #require(provider.singles.last)
        provider.emit(.failure(.single, request: request, reason: .unavailable, fallback: nil))
        #expect(model.singleStatus == .failed && model.lastFix == nil && model.errorMessage != nil)
    }

    @Test func deniedSingleDoesNotUseFallback() throws {
        let provider = FakeLocationProvider()
        let model = LocationModel(provider: provider)
        model.captureOnce()
        let request = try #require(provider.singles.last)
        provider.emit(.failure(.single, request: request, reason: .permissionDenied, fallback: try sampleFix()))
        #expect(model.singleStatus == .failed && model.lastFix == nil)
    }

    @Test func transientFailureKeepsContinuousIntentAndNextFixClearsError() throws {
        let provider = FakeLocationProvider()
        let model = LocationModel(provider: provider)
        model.startContinuous()
        let request = try #require(provider.starts.last)
        provider.emit(.failure(.continuous, request: request, reason: .unavailable, fallback: nil))
        #expect(model.continuousRequested && model.continuousError != nil)
        provider.emit(.locations(.continuous, request: request, fixes: [try sampleFix()]))
        #expect(model.continuousError == nil && model.lastFix != nil)
    }

    @Test func newestSuppliedTimestampWinsWithinBatch() throws {
        let provider = FakeLocationProvider()
        let model = LocationModel(provider: provider)
        model.startContinuous()
        let request = try #require(provider.starts.last)
        let newer = try sampleFix(age: 10)
        provider.emit(.locations(.continuous, request: request, fixes: [newer, try sampleFix(age: 60)]))
        #expect(model.lastFix == newer)
    }

    @Test func shutdownCancelsBothOperationsAndLateUpdatesAreIgnored() throws {
        let provider = FakeLocationProvider()
        let model = LocationModel(provider: provider)
        model.startContinuous()
        model.captureOnce()
        let single = try #require(provider.singles.last)
        let continuous = try #require(provider.starts.last)
        model.shutdown()
        provider.emit(.locations(.single, request: single, fixes: [try sampleFix()]))
        provider.emit(.locations(.continuous, request: continuous, fixes: [try sampleFix()]))
        #expect(!model.continuousRequested && model.singleStatus == .cancelled && model.lastFix == nil)
    }

}

extension LocationModelTests {
    @Test func changingReceiverPausesCaptureBeforeSaving() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.connection.value = ReceiverConnection(deviceIdentifier: "000123-test")
        let provider = FakeLocationProvider()
        let location = LocationModel(provider: provider)
        let configuration = ConfigurationModel(storage: fixture.storage, beforeConnectionChange: { _, _ in
            location.shutdown()
        })
        configuration.loadIfNeeded()
        location.startContinuous()
        location.captureOnce()
        configuration.draft.connection.serverURL = "https://receiver.example"
        #expect(configuration.save() && !location.continuousRequested && location.singleStatus == .cancelled)
    }

    @Test func savedAccuracyLoadsWithoutAccessingKeychainOrOpeningSettings() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        var configuration = AppConfiguration()
        configuration.connection.deviceIdentifier = "000123-test"
        configuration.tracking.accuracy = .high
        try fixture.storage.save(configuration)
        fixture.connection.readError = .keychain(-128)
        let provider = FakeLocationProvider()
        let model = LocationModel(provider: provider, readAccuracy: {
            try fixture.storage.loadTrackingPreferences().accuracy
        })
        model.startContinuous()
        #expect(provider.startedAccuracies == [.high] && fixture.connection.reads == 0)
    }

    @Test func unreadablePreferencesDoNotStartCaptureOrAskPermission() {
        let provider = FakeLocationProvider(permission: .notDetermined)
        let model = LocationModel(provider: provider, readAccuracy: { throw ConfigurationError.unreadableStorage })
        model.startContinuous()
        model.captureOnce()
        #expect(model.errorMessage != nil && !model.continuousRequested)
        #expect(provider.authorizationRequests == 0 && provider.starts.isEmpty && provider.singles.isEmpty)
    }

    @Test func disabledServicesStopBothRequestsAndRecoveryRespectsContinuousIntent() throws {
        let provider = FakeLocationProvider()
        let model = LocationModel(provider: provider)
        model.startContinuous()
        model.captureOnce()
        let old = try #require(provider.starts.last)
        let stops = provider.continuousStops
        provider.availability.services = .disabled
        model.refreshAvailability()
        #expect(provider.continuousStops > stops && provider.singleCancellations > 0)
        #expect(model.continuousRequested && model.singleStatus == .failed)
        provider.emit(.locations(.continuous, request: old, fixes: [try sampleFix()]))
        #expect(model.lastFix == nil)
        provider.availability.services = .enabled
        model.refreshAvailability()
        #expect(provider.starts.count == 2 && provider.starts.last != old)
        #expect(provider.singles.count == 1)
    }

    @Test func initialAvailabilityCheckDelaysPermissionUntilServicesAreEnabled() {
        let provider = FakeLocationProvider(permission: .notDetermined)
        provider.availability.services = .checking
        let model = LocationModel(provider: provider)
        model.startContinuous()
        #expect(provider.authorizationRequests == 0 && provider.starts.isEmpty)
        provider.availability.services = .enabled
        model.refreshAvailability()
        #expect(provider.authorizationRequests == 1 && provider.starts.isEmpty)
        provider.publish(permission: .authorized)
        #expect(provider.starts.count == 1)
    }
}

@MainActor
private final class FakeLocationProvider: LocationProviding {
    var availability: LocationAvailability
    var onEvent: ((LocationEvent) -> Void)?
    var authorizationRequests = 0
    var starts: [Int] = []
    var singles: [Int] = []
    var startedAccuracies: [LocationAccuracy] = []
    var singleCancellations = 0
    var continuousStops = 0

    init(permission: LocationPermission = .authorized) {
        availability = LocationAvailability(permission: permission, services: .enabled)
    }

    func publish(permission: LocationPermission) {
        availability.permission = permission
        onEvent?(.availability(availability))
    }

    func emit(_ event: LocationEvent) { onEvent?(event) }
    func refreshAvailability() { onEvent?(.availability(availability)) }
    func requestAuthorization() { authorizationRequests += 1 }
    func stopContinuous() { continuousStops += 1 }
    func cancelSingle() { singleCancellations += 1 }
    func startContinuous(accuracy: LocationAccuracy, request: Int) {
        starts.append(request)
        startedAccuracies.append(accuracy)
    }
    func requestSingle(accuracy: LocationAccuracy, request: Int) { singles.append(request) }
}

private func sampleFix(age: TimeInterval = 0, accuracy: Double = 100) throws -> LocationFix {
    try #require(LocationFix(CLLocation(
        coordinate: CLLocationCoordinate2D(latitude: 1, longitude: 2), altitude: 10,
        horizontalAccuracy: accuracy, verticalAccuracy: 5,
        timestamp: Date(timeIntervalSince1970: 1_700_000_000 - age)
    )))
}
