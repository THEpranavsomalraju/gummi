import Foundation

/// A contract string enum that decodes values it doesn't know as `unknownValue` instead of failing,
/// so a new backend value (a new card type, mood, or tool) never breaks a whole State decode.
nonisolated protocol ContractEnum: RawRepresentable, Codable, Hashable, Sendable where RawValue == String {
    static var unknownValue: Self { get }
}

nonisolated extension ContractEnum {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? Self.unknownValue
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var isKnown: Bool { self != Self.unknownValue }
}

/// CONTRACT section 9. `thinking` is UI-only on the phone; Backend owns the rest (1.3).
nonisolated enum Mood: String, ContractEnum {
    case calm, rising, high, dipping, low, proud, happy, sleepy, thinking
    case unknown = "_unknown"
    static let unknownValue = Mood.unknown
}

nonisolated enum Trend: String, ContractEnum {
    case risingFast = "rising_fast", rising, flat, falling
    case fallingFast = "falling_fast"
    case unknown = "_unknown"
    static let unknownValue = Trend.unknown
}

nonisolated enum Confidence: String, ContractEnum {
    case high, medium, low
    case unknown = "_unknown"
    static let unknownValue = Confidence.unknown
}

nonisolated enum PointKind: String, ContractEnum {
    case confirmed, estimate, forecast
    case unknown = "_unknown"
    static let unknownValue = PointKind.unknown
}

nonisolated enum PredictionKind: String, ContractEnum {
    case meal, nowcast
    case unknown = "_unknown"
    static let unknownValue = PredictionKind.unknown
}

nonisolated enum PredictionStatus: String, ContractEnum {
    case pending, graded
    case unknown = "_unknown"
    static let unknownValue = PredictionStatus.unknown
}

nonisolated enum CardType: String, ContractEnum {
    case morningBriefing = "morning_briefing"
    case mealDue = "meal_due"
    case mealLogged = "meal_logged"
    case prediction
    case mealStory = "meal_story"
    case grade
    case walkSuggested = "walk_suggested"
    case walkSummary = "walk_summary"
    case eveningRecap = "evening_recap"
    case dexcomStatus = "dexcom_status"
    case unknown = "_unknown"
    static let unknownValue = CardType.unknown
}

nonisolated extension CardType {
    /// SF Symbol for each card type.
    var symbol: String {
        switch self {
        case .morningBriefing: "sun.horizon"
        case .mealDue: "fork.knife"
        case .mealLogged: "checkmark.circle"
        case .prediction: "chart.line.uptrend.xyaxis"
        case .mealStory: "book"
        case .grade: "rosette"
        case .walkSuggested: "figure.walk"
        case .walkSummary: "figure.walk.motion"
        case .eveningRecap: "moon.stars"
        case .dexcomStatus: "antenna.radiowaves.left.and.right"
        case .unknown: "sparkles"
        }
    }
}

nonisolated enum CardActionKind: String, ContractEnum {
    case openChat = "open_chat"
    case logDueMeal = "log_due_meal"
    case unknown = "_unknown"
    static let unknownValue = CardActionKind.unknown
}

nonisolated enum GeneratedBy: String, ContractEnum {
    case agent, template
    case unknown = "_unknown"
    static let unknownValue = GeneratedBy.unknown
}

nonisolated enum AlertType: String, ContractEnum {
    case walkSuggested = "walk_suggested"
    case highForecast = "high_forecast"
    case lowForecast = "low_forecast"
    case dexcomGap = "dexcom_gap"
    case unknown = "_unknown"
    static let unknownValue = AlertType.unknown
}

nonisolated enum AlertActionKind: String, ContractEnum {
    case startWalk = "start_walk"
    case openChat = "open_chat"
    case dismiss
    case unknown = "_unknown"
    static let unknownValue = AlertActionKind.unknown
}

nonisolated enum MealSource: String, ContractEnum {
    case chat, manual, replay
    case replayDue = "replay_due"
    case replayAuto = "replay_auto"
    case unknown = "_unknown"
    static let unknownValue = MealSource.unknown
}

nonisolated enum NutritionSource: String, ContractEnum {
    case seed
    case llmEstimate = "llm_estimate"
    case dataset
    case unknown = "_unknown"
    static let unknownValue = NutritionSource.unknown
}

nonisolated enum Verdict: String, ContractEnum {
    case go
    case goWithTweak = "go_with_tweak"
    case wait
    case unknown = "_unknown"
    static let unknownValue = Verdict.unknown
}

nonisolated enum SimulationMethod: String, ContractEnum {
    case model
    case breakfastResponse = "breakfast_response"
    case unknown = "_unknown"
    static let unknownValue = SimulationMethod.unknown
}

/// Walk effects always carry their source.
nonisolated enum EffectSource: String, ContractEnum {
    case literature
    case yourData = "your data"
    case unknown = "_unknown"
    static let unknownValue = EffectSource.unknown
}

nonisolated enum WalkIntensity: String, ContractEnum {
    case sedentary, light, moderate, vigorous
    case unknown = "_unknown"
    static let unknownValue = WalkIntensity.unknown
}

nonisolated enum DexcomEnvironment: String, ContractEnum {
    case sandbox, production
    case unknown = "_unknown"
    static let unknownValue = DexcomEnvironment.unknown
}

nonisolated enum DexcomSource: String, ContractEnum {
    case dexcomAPI = "dexcom_api"
    case replay, none
    case unknown = "_unknown"
    static let unknownValue = DexcomSource.unknown
}

nonisolated enum IngestMode: String, ContractEnum {
    case statusOnly = "status_only"
    case timeShifted = "time_shifted"
    case unknown = "_unknown"
    static let unknownValue = IngestMode.unknown
}

nonisolated enum GummiMode: String, ContractEnum {
    case mock, live
    case unknown = "_unknown"
    static let unknownValue = GummiMode.unknown
}

/// CONTRACT 1.6 State.data_status.
nonisolated enum DataStatus: String, ContractEnum {
    case live, stale, none
    case unknown = "_unknown"
    static let unknownValue = DataStatus.unknown
}
