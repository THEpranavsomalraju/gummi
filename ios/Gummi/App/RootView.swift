import SwiftUI

/// Tabs: Home, Today, Settings (PROJECT_OVERVIEW section 4). Each tab's content comes in its own chunk.
struct RootView: View {
    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") { HomeView() }
            Tab("Today", systemImage: "list.bullet.rectangle") { TodayView() }
            Tab("Settings", systemImage: "gearshape") { SettingsView() }
        }
    }
}
