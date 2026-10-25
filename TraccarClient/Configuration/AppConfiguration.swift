import Foundation
import Security

struct ReceiverConnection: Codable, Equatable {
    static let demoURL = "http://demo.traccar.org:5055"

    var serverURL = demoURL
    var deviceIdentifier = ""

    var isDemo: Bool {
        URLComponents(string: serverURL)?.host?.lowercased() == "demo.traccar.org"
    }

    func validated() throws -> Self {
        var result = self
        result.serverURL = try Self.canonicalURL(serverURL)
        if !deviceIdentifier.isEmpty {
            guard !deviceIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !deviceIdentifier.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                throw ConfigurationError.invalidIdentifier
            }
        }
        return result
    }

    static func canonicalURL(_ value: String) throws -> String {
        guard !value.isEmpty,
              !value.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.contains),
              let url = URL(string: value, encodingInvalidCharacters: false),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil, components.fragment == nil else {
            throw ConfigurationError.invalidURL
        }
        if let separator = value.range(of: "://") {
            let authority = value[separator.upperBound...].prefix { $0 != "/" && $0 != "?" }
            if authority.hasSuffix(":") { throw ConfigurationError.invalidURL }
        }
        if let port = components.port, !(1...65535).contains(port) {
            throw ConfigurationError.invalidURL
        }
        components.scheme = scheme
        components.host = host.lowercased()
        if (scheme == "http" && components.port == 80) || (scheme == "https" && components.port == 443) {
            components.port = nil
        }
        if components.path == "/" { components.path = "" }
        guard let normalized = components.url?.absoluteString else { throw ConfigurationError.invalidURL }
        return normalized
    }
}

enum LocationAccuracy: String, Codable, CaseIterable {
    case low, medium, high

    var title: String { rawValue.capitalized }
}

struct TrackingPreferences: Codable, Equatable {
    var accuracy: LocationAccuracy = .medium
    var intervalSeconds: Double = 300
    var distanceMetres: Double = 75
    var angleDegrees: Double = 0
    var heartbeatSeconds: Double = 0
    var bufferingEnabled = true
    var stationaryDetectionEnabled = true
    var launchAtLogin = false
    var restoreTracking = false

    func validate() throws {
        let numbers = [intervalSeconds, distanceMetres, angleDegrees, heartbeatSeconds]
        guard numbers.allSatisfy({ $0.isFinite && $0 >= 0 }), angleDegrees <= 180 else {
            throw ConfigurationError.invalidTracking
        }
    }
}

struct AppConfiguration: Equatable {
    var connection = ReceiverConnection()
    var tracking = TrackingPreferences()
}

enum ConfigurationError: Error, LocalizedError, Equatable {
    case invalidURL
    case invalidIdentifier
    case invalidTracking
    case unreadableStorage
    case unsupportedStorageVersion
    case missingIdentity
    case notLoaded
    case keychain(Int32)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Enter an absolute HTTP or HTTPS URL with a host and valid port. No credentials or fragments."
        case .invalidIdentifier:
            "Enter an identifier without control characters, or leave it empty to generate one."
        case .invalidTracking:
            "Tracking values must be finite and non-negative; the angle must not exceed 180 degrees."
        case .unreadableStorage:
            "Saved configuration could not be read. No settings or identifier have been replaced."
        case .unsupportedStorageVersion:
            "This configuration was saved by an unsupported version. No settings have been replaced."
        case .missingIdentity:
            "The saved device identity is missing from Keychain. No replacement has been generated."
        case .notLoaded:
            "Reload the saved configuration successfully before saving changes."
        case .keychain(let status) where status == errSecUserCanceled:
            "Keychain access was cancelled. Saved configuration is unchanged. You can retry when ready."
        case .keychain(let status):
            "Keychain could not complete the operation (status \(status)). Allow access and try again."
        }
    }
}
