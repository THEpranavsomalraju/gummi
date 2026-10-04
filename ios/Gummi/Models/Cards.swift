import Foundation

nonisolated struct CardAction: Codable, Hashable, Sendable {
    let label: String
    let kind: CardActionKind
    var prompt: String? = nil
    var dueId: String? = nil
}

/// Attachment keys per card type (CONTRACT 1.3). Every key is optional.
nonisolated struct CardAttachments: Codable, Hashable, Sendable {
    var meal: Meal? = nil
    var prediction: Prediction? = nil
    var grade: Grade? = nil
    var curve: [GlucosePoint]? = nil
    var walk: WalkSummary? = nil
    var alert: GummiAlert? = nil
}

nonisolated struct StoryCard: Codable, Hashable, Sendable, Identifiable {
    let cardId: String
    let type: CardType
    let createdAt: Date
    let title: String
    let body: String
    let mood: Mood
    var attachments: CardAttachments? = nil
    let actions: [CardAction]
    var traceId: String? = nil
    let generatedBy: GeneratedBy

    var id: String { cardId }

    /// The due meal behind a meal_due card, while it still has a Log it action.
    var pendingDueId: String? {
        actions.first { $0.kind == .logDueMeal }?.dueId
    }
}

nonisolated struct AlertAction: Codable, Hashable, Sendable {
    let label: String
    let kind: AlertActionKind
    var minutes: Int? = nil
}

/// CONTRACT "Alert". Named GummiAlert to avoid clashing with SwiftUI.
nonisolated struct GummiAlert: Codable, Hashable, Sendable, Identifiable {
    let alertId: String
    let type: AlertType
    let message: String
    let createdAt: Date
    let expiresAt: Date
    let action: AlertAction

    var id: String { alertId }
}
