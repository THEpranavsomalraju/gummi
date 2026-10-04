import SwiftUI

/// A meal's foods with a −/+ portion stepper each, the totals, and Save changes once something changed.
/// Edits scale each food's macros on the phone (PATCH /meals keeps what it's sent). Used by chat and the Food tab.
struct PortionEditor: View {
    let meal: Meal
    var saving = false
    var editable = true
    let onSave: ([MealItem]) async -> Bool
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
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name.prefix(1).uppercased() + item.name.dropFirst())
                            .font(.subheadline.weight(.semibold))
                        Text("\(Self.portion(item)) · \(Int(item.carbsG.rounded())) g carbs")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Spacer(minLength: 8)
                    if editable, item.editable, index < quantities.count {
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
                    Task { failed = !(await onSave(items)) }
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
        .onChange(of: meal, initial: true) { _, newMeal in
            quantities = newMeal.items.map(\.quantity)
            failed = false
        }
    }

    static func portion(_ item: MealItem) -> String {
        let amount = item.quantity.formatted(.number.precision(.fractionLength(0...1)))
        return item.unit.isEmpty ? "× \(amount)" : "\(amount) \(item.unit)"
    }
}

/// Half-portion steps, from 0.5 up to 6 (the backend's portion cap). A logged amount above 6 can still step down.
struct PortionStepper: View {
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

