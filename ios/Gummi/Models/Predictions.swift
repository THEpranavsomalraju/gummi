import Foundation

nonisolated struct Prediction: Codable, Hashable, Sendable, Identifiable {
    let predictionId: String
    let kind: PredictionKind
    let madeAt: Date
    let about: String
    let mealId: String?
    let windowStart: Date
    let windowEnd: Date
    let predictedPeakMgDl: Double
    let predictedCurve: [BandPoint]
    /// Null until a CGM-only curve exists (1.3).
    let cgmOnlyPeakMgDl: Double?
    let lastValuePeakMgDl: Double
    let status: PredictionStatus

    var id: String { predictionId }
}

nonisolated struct Grade: Codable, Hashable, Sendable, Identifiable {
    let gradeId: String
    let predictionId: String
    let kind: PredictionKind
    let gradedAt: Date
    let points: Int
    let gummiMaeMgDl: Double
    /// Null when no CGM-only curve was stored (1.3).
    let cgmOnlyMaeMgDl: Double?
    let lastValueMaeMgDl: Double
    let gummiPeakErrorMgDl: Double
    let withinBandPct: Double
    /// False when the window overlaps a phone walk on replayed data: show "Walk effect not graded (replayed data)".
    let walkEffectGraded: Bool
    /// Nullable in backend models.py when CGM-only is missing (CCR item 1). Null means not proud.
    let gummiBeatsCgmOnly: Bool?
    let gummiBeatsLastValue: Bool
    let message: String

    var id: String { gradeId }

    /// Proud plays only when Gummi beats CGM-only (CONTRACT 1.3).
    var earnsProud: Bool { gummiBeatsCgmOnly == true }
}
