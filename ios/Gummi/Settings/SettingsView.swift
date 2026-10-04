import SwiftUI

/// Connection, Dexcom (status only), who you're following, the demo controls, safety, and debug tools.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                connectionSection
                dexcomSection
                Section("Following") {
                    Button {
                        dismiss()
                        model.showsFollowPicker = true
                    } label: {
                        LabeledContent("Acting as", value: model.displayName(for: model.state?.actingAs) ?? "Nobody")
                    }
                    .foregroundStyle(Theme.primaryText)
                }
                DemoControls()
                safetySection
                #if DEBUG
                developerSection
                #endif
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private var connectionSection: some View {
        Section("Connection") {
            @Bindable var model = model
            Picker("Backend", selection: Binding(get: { model.mode }, set: { model.setMode($0) })) {
                Text("Live (Databricks)").tag(AppMode.live)
                Text("Demo data (mock)").tag(AppMode.mock)
            }
            LabeledContent("Status", value: statusText)
            if let version = model.state?.modelVersion {
                LabeledContent("Model", value: version)
            }
            if let updated = model.lastUpdated {
                LabeledContent("Updated") {
                    Text(updated, style: .relative) + Text(" ago")
                }
            }
            Button("Reconnect", systemImage: "arrow.clockwise") { model.reconnect() }
        }
    }

    private var statusText: String {
        if let notice = model.connectionNotice() { return notice.text }
        switch model.connection {
        case .live: return model.mode == .mock ? "Demo data, live" : "Live"
        case .idle: return "Not connected"
        default: return "Connecting…"
        }
    }

    private var dexcomSection: some View {
        Section {
            if let dexcom = model.state?.dexcom {
                LabeledContent("Dexcom", value: dexcom.connected ? "Connected" : "Not connected")
                LabeledContent("Account", value: dexcom.ingestMode == .timeShifted ? "Sandbox (time-shifted)"
                               : dexcom.environment == .production ? "Dexcom" : "Sandbox")
                if let through = dexcom.dataThrough {
                    LabeledContent("Data through", value: through.formatted(date: .abbreviated, time: .shortened))
                }
                if let sync = dexcom.lastSync {
                    LabeledContent("Last sync", value: sync.formatted(date: .omitted, time: .shortened))
                }
                if let error = dexcom.lastError {
                    Text(error).font(.caption).foregroundStyle(Theme.secondaryText)
                }
            } else {
                Text("No status yet").foregroundStyle(Theme.secondaryText)
            }
        } header: {
            Text("Dexcom")
        } footer: {
            Text("Status only: Gummi shows the connection, data range, and last sync, and never uses it for coaching. Connect from a laptop browser at \(Self.connectPath).")
        }
    }

    /// The App's Dexcom connect page, from the configured base URL.
    private static var connectPath: String {
        guard let base = try? AppConfig.load().apiBaseURL else { return "/api/v1/dexcom/connect" }
        return base.appending(path: "dexcom/connect").absoluteString
    }

    private var safetySection: some View {
        Section("Safety") {
            Text("Not for treatment decisions. Check your Dexcom app for current readings.")
                .font(.subheadline.weight(.semibold))
            Text("Gummi is a coach for adults with prediabetes or type 2 diabetes who don't use insulin. It never tells you to change medication or insulin.")
                .font(.footnote)
            Text("Gummi's estimate fills the hour Dexcom holds back and is always labeled as an estimate. The demo replays real, de-identified data from the BIG IDEAs study; the Dexcom connection uses Dexcom's sandbox.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    #if DEBUG
    private var developerSection: some View {
        Section {
            NavigationLink("Puppet playground") { PuppetPlaygroundView() }
            NavigationLink("Data debug") { DebugView() }
            Picker("Gummi renderer", selection: Binding(
                get: { UserDefaults.standard.string(forKey: "gummi.renderer") ?? "canvas" },
                set: { UserDefaults.standard.set($0, forKey: "gummi.renderer") })) {
                Text("120 Hz canvas").tag("canvas")
                Text("RealityView (60 fps)").tag("realityView")
            }
        } header: {
            Text("Developer")
        } footer: {
            Text("The renderer applies after relaunching the app.")
        }
    }
    #endif
}

/// Start, pause or resume, speed, and stop for the shared replay. Every phone and the projector see the change.
struct DemoControls: View {
    @Environment(AppModel.self) private var model
    @State private var confirmsStop = false
    static let speeds: [Double] = [10, 30, 60, 120]

    var body: some View {
        let stream = model.state?.stream
        Section {
            if let stream {
                LabeledContent("Replay", value: replayText(stream))
            }
            if let action = model.streamAction {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(action).foregroundStyle(Theme.secondaryText)
                }
            }
            if stream?.running != true {
                Button("Start the demo day (day 4, 05:00)", systemImage: "play.fill") {
                    Task { await model.startStream() }
                }
            } else {
                Button(stream?.paused == true ? "Resume" : "Pause",
                       systemImage: stream?.paused == true ? "play.fill" : "pause.fill") {
                    Task { await model.setPaused(!(stream?.paused ?? false)) }
                }
                Picker("Speed", selection: Binding(
                    get: { Self.speeds.min { abs($0 - (stream?.speed ?? 60)) < abs($1 - (stream?.speed ?? 60)) } ?? 60 },
                    set: { speed in Task { await model.setStreamSpeed(speed) } })) {
                    ForEach(Self.speeds, id: \.self) { Text("\(Int($0))×").tag($0) }
                }
                .pickerStyle(.segmented)
                Button("Stop the replay", systemImage: "stop.fill", role: .destructive) { confirmsStop = true }
                    .confirmationDialog("Stop the replay?", isPresented: $confirmsStop, titleVisibility: .visible) {
                        Button("Stop for everyone", role: .destructive) { Task { await model.stopStream() } }
                    } message: {
                        Text("Stops the replay for everyone, including the projector.")
                    }
            }
            if let error = model.streamError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        } header: {
            Text("Demo controls")
        } footer: {
            Text("Slow to 10× while chatting so \"now\" doesn't drift. The replay is shared: every phone and the projector see these changes.")
        }
        .disabled(model.streamAction != nil)
    }

    private func replayText(_ stream: StreamStatus) -> String {
        guard stream.running else { return "Stopped" }
        let clock = stream.replayClock.map { $0.replacingOccurrences(of: "T", with: " ").replacingOccurrences(of: "day", with: "Day ") } ?? "–"
        return "\(clock) · \(Int(stream.speed))×\(stream.paused ? " · paused" : "")"
    }
}
