import SwiftUI

/// Chat with Gummi, styled like game dialogue: your lines are bubbles, Gummi's replies type out in a framed box
/// with his name tag, tool steps show as chips, and results land as cards under the reply (CONTRACT section 6).
/// The sheet opens at about 60% height so Gummi stays on stage above it, talking and thinking along.
struct ChatSheet: View {
    /// The compact detent. Home sizes Gummi's stage to the space above it.
    static let compactDetent: CGFloat = 0.58
    static let prompts = ["Can I eat a cookie now?", "How am I doing today?", "I just had a granola bar", "Should I take a walk?"]

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let request: ChatRequest
    @State private var draft = ""
    @State private var detent = ChatSheet.initialDetent

    #if DEBUG
    /// `-gummi.chatDetent large` opens chat full height, for screenshots.
    private static var initialDetent: PresentationDetent {
        UserDefaults.standard.string(forKey: "gummi.chatDetent") == "large" ? .large : .fraction(compactDetent)
    }
    #else
    private static let initialDetent = PresentationDetent.fraction(compactDetent)
    #endif

    var body: some View {
        let chat = model.chat
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if chat.turns.isEmpty {
                            ChatWelcome(actingAs: model.displayName(for: model.state?.actingAs)) { chat.send($0) }
                        }
                        ForEach(chat.turns) { turn in
                            ChatTurnView(turn: turn)
                                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                        }
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: chat.turns.last?.id) {
                    // Each exchange scrolls to its question, so Gummi's line types out in view and its cards sit below.
                    guard let question = chat.turns.last(where: { $0.role == .user }) else { return }
                    withAnimation(.snappy) { proxy.scrollTo(question.id, anchor: .top) }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { inputBar(chat) }
            .background(Theme.background)
            .navigationTitle("Gummi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("New chat", systemImage: "square.and.pencil") { chat.newChat() }
                        .disabled(chat.turns.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.fraction(Self.compactDetent), .large], selection: $detent)
        .presentationBackgroundInteraction(.enabled(upThrough: .fraction(Self.compactDetent)))
        .task(id: request.id) {
            // "Ask Gummi why" on a card asks right away; if a reply is still running, the question waits in the field.
            if let prompt = request.prompt, !chat.send(prompt) { draft = prompt }
        }
        .onDisappear { chat.closed() }
    }

    private func inputBar(_ chat: ChatModel) -> some View {
        VStack(spacing: 8) {
            if let due = model.cards.first(where: { $0.type == .mealDue && $0.pendingDueId != nil }) {
                StoryCardView(card: due, style: .compact)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            HStack(alignment: .bottom, spacing: 10) {
                // The keyboard's mic button handles dictation.
                TextField("Ask Gummi…", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .submitLabel(.send)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .glassSurface(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .onChange(of: draft) { _, text in
                        // A vertical field inserts the return key as a newline, so the newline sends.
                        if text.hasSuffix("\n") {
                            draft.removeLast()
                            sendDraft(chat)
                        }
                    }
                Button {
                    sendDraft(chat)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.headline)
                        .foregroundStyle(canSend(chat) ? Color.white : Theme.secondaryText)
                        .frame(width: 44, height: 44)
                        .background(canSend(chat) ? Theme.accent : Theme.cardSurface, in: Circle())
                }
                .disabled(!canSend(chat))
                .accessibilityLabel("Send")
            }
            SafetyLine()
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(Theme.background)
        .animation(.snappy, value: model.cards.first?.cardId)
    }

    private func canSend(_ chat: ChatModel) -> Bool {
        !chat.isBusy && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendDraft(_ chat: ChatModel) {
        if chat.send(draft) { draft = "" }
    }
}

/// Gummi's hello and the suggested questions, shown while the chat is empty.
private struct ChatWelcome: View {
    let actingAs: String?
    let onPick: (String) -> Void
    @State private var typed = 0

    private var greeting: String {
        if let actingAs {
            "Hi, I'm Gummi! I'm coaching \(actingAs)'s day. Ask me if a food fits right now, tell me what you ate, or ask how today is going."
        } else {
            "Hi, I'm Gummi! Ask me if a food fits right now, tell me what you ate, or ask how today is going."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DialogueBox(speaker: "Gummi", text: greeting, revealed: typed)
                .onTapGesture { typed = greeting.count }
            FlowLayout(spacing: 8) {
                ForEach(ChatSheet.prompts, id: \.self) { prompt in
                    Button {
                        onPick(prompt)
                    } label: {
                        Text(prompt)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(Theme.primaryText)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .glassSurface(in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 4)
        }
        .task(id: greeting) {
            typed = 0
            while typed < greeting.count {
                try? await Task.sleep(for: .milliseconds(22))
                if Task.isCancelled { return }
                typed += 1
            }
        }
    }
}

/// One turn: your bubble, or Gummi's tool chips, dialogue box, retry, and cards.
private struct ChatTurnView: View {
    @Environment(AppModel.self) private var model
    let turn: ChatTurn

    var body: some View {
        switch turn.role {
        case .user:
            HStack {
                Spacer(minLength: 48)
                Text(turn.text)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        case .gummi:
            VStack(alignment: .leading, spacing: 10) {
                if !turn.tools.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(turn.tools) { ToolChipView(chip: $0) }
                    }
                }
                DialogueBox(speaker: "Gummi", text: turn.text, revealed: turn.revealed,
                            thinking: !turn.finished && turn.text.isEmpty)
                    .onTapGesture { model.chat.skipTyping() }
                if turn.failure != nil, turn.finished {
                    Button("Try again", systemImage: "arrow.clockwise") { model.chat.retry(turn.id) }
                        .font(.footnote.weight(.semibold))
                        .buttonStyle(.bordered)
                        .tint(Theme.accent)
                        .disabled(model.chat.isBusy)
                }
                ForEach(turn.cards) { item in
                    ChatCardView(item: item)
                        .transition(.scale(scale: 0.92, anchor: .top).combined(with: .opacity))
                }
            }
        }
    }
}

/// A small glass pill for one tool call: a spinner while it runs, a checkmark when it's done.
private struct ToolChipView: View {
    let chip: ToolChip

    var body: some View {
        HStack(spacing: 6) {
            if chip.finished {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
            } else {
                ProgressView().controlSize(.mini)
            }
            Text(chip.label)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Theme.secondaryText)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassSurface(in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// A game-style dialogue box: thick rounded frame, the speaker's name on a tab, bouncing dots while thinking,
/// text that types out, and a ▼ when the line is done. Unrevealed text is laid out but invisible,
/// so the box never jumps in size while it types.
struct DialogueBox: View {
    let speaker: String
    let text: String
    var revealed: Int
    var thinking = false
    @State private var arrowUp = false

    private var isFinished: Bool { !thinking && revealed >= text.count }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if thinking {
                    ThinkingDots()
                } else {
                    Text(visibleText)
                }
            }
            .font(.system(.body, design: .rounded).weight(.medium))
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 24)
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
        .padding(.top, 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(thinking ? "\(speaker) is thinking" : "\(speaker) says: \(text)")
    }

    private var visibleText: AttributedString {
        let count = min(max(revealed, 0), text.count)
        var shown = AttributedString(String(text.prefix(count)))
        var hidden = AttributedString(String(text.dropFirst(count)))
        hidden.foregroundColor = .clear
        shown.append(hidden)
        return shown
    }
}

/// Three dots bouncing in turn while Gummi thinks.
private struct ThinkingDots: View {
    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 7) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Theme.secondaryText)
                        .frame(width: 9, height: 9)
                        .offset(y: -5 * max(0, sin((time * 2 * .pi / 1.1) - Double(index) * 0.8)))
                }
            }
            .padding(.vertical, 6)
        }
        .accessibilityHidden(true)
    }
}

/// Lays children out left to right, wrapping to a new row when one doesn't fit.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(in: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(in: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func rows(in width: CGFloat, subviews: Subviews) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if let last = rows.last, last.width + spacing + size.width <= width {
                rows[rows.count - 1].indices.append(index)
                rows[rows.count - 1].width += spacing + size.width
                rows[rows.count - 1].height = max(last.height, size.height)
            } else {
                rows.append(([index], size.width, size.height))
            }
        }
        return rows
    }
}
