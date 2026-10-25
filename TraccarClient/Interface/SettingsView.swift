import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var model: ConfigurationModel
    let location: LocationModel
    @State private var focus = WindowFocusController()

    var body: some View {
        VStack(spacing: 12) {
            if model.hasLoaded {
                TabView {
                    connection
                        .tabItem { Label("Connection", systemImage: "network") }
                    tracking
                        .tabItem { Label("Tracking", systemImage: "location") }
                    general
                        .tabItem { Label("General", systemImage: "gearshape") }
                    diagnostics
                        .tabItem { Label("Diagnostics", systemImage: "waveform.path.ecg") }
                }
            } else {
                keychainIntroduction
            }
            VStack(alignment: .leading) {
                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red).textSelection(.enabled)
                } else if let status = model.statusMessage {
                    Label(status, systemImage: "info.circle").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 64, alignment: .topLeading)
            HStack {
                if !model.hasLoaded {
                    Button(model.errorMessage == nil ? "Access Keychain" : "Retry loading") {
                        focus.perform { model.reload() }
                    }
                        .buttonStyle(.borderedProminent)
                }
                Spacer()
                if model.hasLoaded {
                    Button("Save") { focus.perform { model.save() } }
                        .keyboardShortcut("s", modifiers: .command)
                }
            }
        }
        .textFieldStyle(.roundedBorder)
        .formStyle(.grouped)
        .padding()
        .frame(width: 720, height: 700)
        .background(SettingsWindowReader(focus: focus).allowsHitTesting(false))
        .onAppear { model.loadIfNeeded() }
    }

    private var keychainIntroduction: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(model.needsKeychainAuthorization ? "Keychain authorization required" : "Configuration unavailable",
                  systemImage: "lock.shield")
                .font(.title2)
            Text("Your server URL and device identifier are protected in the macOS Keychain.")
            Text("Settings load automatically when access is available. Continue only if macOS needs authorization.")
            Label("macOS may ask for your login keychain password. This app never receives that password.",
                  systemImage: "info.circle")
            Text("In the system dialog, Always Allow remembers access for the recognized app. You can also cancel.")
            Text("Cancelling leaves your saved configuration intact. Access is retried only when you choose to retry.")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    private var connection: some View {
        Form {
            Section("Traccar Server") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Server URL").font(.headline)
                    TextField("http://demo.traccar.org:5055", text: $model.draft.connection.serverURL)
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .accessibilityLabel("Server URL")
                        .privacySensitive()
                }
                Text("HTTP or HTTPS, with an IP address or domain and an optional port and path.")
                if model.draft.connection.isDemo {
                    Label("Traccar public demo server. Configure your own receiver before sending private locations.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            Section("Device identity") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Unique identifier").font(.headline)
                    TextField("Leave blank to generate an identifier", text: $model.draft.connection.deviceIdentifier)
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .accessibilityLabel("Unique identifier")
                        .privacySensitive()
                }
                Text("Use an existing identifier to continue its history. Leave blank to generate eight digits.")
                Text("Generated on save. Add it to the server separately; saving does not register a device.")
            }
            Label("Saving does not start tracking, request location access or contact the server.",
                  systemImage: "info.circle")
                .foregroundStyle(.secondary)
        }
        .disabled(!model.hasLoaded)
    }

    private var tracking: some View {
        Form {
            Picker("Accuracy", selection: $model.draft.tracking.accuracy) {
                ForEach(LocationAccuracy.allCases, id: \.self) { accuracy in
                    Text(accuracy.title).tag(accuracy)
                }
            }
            TextField("Interval (seconds)", value: $model.draft.tracking.intervalSeconds, format: .number)
            TextField("Distance (metres)", value: $model.draft.tracking.distanceMetres, format: .number)
            Text("A position will be selected when time OR distance is reached. Zero disables that threshold.")
            TextField("Angle (degrees)", value: $model.draft.tracking.angleDegrees, format: .number)
            TextField("Heartbeat (seconds)", value: $model.draft.tracking.heartbeatSeconds, format: .number)
            Toggle("Buffer positions offline", isOn: $model.draft.tracking.bufferingEnabled)
            Toggle("Detect stationary periods", isOn: $model.draft.tracking.stationaryDetectionEnabled)
            Text("Accuracy applies on capture start. Selection, buffering and stationary detection are not active yet.")
        }
        .disabled(!model.hasLoaded)
    }

    private var general: some View {
        Form {
            Toggle("Launch at login", isOn: $model.draft.tracking.launchAtLogin).disabled(true)
            Toggle("Restore continuous tracking", isOn: $model.draft.tracking.restoreTracking).disabled(true)
            Text("Login startup and tracking restoration will be available in a later build. Both default to off.")
            Text("Closing Settings keeps requested capture running in the menu bar. Use Pause to stop capture.")
        }
    }

    private var diagnostics: some View {
        Form {
            LabeledContent("Location capture", value: location.continuousRequested ? "Active" : "Paused")
            LabeledContent("Condition", value: location.status)
            LabeledContent("Location permission", value: location.availability.permission.rawValue)
            LabeledContent("Location Services", value: location.availability.services.rawValue)
            LabeledContent("Configuration", value: model.hasLoaded ? "Loaded locally" : "Unavailable")
            Text("Connection and identity: Keychain. Tracking preferences: UserDefaults.")
            Text("No location permission requests or network activity are started by loading or saving settings.")
        }
    }
}

private struct SettingsWindowReader: NSViewRepresentable {
    let focus: WindowFocusController

    func makeNSView(context: Context) -> WindowReaderView {
        WindowReaderView(focus: focus)
    }

    func updateNSView(_ nsView: WindowReaderView, context: Context) {}

    final class WindowReaderView: NSView {
        private let focus: WindowFocusController

        init(focus: WindowFocusController) {
            self.focus = focus
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            focus.window = window
        }
    }
}
