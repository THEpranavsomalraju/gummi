import MetalKit
import RealityKit
import SwiftUI

/// Renders Gummi with RealityRenderer into an MTKView at up to 120 fps on ProMotion iPhones.
/// RealityView stays at 60 fps on iPhone even with CADisableMinimumFrameDurationOnPhone (measured on the device), so
/// Gummi drives his own frame loop here. Needs CADisableMinimumFrameDurationOnPhone in Info.plist (D-125).
struct KoalaCanvas: UIViewRepresentable {
    let controller: KoalaController

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.device)
        view.delegate = context.coordinator
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.framebufferOnly = false
        view.preferredFramesPerSecond = 120
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.backgroundColor = .systemBackground
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {}

    static func dismantleUIView(_ view: MTKView, coordinator: Coordinator) {
        view.isPaused = true
        view.delegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, MTKViewDelegate {
        let device = MTLCreateSystemDefaultDevice()
        private let queue: MTLCommandQueue?
        private let event: MTLSharedEvent?
        private var eventValue: UInt64 = 0
        private var renderer: RealityRenderer?
        private var lastTime: CFTimeInterval?
        private let controller: KoalaController

        init(controller: KoalaController) {
            self.controller = controller
            queue = device?.makeCommandQueue()
            event = device?.makeSharedEvent()
            super.init()
            Task { await setUp() }
        }

        private func setUp() async {
            guard let rig = await controller.prepare(), let renderer = try? RealityRenderer() else { return }
            renderer.entities.append(rig.scene)
            renderer.activeCamera = rig.camera
            // Native 3x pixels without 4x multisampling: sharper than 2x with MSAA and far cheaper on the GPU.
            renderer.cameraSettings.antialiasing = .none
            self.renderer = renderer
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let renderer, let event, let queue, let drawable = view.currentDrawable else { return }
            let now = CACurrentMediaTime()
            let dt = lastTime.map { now - $0 } ?? 1.0 / 120
            lastTime = now
            controller.tick(dt)

            let background = UIColor.systemBackground.resolvedColor(with: view.traitCollection).cgColor
            renderer.cameraSettings.colorBackground = .color(background)
            eventValue += 1
            do {
                let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: drawable.texture))
                try renderer.updateAndRender(deltaTime: dt, cameraOutput: output,
                                             actionsAfterRender: [.signal(event, value: eventValue)])
            } catch {
                return
            }
            // Present only after RealityKit finishes drawing into the drawable: no half-drawn frames.
            guard let present = queue.makeCommandBuffer() else { return }
            present.encodeWaitForEvent(event, value: eventValue)
            present.present(drawable)
            present.commit()
        }
    }
}

/// The RealityView path (60 fps on iPhone), kept as a fallback: `-gummi.renderer realityView`.
struct KoalaRealityView: View {
    let controller: KoalaController

    var body: some View {
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
    }
}
