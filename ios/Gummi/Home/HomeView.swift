import SwiftUI

/// Placeholder Home: Gummi in the middle, driven by the live mood. The coach card, header, and chart come in the Home chunk.
struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        PuppetView(input: PuppetInput(mood: model.mood))
            .ignoresSafeArea(edges: .top)
            .background(Theme.background)
    }
}
