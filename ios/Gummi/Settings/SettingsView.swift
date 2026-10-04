import SwiftUI

/// Placeholder until the Settings chunk. Debug tools stay here in debug builds only (D-92).
struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Not for treatment decisions. Check your Dexcom app for current readings.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                #if DEBUG
                Section("Developer") {
                    NavigationLink("Puppet playground") { PuppetPlaygroundView() }
                    NavigationLink("Data debug") { DebugView() }
                }
                #endif
            }
            .navigationTitle("Settings")
        }
    }
}
