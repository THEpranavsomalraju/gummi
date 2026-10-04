import Foundation
import Testing
@testable import Gummi

@Suite("Contract 1.6 and error states")
struct LiveAppTests {
    private func json(_ name: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Fixtures.data(name)) as? [String: Any])
    }

    private func data(_ object: Any) throws -> Data { try JSONSerialization.data(withJSONObject: object) }

    @Test func staleStateDecodes() throws {
        var state = try json("state_full")
        state["data_status"] = "stale"
        state["minutes_since_reading"] = 3892
        state["gummi_view"] = NSNull()
        let decoded = try JSONCoding.decoder().decode(GummiState.self, from: data(state))
        #expect(GlucoseChart.staleText(200) == "The last one was 3 h ago, so Gummi isn't estimating. Resume the replay to continue.")
        #expect(decoded.dataStatus == .stale && decoded.minutesSinceReading == 3892 && decoded.gummiView == nil)
        // A pre-1.6 State still decodes.
        #expect(try Fixtures.decode(GummiState.self, "state_full").dataStatus == nil)
        #expect(GlucoseChart.staleText(3892) == "The last one was 2 days ago, so Gummi isn't estimating. Resume the replay to continue.")
    }

    @Test func toolLabelsAndMealSavedExtrasDecode() throws {
        let tool = try ChatEvent.decode(event: "tool", data: Data(#"{"name":"log_meal","status":"start","label":"Adding it to your food log…"}"#.utf8))
        #expect(tool == .tool(name: "log_meal", status: .start, label: "Adding it to your food log…"))
        var meal = try json("meal")
        meal["simulated"] = true
        meal["likely_peak_mg_dl"] = 158.0
        meal["peak_at"] = "2026-10-04T13:40:00-04:00"
        let event = try ChatEvent.decode(event: "card", data: data(["card_type": "meal_saved", "payload": meal]))
        guard case .card(.mealSaved(let saved)) = event else { throw CocoaError(.coderInvalidValue) }
        #expect(saved.simulated == true && saved.likelyPeakMgDl == 158 && saved.peakAt != nil && saved.meal.mealId == "m_1")
        let plain = try JSONCoding.decoder().decode(SavedMeal.self, from: Fixtures.data("meal"))
        #expect(plain.simulated == nil)
        #expect(ToolChip(id: 0, name: "log_meal", serverLabel: "Adding it to your food log…").label == "Adding it to your food log…")
        #expect(ToolChip(id: 0, name: "log_meal").label == "Logging your meal…")
    }

    @Test func unreliableSimulationsQuoteNoPeak() throws {
        var simulation = try json("simulation")
        simulation["reliable"] = false
        simulation["requested_carbs_g"] = 1100.0
        let decoded = try JSONCoding.decoder().decode(Simulation.self, from: data(simulation))
        #expect(!decoded.isReliable && decoded.requestedCarbsG == 1100)
        #expect(try Fixtures.decode(Simulation.self, "simulation").isReliable)
    }

    @Test func databricksHtml503BecomesServerAsleep() {
        let html = Data("<!DOCTYPE html><html><head><title>Databricks App Not Available</title>".utf8)
        let error = APIError.from(status: 503, body: html)
        #expect(error.code == "app_unavailable")
        #expect(!error.description.contains("<"))
        #expect(!APIError.from(status: 502, body: html).description.contains("<"))
    }

    @Test func connectionNoticeText() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(ConnectionNotice.from(.live, problem: nil, lastUpdated: now, now: now) == nil)
        #expect(ConnectionNotice.from(.reconnecting(attempt: 1), problem: nil, lastUpdated: now, now: now)?.text == "Reconnecting…")
        #expect(ConnectionNotice.from(.polling, problem: nil, lastUpdated: now.addingTimeInterval(-120), now: now)?.text
                == "Offline · updated 2 min ago")
        let asleep = ConnectionNotice.from(.reconnecting(attempt: 3), problem: .http(status: 503, code: "app_unavailable", message: ""),
                                           lastUpdated: nil, now: now)
        #expect(asleep == ConnectionNotice(kind: .asleep, text: "Server asleep"))
        // Once live again, the old problem no longer shows.
        #expect(ConnectionNotice.from(.live, problem: .http(status: 503, code: "app_unavailable", message: ""), lastUpdated: now, now: now) == nil)
    }

    @Test func emptyTurnSaysSo() async {
        let chat = ChatModel()
        chat.service = ChatModelTests.ScriptedChat([([.mood(.thinking), .mood(.calm), .done(conversationId: "c", traceId: nil)], false)])
        chat.send("hi")
        let task = chat.streamTask
        await task?.value
        #expect(chat.turns.last?.failure == .empty)
        #expect(chat.turns.last?.text == ChatFailure.empty.line)
    }

    @Test func demoControlsCallTheMockAndRefreshState() async throws {
        let name = "gummi.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.set(AppMode.mock.rawValue, forKey: AppModel.modeKey)
        let model = AppModel(defaults: defaults)
        model.start()
        for _ in 0..<100 where model.state == nil { try await Task.sleep(for: .milliseconds(20)) }
        await model.setPaused(true)
        #expect(model.state?.stream.paused == true)
        await model.setStreamSpeed(10)
        #expect(model.state?.stream.speed == 10)
        await model.setPaused(false)
        #expect(model.state?.stream.paused == false && model.streamAction == nil && model.streamError == nil)
        model.stop()
    }
}

@Suite("Chat word fade and chips")
struct ChatFadeTests {
    @Test func revealsGoWordByWord() {
        let text = "Go for it! You'd likely peak near 128."
        #expect(ChatModel.wordEnd(in: text, from: 0, words: 1) == 3)
        #expect(ChatModel.wordEnd(in: text, from: 3, words: 2) == 11)
        #expect(ChatModel.wordEnd(in: text, from: 30, words: 5) == text.count)
    }

    @Test func newWordsFadeInAndTheRestStaysClear() {
        let now = Date(timeIntervalSince1970: 1_000)
        let text = "Go for it!"
        let reveals = [Reveal(end: 3, at: now.addingTimeInterval(-1)), Reveal(end: 7, at: now.addingTimeInterval(-DialogueBox.fade / 2))]
        let runs = Array(DialogueBox.attributed(text, revealed: 7, reveals: reveals, now: now).runs)
        #expect(runs.count == 3)
        #expect(runs[0].foregroundColor == nil)       // settled: solid
        #expect(runs[1].foregroundColor != nil)       // "for " half faded in
        #expect(runs[2].foregroundColor == .clear)    // "it!" not yet revealed, but laid out
        let settled = DialogueBox.attributed(text, revealed: text.count, reveals: reveals, now: now.addingTimeInterval(5))
        #expect(String(settled.characters) == text)
    }

    @Test func doneLabelsLoseTheirTextCheckmark() {
        #expect(ToolChip(id: 0, name: "get_state", finished: true, serverLabel: "Crunched the numbers ✓").label == "Crunched the numbers")
    }
}

@Suite("Chat gap check (1.6)")
struct ChatGapTests {
    @Test func selfCheckCaptureDecodesAndSkipsTheHeartbeat() throws {
        var parser = SSEParser()
        let text = String(decoding: try Fixtures.data("chat_self_check", ext: "txt"), as: UTF8.self)
        let events = try parser.push(Array(text.utf8)).map { try ChatEvent.decode(event: $0.event, data: Data($0.data.utf8)) }
        #expect(events.count == 9)
        #expect(events.contains(.tool(name: "self_check", status: .start, label: "Double-checking myself…")))
        #expect(events.last == .done(conversationId: "conv_9", traceId: "tr-9"))
    }

    @Test func labelsFallBack() {
        #expect(ToolChip(id: 0, name: "self_check").label == "Double-checking myself…")
        #expect(ToolChip(id: 0, name: "self_check", finished: true, serverLabel: "Checked ✓").label == "Checked")
        #expect(ToolChip(id: 0, name: "brand_new_tool").label == "Thinking…")
        #expect(ToolChip(id: 0, name: "brand_new_tool", finished: true).label == "Done")
    }

    @Test func spikeQuestionsGoToExplainSpike() {
        #expect(MockChat.route("Why did I spike?") == .spike)
        #expect(ChatSheet.prompts.count == 4)
    }
}
