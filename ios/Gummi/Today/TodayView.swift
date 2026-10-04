import SwiftUI

/// Placeholder until the Today chunk: the story-card feed.
struct TodayView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("Today", systemImage: "list.bullet.rectangle",
                                   description: Text("Gummi's story cards for the day land here."))
                .navigationTitle("Today")
        }
    }
}
