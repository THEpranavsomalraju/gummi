import Foundation
import simd

/// Short animation clips layered on top of Gummi's mood posture: idle behaviors, reactions, and the dance.
nonisolated enum ClipKind: String, CaseIterable, Sendable {
    // Idle behaviors, picked every few seconds by mood.
    case lookAround, stretch, scratchHead, earTwitch, curiousTilt, doubleHop, wave, yawn, fanBurst, hugSelf
    // Reactions.
    case headTap, bellyTap, squishRelease
    case dance

    static let beat = 0.5 // 120 bpm

    var duration: Double {
        switch self {
        case .lookAround: 3.2
        case .stretch: 2.8
        case .scratchHead: 2.6
        case .earTwitch: 0.9
        case .curiousTilt: 2.4
        case .doubleHop: 1.5
        case .wave: 2.6
        case .yawn: 2.6
        case .fanBurst: 1.6
        case .hugSelf: 2.4
        case .headTap: 0.9
        case .bellyTap: 1.0
        case .squishRelease: 0.8
        case .dance: 12 * Self.beat
        }
    }

    var isIdle: Bool {
        switch self {
        case .headTap, .bellyTap, .squishRelease, .dance: false
        default: true
        }
    }

    /// Idle behaviors each mood picks from, with weights.
    static func idleChoices(for mood: Mood) -> [(ClipKind, Double)] {
        switch mood {
        case .calm, .unknown:
            [(.lookAround, 3), (.stretch, 1.5), (.scratchHead, 1.5), (.earTwitch, 2), (.curiousTilt, 1.5), (.doubleHop, 1), (.wave, 1)]
        case .rising: [(.lookAround, 2), (.earTwitch, 2), (.doubleHop, 2), (.curiousTilt, 1)]
        case .high: [(.fanBurst, 3), (.lookAround, 1), (.earTwitch, 1)]
        case .dipping: [(.yawn, 2), (.lookAround, 1), (.earTwitch, 1)]
        case .low: [(.hugSelf, 3), (.earTwitch, 1)]
        case .proud: [(.wave, 2), (.doubleHop, 2), (.stretch, 1)]
        case .happy: [(.doubleHop, 2), (.wave, 2), (.lookAround, 1)]
        case .sleepy: [(.yawn, 3), (.earTwitch, 1)]
        case .thinking: [(.scratchHead, 2), (.lookAround, 1)]
        }
    }
}

/// What a clip contributes this frame. Channel offsets add to the spring targets.
nonisolated struct ClipOutput: Sendable {
    var target = SIMD32<Float>(repeating: 0)
    var eyeOpenScale: Float = 1
    var eyeLook: SIMD2<Float>?
    var mouth: MouthShape?
    /// Spin that bypasses the springs.
    var yaw: Float = 0
}

/// A one-off velocity kick at a moment in a clip: hops, flicks, jiggles.
nonisolated struct ClipImpulse: Sendable {
    let at: Double
    let kicks: [(PoseChannel, Float)]
}

nonisolated extension ClipKind {
    /// The clip's pose at `s` seconds in. `side` is -1 or 1 for left/right variants.
    func evaluate(at s: Double, side: Float) -> ClipOutput {
        var out = ClipOutput()
        let p = s / duration
        let e = Self.envelope(p)
        switch self {
        case .lookAround:
            let yaw = Self.keyframes(p, [(0, 0), (0.22, -0.5 * side), (0.45, -0.5 * side), (0.68, 0.45 * side), (0.86, 0.45 * side), (1, 0)])
            let lead = Self.keyframes(min(p + 0.06, 1), [(0, 0), (0.22, -0.5 * side), (0.45, -0.5 * side), (0.68, 0.45 * side), (0.86, 0.45 * side), (1, 0)])
            out.target[.headYaw] = yaw
            out.target[.chestYaw] = yaw * 0.25
            out.eyeLook = SIMD2(lead / 0.5 * 0.9, 0.1)
        case .stretch:
            out.target[.leftArmPitch] = -2.7 * e
            out.target[.rightArmPitch] = -2.7 * e
            out.target[.leftArmRoll] = -0.25 * e
            out.target[.rightArmRoll] = 0.25 * e
            out.target[.rootY] = 0.012 * e
            out.target[.squash] = 0.09 * e
            out.target[.headPitch] = -0.18 * e
            out.eyeOpenScale = 1 - 0.85 * e
            if p > 0.25, p < 0.7 { out.mouth = .yawn }
        case .scratchHead:
            out.target[.rightArmPitch] = -2.5 * e
            out.target[.rightArmRoll] = (-0.55 + 0.13 * Float(sin(2 * .pi * 5 * s))) * e
            out.target[.headRoll] = -0.16 * e
            out.target[.leftArmRoll] = -0.08 * e
            out.eyeLook = SIMD2(0.45, 0.6) * e
            out.mouth = .flat
        case .earTwitch:
            out.target[.headRoll] = 0.05 * side * e
        case .curiousTilt:
            out.target[.headRoll] = 0.32 * side * e
            out.target[.hipsPitch] = 0.06 * e
            out.target[.chestYaw] = 0.1 * side * e
            out.eyeOpenScale = 1 + 0.15 * e
        case .doubleHop:
            out.target[.leftArmPitch] = -0.5 * e
            out.target[.rightArmPitch] = -0.5 * e
            out.mouth = .bigSmile
        case .wave:
            out.target[.rightArmPitch] = -2.3 * e
            out.target[.rightArmRoll] = (0.35 + 0.42 * Float(sin(2 * .pi * 2.4 * s))) * e
            out.target[.headRoll] = -0.12 * e
            out.target[.hipsRoll] = 0.04 * e
            out.eyeOpenScale = 1 - 0.3 * e
            out.mouth = .bigSmile
        case .yawn:
            out.target[.headPitch] = -0.18 * e
            out.target[.leftArmRoll] = -0.25 * e
            out.target[.rightArmRoll] = 0.25 * e
            out.target[.squash] = 0.05 * e
            out.eyeOpenScale = 1 - 0.9 * e
            if p > 0.15, p < 0.8 { out.mouth = .yawn }
        case .fanBurst:
            let flap = Float(sin(2 * .pi * 5 * s))
            out.target[.leftArmRoll] = (-0.35 - 0.35 * flap) * e
            out.target[.rightArmRoll] = (0.35 + 0.35 * flap) * e
            out.eyeOpenScale = 1 + 0.15 * e
            out.mouth = .flat
        case .hugSelf:
            out.target[.leftArmRoll] = 0.45 * e
            out.target[.rightArmRoll] = -0.45 * e
            out.target[.leftArmPitch] = -0.55 * e
            out.target[.rightArmPitch] = -0.55 * e
            out.target[.headPitch] = 0.1 * e
            out.mouth = .frown
        case .headTap:
            out.eyeOpenScale = p < 0.45 ? 0.1 : 1
            out.mouth = .bigSmile
        case .bellyTap:
            out.eyeOpenScale = 0.5
            out.mouth = .bigSmile
        case .squishRelease:
            out.mouth = .bigSmile
        case .dance:
            out = danceFrame(at: s)
        }
        return out
    }

    /// Velocity kicks for this clip. Springs turn them into hops, flicks, and jiggles with follow-through.
    func impulses(side: Float) -> [ClipImpulse] {
        switch self {
        case .earTwitch:
            [ClipImpulse(at: 0.02, kicks: [(side < 0 ? .leftEar : .rightEar, 7 * side)])]
        case .doubleHop:
            [0.25, 0.75].map { ClipImpulse(at: $0, kicks: [(.rootY, 0.55), (.squash, 1.3), (.leftEar, 3), (.rightEar, -3)]) }
                + [0.12, 0.62].map { ClipImpulse(at: $0, kicks: [(.squash, -0.9)]) }
        case .headTap:
            [ClipImpulse(at: 0, kicks: [(.headPitch, 3.5), (.leftEar, 8), (.rightEar, -8), (.squash, -0.8)])]
        case .bellyTap:
            [ClipImpulse(at: 0, kicks: [(.squash, -1.8), (.hipsRoll, 1.2 * side), (.leftArmRoll, -5), (.rightArmRoll, 5), (.rootY, 0.25)])]
        case .squishRelease:
            [ClipImpulse(at: 0, kicks: [(.squash, 2.2), (.rootY, 0.45), (.leftArmRoll, -4), (.rightArmRoll, 4), (.leftEar, 6), (.rightEar, -6)])]
        case .dance:
            (0..<12).map { beat in
                let t = Double(beat) * Self.beat
                return switch beat {
                case 0..<4: ClipImpulse(at: t, kicks: [(.squash, -1.0), (.rootY, 0.18)])
                case 6..<10: ClipImpulse(at: t, kicks: [(.rootY, 0.5), (.squash, 1.0), (.leftEar, 4), (.rightEar, -4)])
                default: ClipImpulse(at: t, kicks: [(.squash, -0.6)])
                }
            }
        default:
            []
        }
    }

    /// 120 bpm, 12 beats: sway with alternating arms, a spin with arms out, "yay" hops, a wiggle, and a ta-da.
    private func danceFrame(at s: Double) -> ClipOutput {
        var out = ClipOutput()
        let p = s / duration
        let e = Self.envelope(p, fade: 0.04)
        let beatIndex = Int(s / Self.beat)
        out.mouth = .bigSmile
        switch beatIndex {
        case 0..<4:
            let side: Float = beatIndex.isMultiple(of: 2) ? 1 : -1
            out.target[.hipsShift] = 0.012 * side
            out.target[.hipsRoll] = -0.14 * side
            out.target[.headRoll] = 0.1 * side
            if side > 0 {
                out.target[.rightArmPitch] = -2.3
                out.target[.rightArmRoll] = 0.4
            } else {
                out.target[.leftArmPitch] = -2.3
                out.target[.leftArmRoll] = -0.4
            }
        case 4..<6:
            let spin = (s - 4 * Self.beat) / (2 * Self.beat)
            out.yaw = 2 * .pi * Float(spin < 0.5 ? 2 * spin * spin : 1 - pow(-2 * spin + 2, 2) / 2)
            out.target[.leftArmRoll] = -1.2
            out.target[.rightArmRoll] = 1.2
            out.target[.squash] = 0.04
        case 6..<10:
            out.target[.leftArmPitch] = -2.4
            out.target[.rightArmPitch] = -2.4
            out.target[.leftArmRoll] = -0.6
            out.target[.rightArmRoll] = 0.6
            out.eyeOpenScale = 0.6
        default:
            let wiggle = Float(sin(2 * .pi * 4 * s))
            out.target[.chestYaw] = 0.3 * wiggle
            out.target[.hipsRoll] = -0.08 * wiggle
            out.target[.leftArmRoll] = -0.9
            out.target[.rightArmRoll] = 0.9
            out.target[.leftArmPitch] = -0.4
            out.target[.rightArmPitch] = -0.4
            out.eyeOpenScale = 0.6
        }
        out.target *= e
        return out
    }

    /// Fade in over the first part of a clip and out over the last part.
    static func envelope(_ p: Double, fade: Double = 0.15) -> Float {
        Float(smoothstep(0, fade, p) * (1 - smoothstep(1 - fade, 1, p)))
    }

    /// Smooth interpolation through (progress, value) keys.
    static func keyframes(_ p: Double, _ keys: [(Double, Float)]) -> Float {
        guard let upper = keys.firstIndex(where: { $0.0 >= p }) else { return keys.last?.1 ?? 0 }
        guard upper > 0 else { return keys[0].1 }
        let (p0, v0) = keys[upper - 1], (p1, v1) = keys[upper]
        let t = Float(smoothstep(p0, p1, p))
        return v0 + (v1 - v0) * t
    }

    static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        guard b > a else { return x >= b ? 1 : 0 }
        let t = min(max((x - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
    }
}

/// Smooth 1D value noise in -1...1, for idle life that never loops exactly.
nonisolated enum ValueNoise {
    static func sample(_ x: Double) -> Float {
        let i = floor(x)
        let f = x - i
        let a = hash(Int(i)), b = hash(Int(i) + 1)
        let t = f * f * (3 - 2 * f)
        return Float(a + (b - a) * t)
    }

    private static func hash(_ n: Int) -> Double {
        var z = UInt64(bitPattern: Int64(n)) &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z % 10_000) / 5_000 - 1
    }
}
