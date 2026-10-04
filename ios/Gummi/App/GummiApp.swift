import SwiftUI

@main
struct GummiApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    /// Unit tests host the app; it must not open the live channel or follow anyone then.
    private let isHostingTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if UserDefaults.standard.string(forKey: "gummi.screen") == "playground" {
                    NavigationStack { PuppetPlaygroundView() }
                } else {
                    RootView()
                }
                #else
                RootView()
                #endif
            }
            .environment(model)
        }
        .onChange(of: scenePhase) { _, phase in
            guard !isHostingTests else { return }
            model.scenePhaseChanged(phase)
        }
    }
}
