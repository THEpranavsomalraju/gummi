import QuartzCore
import RealityKit

/// The 3D PuppetRenderer: owns the rig and the animator, and steps them every rendered frame.
@Observable
final class KoalaController: PuppetRenderer {
    @ObservationIgnored let rig = KoalaRig()
    @ObservationIgnored private var animator = PuppetAnimator()
    @ObservationIgnored var subscription: EventSubscription?
    @ObservationIgnored private var frames = 0
    @ObservationIgnored private var windowStart = CACurrentMediaTime()

    @ObservationIgnored var input = PuppetInput() {
        didSet { animator.input = input }
    }

    /// Updated once a second, for the debug FPS counter.
    private(set) var framesPerSecond: Double = 0

    var translucentShell = false {
        didSet { rig.setTranslucent(translucentShell) }
    }

    func react(_ reaction: PuppetReaction) {
        animator.react(reaction)
    }

    func tick(_ dt: Double) {
        rig.apply(animator.step(dt: dt))
        frames += 1
        let now = CACurrentMediaTime()
        if now - windowStart >= 1 {
            framesPerSecond = Double(frames) / (now - windowStart)
            frames = 0
            windowStart = now
        }
    }
}
