import CoreGraphics
import RealityKit
import simd
import UIKit

/// The molded jelly pieces (meshes and jelly data), built once off the main thread and shared by every Gummi on screen.
nonisolated enum KoalaMeshCache {
    static let shared = Task.detached(priority: .userInitiated) { () -> [JellySim] in
        KoalaShape.standard.pieces.map { JellySim(mesh: SurfaceNets.mesh(piece: $0), piece: $0) }
    }
}

/// Gummi as a toy made of jelly pieces (torso, head with ears, arms, legs) with face features riding on the head,
/// plus the camera, lights, and environment.
@MainActor
final class KoalaRig {
    let scene = Entity()
    let camera = PerspectiveCamera()
    /// Gummi himself (body, features, tap targets). Spins turn this whole entity.
    private let puppetRoot = Entity()
    private let shape = KoalaShape.standard
    private let bodies: [JellyBody]
    /// The head piece: face features sit on it and ride its wobble.
    private let head: JellyBody
    private let headPiece: KoalaPiece
    private let hitRoot = Entity()
    private var hitBoxes: [(entity: Entity, region: TapRegion, halfExtent: SIMD3<Float>)] = []
    private var face: KoalaFace?
    private let rimLight = PointLight()

    static let lookTarget = SIMD3<Float>(0, 0.2, 0.03)
    /// Meters of the world visible top to bottom; the camera backs off to show exactly this much.
    var visibleHeight: Float = 1.05

    static func build() async -> KoalaRig? {
        let sims = await KoalaMeshCache.shared.value
        var bodies: [JellyBody] = []
        for (piece, sim) in zip(KoalaShape.standard.pieces, sims) {
            guard let body = try? await JellyBody.make(sim: sim, piece: piece, material: KoalaMaterials.jelly(),
                                                       coreMaterial: KoalaMaterials.core()) else { return nil }
            bodies.append(body)
        }
        guard let headIndex = KoalaShape.standard.pieces.firstIndex(where: { $0.name == "head" }) else { return nil }
        return KoalaRig(bodies: bodies, headIndex: headIndex)
    }

    private init(bodies: [JellyBody], headIndex: Int) {
        self.bodies = bodies
        head = bodies[headIndex]
        headPiece = KoalaShape.standard.pieces[headIndex]
        scene.addChild(puppetRoot)
        for body in bodies {
            puppetRoot.addChild(body.entity)
            puppetRoot.addChild(body.core)
        }
        face = try? KoalaFace(root: puppetRoot, head: headPiece, sim: head.sim)
        addHitTargets()
        setUpCameraAndLights()
        apply(PuppetPose(), dt: 0)
    }

    // MARK: Pose

    func apply(_ pose: PuppetPose, dt: Float) {
        var bones = KoalaSkeleton.matrices(for: pose, joints: shape.joints)
        KoalaCollisions.resolveArms(&bones, shape: shape)
        for body in bodies { body.update(bones: bones, dt: dt) }
        puppetRoot.orientation = simd_quatf(angle: pose.rootYaw, axis: [0, 1, 0])

        let headSim = head.sim
        face?.apply(pose, bones: bones, wobble: { headSim.wobble(at: $0) })

        hitRoot.transform = Transform(matrix: bones[KoalaBone.hips.rawValue])

        rimLight.light.color = UIColor(red: CGFloat(pose.rimColor.x), green: CGFloat(pose.rimColor.y),
                                       blue: CGFloat(pose.rimColor.z), alpha: 1)
        rimLight.light.intensity = 800 + 7000 * pose.rimStrength

        // The camera leans a few degrees toward the finger.
        let azimuth = 0.28 + pose.eyeLook.x * 0.06, elevation = 0.12 + pose.eyeLook.y * 0.04
        let distance = visibleHeight / (2 * tan(camera.camera.fieldOfViewInDegrees * .pi / 360))
        camera.position = Self.lookTarget + SIMD3(sin(azimuth) * cos(elevation), sin(elevation), cos(azimuth) * cos(elevation)) * distance
        camera.look(at: Self.lookTarget, from: camera.position, relativeTo: nil)
    }

    /// The playground's alpha-blended variant of the same jelly surface.
    func setTranslucent(_ translucent: Bool) {
        let material = KoalaMaterials.jelly(translucent: translucent)
        for body in bodies {
            body.entity.model?.materials = [material]
            // Volume color now comes from transmission, so no opaque inner copy is needed.
            body.core.isEnabled = false
        }
    }

    /// Two tap targets: the head and the belly. They move with the hips.
    private func addHitTargets() {
        puppetRoot.addChild(hitRoot)
        // The head box covers the ears; the belly box covers the arms and legs too.
        for (region, center, size) in [(TapRegion.head, SIMD3<Float>(0, 0.33, 0.006), SIMD3<Float>(0.32, 0.22, 0.2)),
                                       (.belly, [0, 0.13, 0.01], [0.38, 0.27, 0.2])] {
            let target = Entity()
            target.position = center
            hitRoot.addChild(target)
            hitBoxes.append((target, region, size / 2))
        }
    }

    /// Which part of Gummi is under a point in the view, by casting a ray from the camera through it.
    func hitRegion(at point: CGPoint, in size: CGSize) -> TapRegion? {
        guard size.width > 0, size.height > 0 else { return nil }
        let tanHalf = tan(camera.camera.fieldOfViewInDegrees * .pi / 360)
        let aspect = Float(size.width / size.height)
        let x = (Float(point.x / size.width) * 2 - 1) * tanHalf * aspect
        let y = (1 - Float(point.y / size.height) * 2) * tanHalf
        let cameraMatrix = camera.transformMatrix(relativeTo: nil)
        let origin = SIMD3(cameraMatrix.columns.3.x, cameraMatrix.columns.3.y, cameraMatrix.columns.3.z)
        let direction4 = cameraMatrix * SIMD4(simd_normalize(SIMD3(x, y, -1)), 0)
        let direction = SIMD3(direction4.x, direction4.y, direction4.z)

        var best: (region: TapRegion, distance: Float)?
        for (entity, region, halfExtent) in hitBoxes {
            let inverse = entity.transformMatrix(relativeTo: nil).inverse
            let o = inverse * SIMD4(origin, 1), d = inverse * SIMD4(direction, 0)
            guard let t = Self.rayBox(origin: SIMD3(o.x, o.y, o.z), direction: SIMD3(d.x, d.y, d.z), halfExtent: halfExtent) else { continue }
            if best == nil || t < best!.distance { best = (region, t) }
        }
        return best?.region
    }

    /// Slab test: distance along the ray to an axis-aligned box centered at the origin, or nil on a miss.
    static func rayBox(origin: SIMD3<Float>, direction: SIMD3<Float>, halfExtent: SIMD3<Float>) -> Float? {
        var near = -Float.infinity, far = Float.infinity
        for axis in 0..<3 {
            if abs(direction[axis]) < 1e-6 {
                if abs(origin[axis]) > halfExtent[axis] { return nil }
                continue
            }
            let t1 = (-halfExtent[axis] - origin[axis]) / direction[axis]
            let t2 = (halfExtent[axis] - origin[axis]) / direction[axis]
            near = max(near, min(t1, t2))
            far = min(far, max(t1, t2))
        }
        return near <= far && far >= 0 ? max(near, 0) : nil
    }

    // MARK: Camera, lights, environment

    private func setUpCameraAndLights() {
        camera.camera.fieldOfViewInDegrees = 30
        scene.addChild(camera)

        let key = DirectionalLight()
        key.light.intensity = 450
        key.look(at: [0, 0.15, 0], from: [-0.6, 1.1, 0.9], relativeTo: nil)
        scene.addChild(key)

        let fill = PointLight()
        fill.light.intensity = 700
        fill.light.attenuationRadius = 3
        fill.position = [0.7, 0.3, 0.8]
        scene.addChild(fill)

        rimLight.light.attenuationRadius = 2
        rimLight.position = [0.1, 0.55, -0.45]
        scene.addChild(rimLight)

        if let environment = KoalaMaterials.environment {
            scene.components.set(ImageBasedLightComponent(source: .single(environment), intensityExponent: 3.2))
            let receivers: [Entity] = bodies.flatMap { [$0.entity, $0.core] } + (face?.models ?? [])
            for entity in receivers {
                entity.components.set(ImageBasedLightReceiverComponent(imageBasedLight: scene))
            }
        }
    }

}
