import SwiftUI

/// Which cards Activity shows.
nonisolated enum ActivityFilter: String, CaseIterable, Sendable, Identifiable {
    case all = "All", meals = "Meals", walks = "Walks", grades = "Grades"

    var id: String { rawValue }

    func matches(_ type: CardType) -> Bool {
        switch self {
        case .all: true
        case .meals: [.mealDue, .mealLogged, .mealStory, .prediction].contains(type)
        case .walks: [.walkSuggested, .walkSummary].contains(type)
        case .grades: [.mealStory, .grade].contains(type)
        }
    }
}

/// Activity: everything Gummi posted or nudged, newest first, grouped by time of day, with filter chips.
/// Tapping a banner or a notification lands here; tapping a meal card opens that meal in Food.
struct ActivityView: View {
    @Environment(AppModel.self) private var model
    @State private var filter = ActivityFilter.all

    private struct Section: Identifiable {
        let id: String
        let cards: [StoryCard]
    }

    /// Groups in feed order (newest first), so the newest part of the day is on top.
    private var sections: [Section] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Theme.timeZone
        var result: [Section] = []
        for card in model.cards where filter.matches(card.type) {
            let hour = calendar.component(.hour, from: card.createdAt)
            let title = switch hour {
            case 5..<12: "Morning"
            case 12..<17: "Afternoon"
            case 17..<22: "Evening"
            default: "Night"
            }
            if result.last?.id == title {
                result[result.count - 1] = Section(id: title, cards: result[result.count - 1].cards + [card])
            } else {
                result.append(Section(id: title, cards: [card]))
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        filterChips
                        if let name = model.displayName(for: model.state?.actingAs) {
                            Text("Acting as \(name)")
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        ForEach(sections) { section in
                            Text(section.id)
                                .font(.title3.bold())
                                .padding(.top, 8)
                            ForEach(section.cards) { card in
                                StoryCardView(card: card, style: .full)
                                    .id(card.cardId)
                                    .contentShape(Rectangle())
                                    .onTapGesture { openMeal(card) }
                                    .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        }
                        SafetyLine().padding(.top, 8)
                    }
                    .padding()
                }
                .overlay {
                    if model.cards.isEmpty {
                        ContentUnavailableView("Nothing yet today", systemImage: "list.bullet.rectangle",
                                               description: Text("Gummi's briefings, meals, and grades land here as the day unfolds."))
                    }
                }
                .safeAreaInset(edge: .top) { ConnectionCapsule() }
                .onChange(of: model.focusedCardId, initial: true) { _, id in
                    guard let id else { return }
                    withAnimation(.snappy) { proxy.scrollTo(id, anchor: .top) }
                    model.focusedCardId = nil
                }
            }
            .navigationTitle("Activity")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Start a walk", systemImage: "figure.walk") { model.startWalk() }
                }
            }
            .background(Theme.background)
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ActivityFilter.allCases) { option in
                    Button {
                        withAnimation(.snappy) { filter = option }
                    } label: {
                        Text(option.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(filter == option ? Color.white : Theme.primaryText)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background {
                                if filter == option { Capsule().fill(Theme.accent) }
                            }
                            .glassSurface(in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(filter == option ? .isSelected : [])
                }
            }
        }
    }

    /// meal_logged and meal_story cards open their meal in Food.
    private func openMeal(_ card: StoryCard) {
        guard card.type == .mealLogged || card.type == .mealStory, let mealId = card.attachments?.meal?.mealId else { return }
        model.focusedMealId = mealId
        model.selectedTab = .food
    }
}
