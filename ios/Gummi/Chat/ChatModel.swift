import Foundation
import Observation
import SwiftUI

nonisolated enum ChatRole: Sendable {
    case user, gummi
}

/// "Logging your meal…" while a tool runs, "Logged your meal" once it ends.
nonisolated struct ToolChip: Identifiable, Equatable, Sendable {
    let id: Int
    let name: String
    var finished = false

    var label: String {
        switch name {
        case "get_state": finished ? "Checked your numbers" : "Checking your numbers…"
        case "simulate_food": finished ? "Simulated that food" : "Simulating that food…"
        case "log_meal": finished ? "Logged your meal" : "Logging your meal…"
        case "suggest_walk": finished ? "Planned a walk" : "Planning a walk…"
        case "get_history": finished ? "Looked back at your day" : "Looking back at your day…"
        case "explain_spike": finished ? "Looked into that spike" : "Looking into that spike…"
        case "today_summary": finished ? "Added up today" : "Adding up today…"
        case "get_gold_summary": finished ? "Read the Databricks gold tables" : "Reading the Databricks gold tables…"
        case "ask_data": finished ? "Asked Gummi Insights" : "Asking Gummi Insights, this can take a bit…"
        case "grade_prediction": finished ? "Graded my prediction" : "Grading my prediction…"
        default: finished ? "Done" : "Working on it…"
        }
    }
}

nonisolated enum ChatFailure: Equatable, Sendable {
    /// rate_limited: another message is still running.
    case busy
    /// The backend apologized (llm_unavailable or internal).
    case unavailable
    /// The connection dropped or closed before `done`.
    case dropped

    var line: String {
        switch self {
        case .busy: "One message at a time, please."
        case .unavailable: "Sorry, I lost my train of thought there. Try me again in a moment."
        case .dropped: "I lost my train of thought. Try again?"
        }
    }
}

nonisolated struct ChatCardItem: Identifiable, Equatable, Sendable {
    let id = UUID()
    var card: ChatCard
    /// For meal_saved while acting as a participant: whose day the entry is simulated on (D-59).
    var simulatedOn: String?
}

nonisolated struct ChatTurn: Identifiable, Equatable, Sendable {
    let id = UUID()
    let role: ChatRole
    /// Everything received so far. Gummi's text types out up to `revealed` characters.
    var text: String
    var revealed: Int
    var tools: [ToolChip] = []
    var cards: [ChatCardItem] = []
    var failure: ChatFailure?
    /// The stream for this turn has ended.
    var finished: Bool
    /// The question this reply answers, for Retry.
    var prompt: String?

    var isTyping: Bool { revealed < text.count }
}

/// One chat conversation per app session (POST /chat, CONTRACT section 6). Gummi's reply types out on the phone
/// like a game dialogue box: the backend sends the checked text in quick 24-character chunks after its tools run.
@Observable
final class ChatModel {
    nonisolated static let maxLength = 2000

    private(set) var turns: [ChatTurn] = []
    private(set) var conversationId: String?
    /// True while a turn streams. Send waits for it, so the backend never sees two at once.
    private(set) var isBusy = false
    /// The mood the last reply ended on, shown by Home's Gummi only while the sheet is open.
    private(set) var mood: Mood?
    private(set) var savingMealIds: Set<String> = []

    @ObservationIgnored var service: (any ChatService)?
    /// Whose day a chat meal is simulated on, when acting as a participant.
    @ObservationIgnored var actingAsName: () -> String? = { nil }
    @ObservationIgnored var charactersPerSecond: Double = 45
    @ObservationIgnored private(set) var streamTask: Task<Void, Never>?
    @ObservationIgnored private var typewriter: Task<Void, Never>?

    /// Gummi thinks from send until his reply starts, and while any tool runs.
    var isThinking: Bool {
        guard isBusy, let last = turns.last, last.role == .gummi else { return false }
        return last.text.isEmpty || last.tools.contains { !$0.finished }
    }

    /// Gummi talks while his text types out.
    var isTalking: Bool { turns.contains { $0.role == .gummi && $0.isTyping } }

    // MARK: Actions

    /// Sends a message. Returns false when it's empty, a turn is still running, or there's no backend.
    @discardableResult
    func send(_ raw: String) -> Bool {
        let text = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxLength))
        guard !text.isEmpty, !isBusy, let service else { return false }
        withAnimation(.snappy) {
            turns.append(ChatTurn(role: .user, text: text, revealed: text.count, finished: true))
        }
        run(text, using: service)
        return true
    }

    /// Asks the same question again in place of a failed reply.
    func retry(_ turnId: UUID) {
        guard !isBusy, let service, let index = turns.firstIndex(where: { $0.id == turnId }),
              let prompt = turns[index].prompt else { return }
        withAnimation(.snappy) { _ = turns.remove(at: index) }
        run(prompt, using: service)
    }

    /// Shows every reply in full, like tapping through a game's dialogue.
    func skipTyping() {
        for index in turns.indices where turns[index].isTyping {
            turns[index].revealed = turns[index].text.count
        }
    }

    func newChat() {
        streamTask?.cancel()
        streamTask = nil
        typewriter?.cancel()
        typewriter = nil
        isBusy = false
        conversationId = nil
        mood = nil
        withAnimation(.snappy) { turns = [] }
    }

    /// The sheet closed: Home's Gummi goes back to the live mood.
    func closed() {
        mood = nil
        skipTyping()
    }

    /// PATCH /meals with edited portions. Every meal_saved card for that meal shows the saved result.
    func savePortions(mealId: String, items: [MealItem]) async -> Bool {
        guard let service, !savingMealIds.contains(mealId) else { return false }
        savingMealIds.insert(mealId)
        defer { savingMealIds.remove(mealId) }
        do {
            let meal = try await service.updateMeal(id: mealId, items: items)
            withAnimation(.snappy) {
                for t in turns.indices {
                    for c in turns[t].cards.indices {
                        if case .mealSaved(let old) = turns[t].cards[c].card, old.mealId == mealId {
                            turns[t].cards[c].card = .mealSaved(meal)
                        }
                    }
                }
            }
            return true
        } catch {
            return false
        }
    }

    // MARK: Streaming

    private func run(_ prompt: String, using service: any ChatService) {
        let reply = ChatTurn(role: .gummi, text: "", revealed: 0, finished: false, prompt: prompt)
        withAnimation(.snappy) { turns.append(reply) }
        isBusy = true
        let conversation = conversationId
        streamTask = Task { [weak self] in
            var ended = false
            do {
                for try await event in service.chat(prompt, conversationId: conversation) {
                    guard let self, !Task.isCancelled else { return }
                    if self.apply(event, to: reply.id) { ended = true }
                }
            } catch {}
            guard !Task.isCancelled else { return }
            self?.finish(reply.id, ended: ended)
        }
    }

    /// Applies one event to the reply. Returns true for the events that end a turn (done, error).
    private func apply(_ event: ChatEvent, to turnId: UUID) -> Bool {
        guard let index = turns.firstIndex(where: { $0.id == turnId }) else { return false }
        switch event {
        case .token(let text):
            turns[index].text += text
            startTypewriter()
        case .tool(let name, let status):
            if status == .start {
                withAnimation(.snappy) { turns[index].tools.append(ToolChip(id: turns[index].tools.count, name: name)) }
            } else if let chip = turns[index].tools.lastIndex(where: { $0.name == name && !$0.finished }) {
                withAnimation(.snappy) { turns[index].tools[chip].finished = true }
            }
        case .card(let card):
            var simulatedOn: String?
            if case .mealSaved = card { simulatedOn = actingAsName() }
            withAnimation(.bouncy) { turns[index].cards.append(ChatCardItem(card: card, simulatedOn: simulatedOn)) }
        case .mood(let newMood):
            // Thinking comes from the turn itself; the final mood shows on Home's Gummi while chat is open.
            if newMood.isKnown, newMood != .thinking { mood = newMood }
        case .done(let id, _):
            conversationId = id
            return true
        case .error(let code, _):
            turns[index].failure = code == "rate_limited" ? .busy : .unavailable
            return true
        case .unknown:
            break
        }
        return false
    }

    private func finish(_ turnId: UUID, ended: Bool) {
        isBusy = false
        streamTask = nil
        guard let index = turns.firstIndex(where: { $0.id == turnId }) else { return }
        turns[index].finished = true
        for chip in turns[index].tools.indices { turns[index].tools[chip].finished = true }
        if !ended, turns[index].failure == nil { turns[index].failure = .dropped }
        // A failure with nothing said yet is said in Gummi's voice.
        if let failure = turns[index].failure, turns[index].text.isEmpty {
            turns[index].text = failure.line
            startTypewriter()
        }
    }

    /// Reveals text a character or a few at a time, faster when a lot is waiting.
    private func startTypewriter() {
        guard typewriter == nil else { return }
        typewriter = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let index = self.turns.firstIndex(where: \.isTyping) else { break }
                let backlog = self.turns[index].text.count - self.turns[index].revealed
                self.turns[index].revealed += min(backlog, backlog > 160 ? 3 : backlog > 80 ? 2 : 1)
                let interval = 1 / max(self.charactersPerSecond, 1)
                do { try await Task.sleep(for: .seconds(interval)) } catch { break }
            }
            self?.typewriter = nil
        }
    }
}
