import SwiftUI

/// "Acting as Participant 12" (opens the Follow picker), with Paused, Stopped, and Mock badges.
struct HomeHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            Button {
                model.showsFollowPicker = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle")
                    if let name = model.displayName(for: model.state?.actingAs) {
                        Text("Acting as \(name)")
                    } else {
                        Text("Choose who to follow")
                    }
                    Image(systemName: "chevron.down").font(.caption2.bold())
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassSurface(in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the list of participants")

            if let stream = model.state?.stream {
                if !stream.running {
                    Badge(text: "Stopped", symbol: "stop.fill")
                } else if stream.paused {
                    Badge(text: "Paused", symbol: "pause.fill")
                }
            }
            if model.mode == .mock {
                Badge(text: "Mock", symbol: "theatermasks")
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// A small glass status pill.
struct Badge: View {
    let text: String
    let symbol: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glassSurface(in: Capsule())
    }
}

/// The safety line every glucose screen carries.
struct SafetyLine: View {
    var body: some View {
        Text("Not for treatment decisions. Check your Dexcom app for current readings.")
            .font(.caption2)
            .foregroundStyle(Theme.secondaryText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}

/// The newest five cards as a swipeable stack with a page indicator. Swiping never deletes anything;
/// a new card slides onto the top.
struct CoachCardStack: View {
    @Environment(AppModel.self) private var model
    @State private var selection: String?

    var body: some View {
        let cards = Array(model.cards.prefix(5))
        Group {
            if cards.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Gummi's coach cards").font(.headline)
                    Text("Briefings, meals, and grades show up here as the day unfolds.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(.horizontal)
            } else {
                TabView(selection: $selection) {
                    ForEach(cards) { card in
                        StoryCardView(card: card, style: .compact)
                            .padding(.horizontal)
                            .padding(.bottom, cards.count > 1 ? 28 : 0)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .tag(Optional(card.cardId))
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: cards.count > 1 ? .always : .never))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                .onChange(of: cards.first?.cardId) { _, newest in
                    withAnimation(.snappy) { selection = newest }
                }
            }
        }
    }
}

/// A glass speech bubble beside Gummi's head, its tail pointing at him. Opens chat.
struct ChatBubbleButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "ellipsis")
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.accent)
                .frame(width: 58, height: 42)
                .padding(.bottom, 8)
                .glassSurface(in: SpeechBubble())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Chat with Gummi")
    }
}

/// A rounded bubble with a tail at the lower left.
struct SpeechBubble: Shape {
    func path(in rect: CGRect) -> Path {
        let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - 8)
        var path = Path(roundedRect: body, cornerRadius: min(18, body.height / 2), style: .continuous)
        path.move(to: CGPoint(x: body.minX + 12, y: body.maxY - 1))
        path.addQuadCurve(to: CGPoint(x: body.minX + 2, y: rect.maxY), control: CGPoint(x: body.minX + 10, y: rect.maxY - 2))
        path.addQuadCurve(to: CGPoint(x: body.minX + 24, y: body.maxY - 1), control: CGPoint(x: body.minX + 16, y: body.maxY + 2))
        path.closeSubpath()
        return path
    }
}
