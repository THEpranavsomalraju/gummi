import SwiftUI

/// Temporary Phase 1A screen: shows the shared AppModel updating live, with the mock/live toggle.
/// Replaced by the Home, Today, and Settings shell in Phase 1B.
struct DebugView: View {
    @Environment(AppModel.self) private var model
    @State private var pingResult: String?

    var body: some View {
        NavigationStack {
            List {
                connectionSection
                nowSection
                if let grade = model.latestGrade { gradeSection(grade) }
                cardsSection
                if let due = model.state?.upcomingDue, !due.isEmpty { upcomingSection(due) }
                if let state = model.state { replaySection(state) }
                Section {
                    Text("Not for treatment decisions. Check your Dexcom app for current readings.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Gummi debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { debugMenu }
        }
    }

    // MARK: Sections

    private var connectionSection: some View {
        Section("Connection") {
            LabeledContent {
                Text(model.connection.label)
            } label: {
                Text(model.mode == .mock ? "Mock" : "Live")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.tint.opacity(0.15), in: Capsule())
            }
            if let now = model.state?.replayNow {
                LabeledContent("Replay now", value: now.formatted(date: .omitted, time: .shortened))
            }
            if let updated = model.lastUpdated {
                LabeledContent("Last update") { Text(updated, style: .relative) + Text(" ago") }
            }
            if let pingResult { Text(pingResult).font(.caption).foregroundStyle(.secondary) }
            if let error = model.lastError { Text(error).font(.caption).foregroundStyle(.red) }
        }
    }

    private func replaySection(_ state: GummiState) -> some View {
        Section("Replay") {
            LabeledContent("Acting as", value: state.actingAs ?? "nobody")
            if let now = state.replayNow {
                LabeledContent("Replay now", value: now.formatted(date: .omitted, time: .shortened))
            }
            LabeledContent("Stream") {
                Text(state.stream.running ? (state.stream.paused ? "Paused" : "Running at \(Int(state.stream.speed))x") : "Stopped")
            }
            if let clock = state.stream.replayClock { LabeledContent("Replay clock", value: clock) }
            if state.stream.running {
                Button(state.stream.paused ? "Resume stream" : "Pause stream") {
                    Task { await model.setPaused(!state.stream.paused) }
                }
            }
        }
    }

    private var nowSection: some View {
        Section("Now") {
            LabeledContent("Mood", value: model.mood.rawValue)
            if let last = model.state?.confirmed.last {
                LabeledContent("Dexcom reading") {
                    Text("\(Int(last.glucoseMgDl)) at \(last.t.formatted(date: .omitted, time: .shortened))")
                }
            }
            if let view = model.state?.gummiView {
                LabeledContent("Gummi's estimate") {
                    Text("\(Int(view.glucoseMgDl)) (\(Int(view.bandLowMgDl)) to \(Int(view.bandHighMgDl))), \(view.trend.rawValue)")
                }
                LabeledContent("Confidence", value: view.confidence.rawValue)
            }
            if let peak = model.state?.forecast.max(by: { $0.glucoseMgDl < $1.glucoseMgDl }) {
                LabeledContent("Forecast peak") {
                    Text("\(Int(peak.glucoseMgDl)) at \(peak.t.formatted(date: .omitted, time: .shortened))")
                }
            }
            if let alert = model.alert {
                Label(alert.message, systemImage: "figure.walk").font(.callout)
            }
        }
    }

    private func gradeSection(_ grade: Grade) -> some View {
        Section("Latest grade") {
            Text(grade.message)
            Text(grade.threeNumberBadge).font(.callout.monospacedDigit().bold())
            if !grade.walkEffectGraded {
                Text("Walk effect not graded (replayed data)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func upcomingSection(_ due: [UpcomingDue]) -> some View {
        Section("Coming due") {
            ForEach(due) { item in
                LabeledContent(item.title) { Text(item.dueAt, style: .timer) }
            }
        }
    }

    private var cardsSection: some View {
        Section("Cards (\(model.cards.count))") {
            ForEach(model.cards) { card in
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.type.rawValue).font(.caption2.monospaced()).foregroundStyle(.secondary)
                    Text(card.title).font(.headline)
                    Text(card.body).font(.subheadline)
                    if let dueId = card.pendingDueId {
                        Button("Log it") { Task { await model.logDueMeal(dueId) } }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var debugMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Backend", selection: Binding(get: { model.mode }, set: { model.setMode($0) })) {
                    Text("Mock").tag(AppMode.mock)
                    Text("Live").tag(AppMode.live)
                }
                Button("Ping backend", systemImage: "antenna.radiowaves.left.and.right") {
                    Task { pingResult = await model.ping() }
                }
                Button("Reconnect", systemImage: "arrow.clockwise") { model.reconnect() }
            } label: {
                Label("Debug", systemImage: "ladybug")
            }
        }
    }
}

extension ConnectionStatus {
    var label: String {
        switch self {
        case .idle: "Idle"
        case .connecting: "Connecting"
        case .live: "Live"
        case .reconnecting(let attempt): "Reconnecting (try \(attempt))"
        case .polling: "Polling every 15 s"
        case .offline(let reason): "Offline: \(reason)"
        }
    }
}

extension Grade {
    /// "Gummi 7 · CGM-only 11 · last value 18". CGM-only shows n/a when null (CONTRACT 1.4).
    var threeNumberBadge: String {
        let cgmOnly = cgmOnlyMaeMgDl.map { "\(Int($0.rounded()))" } ?? "n/a"
        return "Gummi \(Int(gummiMaeMgDl.rounded())) · CGM-only \(cgmOnly) · last value \(Int(lastValueMaeMgDl.rounded()))"
    }
}

#Preview {
    DebugView().environment(AppModel(makeService: { _ in MockGummiService(day: try MockDay.load()) }))
}
