import Charts
import SwiftUI

/// One story card, laid out for its type. `.compact` fits Home's coach stack; `.full` is Today's feed.
struct StoryCardView: View {
    enum Style { case compact, full }

    @Environment(AppModel.self) private var model
    let card: StoryCard
    var style: Style = .full

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Text(card.body)
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)
                .lineLimit(style == .compact ? 2 : nil)
                .fixedSize(horizontal: false, vertical: style == .full)
            details
            actions
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: card.type.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 30, height: 30)
                .background(Theme.accent.opacity(0.15), in: Circle())
            Text(card.title)
                .font(.headline)
                .lineLimit(2)
            Spacer(minLength: 4)
            Text(card.createdAt, format: .dateTime.hour().minute())
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .environment(\.timeZone, Theme.timeZone)
        }
    }

    /// Home's compact cards keep only what you act on (Log it) or celebrate (a grade); Today shows everything.
    @ViewBuilder
    private var details: some View {
        if style == .compact {
            compactDetails
        } else {
            fullDetails
        }
    }

    @ViewBuilder
    private var compactDetails: some View {
        switch card.type {
        case .mealDue:
            fullDetails
        case .mealStory, .grade:
            if let grade = card.attachments?.grade {
                GradeBadge(grade: grade, compact: true)
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var fullDetails: some View {
        switch card.type {
        case .mealDue:
            if let dueId = card.pendingDueId {
                Button {
                    Task { await model.logDueMeal(dueId) }
                } label: {
                    Label("Log it", systemImage: "checkmark")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            } else {
                Label("Logged", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
        case .mealLogged:
            if let meal = card.attachments?.meal {
                MealLine(meal: meal)
            }
            if let prediction = card.attachments?.prediction {
                Text("Predicted peak \(Int(prediction.predictedPeakMgDl.rounded())) mg/dL")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
        case .prediction:
            if let prediction = card.attachments?.prediction {
                Text("Predicted peak \(Int(prediction.predictedPeakMgDl.rounded())) mg/dL")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                if style == .full {
                    MiniCurve(points: prediction.predictedCurve.map { ($0.t, $0.glucoseMgDl) }, dashed: true)
                }
            }
        case .mealStory, .grade:
            if let grade = card.attachments?.grade {
                GradeBadge(grade: grade)
            }
            if style == .full, let curve = card.attachments?.curve, !curve.isEmpty {
                // Gummi's prediction dotted, the real curve drawing in over it.
                let predicted = card.attachments?.grade.flatMap { model.prediction(for: $0.predictionId) }?.predictedCurve ?? []
                RevealingCurves(predicted: predicted.map { ($0.t, $0.glucoseMgDl) },
                                actual: curve.map { ($0.t, $0.glucoseMgDl) }, height: 70)
            }
        case .walkSummary:
            if let walk = card.attachments?.walk {
                WalkLine(walk: walk)
            }
        case .walkSuggested:
            StartWalkButton(minutes: card.attachments?.alert?.action.minutes ?? 10)
        default:
            EmptyView()
        }
    }

    /// "Ask Gummi" opens chat; Start walk lives in the walk_suggested details.
    @ViewBuilder
    private var actions: some View {
        let chatActions = card.actions.filter { $0.kind == .openChat }
        if !chatActions.isEmpty, style == .full {
            HStack {
                ForEach(chatActions, id: \.label) { action in
                    Button(action.label, systemImage: "bubble.left.and.text.bubble.right") {
                        model.askGummi(action.prompt)
                    }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.bordered)
                    .tint(Theme.accent)
                }
            }
        }
    }
}

/// "Gummi 7 · CGM-only 11 · last value 18", with a rosette when Gummi beat CGM-only. Tapping cheers or nods.
struct GradeBadge: View {
    @Environment(AppModel.self) private var model
    let grade: Grade
    var compact = false

    var body: some View {
        Button {
            model.cue(grade.earnsProud ? .cheer : .nod)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if grade.earnsProud {
                        Image(systemName: "rosette").foregroundStyle(Theme.accent)
                    }
                    Text(grade.threeNumberBadge)
                        .font(.footnote.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Theme.primaryText)
                }
                if !compact {
                    Text("Average error in mg/dL, out-of-sample")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                }
                if !grade.walkEffectGraded {
                    Text("Walk effect not graded (replayed data)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Opens the walk screen with the suggested minutes.
struct StartWalkButton: View {
    @Environment(AppModel.self) private var model
    let minutes: Int

    var body: some View {
        Button {
            model.startWalk(minutes: minutes)
        } label: {
            Label("Start a \(minutes)-minute walk", systemImage: "figure.walk")
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
    }
}

/// Food names and carbs for a logged meal.
struct MealLine: View {
    let meal: Meal

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(meal.items.map(\.name).joined(separator: ", "))
                .font(.footnote)
                .lineLimit(2)
            Spacer()
            Text("\(Int(meal.totals.carbsG.rounded())) g carbs")
                .font(.footnote.monospacedDigit().weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
        }
    }
}

/// Minutes, steps, intensity, and the modeled effect with its source.
struct WalkLine: View {
    let walk: WalkSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(walk.minutes) min · \(walk.steps.formatted()) steps · \(walk.intensity.rawValue)")
                .font(.footnote.monospacedDigit().weight(.semibold))
            Text("Modeled effect about \(Int(walk.forecastPeakDropMgDl.rounded())) mg/dL lower at the peak (\(walk.effectSource.rawValue))")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
    }
}

/// A small line chart for a card: the meal's real curve (solid) or a prediction (dashed).
struct MiniCurve: View {
    let points: [(Date, Double)]
    var dashed = false

    var body: some View {
        Chart(Array(points.enumerated()), id: \.offset) { _, point in
            LineMark(x: .value("Time", point.0), y: .value("mg/dL", point.1))
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: dashed ? [6, 4] : []))
                .foregroundStyle(Theme.confirmedLine)
        }
        .chartXAxis(.hidden)
        .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) }
        .frame(height: 70)
        .accessibilityHidden(true)
    }
}
