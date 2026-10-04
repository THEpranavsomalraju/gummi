import QuartzCore
import RealityKit

/// The 3D PuppetRenderer: owns the rig and the animator, and steps them every rendered frame.
@Observable
final class KoalaController: PuppetRenderer {
    @ObservationIgnored private(set) var rig: KoalaRig?
    @ObservationIgnored private var building: Task<KoalaRig?, Never>?
    @ObservationIgnored private var animator = PuppetAnimator()
    @ObservationIgnored var subscription: EventSubscription?
    @ObservationIgnored private var frames = 0
    @ObservationIgnored private var windowStart = CACurrentMediaTime()

    @ObservationIgnored var input = PuppetInput() {
        didSet { animator.input = input }
    }

    private static let logsFPS = UserDefaults.standard.bool(forKey: "gummi.logFPS")

    /// Updated once a second, for the debug FPS counter.
    private(set) var framesPerSecond: Double = 0
    /// Counts dance beats, so the view can tap a haptic on each one.
    private(set) var danceBeats = 0

    var translucentShell = false {
        didSet { rig?.setTranslucent(translucentShell) }
    }

    /// Builds the rig once (the molded mesh is shared and cached).
    func prepare() async -> KoalaRig? {
        if let rig { return rig }
        if building == nil { building = Task { await KoalaRig.build() } }
        let built = await building?.value
        rig = built
        built?.setTranslucent(translucentShell)
        return built
    }

    func react(_ reaction: PuppetReaction) {
        animator.react(reaction)
    }

    @ObservationIgnored private var workTime: CFTimeInterval = 0

    func tick(_ dt: Double) {
        guard let rig else { return }
        let started = CACurrentMediaTime()
        rig.apply(animator.step(dt: dt), dt: Float(min(dt, 1.0 / 20)))
        workTime += CACurrentMediaTime() - started
        if animator.danceBeats != danceBeats { danceBeats = animator.danceBeats }
        frames += 1
        let now = CACurrentMediaTime()
        if now - windowStart >= 1 {
            framesPerSecond = Double(frames) / (now - windowStart)
            // `-gummi.logFPS YES` prints the update rate and Gummi's own work per frame, read from the device console.
            if Self.logsFPS {
                print("gummi.fps \(Int(framesPerSecond.rounded())) work \(String(format: "%.2f", workTime / Double(max(frames, 1)) * 1000)) ms")
            }
            frames = 0
            workTime = 0
            windowStart = now
        }
    }
}
