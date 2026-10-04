import SwiftUI

/// The food log (GET /foodlog), like a Notion database: one row per meal, grouped by meal slot in collapsible
/// sections, with Time · Food · Carbs · Result on iPhone and every property in the detail sheet.
struct FoodLogView: View {
    @Environment(AppModel.self) private var model
    @State private var collapsed: Set<MealSlot> = []
    /// One sheet slot for both the row detail and Log food: two sheet modifiers on one view only present one of them.
    private enum FoodSheet: Identifiable {
        case detail(FoodLogEntry)
        case logFood

        var id: String {
            switch self {
            case .detail(let entry): "detail-\(entry.id)"
            case .logFood: "log-food"
            }
        }
    }

    @State private var sheet: FoodSheet?

    private var entries: [FoodLogEntry] { (model.foodLog?.entries ?? []).sorted { $0.meal.eatenAt < $1.meal.eatenAt } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DaySwitcher(selected: model.foodDate, loaded: model.foodLog?.date) { date in
                        model.foodDate = date
                        Task { await model.loadFoodLog() }
                    }
                    .padding(.bottom, 14)
                    if !entries.isEmpty {
                        columnHeader
                        ForEach(MealSlot.allCases) { slot in
                            let rows = entries.filter { MealSlot.of($0.meal.eatenAt) == slot }
                            if !rows.isEmpty { section(slot, rows) }
                        }
                    }
                    SafetyLine().padding(.top, 20)
                }
                .padding(.horizontal)
                .padding(.bottom, 90)
            }
            .overlay {
                if model.foodLog != nil, entries.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing logged yet", systemImage: "fork.knife")
                    } description: {
                        Text("Tell me what you ate in chat and I'll add it here.")
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) { addButton }
            .refreshable { await model.loadFoodLog() }
            .navigationTitle("Food log")
            .background(Theme.background)
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .detail(let entry): FoodDetailSheet(entry: entry)
                case .logFood: LogFoodSheet()
                }
            }
            .task { await model.loadFoodLog() }
            .onChange(of: model.focusedMealId, initial: true) { _, id in
                guard let id else { return }
                Task {
                    if model.foodLog?.entries.contains(where: { $0.id == id }) != true { await model.loadFoodLog() }
                    sheet = model.foodLog?.entries.first { $0.id == id }.map(FoodSheet.detail)
                    model.focusedMealId = nil
                }
            }
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 10) {
            Text("Time").frame(width: FoodRow.timeWidth, alignment: .leading)
            Text("Food").frame(maxWidth: .infinity, alignment: .leading)
            Text("Carbs").frame(width: FoodRow.carbsWidth, alignment: .trailing)
            Text("Result").frame(width: FoodRow.resultWidth, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Theme.secondaryText)
        .textCase(.uppercase)
        .padding(.bottom, 6)
        .accessibilityHidden(true)
    }

    private func section(_ slot: MealSlot, _ rows: [FoodLogEntry]) -> some View {
        let isCollapsed = collapsed.contains(slot)
        let carbs = rows.map(\.meal.totals.carbsG).reduce(0, +)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy) {
                    if isCollapsed { collapsed.remove(slot) } else { collapsed.insert(slot) }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    Text(slot.rawValue).font(.headline)
                    Text("\(rows.count)").font(.caption.monospacedDigit()).foregroundStyle(Theme.secondaryText)
                    Spacer()
                    Text("\(Int(carbs.rounded())) g carbs")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(slot.rawValue), \(rows.count) meals, \(Int(carbs.rounded())) grams of carbs")
            .accessibilityHint(isCollapsed ? "Expands" : "Collapses")
            Divider()
            if !isCollapsed {
                ForEach(rows) { entry in
                    Button { sheet = .detail(entry) } label: { FoodRow(entry: entry) }
                        .buttonStyle(.plain)
                    Divider()
                }
            }
        }
        .padding(.top, 6)
    }

    private var addButton: some View {
        Button {
            sheet = .logFood
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 46, height: 46)
        }
        .floatingGlassButton()
        .padding(20)
        .accessibilityLabel("Log food")
    }
}

/// Time · Food · Carbs · Result.
struct FoodRow: View {
    static let timeWidth: CGFloat = 58
    static let carbsWidth: CGFloat = 40
    static let resultWidth: CGFloat = 126
    let entry: FoodLogEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(FoodLogText.time(entry.meal.eatenAt))
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.secondaryText)
                .frame(width: Self.timeWidth, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(FoodLogText.foods(entry.meal))
                    .font(.subheadline)
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if entry.origin != .studyLog { SourcePill(origin: entry.origin) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(Int(entry.meal.totals.carbsG.rounded())) g")
                .font(.subheadline.monospacedDigit())
                .frame(width: Self.carbsWidth, alignment: .trailing)
            ResultCell(result: FoodResult.of(entry))
                .frame(width: Self.resultWidth, alignment: .trailing)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(FoodLogText.spoken(entry))
        .accessibilityAddTraits(.isButton)
    }
}

struct ResultCell: View {
    let result: FoodResult

    var body: some View {
        switch result {
        case .graded(let me, let cgmOnly, let lastValue, let actual, let beat):
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 3) {
                    if beat { Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.accent) }
                    Text("Me \(me)" + (actual.map { " → \($0)" } ?? ""))
                }
                .font(.footnote.monospacedDigit().weight(.semibold))
                Text([cgmOnly.map { "CGM \($0)" }, lastValue.map { "last \($0)" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
            }
        case .simulated(let peak):
            VStack(alignment: .trailing, spacing: 2) {
                Text("Not graded")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Theme.secondaryText.opacity(0.12), in: Capsule())
                if let peak {
                    Text("likely \(peak)").font(.caption2.monospacedDigit()).foregroundStyle(Theme.secondaryText)
                }
            }
        case .pending(let after):
            Text(after.map { "Grading after \(FoodLogText.time($0))" } ?? "Grading soon")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.trailing)
        case .none(let note):
            Text(note ?? "–").font(.caption2).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.trailing)
        }
    }
}

/// "Study log", "You", or "Gummi" (with a sparkle), like a Notion select property.
struct SourcePill: View {
    let origin: FoodOrigin

    var body: some View {
        Label {
            Text(FoodLogText.source(origin))
        } icon: {
            Image(systemName: origin == .gummi ? "sparkles" : origin == .you ? "person.fill" : "book.closed.fill")
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(origin == .gummi ? Theme.accent : Theme.secondaryText)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background((origin == .gummi ? Theme.accent : Theme.secondaryText).opacity(0.12), in: Capsule())
    }
}

/// Previous day, the date (with a calendar), next day. Nil means the backend's today.
struct DaySwitcher: View {
    @Environment(AppModel.self) private var model
    let selected: String?
    let loaded: String?
    let onChange: (String?) -> Void

    private var today: Date { model.state?.replayNow ?? .now }
    private var current: Date { selected.flatMap(FoodLogText.date(from:)) ?? loaded.flatMap(FoodLogText.date(from:)) ?? today }

    var body: some View {
        HStack(spacing: 10) {
            Button { move(-1) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("Previous day")
            DatePicker("Day", selection: Binding(get: { current }, set: { pick($0) }), displayedComponents: .date)
                .labelsHidden()
                .environment(\.timeZone, Theme.timeZone)
            Button { move(1) } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel("Next day")
                .disabled(FoodLogText.dateString(current) >= FoodLogText.dateString(today))
            if selected != nil {
                Button("Today") { onChange(nil) }.font(.subheadline.weight(.semibold))
            }
        }
        .font(.headline)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassSurface(in: Capsule())
    }

    private func move(_ days: Int) { pick(Calendar.current.date(byAdding: .day, value: days, to: current) ?? current) }

    private func pick(_ date: Date) {
        let string = FoodLogText.dateString(date)
        onChange(string == FoodLogText.dateString(today) ? nil : string)
    }
}
