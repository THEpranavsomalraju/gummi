import RealityKit
import simd
import UIKit

/// Gummi's face in an anime / Mii-inspired style (original, nothing copied): flat glossy decal eyes with highlights
/// that turn into "^ ^", "- -", "> <", sparkly, or small worried dots; thin brows that tilt with mood; blush for
/// happy moments; and mouth shapes from a small smile to an open grin. Every feature sits on the head's surface and
/// rides the head bone plus the jelly wobble under it.
@MainActor
final class KoalaFace {
    /// A spot on the head's surface. Features hang off it.
    private struct Anchor {
        let entity: Entity
        let bone: KoalaBone
        let position: SIMD3<Float>
        let orientation: simd_quatf
        let vertex: Int
    }

    private struct Eye {
        /// The glossy oval with its highlights; it blinks, follows the finger, and grows or shrinks.
        let open: Entity
        let sparkle: Entity
        let variants: [EyeShape: Entity]
    }

    static let eyeSize = SIMD3<Float>(0.0118, 0.0165, 0.004)

    private var anchors: [Anchor] = []
    private var eyes: [Eye] = []
    private var brows: [(entity: Entity, side: Float)] = []
    private var blushes: [Entity] = []
    private var mouths: [MouthShape: Entity] = [:]
    private var currentMouth = MouthShape.smile
    /// Every model in the face, so the rig can light them with the studio environment.
    private(set) var models: [ModelEntity] = []

    init(root: Entity, head: KoalaPiece, sim: JellySim) throws {
        let ink = KoalaMaterials.feature()
        let white = KoalaMaterials.highlight()
        let disc = try MeshFactory.domeDisc()
        let sphere = MeshResource.generateSphere(radius: 1)

        func anchor(_ origin: SIMD3<Float>, bone: KoalaBone = .head, lift: Float = 0.0005) -> Entity {
            let hit = head.surfacePoint(from: origin, direction: [0, 0, 1])
            let entity = Entity()
            root.addChild(entity)
            anchors.append(Anchor(entity: entity, bone: bone, position: hit.point + hit.normal * lift,
                                  orientation: simd_quatf(from: [0, 0, 1], to: hit.normal), vertex: sim.nearestVertex(to: hit.point)))
            return entity
        }
        func model(_ mesh: MeshResource, _ material: some RealityKit.Material, scale: SIMD3<Float>,
                   at position: SIMD3<Float> = .zero, in parent: Entity) -> ModelEntity {
            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.scale = scale
            entity.position = position
            parent.addChild(entity)
            models.append(entity)
            return entity
        }
        func tube(_ shape: (mesh: MeshResource, ends: (SIMD3<Float>, SIMD3<Float>)), thickness: Float,
                  joints: [SIMD3<Float>] = [], at position: SIMD3<Float> = .zero, in parent: Entity) -> Entity {
            let group = Entity()
            group.position = position
            parent.addChild(group)
            _ = model(shape.mesh, ink, scale: [1, 1, 1], in: group)
            for point in [shape.ends.0, shape.ends.1] + joints {
                _ = model(sphere, ink, scale: SIMD3(repeating: thickness), at: point, in: group)
            }
            return group
        }

        // Eyes.
        for side: Float in [-1, 1] {
            let spot = anchor([side * 0.04, 0.318, 0.006])
            let open = Entity()
            spot.addChild(open)
            _ = model(disc, ink, scale: Self.eyeSize, in: open)
            _ = model(disc, white, scale: [0.0042, 0.0042, 0.001], at: [-0.0035, 0.0062, 0.0042], in: open)
            _ = model(disc, white, scale: [0.002, 0.002, 0.0006], at: [0.0032, -0.0055, 0.0042], in: open)
            let sparkle = Entity()
            open.addChild(sparkle)
            _ = model(disc, white, scale: [0.0008, 0.0048, 0.0005], at: [0.0052, 0.0062, 0.0046], in: sparkle)
            _ = model(disc, white, scale: [0.0048, 0.0008, 0.0005], at: [0.0052, 0.0062, 0.0046], in: sparkle)
            _ = model(disc, white, scale: [0.0026, 0.0026, 0.0005], at: [-0.004, -0.002, 0.0044], in: sparkle)

            let thickness: Float = 0.0021
            let happy = tube(try MeshFactory.arcTube(radius: 0.01, from: 0.2 * .pi, to: 0.8 * .pi, thickness: thickness),
                             thickness: thickness, at: [0, -0.002, 0.001], in: spot)
            let sleepy = tube(try MeshFactory.arcTube(radius: 0.024, from: 1.36 * .pi, to: 1.64 * .pi, thickness: thickness),
                              thickness: thickness, at: [0, -0.001, 0.001], in: spot)
            // ">" on the left eye, "<" on the right: both point toward the nose.
            let tip = SIMD3<Float>(-side * 0.005, 0, 0)
            let chevron = [SIMD3<Float>(side * 0.006, 0.006, 0), tip, SIMD3<Float>(side * 0.006, -0.006, 0)]
            let squeeze = tube(try MeshFactory.polylineTube(chevron, thickness: thickness), thickness: thickness,
                               joints: [tip], at: [0, 0, 0.001], in: spot)
            eyes.append(Eye(open: open, sparkle: sparkle, variants: [.happy: happy, .sleepy: sleepy, .squeeze: squeeze]))
        }

        // Brows: thin gentle arcs above the eyes.
        for side: Float in [-1, 1] {
            let spot = anchor([side * 0.041, 0.348, 0.006])
            let brow = tube(try MeshFactory.arcTube(radius: 0.03, from: 0.4 * .pi, to: 0.6 * .pi, thickness: 0.0018),
                            thickness: 0.0018, in: spot)
            brows.append((brow, side))
        }

        // Blush on the cheeks, only in happy moments.
        for side: Float in [-1, 1] {
            let spot = anchor([side * 0.064, 0.29, 0.006], lift: 0.0008)
            let blush = model(disc, KoalaMaterials.blush(), scale: [0.016, 0.0095, 0.002], in: spot)
            blush.isEnabled = false
            blushes.append(blush)
        }

        // The koala nose: smaller and flatter than before, so the eyes lead.
        let nose = anchor([0, 0.303, 0.006], lift: 0)
        _ = model(sphere, KoalaMaterials.feature(lightness: 0.13), scale: [0.016, 0.02, 0.011], at: [0, 0, -0.005], in: nose)

        // Inner ears.
        for (x, bone) in [(Float(-0.094), KoalaBone.leftEar), (0.094, .rightEar)] {
            let ear = anchor([x, 0.375, -0.012], bone: bone, lift: 0)
            _ = model(sphere, KoalaMaterials.innerEar(), scale: [0.031, 0.03, 0.008], at: [0, 0, -0.004], in: ear)
        }

        // Mouths.
        let mouth = anchor([0, 0.267, 0.006], lift: 0.0008)
        let thickness: Float = 0.0024
        let pi = Float.pi
        let arcs: [(MouthShape, Float, Float, Float)] = [
            (.smile, 0.016, 1.2 * pi, 1.8 * pi),
            (.bigSmile, 0.019, 1.12 * pi, 1.88 * pi),
            (.flat, 0.3, 1.5 * pi - 0.04, 1.5 * pi + 0.04),
            (.frown, 0.016, 0.2 * pi, 0.8 * pi),
        ]
        for (shape, radius, start, end) in arcs {
            mouths[shape] = tube(try MeshFactory.arcTube(radius: radius, from: start, to: end, thickness: thickness),
                                 thickness: thickness, in: mouth)
        }
        let wave = (0...12).map { i -> SIMD3<Float> in
            let x = -0.011 + 0.022 * Float(i) / 12
            return [x, 0.0018 * sin(x / 0.011 * 2 * .pi), 0]
        }
        mouths[.wavy] = tube(try MeshFactory.polylineTube(wave, thickness: 0.0021), thickness: 0.0021, in: mouth)
        let yawn = Entity()
        mouth.addChild(yawn)
        _ = model(disc, ink, scale: [0.0085, 0.011, 0.002], at: [0, -0.004, 0], in: yawn)
        mouths[.yawn] = yawn
        let surprised = Entity()
        mouth.addChild(surprised)
        _ = model(disc, ink, scale: [0.0045, 0.0055, 0.0015], at: [0, -0.002, 0], in: surprised)
        mouths[.surprised] = surprised
        let grin = Entity()
        mouth.addChild(grin)
        _ = model(try MeshFactory.domeDisc(dome: 0.25, fromAngle: .pi, toAngle: 2 * .pi), ink, scale: [0.012, 0.011, 0.0025],
                  at: [0, 0.002, 0], in: grin)
        _ = model(disc, KoalaMaterials.tongue(), scale: [0.0058, 0.0034, 0.0028], at: [0, -0.0058, 0.0004], in: grin)
        mouths[.grin] = grin
        for (shape, group) in mouths { group.isEnabled = shape == .smile }
    }

    func apply(_ pose: PuppetPose, bones: [simd_float4x4], wobble: (Int) -> SIMD3<Float>) {
        for anchor in anchors {
            let local = Transform(rotation: anchor.orientation, translation: anchor.position).matrix
            var transform = Transform(matrix: bones[anchor.bone.rawValue] * local)
            transform.translation += wobble(anchor.vertex)
            anchor.entity.transform = transform
        }

        let isOpen = pose.eyes == .open || pose.eyes == .sparkle || pose.eyes == .small
        let size: Float = pose.eyes == .sparkle ? 1.15 : pose.eyes == .small ? 0.62 : 1
        for eye in eyes {
            eye.open.isEnabled = isOpen
            eye.sparkle.isEnabled = pose.eyes == .sparkle
            if isOpen {
                eye.open.position = [pose.eyeLook.x * 0.005, pose.eyeLook.y * 0.004, 0]
                eye.open.scale = [size, size * max(pose.eyeOpen, 0.08), 1]
            }
            for (shape, entity) in eye.variants { entity.isEnabled = shape == pose.eyes }
        }

        for (brow, side) in brows {
            brow.transform = Transform(rotation: simd_quatf(angle: -side * pose.browTilt * 0.38, axis: [0, 0, 1]),
                                       translation: [0, pose.browRaise * 0.0045, 0.0005])
        }

        for blush in blushes {
            blush.isEnabled = pose.blush > 0.02
            blush.scale = SIMD3<Float>(0.016, 0.0095, 0.002) * max(pose.blush, 0.02)
        }

        if pose.mouth != currentMouth {
            mouths[currentMouth]?.isEnabled = false
            mouths[pose.mouth]?.isEnabled = true
            currentMouth = pose.mouth
        }
    }
}
