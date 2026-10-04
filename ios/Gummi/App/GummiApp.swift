import SwiftUI

@main
struct GummiApp: App {
    @State private var model = AppModel(systemServices: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil)
    @State private var notificationTaps = NotificationTaps()
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
            .onAppear { notificationTaps.onTap = { model.selectedTab = .today } }
            #if DEBUG
            // Screenshot helpers: -gummi.tab today|settings, -gummi.sheet follow|chat|walk, and -gummi.chat "first|second"
            // to ask questions in turn (an empty -gummi.chat opens the empty chat).
            .task {
                let defaults = UserDefaults.standard
                switch defaults.string(forKey: "gummi.tab") {
                case "today": model.selectedTab = .today
                case "settings": model.selectedTab = .settings
                default: break
                }
                try? await Task.sleep(for: .seconds(2))
                switch defaults.string(forKey: "gummi.sheet") {
                case "follow": model.showsFollowPicker = true
                case "walk": model.startWalk(minutes: 10)
                case "chat":
                    let prompts = (defaults.string(forKey: "gummi.chat") ?? "").split(separator: "|").map(String.init)
                    model.askGummi(prompts.first)
                    for prompt in prompts.dropFirst() {
                        try? await Task.sleep(for: .seconds(1))
                        while model.chat.isBusy || model.chat.isTalking { try? await Task.sleep(for: .milliseconds(200)) }
                        model.chat.send(prompt)
                    }
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
