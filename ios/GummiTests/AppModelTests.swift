import Foundation
import Testing
@testable import Gummi

@Suite("App model")
struct AppModelTests {
    /// A scripted service: hands out fixture State, records follow calls, and streams whatever the test sends.
    nonisolated final class FakeService: GummiService, @unchecked Sendable {
        let mode: AppMode
        private let lock = NSLock()
        private var _followed: [String?] = []
        private var continuation: AsyncStream<ServiceEvent>.Continuation?
        let initial: GummiState

        init(mode: AppMode, initial: GummiState) {
            self.mode = mode
            self.initial = initial
        }

        var followed: [String?] { lock.withLock { _followed } }
        func send(_ event: ServiceEvent) { lock.withLock { continuation }?.yield(event) }

        func health() async throws -> Health { Health(status: "ok", mode: .mock, version: "fake") }
        func snapshot() async throws -> GummiState { initial }
        func feed() async throws -> [StoryCard] { [try Fixtures.decode(StoryCard.self, "card_morning_briefing")] }
        func follow(_ userId: String?) async throws -> GummiState {
            lock.withLock { _followed.append(userId) }
            return try Fixtures.decode(GummiState.self, "state_full")
        }
        func logDueMeal(dueId: String) async throws -> Meal { try Fixtures.decode(Meal.self, "meal") }
        func startStream() async throws -> StreamStatus { initial.stream }
        func stopStream() async throws -> StreamStatus { initial.stream }
        func pauseStream() async throws -> StreamStatus { initial.stream }
        func resumeStream() async throws -> StreamStatus { initial.stream }
        func setStreamSpeed(_ speed: Double) async throws -> StreamStatus { initial.stream }
        func events() -> AsyncStream<ServiceEvent> {
            AsyncStream { continuation in lock.withLock { self.continuation = continuation } }
        }
    }

    private func defaults() -> UserDefaults {
        let name = "gummi.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func card(_ name: String) throws -> StoryCard { try Fixtures.decode(StoryCard.self, name) }

    @Test func cardsUpsertByIdAndStayNewestFirst() throws {
        let model = AppModel(defaults: defaults(), makeService: { _ in throw APIError.notConfigured("unused") })
        model.apply(.card(try card("card_meal_due")))
        model.apply(.card(try card("card_morning_briefing")))
        model.apply(.card(try card("card_meal_logged")))
        #expect(model.cards.map(\.cardId) == ["c_brief_1", "c_logged_1", "c_due_1"])
        model.apply(.card(try card("card_meal_due_resolved")))
        #expect(model.cards.count == 3)
        #expect(model.cards.last?.pendingDueId == nil)
        #expect(model.cards.last?.body.hasSuffix("Logged.") == true)
    }

    @Test func unknownCardTypesAreSkipped() throws {
        let model = AppModel(defaults: defaults(), makeService: { _ in throw APIError.notConfigured("unused") })
        model.apply(.card(try card("card_unknown_type")))
        #expect(model.cards.isEmpty)
    }

    @Test func stateMoodGradeAndAlertApply() throws {
        let model = AppModel(defaults: defaults(), makeService: { _ in throw APIError.notConfigured("unused") })
        model.apply(.state(try Fixtures.decode(GummiState.self, "state_full")))
        #expect(model.mood == .high)
        #expect(model.alert?.alertId == "a_1")
        #expect(model.cards.first?.type == .walkSuggested)
        model.apply(.mood(.proud))
        #expect(model.mood == .proud)
        model.apply(.mood(.unknown))
        #expect(model.mood == .proud)
        let grade = try Fixtures.decode(Grade.self, "grade_null_cgm_only")
        model.apply(.grade(grade))
        #expect(model.latestGrade?.threeNumberBadge == "Gummi 9 · CGM-only n/a · last value 31")
        #expect(model.lastUpdated != nil)
    }

    @Test func liveModeAutoFollowsTheDemoParticipantOnce() async throws {
        let store = defaults()
        let fake = FakeService(mode: .live, initial: try Fixtures.decode(GummiState.self, "state_null"))
        store.set("live", forKey: AppModel.modeKey)
        let model = AppModel(defaults: store, makeService: { _ in fake })
        model.start()
        try await waitUntil { model.state?.actingAs == "p_012" }
        #expect(fake.followed == ["p_012"])
        #expect(store.bool(forKey: AppModel.didAutoFollowKey))
        #expect(model.cards.contains { $0.cardId == "c_brief_1" })

        fake.send(.connection(.live))
        fake.send(.live(.card(try card("card_meal_due"))))
        try await waitUntil { model.connection == .live && model.cards.contains { $0.cardId == "c_due_1" } }

        // Background closes the channel; a later launch never re-follows.
        model.scenePhaseChanged(.background)
        #expect(!model.isRunning)
        #expect(model.connection == .idle)
        let again = AppModel(defaults: store, makeService: { _ in fake })
        again.start()
        try await waitUntil { again.state != nil }
        #expect(fake.followed == ["p_012"])
        again.stop()
    }

    @Test func mockModeRunsTheScriptedDay() async throws {
        let store = defaults()
        store.set("mock", forKey: AppModel.modeKey)
        store.set(120.0, forKey: AppModel.mockSpeedKey)
        let model = AppModel(defaults: store)
        #expect(model.mode == .mock)
        model.start()
        try await waitUntil { model.state?.actingAs == "p_012" }
        let firstNow = try #require(model.state?.replayNow)
        // At 120 replay minutes per second, the breakfast meal_due card arrives within a second.
        try await waitUntil(timeout: 3) { model.cards.contains { $0.type == .mealDue } }
        let laterNow = try #require(model.state?.replayNow)
        #expect(laterNow > firstNow)
        model.stop()
    }

    private func waitUntil(timeout: Double = 2, _ condition: @escaping () -> Bool) async throws {
        let deadline = Date.now.addingTimeInterval(timeout)
        while !condition() {
            guard Date.now < deadline else {
                Issue.record("Timed out waiting for condition")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
