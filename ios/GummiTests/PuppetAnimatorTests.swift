import Foundation
import Testing
@testable import Gummi

@Suite("Puppet animator")
struct PuppetAnimatorTests {
    private static let dt = 1.0 / 60

    private func run(_ animator: inout PuppetAnimator, seconds: Double) {
        for _ in 0..<Int((seconds / Self.dt).rounded()) { animator.step(dt: Self.dt) }
    }

    @Test(arguments: [UInt64(1), 42, 7_777])
    func blinksEveryThreeToSixSeconds(seed: UInt64) {
        var animator = PuppetAnimator(seed: seed)
        run(&animator, seconds: 120)
        let gaps = zip(animator.blinkTimes.dropFirst(), animator.blinkTimes).map { $0 - $1 }
        #expect(animator.blinkTimes.count >= 19)
        #expect(gaps.allSatisfy { $0 >= 3 && $0 <= 6 + Self.dt })
    }

    @Test func springsOvershootThenSettle() {
        var springs = ChannelSprings()
        var target = SIMD32<Float>(repeating: 0)
        target[.headYaw] = 0.5
        var peak: Float = 0
        for _ in 0..<120 {
            springs.step(toward: target, dt: Float(Self.dt))
            peak = max(peak, springs.value[.headYaw])
        }
        #expect(peak > 0.5)
        for _ in 0..<240 { springs.step(toward: target, dt: Float(Self.dt)) }
        #expect(abs(springs.value[.headYaw] - 0.5) < 0.005)
    }

    @Test(arguments: [UInt64(3), 11, 2_024])
    func idleBehaviorsKeepHimBusy(seed: UInt64) {
        var animator = PuppetAnimator(seed: seed)
        run(&animator, seconds: 90)
        let log = animator.idleLog
        #expect(log.count >= 7)
        #expect(Set(log.map(\.kind)).count >= 4)
        #expect(log.first.map { $0.start >= 2.5 && $0.start <= 4 + Self.dt } == true)
        for (previous, next) in zip(log, log.dropFirst()) {
            let gap = next.start - previous.start - previous.kind.duration
            #expect(gap >= 4 - Self.dt && gap <= 9 + 2 * Self.dt)
            #expect(previous.kind != next.kind)
        }
    }

    @Test func attentionPausesIdles() {
        var animator = PuppetAnimator(seed: 3)
        animator.input.look = SIMD2(0.3, 0.2)
        run(&animator, seconds: 20)
        #expect(animator.idleLog.isEmpty)
        #expect(animator.motion == nil)
    }

    @Test func danceRunsTwelveBeatsWithOneSpinThenEnds() {
        var animator = PuppetAnimator(seed: 1)
        animator.react(.dance)
        #expect(animator.motion?.kind == .dance)
        var spin: Float = 0
        for _ in 0..<Int(6.2 / Self.dt) {
            animator.step(dt: Self.dt)
            spin = max(spin, animator.pose.rootYaw)
        }
        #expect(animator.danceBeats == 12)
        #expect(animator.motion == nil)
        #expect(spin > 2 * .pi * 0.95)
        #expect(animator.pose.rootYaw == 0)
    }

    @Test func turningHappyStartsADance() {
        var animator = PuppetAnimator(seed: 1)
        animator.input.mood = .happy
        animator.step(dt: Self.dt)
        #expect(animator.motion?.kind == .dance)
    }

    @Test func squishHoldsThenBouncesBack() {
        var animator = PuppetAnimator(seed: 1)
        animator.input.look = .zero
        run(&animator, seconds: 0.5)
        animator.input.pressing = true
        run(&animator, seconds: 1)
        #expect(animator.pose.squash < -0.15)
        #expect(animator.pose.mouth == .flat)
        animator.input.pressing = false
        var peak: Float = -1
        for _ in 0..<30 {
            animator.step(dt: Self.dt)
            peak = max(peak, animator.pose.squash)
        }
        #expect(peak > 0.02)
        run(&animator, seconds: 3)
        #expect(abs(animator.pose.squash) < 0.02)
    }

    @Test func tapsReactByRegion() {
        var animator = PuppetAnimator(seed: 1)
        animator.input.look = .zero
        animator.react(.tap(.head))
        animator.step(dt: Self.dt)
        #expect(animator.reaction?.kind == .headTap)
        #expect(animator.pose.eyeOpen < 0.2)
        run(&animator, seconds: 1)
        #expect(animator.reaction == nil)
        animator.react(.tap(.belly))
        var lowest: Float = 0
        for _ in 0..<20 {
            animator.step(dt: Self.dt)
            lowest = min(lowest, animator.pose.squash)
        }
        #expect(lowest < -0.03)
    }

    @Test func proudSpinsExactlyOnce() {
        var animator = PuppetAnimator(seed: 1)
        animator.input.look = .zero
        run(&animator, seconds: 0.5)
        animator.input.mood = .proud
        var maxYaw: Float = 0
        for _ in 0..<Int(PuppetAnimator.spinDuration / Self.dt) + 5 {
            animator.step(dt: Self.dt)
            maxYaw = max(maxYaw, animator.pose.rootYaw)
        }
        #expect(maxYaw > 2 * .pi * 0.98)
        #expect(maxYaw < 2 * .pi)
        #expect(animator.pose.rootYaw == 0)
        #expect(animator.spinStartedAt == nil)
    }

    @Test func lookIsClampedAndFollowsTheFinger() {
        var animator = PuppetAnimator(seed: 1)
        animator.input.look = SIMD2(5, -5)
        run(&animator, seconds: 1)
        #expect(animator.pose.eyeLook.x <= 1 && animator.pose.eyeLook.x > 0.95)
        #expect(animator.pose.eyeLook.y >= -1 && animator.pose.eyeLook.y < -0.95)
        #expect(animator.pose.headYaw > 0.2)
        animator.input.look = nil
        run(&animator, seconds: 1)
        #expect(abs(animator.pose.eyeLook.x) < 0.01)
    }

    @Test func thinkingLooksUpAndRaisesAPaw() {
        var animator = PuppetAnimator(seed: 1)
        animator.input = PuppetInput(mood: .high, thinking: true)
        run(&animator, seconds: 1)
        #expect(animator.pose.mouth == .flat)
        #expect(animator.pose.eyeLook.y > 0.95)
        #expect(animator.pose.rightArmPitch < -1.8)
    }

    @Test func talkingBobsTheHead() {
        var animator = PuppetAnimator(seed: 1)
        animator.input.talking = true
        run(&animator, seconds: 1)
        var pitches: [Float] = []
        for _ in 0..<30 {
            animator.step(dt: Self.dt)
            pitches.append(animator.pose.headPitch)
        }
        #expect((pitches.max() ?? 0) - (pitches.min() ?? 0) > 0.08)
    }

    @Test func everyMoodHasItsOwnLook() {
        let moods: [Mood] = [.calm, .rising, .high, .dipping, .low, .proud, .happy, .sleepy, .thinking]
        let styles = moods.map(MoodStyle.of)
        for (i, a) in styles.enumerated() {
            for b in styles[(i + 1)...] { #expect(a != b) }
        }
        #expect(MoodStyle.of(.low).mouth == .frown)
        #expect(MoodStyle.of(.sleepy).eyeOpen < 0.5)
        #expect(MoodStyle.of(.unknown) == MoodStyle.of(.calm))
        #expect(moods.allSatisfy { !ClipKind.idleChoices(for: $0).isEmpty })
    }
}
