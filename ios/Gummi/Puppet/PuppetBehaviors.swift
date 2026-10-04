import Foundation
import simd

/// Dances Gummi knows. Jelly Bop is his own; the rest are classic social dances built from their generic steps
/// (no routine copied from any video or game).
nonisolated enum Dance: String, CaseIterable, Sendable {
    case jellyBop, robot, runningMan, twist, discoPoint, sprinkler, cabbagePatch

    var title: String {
        switch self {
        case .jellyBop: "Jelly Bop"
        case .robot: "Robot"
        case .runningMan: "Running Man"
        case .twist: "Twist"
        case .discoPoint: "Disco Point"
        case .sprinkler: "Sprinkler"
        case .cabbagePatch: "Cabbage Patch"
        }
    }

    var clip: ClipKind {
        switch self {
        case .jellyBop: .jellyBop
        case .robot: .robot
        case .runningMan: .runningMan
        case .twist: .twist
        case .discoPoint: .discoPoint
        case .sprinkler: .sprinkler
        case .cabbagePatch: .cabbagePatch
        }
    }
}

/// Short animation clips layered on top of Gummi's mood posture: idle behaviors, reactions, and dances.
nonisolated enum ClipKind: String, CaseIterable, Sendable {
    // Idle behaviors, picked every few seconds by mood.
    case lookAround, stretch, scratchHead, earTwitch, curiousTilt, doubleHop, wave, yawn, fanBurst, hugSelf, toeTap, headBob
    // Reactions.
    case headTap, bellyTap, squishRelease
    // Dances.
    case jellyBop, robot, runningMan, twist, discoPoint, sprinkler, cabbagePatch

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
        case .toeTap: 2.0
        case .headBob: 2.4
        case .headTap: 0.9
        case .bellyTap: 1.0
        case .squishRelease: 0.8
        case .jellyBop: 12 * Self.beat
        case .robot, .runningMan, .twist, .discoPoint, .sprinkler, .cabbagePatch: 16 * Self.beat
        }
    }

    var beats: Int { isDance ? Int((duration / Self.beat).rounded()) : 0 }

    var isDance: Bool {
        switch self {
        case .jellyBop, .robot, .runningMan, .twist, .discoPoint, .sprinkler, .cabbagePatch: true
        default: false
        }
    }

    var isIdle: Bool {
        switch self {
        case .headTap, .bellyTap, .squishRelease: false
        default: !isDance
        }
    }

    /// Idle behaviors each mood picks from, with weights.
    static func idleChoices(for mood: Mood) -> [(ClipKind, Double)] {
        switch mood {
        case .calm, .unknown:
            [(.lookAround, 3), (.stretch, 1.5), (.scratchHead, 1.5), (.earTwitch, 1.5), (.curiousTilt, 1.5), (.doubleHop, 1),
             (.wave, 1), (.toeTap, 2), (.headBob, 1.5)]
        case .rising: [(.lookAround, 2), (.earTwitch, 1.5), (.doubleHop, 2), (.curiousTilt, 1), (.toeTap, 2), (.headBob, 1)]
        case .high: [(.fanBurst, 3), (.lookAround, 1), (.toeTap, 1.5)]
        case .dipping: [(.yawn, 2), (.lookAround, 1), (.earTwitch, 1)]
        case .low: [(.hugSelf, 3), (.earTwitch, 1)]
        case .proud: [(.wave, 2), (.doubleHop, 2), (.stretch, 1), (.headBob, 2)]
        case .happy: [(.doubleHop, 2), (.wave, 2), (.headBob, 2), (.toeTap, 1)]
        case .sleepy: [(.yawn, 3), (.earTwitch, 1)]
        case .thinking: [(.scratchHead, 2), (.lookAround, 1), (.toeTap, 1)]
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

/// A one-off velocity kick at a moment in a clip: hops, flicks, jiggles. Dance beats tap a haptic.
nonisolated struct ClipImpulse: Sendable {
    let at: Double
    let kicks: [(PoseChannel, Float)]
    var isBeat = false
}

/// Arm and head targets for a pose, so dance poses read like a list.
private nonisolated struct ArmPose {
    var pitch: Float = 0, roll: Float = 0, yaw: Float = 0
}

nonisolated extension ClipKind {
    /// The clip's pose at `s` seconds in. `side` is -1 or 1 for left/right variants.
    func evaluate(at s: Double, side: Float) -> ClipOutput {
        var out = ClipOutput()
        let p = s / duration
        let e = Self.envelope(p)
        switch self {
        case .lookAround:
            let keys: [(Double, Float)] = [(0, 0), (0.22, -0.7 * side), (0.45, -0.7 * side), (0.68, 0.65 * side), (0.86, 0.65 * side), (1, 0)]
            let yaw = Self.keyframes(p, keys)
            out.target[.headYaw] = yaw
            out.target[.headPitch] = -0.08 * e
            out.target[.chestYaw] = yaw * 0.3
            out.eyeLook = SIMD2(Self.keyframes(min(p + 0.06, 1), keys) / 0.7 * 0.9, 0.1)
        case .stretch:
            out.target[.leftArmPitch] = -2.8 * e
            out.target[.rightArmPitch] = -2.8 * e
            out.target[.leftArmRoll] = -0.35 * e
            out.target[.rightArmRoll] = 0.35 * e
            out.target[.rootY] = 0.014 * e
            out.target[.squash] = 0.1 * e
            out.target[.headPitch] = -0.28 * e
            out.target[.leftLegLift] = 0.006 * e
            out.target[.rightLegLift] = 0.006 * e
            out.eyeOpenScale = 1 - 0.85 * e
            if p > 0.25, p < 0.7 { out.mouth = .yawn }
        case .scratchHead:
            out.target[.rightArmPitch] = -2.6 * e
            out.target[.rightArmRoll] = (-0.5 + 0.15 * Float(sin(2 * .pi * 5 * s))) * e
            out.target[.headRoll] = -0.28 * e
            out.target[.headPitch] = 0.06 * e
            out.target[.leftArmRoll] = -0.1 * e
            out.target[.leftLegRoll] = -0.1 * e
            out.eyeLook = SIMD2(0.45, 0.6) * e
            out.mouth = .flat
        case .earTwitch:
            out.target[.headRoll] = 0.08 * side * e
        case .curiousTilt:
            out.target[.headRoll] = 0.42 * side * e
            out.target[.headYaw] = 0.15 * side * e
            out.target[.hipsPitch] = 0.07 * e
            out.target[.chestYaw] = 0.12 * side * e
            out.target[side < 0 ? .leftLegPitch : .rightLegPitch] = -0.18 * e
            out.eyeOpenScale = 1 + 0.15 * e
        case .doubleHop:
            out.target[.leftArmPitch] = -0.7 * e
            out.target[.rightArmPitch] = -0.7 * e
            out.target[.leftArmRoll] = -0.3 * e
            out.target[.rightArmRoll] = 0.3 * e
            out.mouth = .bigSmile
        case .wave:
            out.target[.rightArmPitch] = -2.5 * e
            out.target[.rightArmRoll] = (0.4 + 0.45 * Float(sin(2 * .pi * 2.4 * s))) * e
            out.target[.headRoll] = -0.2 * e
            out.target[.headYaw] = 0.12 * e
            out.target[.hipsRoll] = 0.05 * e
            out.target[.leftLegLift] = 0.008 * e
            out.eyeOpenScale = 1 - 0.3 * e
            out.mouth = .bigSmile
        case .yawn:
            out.target[.headPitch] = -0.28 * e
            out.target[.leftArmRoll] = -0.35 * e
            out.target[.rightArmRoll] = 0.35 * e
            out.target[.squash] = 0.05 * e
            out.eyeOpenScale = 1 - 0.9 * e
            if p > 0.15, p < 0.8 { out.mouth = .yawn }
        case .fanBurst:
            let flap = Float(sin(2 * .pi * 5 * s))
            out.target[.leftArmRoll] = (-0.4 - 0.4 * flap) * e
            out.target[.rightArmRoll] = (0.4 + 0.4 * flap) * e
            out.target[.headYaw] = 0.15 * flap * e
            out.eyeOpenScale = 1 + 0.15 * e
            out.mouth = .flat
        case .hugSelf:
            out.target[.leftArmRoll] = 0.4 * e
            out.target[.rightArmRoll] = -0.4 * e
            out.target[.leftArmPitch] = -0.8 * e
            out.target[.rightArmPitch] = -0.8 * e
            out.target[.leftArmYaw] = 0.4 * e
            out.target[.rightArmYaw] = -0.4 * e
            out.target[.headPitch] = 0.16 * e
            out.target[.leftLegRoll] = 0.06 * e
            out.target[.rightLegRoll] = -0.06 * e
            out.mouth = .frown
        case .toeTap:
            let tap = Float(abs(sin(.pi * 3 * p)))
            out.target[side < 0 ? .leftLegPitch : .rightLegPitch] = -0.3 * e
            out.target[side < 0 ? .leftLegLift : .rightLegLift] = 0.014 * tap * e
            out.target[.hipsShift] = -0.006 * side * e
            out.target[.headPitch] = 0.1 * tap * e
            out.target[.headRoll] = 0.12 * side * e
            out.eyeLook = SIMD2(0.1 * side, -0.5) * e
        case .headBob:
            let bob = Float(max(0, sin(2 * .pi * 2 * s)))
            let sway: Float = Int(s * 2).isMultiple(of: 2) ? 1 : -1
            out.target[.headPitch] = 0.24 * bob * e
            out.target[.headRoll] = 0.16 * sway * e
            out.target[.hipsRoll] = -0.05 * sway * e
            out.target[.squash] = -0.04 * bob * e
            out.target[.leftArmRoll] = -0.12 * bob * e
            out.target[.rightArmRoll] = 0.12 * bob * e
            out.eyeOpenScale = 1 - 0.4 * e
            out.mouth = .bigSmile
        case .headTap:
            out.eyeOpenScale = p < 0.45 ? 0.1 : 1
            out.mouth = .bigSmile
        case .bellyTap:
            out.eyeOpenScale = 0.5
            out.mouth = .bigSmile
        case .squishRelease:
            out.mouth = .bigSmile
        case .jellyBop, .robot, .runningMan, .twist, .discoPoint, .sprinkler, .cabbagePatch:
            out = danceFrame(at: s)
        }
        return out
    }

    /// Velocity kicks for this clip. Springs turn them into hops, flicks, and jiggles with follow-through.
    func impulses(side: Float) -> [ClipImpulse] {
        let beatTimes = (0..<beats).map { Double($0) * Self.beat }
        func onBeats(_ kicks: [(PoseChannel, Float)]) -> [ClipImpulse] {
            beatTimes.map { ClipImpulse(at: $0, kicks: kicks, isBeat: true) }
        }
        switch self {
        case .earTwitch:
            return [ClipImpulse(at: 0.02, kicks: [(side < 0 ? .leftEar : .rightEar, 7 * side)])]
        case .doubleHop:
            return [0.25, 0.75].map { ClipImpulse(at: $0, kicks: [(.rootY, 0.6), (.squash, 1.3), (.leftEar, 3), (.rightEar, -3),
                                                                (.leftLegPitch, -2.5), (.rightLegPitch, -2.5)]) }
                + [0.12, 0.62].map { ClipImpulse(at: $0, kicks: [(.squash, -0.9), (.headPitch, 1)]) }
        case .headTap:
            return [ClipImpulse(at: 0, kicks: [(.headPitch, 4.5), (.leftEar, 8), (.rightEar, -8), (.squash, -0.8)])]
        case .bellyTap:
            return [ClipImpulse(at: 0, kicks: [(.squash, -1.8), (.hipsRoll, 1.2 * side), (.leftArmRoll, -5), (.rightArmRoll, 5),
                                               (.rootY, 0.25), (.leftLegRoll, -2), (.rightLegRoll, 2), (.headPitch, -1.5)])]
        case .squishRelease:
            return [ClipImpulse(at: 0, kicks: [(.squash, 2.2), (.rootY, 0.45), (.leftArmRoll, -4), (.rightArmRoll, 4),
                                               (.leftEar, 6), (.rightEar, -6), (.headPitch, -2)])]
        case .jellyBop:
            return beatTimes.enumerated().map { beat, t in
                switch beat {
                case 0..<4: ClipImpulse(at: t, kicks: [(.squash, -1.0), (.rootY, 0.18), (.headPitch, 1.4)], isBeat: true)
                case 6..<10: ClipImpulse(at: t, kicks: [(.rootY, 0.55), (.squash, 1.0), (.leftEar, 4), (.rightEar, -4),
                                                        (.leftLegPitch, -3), (.rightLegPitch, -3)], isBeat: true)
                default: ClipImpulse(at: t, kicks: [(.squash, -0.6), (.headPitch, 1)], isBeat: true)
                }
            }
        case .robot:
            return onBeats([(.squash, -0.45), (.headPitch, 0.6)])
        case .runningMan:
            // A step every half beat; the beat steps tap the haptic.
            return (0..<(beats * 2)).map { step in
                ClipImpulse(at: Double(step) * Self.beat / 2, kicks: [(.rootY, 0.22), (.squash, -0.5), (.headPitch, 0.9)],
                            isBeat: step.isMultiple(of: 2))
            }
        case .twist:
            return onBeats([(.headPitch, 0.8), (.leftEar, 2), (.rightEar, -2)])
        case .discoPoint:
            return onBeats([(.squash, -0.6), (.rootY, 0.12), (.headPitch, 0.7)])
        case .sprinkler:
            // A click every half beat while sprinkling.
            return (0..<(beats * 2)).map { step in
                ClipImpulse(at: Double(step) * Self.beat / 2, kicks: [(.squash, -0.35), (.rootY, 0.06), (.headPitch, 0.5)],
                            isBeat: step.isMultiple(of: 2))
            }
        case .cabbagePatch:
            return onBeats([(.squash, -0.6), (.rootY, 0.1), (.headPitch, 1.1)])
        default:
            return []
        }
    }

    // MARK: Dances

    private func danceFrame(at s: Double) -> ClipOutput {
        var out = ClipOutput()
        let beat = Int(s / Self.beat)
        let phase = s / Self.beat - Double(beat)
        out.mouth = .bigSmile
        switch self {
        case .jellyBop: jellyBop(&out, s: s, beat: beat)
        case .robot: robot(&out, beat: beat)
        case .runningMan: runningMan(&out, s: s)
        case .twist: twist(&out, s: s)
        case .discoPoint: discoPoint(&out, beat: beat, phase: phase)
        case .sprinkler: sprinkler(&out, s: s, beat: beat)
        case .cabbagePatch: cabbagePatch(&out, s: s, beat: beat)
        default: break
        }
        // Every routine ends on a "ta-da": arms out, big smile.
        if beat == beats - 1, self != .jellyBop {
            out.target[.leftArmPitch] = -0.5
            out.target[.rightArmPitch] = -0.5
            out.target[.leftArmRoll] = -0.9
            out.target[.rightArmRoll] = 0.9
            out.target[.leftArmYaw] = 0
            out.target[.rightArmYaw] = 0
            out.target[.headPitch] = -0.15
            out.mouth = .bigSmile
            out.eyeOpenScale = 0.6
        }
        out.target *= Self.envelope(s / duration, fade: 0.04)
        return out
    }

    private func setArms(_ out: inout ClipOutput, left: ArmPose, right: ArmPose) {
        out.target[.leftArmPitch] = left.pitch
        out.target[.leftArmRoll] = left.roll
        out.target[.leftArmYaw] = left.yaw
        out.target[.rightArmPitch] = right.pitch
        out.target[.rightArmRoll] = right.roll
        out.target[.rightArmYaw] = right.yaw
    }

    /// Gummi's own: sway with alternating arm pumps, a spin, "yay" hops, a wiggle.
    private func jellyBop(_ out: inout ClipOutput, s: Double, beat: Int) {
        switch beat {
        case 0..<4:
            let side: Float = beat.isMultiple(of: 2) ? 1 : -1
            out.target[.hipsShift] = 0.014 * side
            out.target[.hipsRoll] = -0.16 * side
            out.target[.headRoll] = 0.22 * side
            out.target[side > 0 ? .leftLegLift : .rightLegLift] = 0.02
            out.target[side > 0 ? .leftLegRoll : .rightLegRoll] = -0.15 * side
            if side > 0 {
                out.target[.rightArmPitch] = -2.5
                out.target[.rightArmRoll] = 0.45
            } else {
                out.target[.leftArmPitch] = -2.5
                out.target[.leftArmRoll] = -0.45
            }
        case 4..<6:
            let spin = (s - 4 * Self.beat) / (2 * Self.beat)
            out.yaw = 2 * .pi * Float(spin < 0.5 ? 2 * spin * spin : 1 - pow(-2 * spin + 2, 2) / 2)
            setArms(&out, left: ArmPose(pitch: -0.3, roll: -1.25), right: ArmPose(pitch: -0.3, roll: 1.25))
            out.target[.leftLegRoll] = -0.12
            out.target[.rightLegRoll] = 0.12
            out.target[.squash] = 0.04
            out.target[.headPitch] = -0.15
        case 6..<10:
            setArms(&out, left: ArmPose(pitch: -2.5, roll: -0.6), right: ArmPose(pitch: -2.5, roll: 0.6))
            out.target[.headPitch] = -0.2
            out.eyeOpenScale = 0.6
        default:
            let wiggle = Float(sin(2 * .pi * 4 * s))
            out.target[.chestYaw] = 0.35 * wiggle
            out.target[.hipsRoll] = -0.1 * wiggle
            out.target[.headYaw] = -0.25 * wiggle
            out.target[.leftLegRoll] = -0.14 * wiggle
            out.target[.rightLegRoll] = -0.14 * wiggle
            setArms(&out, left: ArmPose(pitch: -0.5, roll: -0.9), right: ArmPose(pitch: -0.5, roll: 0.9))
            out.eyeOpenScale = 0.6
        }
    }

    /// The Robot: a new stiff pose on every beat, head snapping to match, little marching steps.
    private func robot(_ out: inout ClipOutput, beat: Int) {
        let forward = ArmPose(pitch: -1.57), up = ArmPose(pitch: -3.0), down = ArmPose()
        let poses: [(ArmPose, ArmPose, yaw: Float, pitch: Float, roll: Float, chest: Float)] = [
            (forward, forward, 0, 0, 0, 0),
            (forward, ArmPose(pitch: -3.0, roll: 0.1), -0.5, 0, 0, 0),
            (ArmPose(roll: -1.45), ArmPose(roll: 1.45), 0.5, 0, 0, 0),
            (up, ArmPose(pitch: -0.3), 0, 0, 0.35, 0),
            (ArmPose(pitch: -1.57, yaw: 0.6), ArmPose(pitch: -1.57, yaw: 0.6), 0.5, 0, 0, 0.4),
            (ArmPose(pitch: -1.57, yaw: -0.6), ArmPose(pitch: -1.57, yaw: -0.6), -0.5, 0, 0, -0.4),
            (down, down, 0, 0.3, 0, 0),
            (up, up, 0, -0.25, 0, 0),
        ]
        let pose = poses[beat % poses.count]
        setArms(&out, left: pose.0, right: pose.1)
        out.target[.headYaw] = pose.yaw
        out.target[.headPitch] = pose.pitch
        out.target[.headRoll] = pose.roll
        out.target[.chestYaw] = pose.chest
        if !beat.isMultiple(of: 2) {
            out.target[beat % 4 == 1 ? .leftLegLift : .rightLegLift] = 0.016
            out.target[beat % 4 == 1 ? .leftLegPitch : .rightLegPitch] = -0.25
        }
        out.eyeOpenScale = 1.1
        out.mouth = beat < beats - 2 ? .flat : .bigSmile
    }

    /// Running Man: one knee lifts while the other foot slides back, every half beat, arms pumping opposite.
    private func runningMan(_ out: inout ClipOutput, s: Double) {
        let stepLength = Self.beat / 2
        let step = Int(s / stepLength)
        let phase = Float(s / stepLength - Double(step))
        let leftUp = step.isMultiple(of: 2)
        let lift = 0.032 * sin(.pi * phase)
        out.target[leftUp ? .leftLegLift : .rightLegLift] = lift
        out.target[leftUp ? .leftLegPitch : .rightLegPitch] = -0.55 * sin(.pi * phase)
        out.target[leftUp ? .rightLegPitch : .leftLegPitch] = 0.45 * sin(.pi * phase)
        let pump: Float = leftUp ? 1 : -1
        setArms(&out, left: ArmPose(pitch: -0.4 + 0.75 * pump, roll: -0.25), right: ArmPose(pitch: -0.4 - 0.75 * pump, roll: 0.25))
        out.target[.chestPitch] = 0.08
        out.target[.chestYaw] = 0.12 * pump
        out.target[.headRoll] = 0.08 * pump
    }

    /// The Twist: shoulders swivel one way while the arms swing the other, sinking low and coming back up.
    private func twist(_ out: inout ClipOutput, s: Double) {
        let swivel = Float(sin(2 * .pi * s / Self.beat))
        out.target[.chestYaw] = 0.45 * swivel
        out.target[.hipsShift] = 0.006 * swivel
        out.target[.hipsRoll] = 0.06 * swivel
        out.target[.leftLegRoll] = -0.14 * swivel
        out.target[.rightLegRoll] = -0.14 * swivel
        out.target[.leftLegPitch] = -0.1 * swivel
        out.target[.rightLegPitch] = 0.1 * swivel
        out.target[.squash] = -0.12 * Float(sin(.pi * s / duration))
        setArms(&out, left: ArmPose(pitch: -0.9, roll: -0.3, yaw: -0.6 * swivel), right: ArmPose(pitch: -0.9, roll: 0.3, yaw: -0.6 * swivel))
        out.target[.headYaw] = -0.3 * swivel
    }

    /// Disco Point: one arm points up and out, then down and across, hand on hip with the other; switches halfway.
    private func discoPoint(_ out: inout ClipOutput, beat: Int, phase: Double) {
        let rightPoints = beat < beats / 2
        let up = beat.isMultiple(of: 2)
        let sign: Float = rightPoints ? 1 : -1
        let pointing = up ? ArmPose(pitch: -2.7, roll: 0.7 * sign) : ArmPose(pitch: -0.8, roll: -0.5 * sign, yaw: -0.5 * sign)
        let onHip = ArmPose(pitch: 0.15, roll: -0.55 * sign)
        if rightPoints { setArms(&out, left: onHip, right: pointing) } else { setArms(&out, left: pointing, right: onHip) }
        out.target[.hipsShift] = (up ? 0.012 : -0.006) * sign
        out.target[.hipsRoll] = (up ? -0.1 : 0.05) * sign
        out.target[.headYaw] = (up ? 0.4 : -0.25) * sign
        out.target[.headPitch] = up ? -0.3 : 0.18
        if up {
            out.target[rightPoints ? .leftLegLift : .rightLegLift] = 0.014
            out.target[rightPoints ? .leftLegRoll : .rightLegRoll] = -0.14 * sign
        }
        out.eyeLook = up ? SIMD2(0.7 * sign, 0.8) : SIMD2(-0.5 * sign, -0.5)
    }

    /// Sprinkler: one hand behind the head, the other arm clicks across in steps, then sweeps back; switches halfway.
    private func sprinkler(_ out: inout ClipOutput, s: Double, beat: Int) {
        let sign: Float = beat < beats / 2 ? 1 : -1
        let cycleTime = s.truncatingRemainder(dividingBy: 4 * Self.beat)
        let sweepBack = cycleTime >= 3 * Self.beat
        let yaw: Float
        if sweepBack {
            let back = Float((cycleTime - 3 * Self.beat) / Self.beat)
            yaw = -0.7 + 1.4 * back
        } else {
            let click = Int(cycleTime / (Self.beat / 2))
            yaw = 0.7 - 1.4 * Float(click) / 5
        }
        // The resting hand tucks behind the head: raised and rolled inward.
        let sprinkling = ArmPose(pitch: -1.5, roll: 0.2 * sign, yaw: yaw * sign)
        if sign > 0 {
            setArms(&out, left: ArmPose(pitch: -2.8, roll: 0.9), right: sprinkling)
        } else {
            setArms(&out, left: sprinkling, right: ArmPose(pitch: -2.8, roll: -0.9))
        }
        out.target[.chestYaw] = 0.5 * yaw * sign
        out.target[.headYaw] = 0.65 * yaw * sign
        out.target[.headRoll] = 0.12 * sign
        let stepUp = Int(cycleTime / (Self.beat / 2)).isMultiple(of: 2)
        out.target[stepUp ? .leftLegLift : .rightLegLift] = 0.01
    }

    /// Cabbage Patch: fists stir a circle in front of the chest while the body rocks along and the knees bounce.
    private func cabbagePatch(_ out: inout ClipOutput, s: Double, beat: Int) {
        let angle = 2 * Double.pi * s / (2 * Self.beat)
        let c = Float(cos(angle)), sn = Float(sin(angle))
        setArms(&out, left: ArmPose(pitch: -1.25 + 0.35 * sn, roll: 0.25, yaw: 0.35 * c),
                right: ArmPose(pitch: -1.25 + 0.35 * sn, roll: -0.25, yaw: 0.35 * c))
        out.target[.hipsShift] = 0.009 * c
        out.target[.hipsRoll] = -0.09 * c
        out.target[.chestYaw] = 0.18 * c
        out.target[.headRoll] = 0.18 * c
        out.target[beat.isMultiple(of: 2) ? .leftLegLift : .rightLegLift] = 0.012
    }

    // MARK: Helpers

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
