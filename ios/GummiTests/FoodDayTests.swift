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
