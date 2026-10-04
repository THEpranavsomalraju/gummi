import Foundation
import simd

/// Mouth shapes. Gummi never opens his mouth to talk; moods and moments change the expression (anime / Mii style).
nonisolated enum MouthShape: CaseIterable, Sendable {
    case smile, bigSmile, flat, frown, yawn
    /// An open "D" grin for happy and proud moments.
    case grin
    /// A small "o" for surprise.
    case surprised
    /// A wobbly line for worry.
    case wavy
}

/// Eye shapes: anime and Mii faces read through the eyes.
nonisolated enum EyeShape: CaseIterable, Sendable {
    /// Glossy ovals with highlights; they blink and follow the finger.
    case open
    /// "^ ^" happy arcs.
    case happy
    /// "- -" sleepy lines.
    case sleepy
    /// "> <" squeezed shut.
    case squeeze
    /// Wide with extra sparkle (proud).
    case sparkle
    /// Small worried dots.
    case small
}

/// Everything a renderer needs for one frame, as joint motions on Gummi's skeleton (KoalaBone).
/// Angles in radians, offsets in meters.
nonisolated struct PuppetPose: Equatable, Sendable {
    /// Whole body: hops and shiver; the proud and dance spins; squash (< 0) and stretch (> 0) from the feet.
    var rootOffset = SIMD3<Float>(repeating: 0)
    var rootYaw: Float = 0
    var squash: Float = 0
    /// Lower body over the legs: weight shift, sway, lean.
    var hipsShift: Float = 0
    var hipsRoll: Float = 0
    var hipsPitch: Float = 0
    var chestYaw: Float = 0
    var chestPitch: Float = 0
    var breath: Float = 0
    var puff: Float = 0
    var headPitch: Float = 0
    var headYaw: Float = 0
    var headRoll: Float = 0
    var leftEarRoll: Float = 0
    var rightEarRoll: Float = 0
    var leftArmRoll: Float = 0
    var leftArmPitch: Float = 0
    /// Swings a raised arm across the body (pointing, stirring, sprinkling).
    var leftArmYaw: Float = 0
    var rightArmRoll: Float = 0
    var rightArmPitch: Float = 0
    var rightArmYaw: Float = 0
    var leftLegLift: Float = 0
    var rightLegLift: Float = 0
    /// Kicks forward (< 0) and back (> 0).
    var leftLegPitch: Float = 0
    var rightLegPitch: Float = 0
    /// Side kicks: outward is negative for the left leg, positive for the right.
    var leftLegRoll: Float = 0
    var rightLegRoll: Float = 0
    /// 1 is open, 0 closed, above 1 wide.
    var eyeOpen: Float = 1
    /// Eye shift toward a look target, -1...1.
    var eyeLook = SIMD2<Float>(repeating: 0)
    var mouth: MouthShape = .smile
    var eyes: EyeShape = .open
    /// Brows: tilt -1 (furrowed, inner ends down) to 1 (worried, inner ends up); raise -1 (low) to 1 (high).
    var browTilt: Float = 0
    var browRaise: Float = 0
    /// Cheek blush, 0 (none) to 1.
    var blush: Float = 0
    /// Rim light color (0...1 RGB) and strength 0...1.
    var rimColor = SIMD3<Float>(repeating: 1)
    var rimStrength: Float = 0.5
}

/// The spring-driven pose channels, one SIMD32 lane each.
nonisolated enum PoseChannel: Int, CaseIterable, Sendable {
    case rootX, rootY, rootZ, hipsShift, hipsRoll, hipsPitch, chestYaw, chestPitch
    case headPitch, headYaw, headRoll, leftEar, rightEar
    case leftArmRoll, leftArmPitch, rightArmRoll, rightArmPitch, leftArmYaw, rightArmYaw
    case leftLegLift, rightLegLift, leftLegPitch, rightLegPitch, leftLegRoll, rightLegRoll, squash, puff
}

nonisolated extension SIMD32 where Scalar == Float {
    subscript(_ channel: PoseChannel) -> Float {
        get { self[channel.rawValue] }
        set { self[channel.rawValue] = newValue }
    }
}

/// Underdamped springs on every channel: motion overshoots and settles like jelly instead of moving on rails.
nonisolated struct ChannelSprings: Equatable, Sendable {
    var value = SIMD32<Float>(repeating: 0)
    var velocity = SIMD32<Float>(repeating: 0)
    private var stiffness = SIMD32<Float>(repeating: 0)
    private var damping = SIMD32<Float>(repeating: 0)

    init() {
        for channel in PoseChannel.allCases {
            let (omega, zeta): (Float, Float) = switch channel {
            case .rootX, .rootY, .rootZ: (20, 0.5)
            case .hipsShift, .hipsRoll, .hipsPitch, .chestYaw, .chestPitch: (12, 0.45)
            case .headPitch, .headYaw, .headRoll: (13, 0.42)
            case .leftEar, .rightEar: (15, 0.18)
            case .leftArmRoll, .leftArmPitch, .rightArmRoll, .rightArmPitch, .leftArmYaw, .rightArmYaw: (11, 0.34)
            case .leftLegLift, .rightLegLift, .leftLegPitch, .rightLegPitch, .leftLegRoll, .rightLegRoll: (17, 0.42)
            case .squash: (17, 0.22)
            case .puff: (8, 0.6)
            }
            stiffness[channel] = omega * omega
            damping[channel] = 2 * zeta * omega
        }
    }

    mutating func step(toward target: SIMD32<Float>, dt: Float) {
        let substeps = max(1, Int((dt * 120).rounded(.up)))
        let h = dt / Float(substeps)
        for _ in 0..<substeps {
            velocity += (stiffness * (target - value) - damping * velocity) * h
            value += velocity * h
        }
    }

    mutating func kick(_ channel: PoseChannel, _ amount: Float) {
        velocity[channel] += amount
    }
}
