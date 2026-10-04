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
            #if DEBUG
            // Screenshot helpers: -gummi.tab today, -gummi.sheet follow|chat.
            .task {
                let defaults = UserDefaults.standard
                if defaults.string(forKey: "gummi.tab") == "today" { model.selectedTab = .today }
                try? await Task.sleep(for: .seconds(2))
                switch defaults.string(forKey: "gummi.sheet") {
                case "follow": model.showsFollowPicker = true
                case "chat": model.askGummi("Why did I peak at 174?")
                default: break
                }
            }
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            guard !isHostingTests else { return }
            model.scenePhaseChanged(phase)
        }
    }
}
