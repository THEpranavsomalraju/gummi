import Foundation

nonisolated struct GlucosePoint: Codable, Hashable, Sendable {
    let t: Date
    let glucoseMgDl: Double
    let kind: PointKind
}

nonisolated struct BandPoint: Codable, Hashable, Sendable {
    let t: Date
    let glucoseMgDl: Double
    let bandLowMgDl: Double
    let bandHighMgDl: Double
    let kind: PointKind
}

/// Gummi's estimate for now. Always shown with the label "Gummi's estimate".
nonisolated struct GummiView: Codable, Hashable, Sendable {
    let glucoseMgDl: Double
    let bandLowMgDl: Double
    let bandHighMgDl: Double
    let trend: Trend
    let asOf: Date
    let minutesSinceConfirmed: Int
    let confidence: Confidence
}
