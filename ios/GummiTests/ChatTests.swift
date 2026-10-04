import Foundation
import Testing
@testable import Gummi

/// Parses a captured SSE body into chat events.
nonisolated private func chatEvents(_ text: String) throws -> [ChatEvent] {
    var parser = SSEParser()
    return try parser.push(Array(text.utf8)).map { try ChatEvent.decode(event: $0.event, data: Data($0.data.utf8)) }
}

nonisolated private func cardEvent(_ type: String, payload: String) throws -> ChatEvent {
    try ChatEvent.decode(event: "card", data: Data(#"{"card_type":"\#(type)","payload":\#(payload)}"#.utf8))
}

@Suite("Chat decoding")
struct ChatDecodingTests {
    @Test func realChatCaptureDecodesInBackendOrder() throws {
        let text = String(decoding: try Fixtures.data("chat_sse_capture", ext: "txt"), as: UTF8.self)
        let events = try chatEvents(text)
        #expect(events.first == .mood(.thinking))
        #expect(events[1] == .tool(name: "get_state", status: .start))
        #expect(events[2] == .tool(name: "get_state", status: .end))
        guard case .card(.gummiView(let view)) = events[3] else {
            Issue.record("expected a gummi_view card, got \(events[3])")
            return
        }
        #expect(view.glucoseMgDl == 121.2)
        let reply = events.compactMap { if case .token(let piece) = $0 { piece } else { nil } }.joined()
        #expect(reply.hasPrefix("Your current estimate is about 121"))
        #expect(events.suffix(2).first == .mood(.calm))
        #expect(events.last == .done(conversationId: "conv_4787", traceId: "tr-f5d662dc2fb939507a6ed2a386eb7c92"))
    }

    @Test func everyCardTypeDecodes() throws {
        let meal = String(decoding: try Fixtures.data("meal"), as: UTF8.self)
        let simulation = String(decoding: try Fixtures.data("simulation"), as: UTF8.self)
        let grade = String(decoding: try Fixtures.data("grade_walk_not_graded"), as: UTF8.self)
        let due = String(decoding: try Fixtures.data("card_meal_due"), as: UTF8.self)
        guard case .card(.mealSaved(let saved)) = try cardEvent("meal_saved", payload: meal) else { throw CocoaError(.coderInvalidValue) }
        #expect(saved.meal.mealId == "m_1")
        guard case .card(.simulation(let sim)) = try cardEvent("simulation", payload: simulation) else { throw CocoaError(.coderInvalidValue) }
        #expect(sim.items.first?.name == "cookie")
        guard case .card(.grade(let graded)) = try cardEvent("grade", payload: grade) else { throw CocoaError(.coderInvalidValue) }
        #expect(!graded.walkEffectGraded)
        guard case .card(.mealDue(let card)) = try cardEvent("meal_due", payload: due) else { throw CocoaError(.coderInvalidValue) }
        #expect(card.pendingDueId != nil)
    }

    @Test func walkSuggestionToleratesNulls() throws {
        let full = try cardEvent("walk_suggestion", payload: #"{"minutes":10,"start":"2026-10-06T14:00:00-04:00","forecast_peak_mg_dl":156.2,"forecast_peak_drop_mg_dl":14.0,"effect_source":"literature"}"#)
        #expect(full == .card(.walkSuggestion(WalkSuggestion(minutes: 10, start: JSONCoding.parseDate("2026-10-06T14:00:00-04:00"),
                                                             forecastPeakMgDl: 156.2, forecastPeakDropMgDl: 14, effectSource: .literature))))
        let sparse = try cardEvent("walk_suggestion", payload: #"{"minutes":10,"start":"2026-10-06T14:00:00-04:00","forecast_peak_mg_dl":null,"forecast_peak_drop_mg_dl":null,"effect_source":null}"#)
        guard case .card(.walkSuggestion(let walk)) = sparse else { throw CocoaError(.coderInvalidValue) }
        #expect(walk.forecastPeakMgDl == nil && walk.effectSource == nil)
    }

    @Test func unknownEventsAndCardTypesAreSkipped() throws {
        #expect(try cardEvent("recipe", payload: "{}") == .unknown(name: "card"))
        #expect(try ChatEvent.decode(event: "sparkle", data: Data("{}".utf8)) == .unknown(name: "sparkle"))
        #expect(try ChatEvent.decode(event: "tool", data: Data(#"{"name":"ask_data","status":"paused"}"#.utf8))
                == .tool(name: "ask_data", status: .unknown))
        #expect(try ChatEvent.decode(event: "error", data: Data(#"{"code":"rate_limited","message":"One message at a time, please."}"#.utf8))
                == .error(code: "rate_limited", message: "One message at a time, please."))
    }

    @Test func portionsScaleEveryMacro() {
        let cookie = MockChat.seeds[0].item(quantity: 1)
        let two = cookie.scaled(toQuantity: 2)
        #expect(two.quantity == 2 && two.carbsG == 44 && two.calories == 320 && two.fatG == 14)
        #expect(cookie.scaled(toQuantity: 1) == cookie)
        #expect(MealTotals(items: [cookie, two]).carbsG == 66)
    }
}

@Suite("Chat client")
struct ChatClientTests {
    private let capture = (try? Fixtures.data("chat_sse_capture", ext: "txt")) ?? Data()

    private func collect(_ stream: AsyncThrowingStream<ChatEvent, Error>) async throws -> [ChatEvent] {
        var events: [ChatEvent] = []
        for try await event in stream { events.append(event) }
        return events
    }

    @Test func streamsEventsAndSendsNullConversationId() async throws {
        let body = capture
        let session = StubURLProtocol.session { request in
            if request.url?.path == "/oidc/v1/token" { return (200, TestConfig.token("t")) }
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/api/v1/chat")
            #expect(request.value(forHTTPHeaderField: "Accept") == "text/event-stream")
            let json = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any]
            #expect(json?["message"] as? String == "How am I doing today?")
            #expect(json?["conversation_id"] is NSNull)
            return (200, body)
        }
        let events = try await collect(APIClient(config: TestConfig.config, session: session)
            .chat(message: "How am I doing today?", conversationId: nil))
        #expect(events.count == 15)
        #expect(events.last == .done(conversationId: "conv_4787", traceId: "tr-f5d662dc2fb939507a6ed2a386eb7c92"))
    }

    @Test func refreshesTheTokenOnceAfterA401() async throws {
        let counter = APIClientTests.Counter()
        let body = capture
        let session = StubURLProtocol.session { request in
            if request.url?.path == "/oidc/v1/token" { return (200, TestConfig.token("t\(counter.bump("token"))")) }
            return request.value(forHTTPHeaderField: "Authorization") == "Bearer t1" ? (401, Data()) : (200, body)
        }
        let events = try await collect(APIClient(config: TestConfig.config, session: session).chat(message: "hi", conversationId: "conv_1"))
        #expect(events.count == 15)
        #expect(counter.count("token") == 2)
    }

    @Test func validationErrorsThrowTheContractError() async throws {
        let session = StubURLProtocol.session { request in
            if request.url?.path == "/oidc/v1/token" { return (200, TestConfig.token("t")) }
            return (422, Data(#"{"error":{"code":"invalid","message":"message is too long"}}"#.utf8))
        }
        await #expect(throws: APIError.http(status: 422, code: "invalid", message: "message is too long")) {
            try await collect(APIClient(config: TestConfig.config, session: session).chat(message: "hi", conversationId: nil))
        }
    }
}

@Suite("Chat model")
struct ChatModelTests {
    /// Plays a fixed list of events per turn, optionally failing afterwards, and records what was sent.
    nonisolated final class ScriptedChat: ChatService, @unchecked Sendable {
        private let lock = NSLock()
        private var scripts: [(events: [ChatEvent], fails: Bool)]
        private var _sent: [(message: String, conversationId: String?)] = []
        private var held: AsyncThrowingStream<ChatEvent, Error>.Continuation?

        init(_ scripts: [(events: [ChatEvent], fails: Bool)]) { self.scripts = scripts }

        var sent: [(message: String, conversationId: String?)] { lock.withLock { _sent } }
        /// The continuation of a turn scripted with no events and no failure: the test drives it by hand.
        var continuation: AsyncThrowingStream<ChatEvent, Error>.Continuation? { lock.withLock { held } }

        func chat(_ message: String, conversationId: String?) -> AsyncThrowingStream<ChatEvent, Error> {
            let script = lock.withLock {
                _sent.append((message, conversationId))
                return scripts.isEmpty ? (events: [], fails: false) : scripts.removeFirst()
            }
            return AsyncThrowingStream { continuation in
                if script.events.isEmpty, !script.fails {
                    lock.withLock { held = continuation }
                    return
                }
                script.events.forEach { continuation.yield($0) }
                continuation.finish(throwing: script.fails ? APIError.transport("connection lost") : nil)
            }
        }

        func updateMeal(id: String, items: [MealItem]) async throws -> SavedMeal {
            SavedMeal(Meal(mealId: id, eatenAt: .now, source: .chat, items: items, totals: MealTotals(items: items),
                           isStandardBreakfast: false, predictionId: nil))
        }
    }

    private let view = try? Fixtures.decode(GummiState.self, "state_full").gummiView
    private let meal = try? Fixtures.decode(Meal.self, "meal")

    private func model(_ service: ScriptedChat) -> ChatModel {
        let chat = ChatModel()
        chat.service = service
        return chat
    }

    private func finish(_ chat: ChatModel) async {
        let task = chat.streamTask
        await task?.value
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(5)) }
    }

    @Test func aTurnCollectsToolsCardsTextMoodAndConversation() async throws {
        let view = try #require(view)
        let service = ScriptedChat([([.mood(.thinking), .tool(name: "get_state", status: .start), .tool(name: "get_state", status: .end),
                                      .card(.gummiView(view)), .token("Hello "), .token("there."), .mood(.rising),
                                      .done(conversationId: "conv_1", traceId: "tr_1")], false),
                                    ([.token("Again."), .done(conversationId: "conv_1", traceId: nil)], false)])
        let chat = model(service)
        #expect(chat.send("  How am I doing?  "))
        await finish(chat)
        #expect(chat.turns.map(\.role) == [.user, .gummi])
        #expect(chat.turns[0].text == "How am I doing?")
        let reply = chat.turns[1]
        #expect(reply.text == "Hello there.")
        #expect(reply.tools == [ToolChip(id: 0, name: "get_state", finished: true)])
        #expect(reply.cards.map(\.card) == [.gummiView(view)])
        #expect(reply.failure == nil && reply.finished)
        #expect(chat.conversationId == "conv_1")
        #expect(chat.mood == .rising)
        #expect(!chat.isBusy && !chat.isThinking)
        chat.skipTyping()
        #expect(!chat.isTalking)

        #expect(chat.send("again"))
        await finish(chat)
        #expect(service.sent.map(\.conversationId) == [nil, "conv_1"])
        chat.closed()
        #expect(chat.mood == nil)
    }

    @Test func thinksUntilTheReplyStartsThenTalksWhileItTypes() async throws {
        let service = ScriptedChat([])
        let chat = model(service)
        chat.charactersPerSecond = 400
        #expect(chat.send("Can I eat a cookie now?"))
        #expect(chat.isThinking)
        #expect(!chat.send("and another?"))
        await waitUntil { service.continuation != nil }
        let stream = try #require(service.continuation)
        stream.yield(.tool(name: "simulate_food", status: .start))
        await waitUntil { chat.turns.last?.tools.isEmpty == false }
        #expect(chat.isThinking)
        stream.yield(.tool(name: "simulate_food", status: .end))
        stream.yield(.token("Go for it!"))
        await waitUntil { chat.turns.last?.text.isEmpty == false }
        #expect(!chat.isThinking)
        #expect(chat.isTalking)
        stream.yield(.done(conversationId: "conv_2", traceId: nil))
        stream.finish()
        await finish(chat)
        await waitUntil { !chat.isTalking }
        #expect(chat.turns.last?.revealed == "Go for it!".count)
    }

    @Test func rateLimitedSaysOneAtATime() async {
        let chat = model(ScriptedChat([([.error(code: "rate_limited", message: "One message at a time, please.")], false)]))
        chat.send("hi")
        await finish(chat)
        #expect(chat.turns.last?.failure == .busy)
        #expect(chat.turns.last?.text == ChatFailure.busy.line)
    }

    @Test func backendApologyKeepsItsOwnWords() async throws {
        let view = try #require(view)
        let apology = "Sorry, I lost my train of thought there. Try me again in a moment."
        let chat = model(ScriptedChat([([.mood(.thinking), .token(apology), .card(.gummiView(view)),
                                         .error(code: "llm_unavailable", message: "The coach is unavailable right now."),
                                         .done(conversationId: "conv_3", traceId: nil)], false)]))
        chat.send("hi")
        await finish(chat)
        #expect(chat.turns.last?.failure == .unavailable)
        #expect(chat.turns.last?.text == apology)
        #expect(chat.turns.last?.cards.count == 1)
    }

    @Test func aDroppedStreamOffersRetryThatAsksAgain() async throws {
        let service = ScriptedChat([([.mood(.thinking), .tool(name: "log_meal", status: .start)], true),
                                    ([.token("Logged."), .done(conversationId: "conv_4", traceId: nil)], false)])
        let chat = model(service)
        chat.send("I just had a granola bar")
        await finish(chat)
        let failed = try #require(chat.turns.last)
        #expect(failed.failure == .dropped)
        #expect(failed.text == ChatFailure.dropped.line)
        #expect(failed.tools.allSatisfy { $0.finished })
        chat.retry(failed.id)
        await finish(chat)
        #expect(chat.turns.count == 2)
        #expect(chat.turns.last?.text == "Logged.")
        #expect(chat.turns.last?.failure == nil)
        #expect(service.sent.map(\.message) == ["I just had a granola bar", "I just had a granola bar"])
    }

    @Test func mealSavedIsTaggedWhileActingAsAndSavesEditedPortions() async throws {
        let meal = try #require(meal)
        let chat = model(ScriptedChat([([.card(.mealSaved(SavedMeal(meal))), .token("Saved."), .done(conversationId: "c", traceId: nil)], false)]))
        chat.actingAsName = { "Participant 12" }
        chat.send("I just had cereal")
        await finish(chat)
        #expect(chat.turns.last?.cards.first?.simulatedOn == "Participant 12")

        let doubled = meal.items.map { $0.scaled(toQuantity: $0.quantity * 2) }
        #expect(await chat.savePortions(mealId: meal.mealId, items: doubled))
        guard case .mealSaved(let saved) = chat.turns.last?.cards.first?.card else {
            Issue.record("expected the meal_saved card")
            return
        }
        #expect(saved.meal.totals.carbsG == (meal.totals.carbsG * 2).rounded(toPlaces: 1))
        #expect(chat.savingMealIds.isEmpty)
    }

    @Test func newChatClearsEverythingAndEmptyMessagesAreIgnored() async {
        let chat = model(ScriptedChat([([.token("Hi"), .done(conversationId: "conv_5", traceId: nil)], false)]))
        #expect(!chat.send("   "))
        chat.send("hello")
        await finish(chat)
        chat.newChat()
        #expect(chat.turns.isEmpty && chat.conversationId == nil && !chat.isBusy)
    }
}

@Suite("Mock chat")
struct MockChatTests {
    private func state(minute: Double = 760, following: Bool = true) throws -> GummiState {
        var session = MockSession(day: try MockDay.load())
        session.following = following ? MockSession.participant : nil
        _ = session.advance(to: minute, wallNow: .now)
        return session.snapshot(wallNow: .now, paused: false, minutesPerSecond: 6)
    }

    private func events(_ reply: MockChat.Reply) -> [ChatEvent] { reply.steps.map(\.event) }

    @Test func routesByKeyword() {
        #expect(MockChat.route("Can I eat a cookie now?") == .simulate)
        #expect(MockChat.route("pizza?") == .simulate)
        #expect(MockChat.route("I just had a granola bar") == .logMeal)
        #expect(MockChat.route("Should I take a walk?") == .walk)
        #expect(MockChat.route("How am I doing today?") == .today)
        #expect(MockChat.route("How did you do on lunch?") == .grade)
        #expect(MockChat.route("hello") == .state)
        #expect(MockChat.route("mock busy") == .busy)
    }

    @Test func simulateFollowsTheBackendOrder() throws {
        let reply = MockChat.reply(to: "Can I eat a cookie now?", state: try state(), latestGrade: nil, turn: 1, conversationId: "conv_m")
        let events = events(reply)
        #expect(events.first == .mood(.thinking))
        #expect(events[1] == .tool(name: "simulate_food", status: .start, label: "Simulating that food…"))
        #expect(events[2] == .tool(name: "simulate_food", status: .end, label: "Simulating that food…"))
        guard case .card(.simulation(let simulation)) = events[3] else {
            Issue.record("expected a simulation card")
            return
        }
        let tokens = events.compactMap { if case .token(let piece) = $0 { piece } else { nil } }
        #expect(tokens.allSatisfy { $0.count <= 24 })
        #expect(tokens.joined().contains("\(Int(simulation.peakMgDl.rounded()))"))
        #expect(simulation.withFoodCurve.count == simulation.baselineCurve.count)
        #expect(simulation.peakMgDl > simulation.baselineCurve.map(\.glucoseMgDl).max()!)
        guard case .mood = events[events.count - 2] else {
            Issue.record("expected the final mood before done")
            return
        }
        #expect(events.last == .done(conversationId: "conv_m", traceId: "tr_mock_chat_1"))
    }

    @Test func logMealWhileActingAsIsSimulatedAndUngraded() throws {
        let reply = MockChat.reply(to: "I just had two cookies", state: try state(), latestGrade: nil, turn: 2, conversationId: "c")
        let saved = try #require(reply.savedMeal)
        let meal = saved.meal
        #expect(saved.simulated == true && saved.likelyPeakMgDl != nil)
        #expect(meal.items.first?.quantity == 2 && meal.totals.carbsG == 44)
        #expect(reply.likelyPeak != nil)
        let text = events(reply).compactMap { if case .token(let piece) = $0 { piece } else { nil } }.joined()
        #expect(text.contains("simulated on Participant 12's day, so I won't grade it"))
        #expect(events(reply).contains(.card(.mealSaved(saved))))
    }

    @Test func notFollowingAnyoneExplainsInsteadOfSimulating() throws {
        let reply = MockChat.reply(to: "Can I eat a cookie now?", state: try state(following: false), latestGrade: nil, turn: 3, conversationId: "c")
        #expect(!events(reply).contains { if case .card = $0 { true } else { false } })
        #expect(events(reply).last == .done(conversationId: "c", traceId: "tr_mock_chat_3"))
    }

    @Test func failureAndBusyPathsMatchTheBackend() throws {
        let busy = events(MockChat.reply(to: "mock busy", state: try state(), latestGrade: nil, turn: 4, conversationId: "c"))
        #expect(busy == [.error(code: "rate_limited", message: "One message at a time, please.")])
        let failure = events(MockChat.reply(to: "mock error", state: try state(), latestGrade: nil, turn: 5, conversationId: "c"))
        #expect(failure.suffix(2) == [.error(code: "internal", message: "The coach is unavailable right now."),
                                      .done(conversationId: "c", traceId: nil)])
    }

    @Test func mockServiceSavesEditedPortions() async throws {
        let service = MockGummiService(day: try MockDay.load())
        var saved: Meal?
        for try await event in service.chat("I just had a granola bar", conversationId: nil) {
            if case .card(.mealSaved(let meal)) = event { saved = meal.meal }
        }
        let meal = try #require(saved)
        let half = meal.items.map { $0.scaled(toQuantity: 0.5) }
        let updated = try await service.updateMeal(id: meal.mealId, items: half)
        #expect(updated.meal.totals.carbsG == 14.5)
        await #expect(throws: APIError.self) { try await service.updateMeal(id: "m_missing", items: half) }
    }
}
