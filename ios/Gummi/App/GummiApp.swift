import SwiftUI

@main
struct GummiApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    /// Unit tests host the app; it must not open the live channel or follow anyone then.
    private let isHostingTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    var body: some Scene {
        WindowGroup {
            DebugView()
                .environment(model)
        }
        .onChange(of: scenePhase) { _, phase in
            guard !isHostingTests else { return }
            model.scenePhaseChanged(phase)
        }
    }
}
