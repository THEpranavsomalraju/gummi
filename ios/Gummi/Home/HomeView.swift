import SwiftUI

/// Home, coaching first: who you're acting as, the newest coach card, Gummi with his chat bubble,
/// the glucose chart, and the safety line (PROJECT_OVERVIEW section 4).
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var puppet = KoalaController()

    /// Meters of the world Gummi's band shows top to bottom: he fills about three quarters of it.
    static let puppetVisibleHeight: Float = 0.56

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let chatting = model.chatRequest != nil
            VStack(spacing: 10) {
                HomeHeader()
                if !chatting {
                    CoachCardStack()
                        .frame(height: height * 0.24)
                        .transition(.opacity)
                }
                ZStack {
                    PuppetView(input: puppetInput(chatting: chatting), controller: puppet, greets: true,
                               cue: model.puppetCue, visibleHeight: Self.puppetVisibleHeight)
                    GeometryReader { band in
                        let showsBubble = puppet.showsChatHint && !chatting
                        ChatBubbleButton { model.askGummi() }
                            .position(x: band.size.width / 2 + band.size.height * 0.33, y: band.size.height * 0.16)
                            .opacity(showsBubble ? 1 : 0)
                            .scaleEffect(showsBubble ? 1 : 0.85)
                            .allowsHitTesting(showsBubble)
                            .animation(.easeInOut(duration: 0.35), value: showsBubble)
                    }
                }
                .frame(height: chatting ? stageHeight(geometry) : nil)
                .frame(maxHeight: chatting ? nil : .infinity)
                if chatting {
                    Spacer(minLength: 0)
                } else if let state = model.state {
                    GlucoseChart(state: state)
                        .frame(height: height * 0.21)
                        .padding(.horizontal)
                        .transition(.opacity)
                }
                SafetyLine()
                    .padding(.horizontal)
            }
            .padding(.top, 4)
            .padding(.bottom, 6)
            .animation(.snappy(duration: 0.45), value: chatting)
        }
        .background(Theme.background)
    }

    /// While chat is open Gummi is on stage: he talks as his reply types out, thinks during tools,
    /// and wears the mood the reply ended on.
    private func puppetInput(chatting: Bool) -> PuppetInput {
        guard chatting else { return PuppetInput(mood: model.mood) }
        return PuppetInput(mood: model.chat.mood ?? model.mood, talking: model.chat.isTalking, thinking: model.chat.isThinking)
    }

    /// The space between the header and the chat sheet's compact detent, so all of Gummi shows above it.
    private func stageHeight(_ geometry: GeometryProxy) -> CGFloat {
        // A fraction detent is measured below the top safe area, which is also where this view starts.
        let insets = geometry.safeAreaInsets
        let belowTopInset = geometry.size.height + insets.bottom
        return max(120, belowTopInset * (1 - ChatSheet.compactDetent) - Self.headerAllowance)
    }

    /// The header row, its spacing, and the top padding.
    static let headerAllowance: CGFloat = 58
}
