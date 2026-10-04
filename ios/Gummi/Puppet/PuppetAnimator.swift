import Foundation
import simd

/// Small seedable RNG so blinks and idle choices are testable.
nonisolated struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// A clip that is playing: when it started, and which side it favors.
nonisolated struct ActiveClip: Sendable {
    let kind: ClipKind
    let start: Double
    let side: Float
    var elapsed: Double = 0
}

/// Gummi's motion as a pure function of time and input. The renderer calls `step` every frame and applies the pose.
/// Layers, bottom to top: mood posture, continuous life (breath, weight shifts, swinging arms), idle behaviors or the
/// dance, reactions, then springs on every channel so everything overshoots and settles like jelly.
nonisolated struct PuppetAnimator: Sendable {
    static let blinkInterval: ClosedRange<Double> = 3...6
    static let blinkDuration = 0.16
    static let spinDuration = 1.2
    static let idleGap: ClosedRange<Double> = 4...9

    var input = PuppetInput()
    private(set) var time: Double = 0
    private(set) var pose = PuppetPose()
    private(set) var style = MoodStyle.of(.calm)
    private(set) var springs = ChannelSprings()
    /// Idle behavior or the dance.
    private(set) var motion: ActiveClip?
    /// Taps, squish release, wave hello.
    private(set) var reaction: ActiveClip?
    private(set) var nextIdleAt: Double
    private(set) var idleLog: [(kind: ClipKind, start: Double)] = []
    private(set) var danceBeats = 0
    private(set) var lastDance: Dance?
    private(set) var spinStartedAt: Double?
    private(set) var nextBlinkAt: Double
    private(set) var blinkTimes: [Double] = []
    private var blinkStartedAt: Double?
    private var lookSmoothed = SIMD2<Float>(repeating: 0)
    private var browTilt: Float = 0
    private var browRaise: Float = 0
    private var blush: Float = 0
    private var talkAmount: Float = 0
    private var thinkAmount: Float = 0
    private var currentMood: Mood = .calm
    private var wasPressing = false
    private var rng: SplitMix64

    init(seed: UInt64 = UInt64.random(in: 1...UInt64.max)) {
        rng = SplitMix64(seed: seed)
        nextBlinkAt = Double.random(in: Self.blinkInterval, using: &rng)
        nextIdleAt = Double.random(in: 2.5...4, using: &rng)
    }

    mutating func react(_ reaction: PuppetReaction) {
        switch reaction {
        case .tap(.head): self.reaction = start(.headTap)
        case .tap(.belly): self.reaction = start(.bellyTap)
        case .wave: self.reaction = start(.wave)
        case .dance(let dance): startDance(dance)
        case .cheer:
            self.reaction = start(.cheer)
            spinStartedAt = time
        case .nod: self.reaction = start(.nod)
        }
    }

    /// True while Gummi is moving a lot or someone is touching him (the chat bubble steps aside).
    var isBusy: Bool {
        if reaction != nil || spinStartedAt != nil || input.pressing || input.look != nil { return true }
        guard let kind = motion?.kind else { return false }
        return kind.isDance || [.doubleHop, .stretch, .wave, .fanBurst, .headBob].contains(kind)
    }

    /// Starts an idle behavior now (tests and the playground).
    mutating func forceIdle(_ kind: ClipKind) {
        motion = start(kind)
        idleLog.append((kind, time))
    }

    private mutating func startDance(_ requested: Dance?) {
        let dance = requested ?? Dance.allCases.filter { $0 != lastDance }.randomElement(using: &rng) ?? .jellyBop
        lastDance = dance
        motion = start(dance.clip)
    }

    @discardableResult
    mutating func step(dt rawDt: Double) -> PuppetPose {
        let dt = min(max(rawDt, 0), 1.0 / 20)
        time += dt
        let t = time
        let fdt = Float(dt)

        if input.mood != currentMood {
            currentMood = input.mood
            if currentMood == .proud { spinStartedAt = time }
            if currentMood == .happy { startDance(nil) }
        }
        style.blend(toward: MoodStyle.of(input.thinking ? .thinking : input.mood), dt: fdt)

        let k = 1 - exp(-fdt * 4 / 0.6)
        talkAmount += ((input.talking ? 1 : 0) - talkAmount) * k
        thinkAmount += ((input.thinking ? 1 : 0) - thinkAmount) * k
        let lookTarget = input.look.map { simd_clamp($0, SIMD2(-1, -1), SIMD2(1, 1)) } ?? .zero
        lookSmoothed += (lookTarget - lookSmoothed) * (1 - exp(-fdt * 10))

        // Squish while pressed; bounce on release.
        if wasPressing, !input.pressing { reaction = start(.squishRelease) }
        wasPressing = input.pressing

        scheduleIdle()

        var target = baseTarget(at: t)
        var motionClip = motion, reactionClip = reaction
        let motionOut = advance(&motionClip, dt: dt)
        let reactionOut = advance(&reactionClip, dt: dt)
        motion = motionClip
        reaction = reactionClip
        target += motionOut?.target ?? .zero
        target += reactionOut?.target ?? .zero
        springs.step(toward: target, dt: fdt)

        var p = PuppetPose()
        let v = springs.value
        let shiver = style.shiver * sin(2 * .pi * 17 * Float(t))
        p.rootOffset = SIMD3(v[.rootX] + shiver, max(v[.rootY], -0.004), v[.rootZ])
        p.squash = v[.squash]
        p.hipsShift = v[.hipsShift]
        p.hipsRoll = v[.hipsRoll]
        p.hipsPitch = v[.hipsPitch]
        p.chestYaw = v[.chestYaw]
        p.chestPitch = v[.chestPitch]
        p.puff = v[.puff]
        p.breath = style.breathAmount * sin(2 * .pi * style.breathRate * Float(t)) * (1 + 0.25 * ValueNoise.sample(t * 0.3 + 7))
        p.headPitch = v[.headPitch]
        p.headYaw = v[.headYaw]
        p.headRoll = v[.headRoll]
        p.leftEarRoll = v[.leftEar]
        p.rightEarRoll = v[.rightEar]
        p.leftArmRoll = v[.leftArmRoll]
        p.leftArmPitch = v[.leftArmPitch]
        p.leftArmYaw = v[.leftArmYaw]
        p.rightArmRoll = v[.rightArmRoll]
        p.rightArmPitch = v[.rightArmPitch]
        p.rightArmYaw = v[.rightArmYaw]
        p.leftLegLift = max(v[.leftLegLift], 0)
        p.rightLegLift = max(v[.rightLegLift], 0)
        p.leftLegPitch = v[.leftLegPitch]
        p.rightLegPitch = v[.rightLegPitch]
        p.leftLegRoll = v[.leftLegRoll]
        p.rightLegRoll = v[.rightLegRoll]
        p.rootYaw = spinYaw() + (motionOut?.yaw ?? 0) + (reactionOut?.yaw ?? 0)

        // Eyes: mood openness, blinks, clip squints; look follows the finger, or up when thinking.
        p.eyeOpen = style.eyeOpen * blinkFactor() * (motionOut?.eyeOpenScale ?? 1) * (reactionOut?.eyeOpenScale ?? 1)
        let thinkingLook = SIMD2(lookSmoothed.x, lookSmoothed.y * (1 - style.eyeLookUp) + style.eyeLookUp)
        p.eyeLook = input.look == nil ? (reactionOut?.eyeLook ?? motionOut?.eyeLook ?? thinkingLook) : thinkingLook

        // Expressions (anime / Mii style): a reaction beats a behavior or dance, which beats the mood.
        p.mouth = reactionOut?.mouth ?? motionOut?.mouth ?? style.mouth
        p.eyes = reactionOut?.eyes ?? motionOut?.eyes ?? style.eyes
        var tiltTarget = reactionOut?.browTilt ?? motionOut?.browTilt ?? style.browTilt
        let raiseTarget = reactionOut?.browRaise ?? motionOut?.browRaise ?? style.browRaise
        let blushTarget = reactionOut?.blush ?? motionOut?.blush ?? style.blush
        if currentMood == .dipping, !input.thinking, motion == nil, reaction == nil, fmod(time, 6) < 1.3 {
            p.mouth = .yawn
            p.eyes = .sleepy
        }
        if input.pressing {
            p.mouth = .wavy
            p.eyes = .squeeze
            tiltTarget = 0.6
        }
        browTilt += (tiltTarget - browTilt) * (1 - exp(-fdt * 12))
        browRaise += (raiseTarget - browRaise) * (1 - exp(-fdt * 12))
        blush += (blushTarget - blush) * (1 - exp(-fdt * 6))
        p.browTilt = browTilt
        p.browRaise = browRaise
        p.blush = blush

        p.rimColor = style.rimColor
        p.rimStrength = style.rimStrength
        pose = p
        return p
    }

    // MARK: Layers

    /// Mood posture plus continuous life, before clips and springs.
    private func baseTarget(at t: Double) -> SIMD32<Float> {
        var target = SIMD32<Float>(repeating: 0)
        let ft = Float(t)

        // Mood posture.
        target[.hipsPitch] = style.bodyPitch
        target[.headPitch] = style.headPitch
        target[.headRoll] = style.headRoll
        target[.leftEar] = style.earDroop
        target[.rightEar] = -style.earDroop
        target[.leftArmRoll] = -style.armSpread
        target[.rightArmRoll] = style.armSpread
        target[.rightArmPitch] = -style.rightArmRaise * 2.1
        target[.rightArmRoll] += -style.rightArmRaise * 0.5
        target[.puff] = style.puff

        // Life: weight shifts between the feet (the free foot lifts), a sway, a wandering head, arms that swing along.
        let weight = ValueNoise.sample(t * 0.22)
        let wander = ValueNoise.sample(t * 0.17 + 31)
        let nodNoise = ValueNoise.sample(t * 0.29 + 57)
        let tilt = ValueNoise.sample(t * 0.23 + 77)
        target[.hipsShift] += 0.009 * weight
        target[.hipsRoll] += -(style.swayAmount * 1.6 + 0.03) * weight
        target[.leftLegLift] += max(0, weight - 0.2) * 0.015
        target[.rightLegLift] += max(0, -weight - 0.2) * 0.015
        target[.leftLegPitch] += -max(0, weight - 0.2) * 0.2
        target[.rightLegPitch] += -max(0, -weight - 0.2) * 0.2
        target[.headYaw] += 0.16 * wander
        target[.headPitch] += 0.07 * nodNoise
        target[.headRoll] += 0.05 * weight + 0.06 * tilt
        target[.leftArmRoll] += 0.1 * ValueNoise.sample(t * 0.41 + 93) - 0.03 * springs.velocity[.hipsRoll]
        target[.rightArmRoll] += 0.1 * ValueNoise.sample(t * 0.37 + 121) - 0.03 * springs.velocity[.hipsRoll]
        target[.leftArmPitch] += 0.08 * ValueNoise.sample(t * 0.31 + 151)
        target[.rightArmPitch] += 0.08 * ValueNoise.sample(t * 0.33 + 171)

        // Mood signature motion.
        target[.rootY] += style.hopHeight * abs(sin(.pi * style.hopRate * ft))
        let fan = style.fan * sin(2 * .pi * 3.2 * ft)
        target[.leftArmRoll] -= fan
        target[.rightArmRoll] += fan
        target[.headPitch] += style.nod * pow(max(0, sin(2 * .pi * ft / 4.5)), 3)

        // Talking bob, thinking tilt, and following the finger.
        target[.headPitch] += talkAmount * 0.1 * sin(2 * .pi * 3 * ft) - thinkAmount * 0.12
        target[.headYaw] += lookSmoothed.x * 0.35
        target[.headPitch] -= lookSmoothed.y * 0.22
        target[.chestYaw] += lookSmoothed.x * 0.08

        if input.pressing {
            target[.squash] -= 0.22
            target[.hipsRoll] += 0.04 * sin(2 * .pi * 1.6 * ft)
        }
        return target
    }

    private mutating func scheduleIdle() {
        let attentive = input.look != nil || input.pressing || input.talking
        if attentive, let current = motion, current.kind.isIdle {
            motion = nil
            nextIdleAt = time + 2
        }
        guard motion == nil, !attentive, time >= nextIdleAt else { return }
        let choices = ClipKind.idleChoices(for: input.thinking ? .thinking : input.mood)
        var pick = Double.random(in: 0..<choices.map(\.1).reduce(0, +), using: &rng)
        var kind = choices[0].0
        for (candidate, weight) in choices {
            if pick < weight {
                kind = candidate
                break
            }
            pick -= weight
        }
        // Avoid repeating the same behavior twice in a row.
        if kind == idleLog.last?.kind, choices.count > 1 {
            kind = choices.first { $0.0 != kind }?.0 ?? kind
        }
        motion = start(kind)
        idleLog.append((kind, time))
    }

    private mutating func start(_ kind: ClipKind) -> ActiveClip {
        ActiveClip(kind: kind, start: time, side: Bool.random(using: &rng) ? 1 : -1)
    }

    /// Plays a clip forward by dt: fires its impulses, ends it when done, and returns this frame's output.
    private mutating func advance(_ slot: inout ActiveClip?, dt: Double) -> ClipOutput? {
        guard var clip = slot else { return nil }
        let before = clip.elapsed
        clip.elapsed += dt
        for impulse in clip.kind.impulses(side: clip.side) where impulse.at >= before && impulse.at < clip.elapsed {
            for (channel, amount) in impulse.kicks { springs.kick(channel, amount) }
            if impulse.isBeat { danceBeats += 1 }
        }
        guard clip.elapsed < clip.kind.duration else {
            slot = nil
            if clip.kind.isIdle || clip.kind.isDance {
                nextIdleAt = time + Double.random(in: clip.kind.isDance ? 3...6 : Self.idleGap, using: &rng)
            }
            return nil
        }
        slot = clip
        return clip.kind.evaluate(at: clip.elapsed, side: clip.side)
    }

    private mutating func spinYaw() -> Float {
        guard let start = spinStartedAt else { return 0 }
        let progress = Float((time - start) / Self.spinDuration)
        if progress >= 1 {
            spinStartedAt = nil
            return 0
        }
        let eased = progress < 0.5 ? 2 * progress * progress : 1 - pow(-2 * progress + 2, 2) / 2
        return 2 * .pi * eased
    }

    private mutating func blinkFactor() -> Float {
        if blinkStartedAt == nil, time >= nextBlinkAt {
            blinkStartedAt = time
            blinkTimes.append(time)
            nextBlinkAt = time + Double.random(in: Self.blinkInterval, using: &rng)
        }
        guard let start = blinkStartedAt else { return 1 }
        let progress = (time - start) / Self.blinkDuration
        if progress >= 1 {
            blinkStartedAt = nil
            return 1
        }
        return Float(abs(1 - 2 * progress)) * 0.9 + 0.1
    }
}
