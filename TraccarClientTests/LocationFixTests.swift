import CoreLocation
import Foundation
import Testing

struct LocationFixTests {
    @Test func preservesOriginalFieldsAndOmitsInvalidOptionalValues() throws {
        let timestamp = Date(timeIntervalSince1970: 1_500_000_000)
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 1, longitude: 2), altitude: 42,
            horizontalAccuracy: 8_000, verticalAccuracy: -1, course: -1, speed: -1, timestamp: timestamp
        )
        let fix = try #require(LocationFix(location))
        #expect(fix.timestamp == timestamp && fix.horizontalAccuracy == 8_000)
        #expect(fix.latitude == 1 && fix.longitude == 2)
        #expect(fix.altitude == nil && fix.speed == nil && fix.course == nil)
    }

    @Test func preservesValidOptionalFields() throws {
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 1, longitude: 2), altitude: 42,
            horizontalAccuracy: 100, verticalAccuracy: 5, course: 90, speed: 0,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let fix = try #require(LocationFix(location))
        #expect(fix.altitude == 42 && fix.speed == 0 && fix.course == 90)
    }

    @Test func invalidCoordinatesOrInvalidFixAccuracyAreNotLocations() {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        for (latitude, accuracy) in [(91.0, 100.0), (1, -1), (1, Double.nan)] {
            let location = CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: 2), altitude: 0,
                horizontalAccuracy: accuracy, verticalAccuracy: -1, timestamp: timestamp
            )
            #expect(LocationFix(location) == nil)
        }
    }

    @MainActor @Test func nativeAccuracyMappingAndAuthorizationUseMacAPIs() {
        #expect(CoreLocationProvider.desiredAccuracy(.medium) == kCLLocationAccuracyHundredMeters)
        #expect(CoreLocationProvider.desiredAccuracy(.low) == kCLLocationAccuracyKilometer)
        #expect(CoreLocationProvider.desiredAccuracy(.high) == kCLLocationAccuracyBest)
        #expect(LocationPermission(.authorizedAlways) == .authorized)
        #expect(LocationPermission(.denied) == .denied)
        #expect(LocationPermission(.restricted) == .restricted)
    }
}
