import Foundation

// GET /foodlog (CONTRACT 1.5) and GET /day (1.6).

nonisolated enum FoodOrigin: String, ContractEnum {
    case studyLog = "study_log", you, gummi
    case unknown = "_unknown"
    static let unknownValue = FoodOrigin.unknown
}

nonisolated struct FoodLogPrediction: Codable, Hashable, Sendable {
    let predictedPeakMgDl: Double
    let cgmOnlyPeakMgDl: Double?
    let lastValuePeakMgDl: Double?
    let status: PredictionStatus
}

nonisolated struct FoodLogEntry: Codable, Hashable, Sendable, Identifiable {
    let meal: Meal
    let origin: FoodOrigin
    let graded: Bool
    let prediction: FoodLogPrediction?
    let grade: Grade?
    let note: String?

    var id: String { meal.mealId }
}

nonisolated struct FoodLog: Codable, Hashable, Sendable {
    let date: String?
    let entries: [FoodLogEntry]
}

nonisolated struct DayMoment: Codable, Hashable, Sendable {
    let mgDl: Double
    let at: Date
}

nonisolated struct DayGlucose: Codable, Hashable, Sendable {
    let readings: Int
    let timeInRangePct: Double
    let averageMgDl: Double
    let peak: DayMoment
    let low: DayMoment
}

nonisolated struct DayHour: Codable, Hashable, Sendable, Identifiable {
    let hour: Int
    let avgMgDl: Double
    let minMgDl: Double
    let maxMgDl: Double

    var id: Int { hour }
}

nonisolated struct DayMealBiggest: Codable, Hashable, Sendable {
    let food: String
    let carbsG: Double
    let at: Date
}

nonisolated struct DayMeals: Codable, Hashable, Sendable {
    let count: Int
    let carbsG: Double
    let biggest: DayMealBiggest?
}

nonisolated struct DayActivity: Codable, Hashable, Sendable {
    let steps: Int
    let walks: Int
    let walkMinutes: Int
}

nonisolated struct DayPredictions: Codable, Hashable, Sendable {
    let made: Int
    let graded: Int
    let gummiMaeMgDl: Double?
    let cgmOnlyMaeMgDl: Double?
    let lastValueMaeMgDl: Double?
    let beatCgmOnlyPct: Double?
}

nonisolated struct DayBestCall: Codable, Hashable, Sendable {
    let about: String?
    let message: String
    let gummiPeakErrorMgDl: Double
}

nonisolated struct DaySpike: Codable, Hashable, Sendable {
    let peakMgDl: Double
    let at: Date
    let afterMeal: String?
}

/// One day at a glance, computed by the backend without an LLM (CONTRACT 1.6).
nonisolated struct DaySummary: Codable, Hashable, Sendable {
    let date: String
    let participant: String?
    let dataStatus: DataStatus
    let glucose: DayGlucose?
    let hourly: [DayHour]
    let meals: DayMeals
    let activity: DayActivity
    let predictions: DayPredictions
    let bestCall: DayBestCall?
    let biggestSpike: DaySpike?
    let highlights: [String]
    let recap: StoryCard?
}
