import Foundation

/// Pairs a replay time with a wall-clock time. Null fields while the stream is stopped.
nonisolated struct ReplayAnchor: Codable, Hashable, Sendable {
    let replayTime: Date?
    let wallTime: Date?
}

nonisolated struct StreamStatus: Codable, Hashable, Sendable {
    let running: Bool
    let paused: Bool
    let speed: Double
    let delayMinutes: Int
    let participants: Int
    /// Display only, for example "day6T08:15". Null when stopped.
    let replayClock: String?
    let replayAnchor: ReplayAnchor
    let eventsReleased: Int
    let eventsPerSecond: Double
    let pipelineLagSeconds: Double?

    /// Wall-clock time at which `replayTime` happens, from the anchor and speed. Nil while stopped or paused.
    func wallTime(forReplay replayTime: Date) -> Date? {
        guard running, !paused, speed > 0,
              let anchorReplay = replayAnchor.replayTime, let anchorWall = replayAnchor.wallTime else { return nil }
        return anchorWall.addingTimeInterval(replayTime.timeIntervalSince(anchorReplay) / speed)
    }
}

nonisolated struct FleetEntry: Codable, Hashable, Sendable, Identifiable {
    let userId: String
    let displayName: String
    let mood: Mood
    let dataThrough: Date?
    let sparkline: [GlucosePoint]
    let grades: Int
    let gummiMaeMgDl: Double?
    let cgmOnlyMaeMgDl: Double?
    let lastValueMaeMgDl: Double?
    let lastGrade: Grade?

    var id: String { userId }
}

nonisolated struct Fleet: Codable, Hashable, Sendable {
    let entries: [FleetEntry]
    let fleetGummiMaeMgDl: Double?
    let fleetCgmOnlyMaeMgDl: Double?
    let fleetLastValueMaeMgDl: Double?
    let stream: StreamStatus
}
