import Foundation

/// The walk_suggestion chat card (backend agent/tools.py suggest_walk). Not in CONTRACT section 3 yet,
/// so everything past `minutes` is optional.
nonisolated struct WalkSuggestion: Codable, Hashable, Sendable {
    let minutes: Int
    var start: Date? = nil
    var forecastPeakMgDl: Double? = nil
    var forecastPeakDropMgDl: Double? = nil
    var effectSource: EffectSource? = nil
}

/// An inline chat card (CONTRACT section 6). A card_type this build doesn't know decodes as nil and is skipped.
nonisolated enum ChatCard: Hashable, Sendable {
    case mealSaved(Meal)
    case simulation(Simulation)
    case gummiView(GummiView)
    case walkSuggestion(WalkSuggestion)
    case grade(Grade)
    case mealDue(StoryCard)

    nonisolated private struct Head: Decodable { let cardType: String }
    nonisolated private struct Body<Payload: Decodable>: Decodable { let payload: Payload }

    /// Decodes `{"card_type", "payload"}`. Throws only when a known type carries a malformed payload.
    static func decode(_ data: Data, using decoder: JSONDecoder = JSONCoding.decoder()) throws -> ChatCard? {
        func payload<P: Decodable>(_ type: P.Type) throws -> P { try decoder.decode(Body<P>.self, from: data).payload }
        switch try decoder.decode(Head.self, from: data).cardType {
        case "meal_saved": return .mealSaved(try payload(Meal.self))
        case "simulation": return .simulation(try payload(Simulation.self))
        case "gummi_view": return .gummiView(try payload(GummiView.self))
        case "walk_suggestion": return .walkSuggestion(try payload(WalkSuggestion.self))
        case "grade": return .grade(try payload(Grade.self))
        case "meal_due": return .mealDue(try payload(StoryCard.self))
        default: return nil
        }
    }
}

/// POST /chat body. `conversation_id` is sent as null to start a new conversation.
nonisolated struct ChatBody: Encodable, Sendable {
    let message: String
    let conversationId: String?

    private enum CodingKeys: String, CodingKey { case message, conversationId }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(message, forKey: .message)
        try container.encode(conversationId, forKey: .conversationId)
    }
}

nonisolated extension MealItem {
    /// The same food at a new quantity. PATCH /meals keeps the macros it is sent (backend nutrition.item),
    /// so the phone scales every macro and the calories by the same ratio.
    func scaled(toQuantity newQuantity: Double) -> MealItem {
        guard quantity > 0, newQuantity != quantity else { return self }
        let ratio = newQuantity / quantity
        var item = self
        item.quantity = newQuantity
        item.carbsG = (carbsG * ratio).rounded(toPlaces: 1)
        item.sugarG = (sugarG * ratio).rounded(toPlaces: 1)
        item.fiberG = (fiberG * ratio).rounded(toPlaces: 1)
        item.proteinG = (proteinG * ratio).rounded(toPlaces: 1)
        item.fatG = (fatG * ratio).rounded(toPlaces: 1)
        item.calories = (calories * ratio).rounded(toPlaces: 1)
        return item
    }
}

nonisolated extension MealTotals {
    init(items: [MealItem]) {
        func sum(_ value: (MealItem) -> Double) -> Double { items.map(value).reduce(0, +).rounded(toPlaces: 1) }
        self.init(carbsG: sum(\.carbsG), sugarG: sum(\.sugarG), fiberG: sum(\.fiberG), proteinG: sum(\.proteinG),
                  fatG: sum(\.fatG), calories: sum(\.calories))
    }
}
