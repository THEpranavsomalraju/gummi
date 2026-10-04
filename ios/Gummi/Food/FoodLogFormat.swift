import Foundation

/// Breakfast before 11, lunch 11 to 15, dinner 17 to 22, snack otherwise, by local time (Pranav's Food spec).
nonisolated enum MealSlot: String, CaseIterable, Sendable, Identifiable {
    case breakfast = "Breakfast", lunch = "Lunch", snack = "Snack", dinner = "Dinner"

    var id: String { rawValue }

    static func of(_ date: Date) -> MealSlot {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Theme.timeZone
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case ..<11: return .breakfast
        case 11..<15: return .lunch
        case 17..<22: return .dinner
        default: return .snack
        }
    }
}

/// What the Result column says for one food log entry.
nonisolated enum FoodResult: Equatable, Sendable {
    /// Me, CGM-only, last value, what happened, and whether Gummi beat CGM-only.
    case graded(me: Int, cgmOnly: Int?, lastValue: Int?, actual: Int?, beatCgmOnly: Bool)
    /// Your or Gummi's entry on a participant's day: never graded.
    case simulated(likelyPeak: Int?)
    /// A study meal waiting for its 2-hour window plus the data delay.
    case pending(after: Date?)
    case none(String?)

    static func of(_ entry: FoodLogEntry, delayMinutes: Int = 60) -> FoodResult {
        let prediction = entry.prediction
        if let grade = entry.grade, let prediction {
            return .graded(me: Int(prediction.predictedPeakMgDl.rounded()), cgmOnly: prediction.cgmOnlyPeakMgDl.map { Int($0.rounded()) },
                           lastValue: prediction.lastValuePeakMgDl.map { Int($0.rounded()) },
                           actual: actualPeak(in: grade.message), beatCgmOnly: grade.earnsProud)
        }
        if entry.origin == .you || entry.origin == .gummi {
            return .simulated(likelyPeak: prediction.map { Int($0.predictedPeakMgDl.rounded()) })
        }
        if prediction != nil {
            return .pending(after: entry.meal.eatenAt.addingTimeInterval(Double(120 + delayMinutes) * 60))
        }
        return .none(entry.note)
    }

    /// The real peak from a grade message ("I predicted 135 for breakfast. It was 188. …"). The food log doesn't carry
    /// the actual peak as a number yet (asked Backend for actual_peak_mg_dl).
    static func actualPeak(in message: String) -> Int? {
        guard let range = message.range(of: #"It was (\d+)"#, options: .regularExpression) else { return nil }
        return Int(message[range].filter(\.isNumber))
    }
}

nonisolated enum FoodLogText {
    static func time(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: Theme.timeZone))
    }

    static func foods(_ meal: Meal) -> String {
        let names = meal.items.map(\.name)
        guard let first = names.first else { return "Meal" }
        return names.count == 1 ? first : names.dropLast().joined(separator: ", ") + " and " + names.last!
    }

    static func source(_ origin: FoodOrigin) -> String {
        switch origin {
        case .studyLog: "Study log"
        case .you: "You"
        case .gummi: "Gummi"
        case .unknown: "Other"
        }
    }

    /// One VoiceOver sentence per row.
    static func spoken(_ entry: FoodLogEntry) -> String {
        let meal = entry.meal
        var parts = ["\(MealSlot.of(meal.eatenAt).rawValue), \(time(meal.eatenAt))", foods(meal).lowercased(),
                     "\(Int(meal.totals.carbsG.rounded())) grams of carbs", "from \(source(entry.origin).lowercased())"]
        switch FoodResult.of(entry) {
        case .graded(let me, let cgmOnly, _, let actual, _):
            parts.append("I predicted \(me)" + (actual.map { ", actual \($0)" } ?? "") + (cgmOnly.map { ", CGM-only said \($0)" } ?? ""))
        case .simulated(let peak):
            parts.append("simulated, not graded" + (peak.map { ", likely peak \($0)" } ?? ""))
        case .pending(let after):
            parts.append("grading" + (after.map { " after \(time($0))" } ?? " soon"))
        case .none(let note):
            if let note { parts.append(note) }
        }
        return parts.joined(separator: ", ")
    }

    /// YYYY-MM-DD for /foodlog and /day, moving `days` from `base` in the profile timezone.
    static func dateString(_ base: Date, plusDays days: Int = 0) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Theme.timeZone
        let date = calendar.date(byAdding: .day, value: days, to: base) ?? base
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func date(from string: String) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Theme.timeZone
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }
}
