import RealityKit
import SwiftUI

/// Gummi, ready to drop into any screen. Eyes and head follow the finger anywhere on the view;
/// tapping Gummi makes him jiggle with a light haptic.
struct PuppetView: View {
    var input: PuppetInput
    var showsFPS = false
    var translucentShell = false
    /// Bump to play a tap reaction from outside (the playground's Tap button).
    var tapTrigger = 0

    @State private var controller = KoalaController()
    @State private var look: SIMD2<Float>?
    @State private var taps = 0
    @State private var proudSpins = 0

    var body: some View {
        GeometryReader { geometry in
            RealityView { content in
                content.camera = .virtual
                content.add(controller.rig.scene)
                let controller = controller
                controller.subscription = content.subscribe(to: SceneEvents.Update.self) { event in
                    let dt = event.deltaTime
                    MainActor.assumeIsolated { controller.tick(dt) }
                }
            }
            .gesture(SpatialTapGesture().targetedToAnyEntity().onEnded { _ in tap() })
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let size = geometry.size
                        look = SIMD2(Float(value.location.x / max(size.width, 1) * 2 - 1),
                                     Float(1 - value.location.y / max(size.height, 1) * 2))
                    }
                    .onEnded { _ in look = nil }
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
        .onAppear { sync() }
        .onChange(of: input) { sync() }
        .onChange(of: look) { sync() }
        .onChange(of: translucentShell, initial: true) { controller.translucentShell = translucentShell }
        .onChange(of: tapTrigger) { tap() }
        .onChange(of: input.mood) { _, mood in
            if mood == .proud { proudSpins += 1 }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
        .sensoryFeedback(.success, trigger: proudSpins)
        .accessibilityElement()
        .accessibilityLabel("Gummi is \(input.thinking ? "thinking" : input.mood == .unknown ? "calm" : input.mood.rawValue).")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { tap() }
    }

    private func sync() {
        var merged = input
        merged.look = look
        controller.input = merged
    }

    private func tap() {
        controller.react(.tap)
        taps += 1
    }
}
