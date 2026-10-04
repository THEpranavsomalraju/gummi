import Foundation
import simd

/// Mouth shapes. Gummi never opens his mouth to talk; moods change the expression.
nonisolated enum MouthShape: CaseIterable, Sendable {
    case smile, bigSmile, flat, frown, yawn
}

/// Everything a renderer needs for one frame. Angles in radians, offsets in meters.
nonisolated struct PuppetPose: Equatable, Sendable {
    /// Whole-body offset (hops, bounces, shiver).
    var rootOffset = SIMD3<Float>(repeating: 0)
    /// Whole-body turn (the proud spin).
    var rootYaw: Float = 0
    /// Squash and stretch, applied from the seat up.
    var rootScale = SIMD3<Float>(repeating: 1)
    /// Breathing and puffing, applied to the body only.
    var bodyScale = SIMD3<Float>(repeating: 1)
    var bodyPitch: Float = 0
    var bodyRoll: Float = 0
    var headPitch: Float = 0
    var headYaw: Float = 0
    var headRoll: Float = 0
    var leftEarRoll: Float = 0
    var rightEarRoll: Float = 0
    var leftArmRoll: Float = 0
    var rightArmRoll: Float = 0
    var leftArmPitch: Float = 0
    var rightArmPitch: Float = 0
    /// 1 is open, 0 closed, above 1 wide.
    var eyeOpen: Float = 1
    /// Eye shift toward a look target, -1...1.
    var eyeLook = SIMD2<Float>(repeating: 0)
    var mouth: MouthShape = .smile
    /// Rim light color (linear-ish RGB, 0...1) and strength 0...1.
    var rimColor = SIMD3<Float>(repeating: 1)
    var rimStrength: Float = 0.5
}
