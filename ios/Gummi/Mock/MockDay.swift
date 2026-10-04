import Foundation

/// p_012's real replay day 6 (D-15) from data/reports/demo_day, bundled for MockAPI.
nonisolated struct MockDay: Sendable {
    struct Reading: Sendable {
        let minute: Int
        let glucose: Double
    }

    struct DayMeal: Sendable {
        let index: Int
        let mealId: String
        let minute: Int
        let items: [MealItem]
        let totals: MealTotals
        let isStandardBreakfast: Bool

        /// "Milk and Frosted Flake", "A, B, and 4 more".
        var text: String {
            let names = items.map(\.name)
            switch names.count {
            case 0: return "A meal"
            case 1: return names[0]
            case 2: return "\(names[0]) and \(names[1])"
            case 3: return "\(names[0]), \(names[1]), and \(names[2])"
            default: return "\(names[0]), \(names[1]), and \(names.count - 2) more"
            }
        }

        var label: String {
            switch minute {
            case ..<600: "Breakfast"
            case ..<690: "Snack"
            case ..<900: "Lunch"
            case ..<1020: "Snack"
            case ..<1110: "Dinner"
            default: "Snack"
            }
        }
    }

    let readings: [Reading]
    let meals: [DayMeal]

    static func load(bundle: Bundle = .main) throws -> MockDay {
        func text(_ name: String) throws -> String {
            guard let url = bundle.url(forResource: name, withExtension: "csv") else {
                throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "\(name).csv"])
            }
            return try String(contentsOf: url, encoding: .utf8)
        }
        return try MockDay(cgmCSV: text("p012_day6_cgm"), mealsCSV: text("p012_day6_meals"),
                           foodLogCSV: text("p012_day6_food_log"))
    }

    init(cgmCSV: String, mealsCSV: String, foodLogCSV: String) throws {
        let cgm = CSV.rows(cgmCSV)
        readings = cgm.compactMap { row in
            guard let minute = Int(row["minute_of_day"] ?? ""), let glucose = Double(row["glucose_mg_dl"] ?? "") else { return nil }
            return Reading(minute: minute, glucose: glucose)
        }.sorted { $0.minute < $1.minute }

        let logRows = CSV.rows(foodLogCSV)
        meals = CSV.rows(mealsCSV).enumerated().compactMap { index, row in
            guard let mealId = row["meal_id"], let minute = Int(row["minute_of_day"] ?? "") else { return nil }
            let value = { (key: String) in Double(row[key] ?? "") ?? 0 }
            let items = logRows.filter { $0["meal_id"] == mealId }.map(Self.item)
            let fatTotal = value("fat_g") * 9 > max(value("calories"), 1) ? 0 : value("fat_g")
            return DayMeal(index: index, mealId: mealId, minute: minute, items: items,
                           totals: MealTotals(carbsG: value("carbs_g"), sugarG: value("sugar_g"), fiberG: value("fiber_g"),
                                              proteinG: value("protein_g"), fatG: fatTotal, calories: value("calories")),
                           isStandardBreakfast: row["is_standard_breakfast"] == "True")
        }
        guard !readings.isEmpty, !meals.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
    }

    private static func item(_ log: [String: String]) -> MealItem {
        func number(_ key: String) -> Double { Double(log[key] ?? "") ?? 0 }
        let carbs = number("carbs_g")
        let protein = number("protein_g")
        // The source logs fat 255 g for the almonds (it equals the calories). Drop impossible fat.
        let fat = number("fat_g") > 100 ? 0 : number("fat_g")
        let calories: Double = (4 * carbs + 4 * protein + 9 * fat).rounded()
        return MealItem(name: log["logged_food"] ?? "Food", quantity: Double(log["amount"] ?? "") ?? 1,
                        unit: log["unit"] ?? "", carbsG: carbs, sugarG: number("sugar_g"), fiberG: 0,
                        proteinG: protein, fatG: fat, calories: calories, nutritionSource: .dataset, editable: true)
    }

    /// Linear interpolation between readings, clamped at the ends.
    func glucose(at minute: Double) -> Double {
        guard let after = readings.firstIndex(where: { Double($0.minute) >= minute }) else { return readings.last!.glucose }
        guard after > 0 else { return readings[0].glucose }
        let a = readings[after - 1], b = readings[after]
        let f = (minute - Double(a.minute)) / Double(b.minute - a.minute)
        return a.glucose + (b.glucose - a.glucose) * f
    }

    func lastReading(atOrBefore minute: Double) -> Reading? {
        readings.last { Double($0.minute) <= minute }
    }

    func peak(from start: Int, to end: Int) -> Reading? {
        readings.filter { $0.minute >= start && $0.minute <= end }.max { $0.glucose < $1.glucose }
    }
}

/// Minimal CSV reader: header row, quoted fields with commas.
nonisolated enum CSV {
    static func rows(_ text: String) -> [[String: String]] {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        guard let header = lines.first.map(fields) else { return [] }
        return lines.dropFirst().map { line in
            Dictionary(zip(header, fields(line)), uniquingKeysWith: { first, _ in first })
        }
    }

    static func fields(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var quoted = false
        for character in line {
            switch character {
            case "\"": quoted.toggle()
            case "," where !quoted:
                result.append(current)
                current = ""
            default: current.append(character)
            }
        }
        result.append(current)
        return result
    }
}
