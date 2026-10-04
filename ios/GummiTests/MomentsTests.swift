import Foundation
import Testing
@testable import Gummi

@Suite("Notification planner")
struct NotificationPlannerTests {
    /// The mock day's State at a replay minute, following p_012 at the given speed (minutes per wall second).
    private func state(minute: Double, paused: Bool = false, following: Bool = true, minutesPerSecond: Double = 1,
                       wallNow: Date) throws -> GummiState {
        var session = MockSession(day: try MockDay.load())
        session.following = following ? MockSession.participant : nil
        _ = session.advance(to: minute, wallNow: wallNow)
        return session.snapshot(wallNow: wallNow, paused: paused, minutesPerSecond: minutesPerSecond)
    }

    @Test func replayTimesBecomeWallTimesThroughTheAnchorAndSpeed() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let state = try state(minute: 330, wallNow: now)   // 05:30, breakfast due at 05:54, speed 60
        let plan = NotificationPlanner.plan(state: state, displayName: "Participant 12", now: now)
        let due = try #require(plan.first { $0.id == "due_d_1" })
        #expect(abs(due.fireAt.timeIntervalSince(now) - 24) < 1.5)   // 24 replay minutes at 60x is 24 s
        #expect(due.title == "Breakfast time for Participant 12")
        let recap = try #require(plan.first { $0.id.hasPrefix("recap_") })
        #expect(abs(recap.fireAt.timeIntervalSince(now) - (20 * 60 - 330)) < 1.5)
        #expect(plan.map(\.fireAt) == plan.map(\.fireAt).sorted())
        #expect(plan.allSatisfy { $0.fireAt > now })
    }

    @Test func mockSpeedCompressesTheSchedule() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let state = try state(minute: 330, minutesPerSecond: 6, wallNow: now)   // 360x
        let plan = NotificationPlanner.plan(state: state, displayName: nil, now: now)
        let due = try #require(plan.first { $0.id == "due_d_1" })
        #expect(abs(due.fireAt.timeIntervalSince(now) - 4) < 1)
    }

    @Test func mealStoriesFireWhenDelayedDataCoversTheWindow() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let state = try state(minute: 380, wallNow: now)   // breakfast logged at 05:54, pending
        let prediction = try #require(state.pendingPredictions.first)
        let plan = NotificationPlanner.plan(state: state, displayName: nil, now: now)
        let story = try #require(plan.first { $0.id == "story_\(prediction.predictionId)" })
        let expected = state.stream.wallTime(forReplay: prediction.windowEnd.addingTimeInterval(3600))
        #expect(story.fireAt == expected)
    }

    @Test func nothingWhilePausedOrNotFollowing() throws {
        let now = Date.now
        #expect(NotificationPlanner.plan(state: try state(minute: 330, paused: true, wallNow: now), displayName: nil, now: now).isEmpty)
        #expect(NotificationPlanner.plan(state: try state(minute: 330, following: false, wallNow: now), displayName: nil, now: now).isEmpty)
    }
}

@Suite("Steps upload window")
struct StepsWindowTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_123)   // 2 min 3 s past a 5-minute boundary

    @Test func firstRunLooksBackTwoHoursToTheLastFullBucket() throws {
        let window = try #require(StepsUploader.window(cursor: nil, now: now))
        #expect(window.end.timeIntervalSince1970.truncatingRemainder(dividingBy: 300) == 0)
        #expect(window.end <= now && now.timeIntervalSince(window.end) < 300)
        #expect(window.duration == 2 * 3600)
    }

    @Test func continuesFromTheCursorAndNeverRepeats() throws {
        let first = try #require(StepsUploader.window(cursor: nil, now: now))
        #expect(StepsUploader.window(cursor: first.end, now: now) == nil)
        let later = try #require(StepsUploader.window(cursor: first.end, now: now.addingTimeInterval(600)))
        #expect(later.start == first.end)
        #expect(later.duration == 600)
    }
}

@Suite("Walk")
struct WalkTests {
    nonisolated final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _events: [WalkEventBody] = []
        var events: [WalkEventBody] { lock.withLock { _events } }
        func add(_ event: WalkEventBody) { lock.withLock { _events.append(event) } }
    }

    /// A pedometer that reports a fixed count once.
    nonisolated struct FixedSteps: StepSource {
        let reading: StepReading
        func readings(from start: Date) -> AsyncStream<StepReading> {
            AsyncStream { $0.yield(reading); $0.finish() }
        }
    }

    nonisolated final class WalkService: GummiService, @unchecked Sendable {
        let mode = AppMode.mock
        let recorder = Recorder()
        private let state: GummiState
        init(state: GummiState) { self.state = state }
        func health() async throws -> Health { Health(status: "ok", mode: .mock, version: "t") }
        func snapshot() async throws -> GummiState { state }
        func feed() async throws -> [StoryCard] { [] }
        func fleet() async throws -> Fleet { try Fixtures.decode(Fleet.self, "live_fleet") }
        func follow(_ userId: String?) async throws -> GummiState { state }
        func logDueMeal(dueId: String) async throws -> Meal { try Fixtures.decode(Meal.self, "meal") }
        func startStream() async throws -> StreamStatus { state.stream }
        func stopStream() async throws -> StreamStatus { state.stream }
        func pauseStream() async throws -> StreamStatus { state.stream }
        func resumeStream() async throws -> StreamStatus { state.stream }
        func setStreamSpeed(_ speed: Double) async throws -> StreamStatus { state.stream }
        func events() -> AsyncStream<ServiceEvent> { AsyncStream { $0.finish() } }
        func chat(_ message: String, conversationId: String?) -> AsyncThrowingStream<ChatEvent, Error> { AsyncThrowingStream { $0.finish() } }
        func updateMeal(id: String, items: [MealItem]) async throws -> Meal { try Fixtures.decode(Meal.self, "meal") }
        func sendWalkEvent(_ body: WalkEventBody) async throws { recorder.add(body) }
        func latestWalk() async throws -> WalkSummary { try Fixtures.decode(WalkSummary.self, "walk_summary") }
        func uploadSteps(_ samples: [StepSample]) async throws -> Int { samples.count }
    }

    nonisolated final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
    }

    private func service() throws -> WalkService { WalkService(state: try Fixtures.decode(GummiState.self, "state_full")) }

    @Test func aWalkSendsStartedThenCompletedWithAverageCadenceAndShowsTheSummary() async throws {
        let service = try service()
        let clock = Clock()
        let walk = WalkModel(minutes: 10, service: service, source: FixedSteps(reading: StepReading(steps: 1100, cadenceSpm: 112)),
                             clock: { clock.now })
        walk.start()
        for _ in 0..<50 where walk.steps == 0 { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(walk.steps == 1100 && walk.cadenceSpm == 112)
        clock.now = clock.now.addingTimeInterval(600)
        await walk.end()
        for _ in 0..<50 where service.recorder.events.count < 2 { try? await Task.sleep(for: .milliseconds(5)) }
        let events = service.recorder.events
        #expect(events.map(\.type).sorted() == ["walk_completed", "walk_started"])
        let completed = try #require(events.first { $0.type == "walk_completed" })
        #expect(completed.steps == 1100 && completed.cadenceSpm == 110)
        guard case .done(let summary) = walk.phase else {
            Issue.record("expected the summary, got \(walk.phase)")
            return
        }
        #expect(summary != nil)
    }

    @Test func underAMinuteIsDiscardedWithoutCompleting() async throws {
        let service = try service()
        let clock = Clock()
        let walk = WalkModel(minutes: 10, service: service, source: FixedSteps(reading: StepReading(steps: 40, cadenceSpm: 90)),
                             clock: { clock.now })
        walk.start()
        clock.now = clock.now.addingTimeInterval(45)
        await walk.end()
        #expect(walk.phase == .discarded)
        try? await Task.sleep(for: .milliseconds(30))
        #expect(!service.recorder.events.contains { $0.type == "walk_completed" })
    }

    @Test func mockWalkPostsTheSummaryCardAndHappy() async throws {
        let mock = MockGummiService(day: try MockDay.load())
        let start = Date.now.addingTimeInterval(-11 * 60)
        try await mock.sendWalkEvent(.completed(at: .now, startedAt: start, steps: 1210, cadenceSpm: 110))
        let walk = try await mock.latestWalk()
        #expect(walk.minutes == 11 && walk.intensity == .moderate && walk.effectSource == .literature)
        #expect(try await mock.snapshot().mood == .happy)
        #expect(try await mock.feed().contains { $0.type == .walkSummary && $0.cardId.hasPrefix("c_phone_walk") })
    }

    @Test func gummiWalksInPlaceWithAlternatingLegs() {
        var animator = PuppetAnimator(seed: 7)
        animator.input = PuppetInput(mood: .happy, walking: true, walkCadence: 120)
        var leftUp = false, rightUp = false
        for _ in 0..<240 {
            _ = animator.step(dt: 1.0 / 60)
            if animator.pose.leftLegLift > 0.008 { leftUp = true }
            if animator.pose.rightLegLift > 0.008 { rightUp = true }
        }
        #expect(leftUp && rightUp)
        #expect(animator.walkAmount > 0.9)
    }
}

@Suite("Grade moment")
struct GradeMomentTests {
    private func model() -> AppModel {
        let name = "gummi.tests.\(UUID().uuidString)"
        return AppModel(defaults: UserDefaults(suiteName: name)!, makeService: { _ in throw APIError.notConfigured("unused") })
    }

    @Test func aGradeThatLosesToCgmOnlyNods() throws {
        let model = model()
        model.apply(.state(try Fixtures.decode(GummiState.self, "state_full")))
        let grade = try Fixtures.decode(Grade.self, "grade_null_cgm_only")
        model.apply(.grade(grade))
        #expect(model.gradeMoment?.grade.gradeId == grade.gradeId)
        #expect(model.puppetCue?.reaction == .nod)
        model.dismissGradeMoment()
        #expect(model.gradeMoment == nil)
    }

    @Test func aWinningGradeCheersOnceAndRemembersThePrediction() throws {
        let model = model()
        let state = try Fixtures.decode(GummiState.self, "state_full")
        model.apply(.state(state))
        let prediction = try #require(state.pendingPredictions.first)
        let base = try Fixtures.decode(Grade.self, "grade_walk_not_graded")
        let grade = Grade(gradeId: "g_win", predictionId: prediction.predictionId, kind: .meal, gradedAt: .now, points: 24,
                          gummiMaeMgDl: 6, cgmOnlyMaeMgDl: 11, lastValueMaeMgDl: 18, gummiPeakErrorMgDl: 3, withinBandPct: 90,
                          walkEffectGraded: base.walkEffectGraded, gummiBeatsCgmOnly: true, gummiBeatsLastValue: true,
                          message: "I predicted it.")
        model.apply(.grade(grade))
        #expect(model.gradeMoment?.prediction?.predictionId == prediction.predictionId)
        #expect(model.puppetCue?.reaction == .cheer)
        let cue = model.puppetCue
        model.apply(.grade(grade))
        #expect(model.puppetCue == cue)
    }
}
