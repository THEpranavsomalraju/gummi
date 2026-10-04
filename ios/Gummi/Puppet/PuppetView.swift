import SwiftUI

/// Gummi, ready to drop into any screen.
/// Eyes and head follow the finger anywhere on the view. Tap his head or belly for different reactions,
/// double-tap for a random dance, press and hold to squish him.
struct PuppetView: View {
    var input: PuppetInput
    var showsFPS = false
    var translucentShell = false
    /// Wave hello when the view appears (Home).
    var greets = false
    /// A reaction the app asks for (cheer or nod when a grade opens).
    var cue: PuppetCue?

    @State private var controller: KoalaController
    @State private var look: SIMD2<Float>?
    @State private var pressing = false
    @State private var touch: (start: CGPoint, moved: Bool)?
    @State private var pressTimer: Task<Void, Never>?
    @State private var lastTap = Date.distantPast
    @State private var taps = 0
    @State private var releases = 0
    @State private var releasedAt = Date.distantPast
    @State private var proudSpins = 0

    /// `-gummi.renderer realityView` uses the 60 fps RealityView path instead of the 120 fps canvas.
    private static let usesRealityView = UserDefaults.standard.string(forKey: "gummi.renderer") == "realityView"

    init(input: PuppetInput, controller: KoalaController? = nil, showsFPS: Bool = false,
         translucentShell: Bool = false, greets: Bool = false, cue: PuppetCue? = nil, visibleHeight: Float = 1.05) {
        self.input = input
        self.showsFPS = showsFPS
        self.translucentShell = translucentShell
        self.greets = greets
        self.cue = cue
        let controller = controller ?? KoalaController()
        controller.visibleHeight = visibleHeight
        _controller = State(initialValue: controller)
    }

    /// The controller, so a parent can read `showsChatHint`.
    var puppet: KoalaController { controller }

    var body: some View {
        GeometryReader { geometry in
            Group {
                if Self.usesRealityView {
                    KoalaRealityView(controller: controller)
                } else {
                    KoalaCanvas(controller: controller)
                }
            }
            .gesture(SpatialTapGesture().onEnded { value in
                if let region = controller.rig?.hitRegion(at: value.location, in: geometry.size) { tap(region) }
            })
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in touchMoved(to: value.location, in: geometry.size) }
                    .onEnded { _ in touchEnded() }
            )
        }
        .overlay(alignment: .topLeading) {
            if showsFPS {
                Text("\(Int(controller.framesPerSecond.rounded())) fps")
                    .font(.caption.monospacedDigit().bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .glassSurface(in: Capsule())
                    .padding()
            }
        }
        .onAppear {
            sync()
            if greets { controller.react(.wave) }
        }
        .onChange(of: input) { sync() }
        .onChange(of: cue) { _, cue in
            if let cue { controller.react(cue.reaction) }
        }
        .onChange(of: look) { sync() }
        .onChange(of: pressing) { sync() }
        .onChange(of: translucentShell, initial: true) { controller.translucentShell = translucentShell }
        .onChange(of: input.mood) { _, mood in
            if mood == .proud { proudSpins += 1 }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: releases)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.5), trigger: controller.danceBeats)
        .sensoryFeedback(.success, trigger: proudSpins)
        .accessibilityElement()
        .accessibilityLabel("Gummi is \(input.thinking ? "thinking" : input.mood == .unknown ? "calm" : input.mood.rawValue).")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { tap(.belly) }
        .accessibilityAction(named: "Dance") { controller.react(.dance(nil)) }
    }

    private func sync() {
        var merged = input
        merged.look = look
        merged.pressing = pressing
        controller.input = merged
    }

    /// Eyes follow the finger. A finger held still on Gummi for 0.3 s squishes him.
    private func touchMoved(to location: CGPoint, in size: CGSize) {
        look = SIMD2(Float(location.x / max(size.width, 1) * 2 - 1), Float(1 - location.y / max(size.height, 1) * 2))
        if let current = touch {
            if !current.moved, hypot(location.x - current.start.x, location.y - current.start.y) > 12 {
                touch?.moved = true
                pressTimer?.cancel()
            }
            return
        }
        touch = (location, false)
        guard controller.rig?.hitRegion(at: location, in: size) != nil else { return }
        pressTimer = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, touch?.moved == false else { return }
            pressing = true
        }
    }

    private func touchEnded() {
        pressTimer?.cancel()
        pressTimer = nil
        touch = nil
        look = nil
        if pressing {
            pressing = false
            releases += 1
            releasedAt = .now
        }
    }

    /// A second tap within 0.35 s makes him dance; the first tap still reacts right away.
    private func tap(_ region: TapRegion) {
        // Letting go of a squish is not a tap.
        guard !pressing, Date.now.timeIntervalSince(releasedAt) > 0.2 else { return }
        let now = Date.now
        if now.timeIntervalSince(lastTap) < 0.35 {
            controller.react(.dance(nil))
            lastTap = .distantPast
        } else {
            controller.react(.tap(region))
            lastTap = now
        }
        taps += 1
    }
}
