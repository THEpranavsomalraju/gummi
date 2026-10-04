import Foundation
import Testing
@testable import Gummi

@Suite("Food log")
struct FoodLogTests {
    private func log() throws -> FoodLog { try Fixtures.decode(FoodLog.self, "foodlog") }

    @Test func allThreeOriginsDecode() throws {
        let entries = try log().entries
        #expect(Set(entries.map(\.origin)) == [.studyLog, .you, .gummi])
        #expect(entries.filter(\.graded).count == 1)
    }

    @Test func resultsForGradedSimulatedAndPending() throws {
        let entries = try log().entries
        let breakfast = try #require(entries.first { $0.meal.mealId == "m_1" })
        #expect(FoodResult.of(breakfast) == .graded(me: 135, cgmOnly: 112, lastValue: 104, actual: 188, beatCgmOnly: true))
        let cookie = try #require(entries.first { $0.origin == .gummi })
        #expect(FoodResult.of(cookie) == .simulated(likelyPeak: 149))
        let eggs = try #require(entries.first { $0.meal.mealId == "m_2" })
        #expect(FoodResult.of(eggs) == .pending(after: eggs.meal.eatenAt.addingTimeInterval(3 * 3600)))
        #expect(FoodResult.actualPeak(in: "I predicted 185 for the evening snack. It was 186. CGM-only said 155.") == 186)
    }

    @Test func mealSlotsByLocalTime() {
        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = Theme.timeZone
            return calendar.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: hour, minute: minute))!
        }
        #expect(MealSlot.of(at(5, 56)) == .breakfast)
        #expect(MealSlot.of(at(12, 18)) == .lunch)
        #expect(MealSlot.of(at(15, 32)) == .snack)
        #expect(MealSlot.of(at(19, 1)) == .dinner)
        #expect(MealSlot.of(at(22, 30)) == .snack)
    }

    @Test func rowsReadAsOneSentence() throws {
        let breakfast = try #require(try log().entries.first { $0.meal.mealId == "m_1" })
        #expect(FoodLogText.spoken(breakfast).replacingOccurrences(of: "\u{202F}", with: " ") == "Breakfast, 5:56 AM, milk and frosted flake, 57 grams of carbs, from study log, I predicted 135, actual 188, CGM-only said 112")
    }

    @Test func mockFoodLogMatchesTheMockGrades() async throws {
        let mock = MockGummiService(day: try MockDay.load(), minutesPerSecond: 600)
        _ = try await mock.follow(MockSession.participant)
        let stream = mock.events()
        let task = Task { for await _ in stream {} }
        try await Task.sleep(for: .seconds(1.5))
        task.cancel()
        let log = try await mock.foodLog(date: nil)
        #expect(!log.entries.isEmpty)
        #expect(log.entries.allSatisfy { $0.origin == .studyLog })
        let meal = try await mock.logFood(LogFoodBody(items: [.init(name: "apple", quantity: 1, unit: nil)]))
        #expect(meal.totals.carbsG == 25)
        let after = try await mock.foodLog(date: nil)
        #expect(after.entries.contains { $0.origin == .you && FoodResult.of($0) != .none(nil) })
    }
}

@Suite("Activity")
struct ActivityTests {
    private func model() -> AppModel {
        AppModel(defaults: UserDefaults(suiteName: "gummi.tests.\(UUID().uuidString)")!,
                 makeService: { _ in throw APIError.notConfigured("unused") })
    }

    @Test func filtersMatchCardTypes() {
        #expect(ActivityFilter.meals.matches(.mealDue) && ActivityFilter.meals.matches(.mealStory))
        #expect(!ActivityFilter.meals.matches(.walkSummary))
        #expect(ActivityFilter.walks.matches(.walkSuggested) && !ActivityFilter.walks.matches(.eveningRecap))
        #expect(ActivityFilter.grades.matches(.mealStory) && !ActivityFilter.grades.matches(.mealLogged))
        #expect(ActivityFilter.allCases.allSatisfy { $0 != .all || $0.matches(.morningBriefing) })
    }

    @Test func newCardsBadgeActivityUntilOpened() throws {
        let model = model()
        model.apply(.card(try Fixtures.decode(StoryCard.self, "card_meal_due")))
        model.apply(.card(try Fixtures.decode(StoryCard.self, "card_morning_briefing")))
        // An upgrade of a card already held doesn't count again.
        model.apply(.card(try Fixtures.decode(StoryCard.self, "card_meal_due_resolved")))
        #expect(model.activityUnseen == 2)
        model.selectedTab = .activity
        #expect(model.activityUnseen == 0)
        model.apply(.card(try Fixtures.decode(StoryCard.self, "card_meal_logged")))
        #expect(model.activityUnseen == 0)
    }
}

@Suite("Day")
struct DayTests {
    @Test func fixturesDecodeEveryVariant() throws {
        let full = try Fixtures.decode(DaySummary.self, "day_full")
        #expect(full.dataStatus == .live && full.glucose?.peak.mgDl == 193 && full.hourly.count == 23)
        #expect(full.predictions.beatCgmOnlyPct == 83.3 && full.recap?.type == .eveningRecap)
        #expect(full.bestCall?.message.contains("It was 186") == true)
        #expect(try Fixtures.decode(DaySummary.self, "day_stale").dataStatus == .stale)
        let empty = try Fixtures.decode(DaySummary.self, "day_empty")
        #expect(empty.dataStatus == DataStatus.none && empty.glucose == nil && empty.hourly.isEmpty)
    }

    @Test func hourlyDomainHugsTheDayAndKeepsTheLines() throws {
        let full = try Fixtures.decode(DaySummary.self, "day_full")
        let domain = HourlyStrip.yDomain(full.hourly)
        #expect(domain.lowerBound <= 60 && domain.upperBound >= 186 && domain.upperBound < 250)
        #expect(HourlyStrip.yDomain([]) == 60...155)
    }

    @Test func mockDayAgreesWithItsGrades() async throws {
        var session = MockSession(day: try MockDay.load())
        _ = session.advance(to: 1349, wallNow: .now)
        let day = session.daySummary(steps: 4000, walks: 1)
        #expect(day.predictions.graded == session.grades.count && day.predictions.graded == 6)
        #expect(day.predictions.beatCgmOnlyPct == (100 * 5.0 / 6).rounded(toPlaces: 1))
        #expect(day.bestCall?.message.hasPrefix("I predicted 178") == true)
        #expect(day.glucose?.peak.mgDl == 193)
        #expect(day.recap != nil)
        session.following = nil
        #expect(session.daySummary(steps: 0, walks: 0).dataStatus == DataStatus.none)
    }
}
