import SwiftUI

/// Every property of one food log entry, the meal's curve when it's been graded, editable portions for your and
/// Gummi's entries, and a way to ask Gummi about it.
struct FoodDetailSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let entry: FoodLogEntry
    @State private var saving = false

    private var meal: Meal { entry.meal }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(FoodLogText.foods(meal)).font(.title2.bold())
                    properties
                    if let curve { curve }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Foods").font(.headline)
                        PortionEditor(meal: meal, saving: saving, editable: entry.origin != .studyLog) { items in
                            saving = true
                            defer { saving = false }
                            return await model.savePortions(mealId: meal.mealId, items: items)
                        }
                        if entry.origin == .studyLog {
                            Text("From the participant's own food log, so portions stay as they logged them.")
                                .font(.caption).foregroundStyle(Theme.secondaryText)
                        }
                    }
                    Button {
                        dismiss()
                        model.askGummi("Tell me about my \(FoodLogText.foods(meal).lowercased()) at \(FoodLogText.time(meal.eatenAt)).")
                    } label: {
                        Label("Ask Gummi about this meal", systemImage: "bubble.left.and.text.bubble.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.accent)
                    SafetyLine()
                }
                .padding()
            }
            .navigationTitle(MealSlot.of(meal.eatenAt).rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private var properties: some View {
        let result = FoodResult.of(entry)
        return VStack(spacing: 0) {
            row("Time", FoodLogText.time(meal.eatenAt))
            row("Source") { SourcePill(origin: entry.origin) }
            row("Carbs", "\(Int(meal.totals.carbsG.rounded())) g · \(Int(meal.totals.calories.rounded())) kcal")
            if let prediction = entry.prediction {
                row(entry.origin == .studyLog ? "Gummi predicted" : "Likely peak", "\(Int(prediction.predictedPeakMgDl.rounded())) mg/dL")
                if let cgm = prediction.cgmOnlyPeakMgDl { row("CGM-only", "\(Int(cgm.rounded())) mg/dL") }
                if let last = prediction.lastValuePeakMgDl { row("Last value", "\(Int(last.rounded())) mg/dL") }
            }
            if case .graded(_, _, _, let actual?, let beat) = result {
                row("Actual peak", "\(actual) mg/dL" + (beat ? " · beat CGM-only" : ""))
            }
            row("Result") { ResultCell(result: result) }
            if let note = entry.note { row("Note", note) }
            if let grade = entry.grade, !grade.walkEffectGraded { row("Walk", "Walk effect not graded (replayed data)") }
        }
        .padding(.horizontal, 14)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// The real curve from the meal's story card over Gummi's dotted prediction.
    private var curve: RevealingCurves? {
        guard let grade = entry.grade,
              let card = model.cards.first(where: { $0.type == .mealStory && $0.attachments?.grade?.predictionId == grade.predictionId }),
              let actual = card.attachments?.curve, !actual.isEmpty else { return nil }
        let predicted = model.prediction(for: grade.predictionId)?.predictedCurve ?? []
        return RevealingCurves(predicted: predicted.map { ($0.t, $0.glucoseMgDl) }, actual: actual.map { ($0.t, $0.glucoseMgDl) }, height: 90)
    }

    private func row(_ title: String, _ value: String) -> some View {
        row(title) { Text(value).multilineTextAlignment(.trailing) }
    }

    private func row<V: View>(_ title: String, @ViewBuilder value: () -> V) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).foregroundStyle(Theme.secondaryText)
                Spacer(minLength: 12)
                value()
            }
            .font(.subheadline.monospacedDigit())
            .padding(.vertical, 10)
            Divider()
        }
    }
}

/// "+": what you ate, how much, and an optional unit. The backend looks up the nutrition.
struct LogFoodSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var quantity = 1.0
    @State private var unit = ""
    @State private var saving = false
    @State private var failed = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What did you eat?", text: $name)
                        .focused($focused)
                        .submitLabel(.done)
                    Stepper(value: $quantity, in: 0.5...6, step: 0.5) {
                        LabeledContent("Portions", value: quantity.formatted(.number.precision(.fractionLength(0...1))))
                    }
                    TextField("Unit (optional), like slice or cup", text: $unit)
                } footer: {
                    if let name = model.displayName(for: model.state?.actingAs) {
                        Text("Added to \(name)'s day as a simulated entry. It's never graded, because they didn't really eat it.")
                    } else {
                        Text("Gummi looks up the nutrition, and you can fix portions afterwards.")
                    }
                }
                if failed {
                    Text("Couldn't save that. Try again.").foregroundStyle(.red)
                }
            }
            .navigationTitle("Log food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") {
                        Task {
                            saving = true
                            let trimmedUnit = unit.trimmingCharacters(in: .whitespaces)
                            let ok = await model.logFood(name: name.trimmingCharacters(in: .whitespaces), quantity: quantity,
                                                         unit: trimmedUnit.isEmpty ? nil : trimmedUnit)
                            saving = false
                            if ok { dismiss() } else { failed = true }
                        }
                    }
                    .disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }
}
