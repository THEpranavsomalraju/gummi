import SwiftUI

/// Debug-only playground for Gummi: try every mood, tap, talk, and think on the phone (D-92).
struct PuppetPlaygroundView: View {
    @State private var mood: Mood = .calm
    @State private var talking = false
    @State private var thinking = false
    /// `-gummi.playgroundTour YES` starts the tour, for screenshots.
    @State private var touring = UserDefaults.standard.bool(forKey: "gummi.playgroundTour")
    @State private var translucent = false
    @State private var tapTrigger = 0

    private static let moods: [Mood] = [.calm, .rising, .high, .dipping, .low, .proud, .happy, .sleepy, .thinking]

    var body: some View {
        VStack(spacing: 0) {
            PuppetView(input: PuppetInput(mood: mood == .thinking ? .calm : mood, talking: talking,
                                          thinking: thinking || mood == .thinking),
                       showsFPS: true, translucentShell: translucent, tapTrigger: tapTrigger)
            controls
        }
        .background(Theme.background)
        .navigationTitle("Puppet playground")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: touring) {
            guard touring else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                let index = Self.moods.firstIndex(of: mood) ?? 0
                mood = Self.moods[(index + 1) % Self.moods.count]
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.moods, id: \.self) { option in
                        Button(option.rawValue) { mood = option }
                            .buttonStyle(.bordered)
                            .tint(option == mood ? Theme.accent : .secondary)
                    }
                }
                .padding(.horizontal)
            }
            HStack(spacing: 8) {
                Button("Tap", systemImage: "hand.tap") { tapTrigger += 1 }
                Toggle("Talk", systemImage: "waveform", isOn: $talking)
                Toggle("Think", systemImage: "ellipsis.bubble", isOn: $thinking)
                Toggle("Tour", systemImage: "play", isOn: $touring)
            }
            .toggleStyle(.button)
            .buttonStyle(.bordered)
            Toggle("Translucent jelly shell", isOn: $translucent)
                .padding(.horizontal)
        }
        .padding(.vertical, 12)
        .glassSurface(in: RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}

#Preview {
    NavigationStack { PuppetPlaygroundView() }
}
