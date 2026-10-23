import SwiftUI    

struct SettingsView: View {
    var body: some View {
        TabView {
            Form {
                LabeledContent("Status", value: "Paused")
                Text("Server and device configuration will be available in a later build.")
            }
            .tabItem { Label("Connection", systemImage: "network") }

            Form {
                Text("Continuous tracking, manual location and SOS are not implemented yet.")
                Text("This build does not request your location or send positions.")
            }
            .tabItem { Label("Tracking", systemImage: "location") }

            Form {
                Text("Login startup and tracking restoration are not enabled.")
                Text("Closing Settings keeps the app in the menu bar. Use Quit to exit.")
            }
            .tabItem { Label("General", systemImage: "gearshape") }

            Form {
                LabeledContent("Status", value: "Paused")
                Text("No location or network activity is started by this application shell.")
            }
            .tabItem { Label("Diagnostics", systemImage: "waveform.path.ecg") }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 560, height: 320)
    }
}

#error("Issue #2: deliberate remote CI compilation failure")
