import Charts
import SwiftUI

/// An inline chat card, laid out for its type (CONTRACT section 6).
struct ChatCardView: View {
    let item: ChatCardItem

    var body: some View {
        switch item.card {
        case .mealSaved(let meal): MealSavedCard(meal: meal, simulatedOn: item.simulatedOn)
        case .simulation(let simulation): SimulationCard(simulation: simulation)
        case .gummiView(let view): GummiViewCard(view: view)
        case .walkSuggestion(let walk): WalkSuggestionCard(walk: walk)
        case .grade(let grade): GradeChatCard(grade: grade)
        case .mealDue(let card): StoryCardView(card: card, style: .full)
        }
    }
}

// MARK: meal_saved

/// The saved meal with a −/+ stepper per food. Edits scale that food's macros on the phone and save through
/// PATCH /meals; the card then shows what the backend stored.
private struct MealSavedCard: View {
    @Environment(AppModel.self) private var model
    let meal: Meal
    let simulatedOn: String?
    @State private var quantities: [Double] = []
    @State private var failed = false

    private var edited: Bool { quantities.count == meal.items.count && quantities != meal.items.map(\.quantity) }
    private var draftItems: [MealItem] {
        guard quantities.count == meal.items.count else { return meal.items }
        return zip(meal.items, quantities).map { $0.scaled(toQuantity: $1) }
    }

    var body: some View {
        let items = draftItems
        let totals = MealTotals(items: items)
        let saving = model.chat.savingMealIds.contains(meal.mealId)
        VStack(alignment: .leading, spacing: 12) {
            ChatCardHeader(symbol: "fork.knife", title: "Saved to your food log")
            if let simulatedOn {
                ChatTag(text: "Simulated on \(simulatedOn)'s day · not graded", symbol: "flask")
            }
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name.prefix(1).uppercased() + item.name.dropFirst())
                            .font(.subheadline.weight(.semibold))
                        Text("\(portion(item)) · \(Int(item.carbsG.rounded())) g carbs")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Spacer(minLength: 8)
                    if item.editable, index < quantities.count {
                        PortionStepper(value: $quantities[index])
                    }
                }
            }
            Divider()
            HStack {
                Text("Total").font(.footnote.weight(.semibold))
                Spacer()
                Text("\(Int(totals.carbsG.rounded())) g carbs · \(Int(totals.calories.rounded())) kcal")
                    .font(.footnote.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
            if edited {
                Button {
                    Task {
                        failed = !(await model.chat.savePortions(mealId: meal.mealId, items: items))
                    }
                } label: {
                    Label(saving ? "Saving…" : "Save changes", systemImage: "checkmark")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(saving)
            }
            if failed {
                Text("Couldn't save that. Try again.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .chatCardStyle()
        .onChange(of: meal, initial: true) { _, saved in
            quantities = saved.items.map(\.quantity)
            failed = false
        }
    }

    private func portion(_ item: MealItem) -> String {
        let amount = item.quantity.formatted(.number.precision(.fractionLength(0...1)))
        return item.unit.isEmpty ? "× \(amount)" : "\(amount) \(item.unit)"
    }
}

/// Half-portion steps, from 0.5 up to 6 (the backend's portion cap). A logged amount above 6 can still step down.
private struct PortionStepper: View {
    @Binding var value: Double

    var body: some View {
        HStack(spacing: 4) {
            step("minus", by: -0.5, enabled: value > 0.5)
            Text(value.formatted(.number.precision(.fractionLength(0...1))))
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .frame(minWidth: 30)
            step("plus", by: 0.5, enabled: value < 6)
        }
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Portions")
        .accessibilityValue(value.formatted())
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if value < 6 { value += 0.5 }
            case .decrement: if value > 0.5 { value -= 0.5 }
            @unknown default: break
            }
        }
    }

    private func step(_ symbol: String, by delta: Double, enabled: Bool) -> some View {
        Button {
            value = max(0.5, value + delta)
        } label: {
            Image(systemName: symbol)
                .font(.footnote.bold())
                .frame(width: 32, height: 32)
                .glassSurface(in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

// MARK: simulation

/// Two curves (without it dashed, with it solid on its band), the verdict, and the alternatives.
private struct SimulationCard: View {
    @Environment(AppModel.self) private var model
    let simulation: Simulation

    private var highLine: Double { model.state?.profile.highLineMgDl ?? 140 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                ChatCardHeader(symbol: "wand.and.stars", title: title)
                Spacer(minLength: 6)
                VerdictPill(verdict: simulation.verdict)
            }
            chart
            HStack(spacing: 14) {
                LegendItem(title: "Without it", dash: [5, 4], color: Theme.secondaryText)
                LegendItem(title: "With it", dash: [], color: Theme.accent)
            }
            .font(.caption2)
            .foregroundStyle(Theme.secondaryText)
            if !simulation.alternatives.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(simulation.alternatives, id: \.label) { alternative in
                        HStack {
                            Image(systemName: alternative.effectSource == nil ? "circle.lefthalf.filled" : "figure.walk")
                                .foregroundStyle(Theme.accent)
                                .frame(width: 20)
                            Text(alternative.label).font(.footnote)
                            Spacer()
                            Text("likely peak \(Int(alternative.peakMgDl.rounded()))")
                                .font(.footnote.monospacedDigit().weight(.semibold))
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
            }
            ForEach(notes, id: \.self) { note in
                Text(note)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            ChatTag(text: "Simulated, not logged", symbol: "flask")
        }
        .chatCardStyle()
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        let names = simulation.items.map(\.name).joined(separator: ", ")
        return names.isEmpty ? "If you eat it" : "If you eat the \(names)"
    }

    private var notes: [String] {
        var notes: [String] = []
        if simulation.method == .breakfastResponse {
            notes.append("Scaled from this person's standardized breakfast response.")
        }
        let sources = Set(simulation.alternatives.compactMap(\.effectSource))
        if sources.contains(.literature) { notes.append("Walk effect from published research (literature), not your own data yet.") }
        if sources.contains(.yourData) { notes.append("Walk effect from your own data.") }
        return notes
    }

    private var chart: some View {
        let peak = simulation.peakMgDl
        return Chart {
            ForEach(simulation.withFoodCurve, id: \.t) { point in
                AreaMark(x: .value("Time", point.t), yStart: .value("Low", point.bandLowMgDl),
                         yEnd: .value("High", point.bandHighMgDl), series: .value("Curve", "Band"))
                    .foregroundStyle(Theme.band)
                    .interpolationMethod(.catmullRom)
            }
            ForEach(simulation.baselineCurve, id: \.t) { point in
                LineMark(x: .value("Time", point.t), y: .value("mg/dL", point.glucoseMgDl), series: .value("Curve", "Without it"))
                    .foregroundStyle(Theme.secondaryText)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 4]))
                    .interpolationMethod(.catmullRom)
            }
            ForEach(simulation.withFoodCurve, id: \.t) { point in
                LineMark(x: .value("Time", point.t), y: .value("mg/dL", point.glucoseMgDl), series: .value("Curve", "With it"))
                    .foregroundStyle(Theme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.catmullRom)
            }
            RuleMark(y: .value("High line", highLine))
                .foregroundStyle(Theme.rangeLine)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
            PointMark(x: .value("Time", simulation.peakAt), y: .value("mg/dL", peak))
                .foregroundStyle(Theme.accent)
                .annotation(position: .top, spacing: 2) {
                    Text("\(Int(peak.rounded()))")
                        .font(.caption2.monospacedDigit().bold())
                        .foregroundStyle(Theme.primaryText)
                }
        }
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour)) {
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) }
        .environment(\.timeZone, Theme.timeZone)
        .frame(height: 130)
        .accessibilityHidden(true)
    }

    private var yDomain: ClosedRange<Double> {
        let values = simulation.withFoodCurve.flatMap { [$0.bandLowMgDl, $0.bandHighMgDl] } + simulation.baselineCurve.map(\.glucoseMgDl)
        let low = max(40, min(values.min() ?? highLine, highLine) - 10)
        let high = min(400, max(values.max() ?? highLine, highLine) + 10)
        return low...max(high, low + 20)
    }
}

/// Go, Go with a tweak, or Wait, in the mood colors.
private struct VerdictPill: View {
    let verdict: Verdict

    var body: some View {
        let (text, symbol, mood): (String, String, Mood) = switch verdict {
        case .go: ("Go", "checkmark", .happy)
        case .goWithTweak: ("Go with a tweak", "slider.horizontal.3", .rising)
        case .wait: ("Wait", "hand.raised", .high)
        case .unknown: ("Maybe", "questionmark", .calm)
        }
        Label(text, systemImage: symbol)
            .font(.caption.bold())
            .foregroundStyle(.black.opacity(0.8))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.color(mood), in: Capsule())
            .fixedSize()
    }
}

// MARK: gummi_view

/// Gummi's estimate for now, always labeled as an estimate next to how old the last Dexcom reading is.
private struct GummiViewCard: View {
    let view: GummiView

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ChatCardHeader(symbol: "sparkles", title: "Gummi's estimate")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(view.glucoseMgDl.rounded()))")
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                Text("mg/dL").font(.footnote).foregroundStyle(Theme.secondaryText)
                Spacer()
                Label(trendText, systemImage: trendSymbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
            Text("Likely \(Self.display(view.bandLowMgDl))–\(Self.display(view.bandHighMgDl)) · \(view.confidence.isKnown ? view.confidence.rawValue : "unknown") confidence")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.secondaryText)
            Text("Last Dexcom reading \(age) ago. Dexcom shares data an hour late, so this is Gummi's estimate, not a reading.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .chatCardStyle()
        .accessibilityElement(children: .combine)
    }

    /// Bands are shown inside the Dexcom range (40 to 400 mg/dL).
    static func display(_ value: Double) -> Int { Int(min(400, max(40, value)).rounded()) }

    private var age: String {
        let minutes = view.minutesSinceConfirmed
        if minutes < 120 { return "\(minutes) min" }
        let hours = minutes / 60
        return hours < 48 ? "\(hours) hours" : "\(hours / 24) days"
    }

    private var trendText: String {
        switch view.trend {
        case .risingFast: "Rising fast"
        case .rising: "Rising"
        case .flat: "Steady"
        case .falling: "Falling"
        case .fallingFast: "Falling fast"
        case .unknown: "Trend unknown"
        }
    }

    private var trendSymbol: String {
        switch view.trend {
        case .risingFast: "arrow.up"
        case .rising: "arrow.up.right"
        case .flat: "arrow.right"
        case .falling: "arrow.down.right"
        case .fallingFast: "arrow.down"
        case .unknown: "questionmark"
        }
    }
}

// MARK: walk_suggestion and grade

/// Minutes, the modeled peak drop, where that effect comes from, and Start walk.
private struct WalkSuggestionCard: View {
    let walk: WalkSuggestion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ChatCardHeader(symbol: "figure.walk", title: "\(walk.minutes)-minute walk")
            if let drop = walk.forecastPeakDropMgDl {
                Text("Could trim the forecast peak by about \(Int(drop.rounded())) mg/dL.")
                    .font(.subheadline)
            }
            if let peak = walk.forecastPeakMgDl {
                Text("Forecast peak likely near \(Int(peak.rounded())) mg/dL without it.")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
            }
            if let source = walk.effectSource, source.isKnown {
                ChatTag(text: source == .literature ? "Effect source: literature" : "Effect source: your data", symbol: "book")
            }
            StartWalkButton(minutes: walk.minutes)
        }
        .chatCardStyle()
        .accessibilityElement(children: .combine)
    }
}

private struct GradeChatCard: View {
    let grade: Grade

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ChatCardHeader(symbol: "checkmark.seal", title: "Prediction graded")
            Text(grade.message).font(.subheadline)
            GradeBadge(grade: grade)
        }
        .chatCardStyle()
    }
}

// MARK: Shared pieces

private struct ChatCardHeader: View {
    let symbol: String
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 30, height: 30)
                .background(Theme.accent.opacity(0.15), in: Circle())
            Text(title)
                .font(.headline)
                .lineLimit(2)
        }
    }
}

/// A small label like "Simulated, not logged".
private struct ChatTag: View {
    let text: String
    let symbol: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Theme.accent.opacity(0.12), in: Capsule())
    }
}

private extension View {
    func chatCardStyle() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
