import SwiftUI

/// Today: the day's story cards, newest first, grouped by time of day. Tapping a banner scrolls here.
struct TodayView: View {
    @Environment(AppModel.self) private var model

    private struct Section: Identifiable {
        let id: String
        let cards: [StoryCard]
    }

    /// Groups in feed order (newest first), so the newest part of the day is on top.
    private var sections: [Section] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Theme.timeZone
        var result: [Section] = []
        for card in model.cards {
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
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Start a walk", systemImage: "figure.walk") { model.startWalk() }
                }
            }
            .background(Theme.background)
        }
    }
}
