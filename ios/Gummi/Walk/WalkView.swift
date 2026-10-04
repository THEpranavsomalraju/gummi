import SwiftUI

/// The walk screen: Gummi walking in place, live steps and pace, a timer toward the suggested minutes,
/// then the summary with the effect's source.
struct WalkView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var walk: WalkModel
    @State private var puppet = KoalaController()

    init(request: WalkRequest, service: (any GummiService)?, source: any StepSource = StepSources.standard()) {
        _walk = State(initialValue: WalkModel(minutes: request.minutes, service: service, source: source))
    }

    var body: some View {
        VStack(spacing: 16) {
            switch walk.phase {
            case .walking, .finishing:
                walking
            case .done(let summary):
                finished(summary)
            case .discarded:
                message("That was under a minute, so I didn't count it. Try again when you have a few minutes.")
            case .failed(let error):
                message("I couldn't save that walk. \(error)")
            }
            SafetyLine()
        }
        .padding()
        .background(Theme.background)
        .onAppear { walk.start() }
        .onDisappear { walk.cancel() }
    }

    private var walking: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(walk.startedAt))
            VStack(spacing: 16) {
                Text("Walking with Gummi")
                    .font(.system(.title2, design: .rounded).bold())
                // Calm while walking: turning happy starts a dance, which belongs to the end of the walk.
                PuppetView(input: PuppetInput(mood: .calm, walking: true, walkCadence: Double(walk.cadenceSpm ?? 105)),
                           controller: puppet, visibleHeight: 0.8)
                    .frame(maxHeight: .infinity)
                HStack(spacing: 28) {
                    stat(walk.steps.formatted(), "steps")
                    stat(walk.cadenceSpm.map(String.init) ?? "–", "steps/min")
                    timer(elapsed)
                }
                Button {
                    Task { await walk.end() }
                } label: {
                    Label(walk.phase == .finishing ? "Saving…" : "End walk", systemImage: "flag.checkered")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(walk.phase != .walking)
            }
        }
    }

    private func timer(_ elapsed: TimeInterval) -> some View {
        let target = Double(walk.targetMinutes * 60)
        return ZStack {
            Circle().stroke(Theme.accent.opacity(0.15), lineWidth: 6)
            Circle()
                .trim(from: 0, to: min(1, elapsed / target))
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: elapsed)
            VStack(spacing: 0) {
                Text(Duration.seconds(Int(elapsed)).formatted(.time(pattern: .minuteSecond)))
                    .font(.headline.monospacedDigit())
                Text("of \(walk.targetMinutes) min").font(.caption2).foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(width: 86, height: 86)
        .accessibilityElement(children: .combine)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title, design: .rounded).bold().monospacedDigit())
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
            Text(label).font(.caption).foregroundStyle(Theme.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }

    private func finished(_ summary: WalkSummary?) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "figure.walk.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Theme.accent)
            Text("Nice walk!").font(.system(.largeTitle, design: .rounded).bold())
            if let summary {
                VStack(alignment: .leading, spacing: 10) {
                    WalkLine(walk: summary)
                    Label(summary.effectSource == .yourData ? "Effect source: your data" : "Effect source: literature",
                          systemImage: "book")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    Text("Your real walk shows over the replayed day. Replayed glucose can't change, so its effect isn't graded.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            Spacer()
            doneButton
        }
    }

    private func message(_ text: String) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Text(text).font(.body).multilineTextAlignment(.center)
            Spacer()
            doneButton
        }
    }

    private var doneButton: some View {
        Button {
            dismiss()
        } label: {
            Text("Done").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
    }
}
