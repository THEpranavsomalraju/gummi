import Foundation
import simd

/// A damped spring around 0 (semi-implicit Euler).
nonisolated struct Spring: Equatable, Sendable {
    var value: Float = 0
    var velocity: Float = 0
    var stiffness: Float
    var damping: Float

    mutating func step(toward target: Float = 0, dt: Float) {
        velocity += (-stiffness * (value - target) - damping * velocity) * dt
        value += velocity * dt
    }

    var isAtRest: Bool { abs(value) < 0.001 && abs(velocity) < 0.01 }
}

/// Small seedable RNG so blink timing is testable.
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

/// Gummi's motion as a pure function of time and input. The renderer calls `step` every frame and applies the pose.
nonisolated struct PuppetAnimator: Sendable {
    static let blinkInterval: ClosedRange<Double> = 3...6
    static let blinkDuration = 0.16
    static let spinDuration = 1.2

    var input = PuppetInput()
    private(set) var time: Double = 0
    private(set) var pose = PuppetPose()
    private(set) var style = MoodStyle.of(.calm)
    private(set) var squash = Spring(stiffness: 260, damping: 7)
    private var leftEar = Spring(stiffness: 120, damping: 6)
    private var rightEar = Spring(stiffness: 120, damping: 6)
    private var lookSmoothed = SIMD2<Float>(repeating: 0)
    private var talkAmount: Float = 0
    private var thinkAmount: Float = 0
    private var currentMood: Mood = .calm
    private(set) var spinStartedAt: Double?
    private(set) var nextBlinkAt: Double
    private var blinkStartedAt: Double?
    private(set) var blinkTimes: [Double] = []
    private var rng: SplitMix64

    init(seed: UInt64 = UInt64.random(in: 1...UInt64.max)) {
        rng = SplitMix64(seed: seed)
        nextBlinkAt = Double.random(in: Self.blinkInterval, using: &rng)
    }

    mutating func react(_ reaction: PuppetReaction) {
        switch reaction {
        case .tap:
            squash.velocity -= 2.6
            leftEar.velocity += 4
            rightEar.velocity -= 4
        }
    }

    @discardableResult
    mutating func step(dt rawDt: Double) -> PuppetPose {
        let dt = Float(min(max(rawDt, 0), 1.0 / 20))
        time += Double(dt)
        let t = Float(time)

        if input.mood != currentMood {
            if input.mood == .proud { spinStartedAt = time }
            currentMood = input.mood
        }
        let target = MoodStyle.of(input.thinking ? .thinking : input.mood)
        style.blend(toward: target, dt: dt)

        let k = 1 - exp(-dt * 4 / 0.6)
        talkAmount += ((input.talking ? 1 : 0) - talkAmount) * k
        thinkAmount += ((input.thinking ? 1 : 0) - thinkAmount) * k
        let lookTarget = input.look.map { simd_clamp($0, SIMD2(-1, -1), SIMD2(1, 1)) } ?? .zero
        lookSmoothed += (lookTarget - lookSmoothed) * (1 - exp(-dt * 10))

        squash.step(dt: dt)

        var p = PuppetPose()

        // Breathing and puffing.
        let breath = style.breathAmount * sin(2 * .pi * style.breathRate * t)
        p.bodyScale = SIMD3(1 + style.puff + breath * 0.6, 1 + style.puff * 0.6 + breath, 1 + style.puff + breath * 0.6)

        // Squash and stretch: volume-preserving-ish.
        p.rootScale = SIMD3(1 - squash.value * 0.55, 1 + squash.value, 1 - squash.value * 0.55)

        // Hops (abs-sine), gentle sway, shiver.
        let hop = style.hopHeight * abs(sin(.pi * style.hopRate * t))
        let shiver = style.shiver * sin(2 * .pi * 17 * t)
        p.rootOffset = SIMD3(shiver, hop, 0)
        p.bodyRoll = style.swayAmount * sin(2 * .pi * 0.23 * t)
        p.bodyPitch = style.bodyPitch

        // Proud: one full turn on entering the mood.
        if let start = spinStartedAt {
            let progress = Float((time - start) / Self.spinDuration)
            if progress >= 1 {
                spinStartedAt = nil
            } else {
                let eased = progress < 0.5 ? 2 * progress * progress : 1 - pow(-2 * progress + 2, 2) / 2
                p.rootYaw = 2 * .pi * eased
            }
        }

        // Head: mood posture, nod, talking bob, look-at.
        let nod = style.nod * pow(max(0, sin(2 * .pi * t / 4.5)), 3)
        let talkBob = talkAmount * 0.07 * sin(2 * .pi * 3 * t)
        p.headPitch = style.headPitch + nod + talkBob - lookSmoothed.y * 0.22 - thinkAmount * 0.12
        p.headYaw = lookSmoothed.x * 0.35
        p.headRoll = style.headRoll - p.bodyRoll * 0.5

        // Ears lag behind the head and droop with mood.
        leftEar.step(toward: p.headRoll * 0.8, dt: dt)
        rightEar.step(toward: p.headRoll * 0.8, dt: dt)
        p.leftEarRoll = style.earDroop + leftEar.value
        p.rightEarRoll = -style.earDroop + rightEar.value

        // Arms: rest at the sides, spread or fan with mood, right arm raised to the chin when thinking.
        let fan = style.fan * sin(2 * .pi * 3.2 * t)
        p.leftArmRoll = -(style.armSpread + fan)
        p.rightArmRoll = style.armSpread - fan
        p.rightArmPitch = -style.rightArmRaise * 1.9
        p.rightArmRoll += style.rightArmRaise * 0.35

        // Eyes: mood openness times blink; look follows the finger, or up when thinking.
        p.eyeOpen = style.eyeOpen * blinkFactor()
        p.eyeLook = SIMD2(lookSmoothed.x, lookSmoothed.y * (1 - style.eyeLookUp) + style.eyeLookUp)

        // Dipping: a slow yawn every 6 seconds.
        p.mouth = style.mouth
        if currentMood == .dipping, !input.thinking, fmod(time, 6) < 1.3 {
            p.mouth = .yawn
            p.eyeOpen *= 0.4
        }

        p.rimColor = style.rimColor
        p.rimStrength = style.rimStrength
        pose = p
        return p
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
