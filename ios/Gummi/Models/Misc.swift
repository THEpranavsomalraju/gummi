import Foundation

nonisolated struct DexcomStatus: Codable, Hashable, Sendable {
    let connected: Bool
    let environment: DexcomEnvironment
    let dataThrough: Date?
    let delayMinutes: Int
    let lastSync: Date?
    let lastError: String?
    let source: DexcomSource
    let ingestMode: IngestMode
}

nonisolated struct WalkSummary: Codable, Hashable, Sendable {
    let startedAt: Date
    let endedAt: Date
    let minutes: Int
    let steps: Int
    let cadenceSpm: Int
    let intensity: WalkIntensity
    let forecastPeakDropMgDl: Double
    let effectSource: EffectSource
}

nonisolated struct Profile: Codable, Hashable, Sendable {
    let userId: String
    var displayName: String
    var highLineMgDl: Double
    var lowLineMgDl: Double
    var timezone: String
    var onboarded: Bool
}

nonisolated struct Health: Codable, Hashable, Sendable {
    /// "ok", "warming_up", or "error".
    let status: String
    let mode: GummiMode
    let version: String
}

/// `{"error": {"code", "message"}}` (CONTRACT section 1).
nonisolated struct APIErrorBody: Codable, Hashable, Sendable {
    nonisolated struct Detail: Codable, Hashable, Sendable {
        let code: String
        let message: String
    }
    let error: Detail
}
