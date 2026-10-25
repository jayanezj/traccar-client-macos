import Foundation
import Observation

@MainActor
@Observable
final class LocationModel {
    private(set) var availability: LocationAvailability
    private(set) var continuousRequested = false
    private(set) var singleStatus: SingleCaptureStatus = .idle
    private(set) var lastFix: LocationFix?
    private(set) var lastFixOrigin: LocationFixOrigin?
    private(set) var errorMessage: String?
    private(set) var continuousError: String?

    @ObservationIgnored private let provider: any LocationProviding
    @ObservationIgnored private let readAccuracy: () throws -> LocationAccuracy
    @ObservationIgnored private var permissionRequested = false
    @ObservationIgnored private var continuousRequest: Int?
    @ObservationIgnored private var singleRequest: Int?
    @ObservationIgnored private var nextRequest = 0
    @ObservationIgnored private var continuousBlocked = false
    @ObservationIgnored private var continuousAccuracy: LocationAccuracy = .medium
    @ObservationIgnored private var singleAccuracy: LocationAccuracy = .medium

    init(provider: any LocationProviding, readAccuracy: @escaping () throws -> LocationAccuracy = { .medium }) {
        self.provider = provider
        self.readAccuracy = readAccuracy
        availability = provider.availability
        provider.onEvent = { [weak self] in self?.receive($0) }
    }

    var status: String {
        if availability.services == .disabled { return "Location Services disabled" }
        if availability.permission == .denied { return "Location permission denied" }
        if availability.permission == .restricted { return "Location permission restricted" }
        if continuousError != nil { return "Location unavailable" }
        if continuousRequested || singleStatus == .waiting {
            if !availability.canCapture { return "Waiting for location authorization" }
            return lastFix == nil ? "Waiting for location" : "Location capture active"
        }
        return "Paused"
    }

    func startContinuous(accuracy: LocationAccuracy? = nil) {
        guard !continuousRequested else { return }
        guard let selected = selectedAccuracy(accuracy) else { return }
        preparePermissionRequest()
        continuousRequested = true
        continuousAccuracy = selected
        continuousBlocked = false
        continuousError = nil
        errorMessage = nil
        provider.refreshAvailability()
        reconcile()
    }

    func pause() {
        continuousRequested = false
        stopContinuous()
        continuousError = nil
        continuousBlocked = false
    }

    func captureOnce(accuracy: LocationAccuracy? = nil) {
        guard singleStatus != .waiting else { return }
        guard let selected = selectedAccuracy(accuracy) else {
            singleStatus = .failed
            return
        }
        preparePermissionRequest()
        singleStatus = .waiting
        singleAccuracy = selected
        errorMessage = nil
        provider.refreshAvailability()
        reconcile()
    }

    func cancelSingle() {
        guard singleStatus == .waiting else { return }
        singleRequest = nil
        singleStatus = .cancelled
        provider.cancelSingle()
    }

    func shutdown() {
        pause()
        cancelSingle()
    }

    func refreshAvailability() { provider.refreshAvailability() }

    private func preparePermissionRequest() {
        // A new explicit attempt may retry an undetermined request; status refreshes never do so on their own.
        if !continuousRequested && singleStatus != .waiting { permissionRequested = false }
    }

    private func selectedAccuracy(_ requested: LocationAccuracy?) -> LocationAccuracy? {
        do {
            return try requested ?? readAccuracy()
        } catch {
            errorMessage = "Saved tracking preferences could not be read. Review Settings before capture."
            return nil
        }
    }

    private func reconcile() {
        guard continuousRequested || singleStatus == .waiting else { return }
        if availability.services == .disabled || [.denied, .restricted].contains(availability.permission) {
            stopContinuous()
            errorMessage = availability.services == .disabled
                ? "Enable Location Services in System Settings to capture locations."
                : "Location access is denied or restricted. Review Location Services in System Settings."
            if singleStatus == .waiting {
                singleRequest = nil
                singleStatus = .failed
                provider.cancelSingle()
            }
            return
        }
        guard availability.services == .enabled else { return }
        if availability.permission == .notDetermined {
            guard !permissionRequested else { return }
            permissionRequested = true
            provider.requestAuthorization()
            return
        }
        guard availability.canCapture else { return }
        if continuousRequested && continuousRequest == nil && !continuousBlocked {
            nextRequest += 1
            continuousRequest = nextRequest
            provider.startContinuous(accuracy: continuousAccuracy, request: nextRequest)
        }
        if singleStatus == .waiting && singleRequest == nil {
            nextRequest += 1
            singleRequest = nextRequest
            provider.requestSingle(accuracy: singleAccuracy, request: nextRequest)
        }
    }

    private func stopContinuous() {
        continuousRequest = nil
        provider.stopContinuous()
    }

    private func receive(_ event: LocationEvent) {
        switch event {
        case .availability(let value):
            if availability != value {
                continuousBlocked = false
                continuousError = nil
                errorMessage = nil
            }
            availability = value
            if !value.canCapture { stopContinuous() }
            reconcile()
        case .locations(let kind, let request, let fixes):
            guard accepts(kind, request: request), let fix = fixes.max(by: { $0.timestamp < $1.timestamp }) else {
                return
            }
            lastFix = fix
            lastFixOrigin = kind == .single ? .single : .continuous
            if kind == .single {
                singleStatus = .received
                singleRequest = nil
            } else {
                continuousError = nil
            }
            errorMessage = nil
        case .failure(let kind, let request, let reason, let fallback):
            guard accepts(kind, request: request) else { return }
            handleFailure(kind, reason: reason, fallback: fallback)
        }
    }

    private func accepts(_ kind: LocationRequestKind, request: Int) -> Bool {
        kind == .single ? singleStatus == .waiting && singleRequest == request
            : continuousRequested && continuousRequest == request
    }

    private func handleFailure(_ kind: LocationRequestKind, reason: LocationFailure, fallback: LocationFix?) {
        if kind == .continuous {
            continuousError = reason.message
            if reason == .permissionDenied {
                continuousBlocked = true
                stopContinuous()
            }
            return
        }
        singleRequest = nil
        if reason != .permissionDenied, let known = fallback ?? lastFix {
            lastFix = known
            lastFixOrigin = .lastKnown
            singleStatus = .lastKnown
        } else {
            singleStatus = .failed
        }
        errorMessage = reason.message
    }
}
