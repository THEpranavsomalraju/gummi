import SwiftUI

/// Debug-only playground for Gummi: try every mood, tap, wave, dance, talk, and think on the phone (D-92).
struct PuppetPlaygroundView: View {
    @State private var mood: Mood = .calm
    @State private var talking = false
    @State private var thinking = false
    /// `-gummi.playgroundTour YES` starts the tour, for screenshots.
    @State private var touring = UserDefaults.standard.bool(forKey: "gummi.playgroundTour")
    @State private var translucent = false
    @State private var controller = KoalaController()

    private static let moods: [Mood] = [.calm, .rising, .high, .dipping, .low, .proud, .happy, .sleepy, .thinking]

    var body: some View {
        VStack(spacing: 0) {
            PuppetView(input: PuppetInput(mood: mood == .thinking ? .calm : mood, talking: talking,
                                          thinking: thinking || mood == .thinking),
                       controller: controller, showsFPS: true, translucentShell: translucent)
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
        .task {
            // `-gummi.playgroundDance YES` dances on open, for screenshots.
            if UserDefaults.standard.bool(forKey: "gummi.playgroundDance") {
                try? await Task.sleep(for: .seconds(1))
                controller.react(.dance)
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
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
                Button("Head", systemImage: "hand.tap") { controller.react(.tap(.head)) }
                Button("Belly", systemImage: "hand.point.up.left") { controller.react(.tap(.belly)) }
                Button("Wave", systemImage: "hand.wave") { controller.react(.wave) }
                Button("Dance", systemImage: "figure.dance") { controller.react(.dance) }
            }
            .buttonStyle(.bordered)
            .labelStyle(.titleAndIcon)
            HStack(spacing: 8) {
                Toggle("Talk", systemImage: "waveform", isOn: $talking)
                Toggle("Think", systemImage: "ellipsis.bubble", isOn: $thinking)
                Toggle("Tour", systemImage: "play", isOn: $touring)
                Toggle("Shell", systemImage: "circle.dotted", isOn: $translucent)
            }
            .toggleStyle(.button)
            .buttonStyle(.bordered)
            Text("Press and hold Gummi to squish him. Double-tap to dance.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
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
