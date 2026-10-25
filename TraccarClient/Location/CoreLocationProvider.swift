import CoreLocation
import Foundation

@MainActor
final class CoreLocationProvider: LocationProviding {
    private(set) var availability: LocationAvailability
    var onEvent: ((LocationEvent) -> Void)?

    private let permissionManager: CLLocationManager
    private var permissionDelegate: NativeLocationDelegate?
    private var continuousManager: CLLocationManager?
    private var continuousDelegate: NativeLocationDelegate?
    private var singleManager: CLLocationManager?
    private var singleDelegate: NativeLocationDelegate?
    private var availabilityRevision = 0
    private var continuousRequest: Int?
    private var singleRequest: Int?

    init() {
        permissionManager = CLLocationManager()
        availability = LocationAvailability(
            permission: LocationPermission(permissionManager.authorizationStatus), services: .checking
        )
        permissionDelegate = NativeLocationDelegate { [weak self] _ in self?.refreshAvailability() }
        permissionManager.delegate = permissionDelegate
        refreshAvailability()
    }

    func refreshAvailability() {
        availability.permission = LocationPermission(permissionManager.authorizationStatus)
        onEvent?(.availability(availability))
        availabilityRevision += 1
        let revision = availabilityRevision
        Task { [weak self] in
            // The synchronous service-status query may block; do not perform it on the UI thread.
            let enabled = await Task.detached { CLLocationManager.locationServicesEnabled() }.value
            guard let self, revision == availabilityRevision else { return }
            availability.services = enabled ? .enabled : .disabled
            onEvent?(.availability(availability))
        }
    }

    func requestAuthorization() { permissionManager.requestWhenInUseAuthorization() }

    func startContinuous(accuracy: LocationAccuracy, request: Int) {
        stopContinuous()
        let manager = CLLocationManager()
        continuousManager = manager
        continuousRequest = request
        continuousDelegate = makeDelegate(kind: .continuous, request: request)
        manager.delegate = continuousDelegate
        manager.desiredAccuracy = Self.desiredAccuracy(accuracy)
        manager.distanceFilter = kCLDistanceFilterNone
        manager.startUpdatingLocation()
    }

    func stopContinuous() {
        continuousRequest = nil
        continuousManager?.stopUpdatingLocation()
        continuousManager?.delegate = nil
        continuousManager = nil
        continuousDelegate = nil
    }

    func requestSingle(accuracy: LocationAccuracy, request: Int) {
        cancelSingle()
        let manager = CLLocationManager()
        singleManager = manager
        singleRequest = request
        singleDelegate = makeDelegate(kind: .single, request: request)
        manager.delegate = singleDelegate
        manager.desiredAccuracy = Self.desiredAccuracy(accuracy)
        manager.requestLocation()
    }

    func cancelSingle() {
        singleRequest = nil
        singleManager?.stopUpdatingLocation()
        singleManager?.delegate = nil
        singleManager = nil
        singleDelegate = nil
    }

    static func desiredAccuracy(_ accuracy: LocationAccuracy) -> CLLocationAccuracy {
        switch accuracy {
        case .low: kCLLocationAccuracyKilometer
        case .medium: kCLLocationAccuracyHundredMeters
        case .high: kCLLocationAccuracyBest
        }
    }

    private func makeDelegate(kind: LocationRequestKind, request: Int) -> NativeLocationDelegate {
        NativeLocationDelegate { [weak self] event in
            guard let self else { return }
            switch event {
            case .authorization:
                refreshAvailability()
            case .locations(let locations):
                deliver(locations, kind: kind, request: request)
            case .failure(let error):
                deliver(error, kind: kind, request: request)
            }
        }
    }

    private func deliver(_ locations: [CLLocation], kind: LocationRequestKind, request: Int) {
        guard isCurrent(kind, request: request) else { return }
        let fixes = locations.compactMap(LocationFix.init)
        if fixes.isEmpty {
            onEvent?(.failure(kind, request: request, reason: .unavailable, fallback: nil))
        } else {
            onEvent?(.locations(kind, request: request, fixes: fixes))
        }
        if kind == .single && singleRequest == request { cancelSingle() }
    }

    private func deliver(_ error: any Error, kind: LocationRequestKind, request: Int) {
        guard isCurrent(kind, request: request) else { return }
        let reason: LocationFailure
        switch (error as? CLError)?.code {
        case .denied: reason = .permissionDenied
        case .locationUnknown: reason = .unavailable
        default: reason = .other((error as NSError).code)
        }
        let fallback = singleManager?.location.flatMap(LocationFix.init)
        onEvent?(.failure(kind, request: request, reason: reason, fallback: fallback))
        if kind == .single && singleRequest == request { cancelSingle() }
        if reason == .permissionDenied { refreshAvailability() }
    }

    private func isCurrent(_ kind: LocationRequestKind, request: Int) -> Bool {
        kind == .single ? singleRequest == request : continuousRequest == request
    }
}

private enum NativeLocationEvent {
    case authorization
    case locations([CLLocation])
    case failure(any Error)
}

// CLLocationManager is created on MainActor and delivers delegates on that thread's run loop.
@MainActor
private final class NativeLocationDelegate: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let receive: (NativeLocationEvent) -> Void

    init(receive: @escaping (NativeLocationEvent) -> Void) { self.receive = receive }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { receive(.authorization) }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        receive(.locations(locations))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        receive(.failure(error))
    }
}
