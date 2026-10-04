import SwiftUI

/// Placeholder Home: Gummi, driven by the live mood. The coach card, header, and chart come in the Home chunk.
struct HomeView: View {
    @Environment(AppModel.self) private var model

    /// How far Gummi sits below the middle of the screen, as a fraction of its height.
    /// Puts his feet just above the tab bar; the Home chunk retunes this when the card and chart arrive.
    static let puppetDrop: CGFloat = 0.19

    var body: some View {
        GeometryReader { geometry in
            PuppetView(input: PuppetInput(mood: model.mood), greets: true)
                .offset(y: geometry.size.height * Self.puppetDrop)
        }
        .ignoresSafeArea()
        .background(Theme.background)
    }
}
