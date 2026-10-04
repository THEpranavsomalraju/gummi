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
            VStack(spacing: 10) {
                HomeHeader()
                CoachCardStack()
                    .frame(height: height * 0.24)
                ZStack {
                    PuppetView(input: PuppetInput(mood: model.mood), controller: puppet, greets: true,
                               cue: model.puppetCue, visibleHeight: Self.puppetVisibleHeight)
                    GeometryReader { band in
                        ChatBubbleButton { model.askGummi() }
                            .position(x: band.size.width / 2 + band.size.height * 0.33, y: band.size.height * 0.16)
                            .opacity(puppet.showsChatHint ? 1 : 0)
                            .scaleEffect(puppet.showsChatHint ? 1 : 0.85)
                            .allowsHitTesting(puppet.showsChatHint)
                            .animation(.easeInOut(duration: 0.35), value: puppet.showsChatHint)
                    }
                }
                .frame(maxHeight: .infinity)
                if let state = model.state {
                    GlucoseChart(state: state)
                        .frame(height: height * 0.21)
                        .padding(.horizontal)
                }
                SafetyLine()
                    .padding(.horizontal)
            }
            .padding(.top, 4)
            .padding(.bottom, 6)
        }
        .background(Theme.background)
    }
}
