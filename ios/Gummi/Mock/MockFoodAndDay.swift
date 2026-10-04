import Foundation

/// GET /foodlog and GET /day for the mock day, computed from what the scripted session has released so far,
/// so the Food and Day tabs agree with the mock's cards and grades.
nonisolated extension MockSession {
    /// The replay day as YYYY-MM-DD in the profile timezone.
    var dateString: String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Theme.timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: dayStart)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    func label(forPrediction id: String) -> String? {
        guard let index = Int(id.dropFirst(3)).map({ $0 - 1 }), day.meals.indices.contains(index) else { return nil }
        return day.meals[index].label
    }

    /// The study meals logged so far (graded or pending) plus `extra` (your and Gummi's entries), newest first.
    func foodLog(extra: [FoodLogEntry]) -> FoodLog {
        guard following != nil else { return FoodLog(date: dateString, entries: extra) }
        let study = logged.sorted { $0.key < $1.key }.map { index, entry -> FoodLogEntry in
            let prediction = predictions[index]
            let grade = prediction.flatMap { p in grades.first { $0.predictionId == p.predictionId } }
            return FoodLogEntry(
                meal: entry.meal, origin: .studyLog, graded: grade != nil,
                prediction: prediction.map {
                    FoodLogPrediction(predictedPeakMgDl: $0.predictedPeakMgDl, cgmOnlyPeakMgDl: $0.cgmOnlyPeakMgDl,
                                      lastValuePeakMgDl: $0.lastValuePeakMgDl, status: grade == nil ? .pending : .graded)
                },
                grade: grade, note: prediction == nil ? "No prediction for this one" : nil)
        }
        return FoodLog(date: dateString, entries: (study + extra).sorted { $0.meal.eatenAt > $1.meal.eatenAt })
    }

    func daySummary(steps: Int, walks: Int) -> DaySummary {
        guard following != nil else { return Self.emptyDay(date: dateString) }
        let readings = day.readings.filter { Double($0.minute) <= dataThrough }
        var glucose: DayGlucose?
        if let peak = readings.max(by: { $0.glucose < $1.glucose }), let low = readings.min(by: { $0.glucose < $1.glucose }) {
            let inRange = readings.filter { $0.glucose >= Self.lowLine && $0.glucose <= Self.highLine }.count
            glucose = DayGlucose(readings: readings.count,
                                 timeInRangePct: (100 * Double(inRange) / Double(readings.count)).rounded(toPlaces: 1),
                                 averageMgDl: readings.map(\.glucose).average.rounded(toPlaces: 1),
                                 peak: DayMoment(mgDl: peak.glucose, at: date(Double(peak.minute))),
                                 low: DayMoment(mgDl: low.glucose, at: date(Double(low.minute))))
        }
        let hourly = Dictionary(grouping: readings) { $0.minute / 60 }.sorted { $0.key < $1.key }.map { hour, values in
            DayHour(hour: hour, avgMgDl: values.map(\.glucose).average.rounded(toPlaces: 1),
                    minMgDl: values.map(\.glucose).min() ?? 0, maxMgDl: values.map(\.glucose).max() ?? 0)
        }
        let meals = logged.values.map(\.meal)
        let biggest = meals.max { $0.totals.carbsG < $1.totals.carbsG }.map {
            DayMealBiggest(food: $0.items.map(\.name).joined(separator: ", "), carbsG: $0.totals.carbsG, at: $0.eatenAt)
        }
        let counted = grades.filter(\.walkEffectGraded)
        func mean(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.average.rounded(toPlaces: 1) }
        let predictionsSummary = DayPredictions(
            made: predictions.count, graded: grades.count,
            gummiMaeMgDl: mean(counted.map(\.gummiMaeMgDl)), cgmOnlyMaeMgDl: mean(counted.compactMap(\.cgmOnlyMaeMgDl)),
            lastValueMaeMgDl: mean(counted.map(\.lastValueMaeMgDl)),
            beatCgmOnlyPct: grades.isEmpty ? nil : (100 * Double(grades.filter(\.earnsProud).count) / Double(grades.count)).rounded(toPlaces: 1))
        let best = grades.min { $0.gummiPeakErrorMgDl < $1.gummiPeakErrorMgDl }.map {
            DayBestCall(about: label(forPrediction: $0.predictionId), message: $0.message, gummiPeakErrorMgDl: $0.gummiPeakErrorMgDl)
        }
        let spike = readings.max(by: { $0.glucose < $1.glucose }).map { peak in
            DaySpike(peakMgDl: peak.glucose, at: date(Double(peak.minute)),
                     afterMeal: day.meals.last { $0.minute <= peak.minute && peak.minute - $0.minute <= 180 }?.label)
        }
        var highlights: [String] = []
        if !grades.isEmpty {
            highlights.append("I beat CGM-only on \(grades.filter(\.earnsProud).count) of \(grades.count) graded meals so far.")
        }
        if let spike, let meal = spike.afterMeal { highlights.append("The biggest rise was after \(meal.lowercased()): \(Int(spike.peakMgDl)) mg/dL.") }
        if let glucose { highlights.append("\(Int(glucose.timeInRangePct.rounded()))% of readings were in range.") }
        return DaySummary(date: dateString, participant: following, dataStatus: .live, glucose: glucose, hourly: hourly,
                          meals: DayMeals(count: meals.count, carbsG: meals.map(\.totals.carbsG).reduce(0, +).rounded(toPlaces: 1), biggest: biggest),
                          activity: DayActivity(steps: steps, walks: walks, walkMinutes: walks * 12),
                          predictions: predictionsSummary, bestCall: best, biggestSpike: spike, highlights: highlights,
                          recap: cards.first { $0.type == .eveningRecap })
    }

    static func emptyDay(date: String) -> DaySummary {
        DaySummary(date: date, participant: nil, dataStatus: DataStatus.none, glucose: nil, hourly: [],
                   meals: DayMeals(count: 0, carbsG: 0, biggest: nil), activity: DayActivity(steps: 0, walks: 0, walkMinutes: 0),
                   predictions: DayPredictions(made: 0, graded: 0, gummiMaeMgDl: nil, cgmOnlyMaeMgDl: nil, lastValueMaeMgDl: nil,
                                               beatCgmOnlyPct: nil),
                   bestCall: nil, biggestSpike: nil, highlights: [], recap: nil)
    }
}
