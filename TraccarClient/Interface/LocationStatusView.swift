import SwiftUI

struct LocationStatusView: View {
    let location: LocationModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Location capture", systemImage: "location")
                .font(.title2)
            Text("Capture your Mac's location continuously or once while paused. Nothing is sent to a server.")
            Text("Choose Start or Capture once to allow macOS to request location permission if needed.")
                .foregroundStyle(.secondary)
            Form {
                LabeledContent("Continuous capture", value: location.continuousRequested ? "Active" : "Paused")
                LabeledContent("Condition", value: location.status)
                LabeledContent("Location Services", value: location.availability.services.rawValue)
                LabeledContent("Permission", value: location.availability.permission.rawValue)
                LabeledContent("Single capture", value: location.singleStatus.rawValue)
                if let fix = location.lastFix {
                    LabeledContent("Fix timestamp", value: fix.timestamp.formatted(date: .numeric, time: .standard))
                    LabeledContent("Reported accuracy", value: "\(fix.horizontalAccuracy.formatted()) m")
                    LabeledContent("Source", value: location.lastFixOrigin?.rawValue ?? "Location Services")
                } else {
                    Text("No location received.").foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            if let error = location.errorMessage ?? location.continuousError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            HStack {
                Button(location.continuousRequested ? "Pause" : "Start") {
                    if location.continuousRequested { location.pause() } else {
                        location.startContinuous()
                    }
                }
                Button("Capture once") {
                    location.captureOnce()
                }
                .disabled(location.singleStatus == .waiting)
                if location.singleStatus == .waiting {
                    Button("Cancel capture") { location.cancelSingle() }
                }
                Spacer()
                Button("Refresh status") { location.refreshAvailability() }
            }
        }
        .padding(20)
        .frame(width: 620, height: 540)
        .onAppear { location.refreshAvailability() }
    }
}
