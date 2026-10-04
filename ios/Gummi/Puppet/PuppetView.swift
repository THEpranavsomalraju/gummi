import RealityKit
import SwiftUI

/// Gummi, ready to drop into any screen.
/// Eyes and head follow the finger anywhere on the view. Tap his head or belly for different reactions,
/// double-tap to make him dance, press and hold to squish him.
struct PuppetView: View {
    var input: PuppetInput
    var showsFPS = false
    var translucentShell = false
    /// Wave hello when the view appears (Home).
    var greets = false

    @State private var controller: KoalaController
    @State private var look: SIMD2<Float>?
    @State private var pressing = false
    @State private var lastTap = Date.distantPast
    @State private var taps = 0
    @State private var releases = 0
    @State private var proudSpins = 0

    init(input: PuppetInput, controller: KoalaController? = nil, showsFPS: Bool = false,
         translucentShell: Bool = false, greets: Bool = false) {
        self.input = input
        self.showsFPS = showsFPS
        self.translucentShell = translucentShell
        self.greets = greets
        _controller = State(initialValue: controller ?? KoalaController())
    }

    var body: some View {
        GeometryReader { geometry in
            RealityView { content in
                content.camera = .virtual
                guard let rig = await controller.prepare() else { return }
                content.add(rig.scene)
                let controller = controller
                controller.subscription = content.subscribe(to: SceneEvents.Update.self) { event in
                    let dt = event.deltaTime
                    MainActor.assumeIsolated { controller.tick(dt) }
                }
            }
            .gesture(SpatialTapGesture().targetedToAnyEntity().onEnded { value in
                tap(value.entity.name == "head" ? .head : .belly)
            })
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.3).targetedToAnyEntity().onEnded { _ in
                pressing = true
            })
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let size = geometry.size
                        look = SIMD2(Float(value.location.x / max(size.width, 1) * 2 - 1),
                                     Float(1 - value.location.y / max(size.height, 1) * 2))
                    }
                    .onEnded { _ in
                        look = nil
                        if pressing {
                            pressing = false
                            releases += 1
                        }
                    }
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
        .accessibilityAction(named: "Dance") { controller.react(.dance) }
    }

    private func sync() {
        var merged = input
        merged.look = look
        merged.pressing = pressing
        controller.input = merged
    }

    /// A second tap within 0.35 s makes him dance; the first tap still reacts right away.
    private func tap(_ region: TapRegion) {
        let now = Date.now
        if now.timeIntervalSince(lastTap) < 0.35 {
            controller.react(.dance)
            lastTap = .distantPast
        } else {
            controller.react(.tap(region))
            lastTap = now
        }
        taps += 1
    }
}
