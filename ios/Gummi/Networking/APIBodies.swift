import Foundation

// Request and wrapper bodies for CONTRACT section 4.

nonisolated struct FeedResponse: Codable, Sendable { let cards: [StoryCard] }
nonisolated struct PredictionsResponse: Codable, Sendable { let predictions: [Prediction] }
nonisolated struct GradesResponse: Codable, Sendable { let grades: [Grade] }
nonisolated struct MealsResponse: Codable, Sendable { let meals: [Meal] }
nonisolated struct DeletedResponse: Codable, Sendable { let deleted: Bool }
nonisolated struct AcceptedResponse: Codable, Sendable { let accepted: Int }
nonisolated struct OKResponse: Codable, Sendable { let ok: Bool }

nonisolated struct NewMealBody: Encodable, Sendable {
    let items: [MealItem]
    let eatenAt: Date
    var source: MealSource = .manual
}

nonisolated struct MealItemsBody: Encodable, Sendable { let items: [MealItem] }

/// `eat_at` is sent as null for "now", matching the contract example.
nonisolated struct SimulateBody: Encodable, Sendable {
    let items: [MealItem]
    let eatAt: Date?

    private enum CodingKeys: String, CodingKey { case items, eatAt }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(items, forKey: .items)
        try container.encode(eatAt, forKey: .eatAt)
    }
}

nonisolated struct StepSample: Encodable, Sendable {
    var type = "steps"
    let value: Int
    let start: Date
    let end: Date
}

nonisolated struct VitalsBody: Encodable, Sendable { let samples: [StepSample] }

/// POST /events: walk_started, or walk_completed with the phone's counts (1.3).
nonisolated struct WalkEventBody: Encodable, Sendable {
    let type: String
    let at: Date
    var startedAt: Date? = nil
    var steps: Int? = nil
    var cadenceSpm: Int? = nil

    static func started(at: Date) -> WalkEventBody { .init(type: "walk_started", at: at) }

    static func completed(at: Date, startedAt: Date, steps: Int, cadenceSpm: Int) -> WalkEventBody {
        .init(type: "walk_completed", at: at, startedAt: startedAt, steps: steps, cadenceSpm: cadenceSpm)
    }
}

/// `{"user_id": null}` unfollows (1.3), so null is encoded explicitly.
nonisolated struct FollowBody: Encodable, Sendable {
    let userId: String?

    private enum CodingKeys: String, CodingKey { case userId }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userId, forKey: .userId)
    }
}

nonisolated struct StreamStartBody: Encodable, Sendable {
    var speed: Double = 60
    var delayMinutes: Int = 60
    /// D-62: start before the 05:56 standardized breakfast (demo day 4, D-15).
    var startAt: String = "day4T05:00"
}

nonisolated struct StreamSpeedBody: Encodable, Sendable { let speed: Double }
