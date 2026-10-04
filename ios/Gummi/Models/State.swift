import Foundation

nonisolated struct Today: Codable, Hashable, Sendable {
    let timeInRangePct: Double
    let peakMgDl: Double
    let meals: Int
    /// Steps and walks belong to the teammate user, shown as an overlay on the followed participant.
    let steps: Int
    let walks: Int
    let gummiMaeMgDl: Double?
    let cgmOnlyMaeMgDl: Double?
    let lastValueMaeMgDl: Double?
}

nonisolated struct ProfileLines: Codable, Hashable, Sendable {
    let highLineMgDl: Double
    let lowLineMgDl: Double
}

/// A withheld meal coming due. `dueAt` is already wall-clock time (1.2).
nonisolated struct UpcomingDue: Codable, Hashable, Sendable, Identifiable {
    let dueId: String
    let dueAt: Date
    let title: String
    let body: String

    var id: String { dueId }
}

/// CONTRACT "State" (GET /state and the "state" live event). Named GummiState to avoid clashing with SwiftUI.
nonisolated struct GummiState: Codable, Hashable, Sendable {
    let userId: String
    let following: String?
    let actingAs: String?
    let dexcom: DexcomStatus
    let gummiView: GummiView?
    let confirmed: [GlucosePoint]
    let estimate: [BandPoint]
    let forecast: [BandPoint]
    let mood: Mood
    let alert: GummiAlert?
    let topCard: StoryCard?
    let pendingPredictions: [Prediction]
    let today: Today
    let profile: ProfileLines
    let upcomingDue: [UpcomingDue]
    /// The chart's "now" while acting as a replay participant; null otherwise (1.3).
    let replayNow: Date?
    let stream: StreamStatus
    /// 1.6: "stale" means the newest reading is over 3 hours old, so there's no estimate or forecast.
    var dataStatus: DataStatus? = nil
    var minutesSinceReading: Int? = nil
    let modelVersion: String
    /// Wall clock.
    let serverTime: Date
}
