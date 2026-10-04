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

    @Test func tapSquashesThenSettles() {
        var animator = PuppetAnimator(seed: 1)
        animator.react(.tap)
        animator.step(dt: Self.dt)
        run(&animator, seconds: 0.05)
        #expect(animator.pose.rootScale.y < 1)
        #expect(animator.pose.rootScale.x > 1)
        run(&animator, seconds: 2)
        #expect(animator.squash.isAtRest)
        #expect(abs(animator.pose.rootScale.y - 1) < 0.002)
    }

    @Test func moodChangesSettleInAboutSixTenthsOfASecond() {
        var animator = PuppetAnimator(seed: 1)
        animator.input.mood = .high
        let target = MoodStyle.of(.high)
        run(&animator, seconds: 0.25)
        #expect(animator.style.puff < target.puff * 0.9)
        run(&animator, seconds: 0.35)
        #expect(abs(animator.style.puff - target.puff) < target.puff * 0.05)
        #expect(animator.pose.mouth == .flat)
    }

    @Test func proudSpinsExactlyOnce() {
        var animator = PuppetAnimator(seed: 1)
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
        run(&animator, seconds: 3)
        #expect(animator.pose.rootYaw == 0)
    }

    @Test func lookIsClampedAndFollowsTheFinger() {
        var animator = PuppetAnimator(seed: 1)
        animator.input.look = SIMD2(5, -5)
        run(&animator, seconds: 1)
        #expect(animator.pose.eyeLook.x <= 1 && animator.pose.eyeLook.x > 0.95)
        #expect(animator.pose.eyeLook.y >= -1 && animator.pose.eyeLook.y < -0.95)
        #expect(animator.pose.headYaw > 0.3)
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
        #expect((pitches.max() ?? 0) - (pitches.min() ?? 0) > 0.1)
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
    }
}
