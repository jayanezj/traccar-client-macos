import CoreLocation
import Foundation

enum LocationPermission: String {
    case notDetermined = "Not requested"
    case authorized = "Authorized"
    case denied = "Denied"
    case restricted = "Restricted"

    init(_ status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways: self = .authorized
        case .notDetermined: self = .notDetermined
        case .denied: self = .denied
        default: self = .restricted
        }
    }
}

enum LocationServices: String {
    case checking = "Checking"
    case enabled = "Enabled"
    case disabled = "Disabled"
}

struct LocationAvailability: Equatable {
    var permission: LocationPermission
    var services: LocationServices

    var canCapture: Bool { permission == .authorized && services == .enabled }
}

struct LocationFix: Equatable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    let horizontalAccuracy: Double
    let altitude: Double?
    let speed: Double?
    let course: Double?

    init?(_ location: CLLocation) {
        guard CLLocationCoordinate2DIsValid(location.coordinate),
              location.horizontalAccuracy.isFinite, location.horizontalAccuracy >= 0,
              location.timestamp.timeIntervalSinceReferenceDate.isFinite else { return nil }
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        timestamp = location.timestamp
        horizontalAccuracy = location.horizontalAccuracy
        altitude = location.verticalAccuracy >= 0 && location.altitude.isFinite ? location.altitude : nil
        speed = location.speed >= 0 && location.speed.isFinite ? location.speed : nil
        course = (0..<360).contains(location.course) && location.course.isFinite ? location.course : nil
    }
}

enum LocationFailure: Equatable {
    case permissionDenied
    case unavailable
    case other(Int)

    var message: String {
        switch self {
        case .permissionDenied: "Location access is denied. Review Location Services in System Settings."
        case .unavailable: "No location is available. Try again when Location Services can obtain a fix."
        case .other(let code): "Location could not be obtained (error \(code))."
        }
    }
}

enum LocationRequestKind { case continuous, single }
enum LocationFixOrigin: String {
    case continuous = "Continuous capture"
    case single = "Single capture"
    case lastKnown = "Last-known location; no new fix"
}

enum SingleCaptureStatus: String {
    case idle = "Idle"
    case waiting = "Waiting for location"
    case received = "Location received"
    case lastKnown = "Last-known location used; no new fix"
    case failed = "No location obtained"
    case cancelled = "Cancelled"
}

enum LocationEvent {
    case availability(LocationAvailability)
    case locations(LocationRequestKind, request: Int, fixes: [LocationFix])
    case failure(LocationRequestKind, request: Int, reason: LocationFailure, fallback: LocationFix?)
}

@MainActor
protocol LocationProviding: AnyObject {
    var availability: LocationAvailability { get }
    var onEvent: ((LocationEvent) -> Void)? { get set }
    func refreshAvailability()
    func requestAuthorization()
    func startContinuous(accuracy: LocationAccuracy, request: Int)
    func stopContinuous()
    func requestSingle(accuracy: LocationAccuracy, request: Int)
    func cancelSingle()
}
