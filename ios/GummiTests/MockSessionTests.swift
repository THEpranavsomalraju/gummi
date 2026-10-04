import Foundation
import Testing
@testable import Gummi

@Suite("Mock day (p_012, day 6)")
struct MockSessionTests {
    let day: MockDay

    init() throws {
        day = try MockDay.load()
    }

    /// Runs the whole scripted day one replay minute at a time, logging nothing by hand.
    private func runDay() -> (session: MockSession, timeline: [(minute: Double, output: MockSession.Output)]) {
        var session = MockSession(day: day)
        var timeline: [(Double, MockSession.Output)] = []
        let wall = Date.now
        while session.minute < MockSession.endMinute {
            let next = session.minute + 1
            for output in session.advance(to: next, wallNow: wall) { timeline.append((session.minute, output)) }
        }
        return (session, timeline)
    }

    private func cards(_ timeline: [(minute: Double, output: MockSession.Output)]) -> [(Double, StoryCard)] {
        timeline.compactMap { if case .event(.card(let card)) = $0.output { ($0.minute, card) } else { nil } }
    }

    @Test func realDataLoads() {
        #expect(day.readings.count == 288)
        #expect(day.meals.count == 9)
        #expect(day.meals[0].isStandardBreakfast)
        #expect(day.meals[0].minute == 354)
        #expect(day.meals[0].text == "Milk and Frosted Flake")
        #expect(day.meals[4].items.first?.name == "Salad - (chicken, tomato, ranch)")
        #expect(day.peak(from: 354, to: 474)?.glucose == 174)
        // The source's 255 g of fat on the almonds is dropped as a logging error.
        #expect(day.meals[3].items.allSatisfy { $0.fatG < 100 })
    }

    @Test func scriptedBeatsHappenInOrder() {
        let (_, timeline) = runDay()
        let all = cards(timeline)
        func first(_ type: CardType, id: String? = nil) -> Double? {
            all.first { $0.1.type == type && (id == nil || $0.1.cardId == id) }?.0
        }
        let due = first(.mealDue, id: "c_due_1"), briefing = first(.morningBriefing), walkSuggested = first(.walkSuggested)
        let walkSummary = first(.walkSummary), story = first(.mealStory, id: "c_story_1"), recap = first(.eveningRecap)
        #expect(due == 354)
        #expect(briefing == 360)
        #expect(walkSuggested.map { $0 > 354 && $0 < 420 } == true)
        #expect(walkSummary.map { $0 > walkSuggested! } == true)
        // Breakfast is graded once confirmed data covers 05:54 to 07:54, an hour later on the replay clock.
        #expect(story == Double(354 + 120 + 60))
        #expect(recap == 1200)
        #expect(timeline.contains { if case .pause = $0.output { $0.minute == 600 } else { false } })
    }

    @Test func dueMealAutoLogsAfterTenMinutesAndResolvesByUpsert() {
        let (session, timeline) = runDay()
        let breakfastCards = cards(timeline).filter { $0.1.cardId == "c_due_1" }
        #expect(breakfastCards.count == 2)
        #expect(breakfastCards.first?.1.pendingDueId == "d_1")
        #expect(breakfastCards.last?.0 == 364)
        #expect(breakfastCards.last?.1.pendingDueId == nil)
        #expect(breakfastCards.last?.1.body.hasSuffix("Logged.") == true)
        #expect(session.logged[0]?.meal.source == .replayAuto)
        #expect(session.cards.filter { $0.cardId == "c_due_1" }.count == 1)
    }

    @Test func tappingLogItUsesReplayDueAndRejectsASecondTap() throws {
        var session = MockSession(day: day)
        _ = session.advance(to: 356, wallNow: .now)
        let (meal, events) = try session.logDue(dueId: "d_1")
        #expect(meal.source == .replayDue)
        #expect(meal.isStandardBreakfast)
        #expect(events.count == 2)
        #expect(throws: APIError.http(status: 409, code: "due_already_logged", message: "d_1 was logged already")) {
            try session.logDue(dueId: "d_1")
        }
        #expect(throws: APIError.self) { try session.logDue(dueId: "d_5") }
    }

    @Test func gradesCarryHonestyAndProudRules() {
        let (session, timeline) = runDay()
        #expect(session.grades.count == 2)
        let breakfast = session.grades[0], lunch = session.grades[1]
        // The scripted walk overlapped breakfast, and CGM-only edged Gummi: no proud.
        #expect(!breakfast.walkEffectGraded)
        #expect(breakfast.message.hasSuffix("Walk effect not graded (replayed data)."))
        #expect(!breakfast.earnsProud)
        #expect(lunch.walkEffectGraded)
        #expect(lunch.earnsProud)
        let proudMoods = timeline.filter { if case .event(.mood(.proud)) = $0.output { true } else { false } }
        #expect(proudMoods.count == 1)
        #expect(proudMoods.first?.minute == lunch.gradedAt.timeIntervalSince(session.dayStart) / 60)
    }

    @Test func snapshotFollowsTheContract() {
        var session = MockSession(day: day)
        _ = session.advance(to: 370, wallNow: .now)
        let wall = Date.now
        let state = session.snapshot(wallNow: wall, paused: false, minutesPerSecond: 6)
        let now = session.date(370)
        #expect(state.actingAs == "p_012")
        #expect(state.replayNow == now)
        #expect(state.confirmed.last.map { $0.t <= now.addingTimeInterval(-3600) } == true)
        #expect(state.estimate.first.map { $0.t == now.addingTimeInterval(-3600) } == true)
        #expect(state.forecast.first.map { $0.t > now } == true)
        #expect(state.forecast.last.map { $0.t == now.addingTimeInterval(7200) } == true)
        #expect(state.gummiView != nil)
        #expect(state.topCard?.cardId == state.topCard.map { _ in session.cards[0].cardId })
        #expect(state.stream.replayClock == "day6T06:10")
        #expect(state.stream.speed == 360)
        // Breakfast is logged and in its window: the forecast crosses the high line.
        #expect(state.mood == .high)
        #expect(state.alert != nil)
        // Upcoming due meals are converted to wall-clock time.
        let next = state.upcomingDue.first
        #expect(next?.dueId == "d_2")
        #expect(next.map { abs($0.dueAt.timeIntervalSince(wall) - (460 - 370) / 6) < 0.01 } == true)
        #expect(session.snapshot(wallNow: wall, paused: true, minutesPerSecond: 6).upcomingDue.isEmpty)
    }

    @Test func earlyMorningIsSleepyAndUnfollowEmptiesState() {
        var session = MockSession(day: day)
        _ = session.advance(to: 320, wallNow: .now)
        #expect(session.snapshot(wallNow: .now, paused: false, minutesPerSecond: 6).mood == .sleepy)
        session.following = nil
        let state = session.snapshot(wallNow: .now, paused: false, minutesPerSecond: 6)
        #expect(state.actingAs == nil && state.replayNow == nil && state.gummiView == nil && state.confirmed.isEmpty)
    }

    @Test func todayAccuracyExcludesWalkWindows() {
        let (session, _) = runDay()
        let state = session.snapshot(wallNow: .now, paused: false, minutesPerSecond: 6)
        // Only lunch counts: breakfast overlapped the phone walk.
        #expect(state.today.gummiMaeMgDl == 6.8)
        #expect(state.today.cgmOnlyMaeMgDl == 9.9)
        #expect(state.today.walks == 1)
    }
}
