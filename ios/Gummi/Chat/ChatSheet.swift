import SwiftUI

/// The chat sheet shell, styled like a game dialogue box: a name tag, text that types out, and a blinking arrow.
/// Real conversations arrive in the chat chunk; for now Gummi says hello and the question you tapped waits in the field.
struct ChatSheet: View {
    let request: ChatRequest
    @State private var typed = 0
    @State private var draft = ""

    private let greeting = "Hi, I'm Gummi! I'm still learning to chat. Soon you can ask me about your meals, your walks, and where your glucose is headed."

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Spacer()
                DialogueBox(speaker: "Gummi", text: String(greeting.prefix(typed)), isFinished: typed >= greeting.count)
                HStack(spacing: 10) {
                    TextField("Ask Gummi…", text: $draft, axis: .vertical)
                        .lineLimit(1...3)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .glassSurface(in: Capsule())
                    Button {} label: {
                        Image(systemName: "arrow.up")
                            .font(.headline)
                            .frame(width: 40, height: 40)
                            .glassSurface(in: Circle())
                    }
                    .disabled(true)
                    .accessibilityLabel("Send (coming with chat)")
                }
            }
            .padding()
            .background(Theme.background)
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                draft = request.prompt ?? ""
                typed = 0
                for count in 0...greeting.count {
                    typed = count
                    try? await Task.sleep(for: .milliseconds(22))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// A game-style dialogue box: thick rounded frame, the speaker's name on a tab, and a ▼ when the line is done.
struct DialogueBox: View {
    let speaker: String
    let text: String
    let isFinished: Bool
    @State private var arrowUp = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text(text)
                .font(.system(.body, design: .rounded).weight(.medium))
                .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
                .padding(.horizontal, 18)
                .padding(.top, 22)
                .padding(.bottom, 26)
                .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Theme.primaryText.opacity(0.85), lineWidth: 3)
                }
                .overlay(alignment: .bottomTrailing) {
                    if isFinished {
                        Image(systemName: "arrowtriangle.down.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.accent)
                            .offset(y: arrowUp ? -3 : 0)
                            .padding(12)
                            .onAppear {
                                withAnimation(.easeInOut(duration: 0.5).repeatForever()) { arrowUp = true }
                            }
                    }
                }
            Text(speaker)
                .font(.system(.subheadline, design: .rounded).bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(Theme.accent, in: Capsule())
                .offset(x: 18, y: -14)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(speaker) says: \(text)")
    }
}
