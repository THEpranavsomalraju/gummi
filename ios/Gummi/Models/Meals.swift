import Foundation

nonisolated struct MealItem: Codable, Hashable, Sendable {
    var name: String
    var quantity: Double
    /// May be "" for food-log rows without a unit (CCR item 5).
    var unit: String
    var carbsG: Double
    var sugarG: Double
    var fiberG: Double
    var proteinG: Double
    var fatG: Double
    var calories: Double
    var nutritionSource: NutritionSource
    var editable: Bool
}

nonisolated struct MealTotals: Codable, Hashable, Sendable {
    let carbsG: Double
    let sugarG: Double
    let fiberG: Double
    let proteinG: Double
    let fatG: Double
    let calories: Double
}

nonisolated struct Meal: Codable, Hashable, Sendable, Identifiable {
    let mealId: String
    let eatenAt: Date
    let source: MealSource
    let items: [MealItem]
    let totals: MealTotals
    let isStandardBreakfast: Bool
    let predictionId: String?

    var id: String { mealId }
}

nonisolated struct Alternative: Codable, Hashable, Sendable {
    let label: String
    let peakMgDl: Double
    var effectSource: EffectSource? = nil
}

nonisolated struct Simulation: Codable, Hashable, Sendable {
    let items: [MealItem]
    let eatAt: Date
    let baselineCurve: [BandPoint]
    let withFoodCurve: [BandPoint]
    let peakMgDl: Double
    let peakAt: Date
    let verdict: Verdict
    let summary: String
    let alternatives: [Alternative]
    let method: SimulationMethod
    let predictionId: String
    /// False (1.6) when the food is beyond what the model has learned (over about 140 g carbs): no peak is quoted.
    var reliable: Bool? = nil
    var requestedCarbsG: Double? = nil

    var isReliable: Bool { reliable != false }
}
