import CoreGraphics
import RealityKit
import simd
import UIKit

/// The molded koala mesh and its jelly data, built once off the main thread and shared by every Gummi on screen.
nonisolated enum KoalaMeshCache {
    static let cellSize: Float = 0.0065
    static let shared = Task.detached(priority: .userInitiated) { () -> JellySim in
        let shape = KoalaShape.standard
        return JellySim(mesh: SurfaceNets.mesh(shape: shape, cell: cellSize), shape: shape)
    }
}

/// Gummi as one molded jelly koala with face features riding on top, plus the camera, lights, and environment.
@MainActor
final class KoalaRig {
    /// A face feature placed on the surface. It follows its bone plus the jelly wobble of the nearest vertex.
    private struct Feature {
        let entity: Entity
        let bone: KoalaBone
        let position: SIMD3<Float>
        let orientation: simd_quatf
        let scale: SIMD3<Float>
        let anchor: Int
        var isEye = false
    }

    let scene = Entity()
    let camera = PerspectiveCamera()
    /// Gummi himself (body, features, tap targets). Spins turn this whole entity.
    private let puppetRoot = Entity()
    private let shape = KoalaShape.standard
    private let body: JellyBody
    private let hitRoot = Entity()
    private var features: [Feature] = []
    private var mouths: [MouthShape: Entity] = [:]
    private var currentMouth: MouthShape = .smile
    private let rimLight = PointLight()

    static let lookTarget = SIMD3<Float>(0, 0.2, 0.03)

    static func build() async -> KoalaRig? {
        let sim = await KoalaMeshCache.shared.value
        guard let body = try? await JellyBody.make(sim: sim, shape: .standard, material: KoalaMaterials.jelly(),
                                                   coreMaterial: KoalaMaterials.core()) else { return nil }
        return KoalaRig(body: body)
    }

    private init(body: JellyBody) {
        self.body = body
        scene.addChild(puppetRoot)
        puppetRoot.addChild(body.entity)
        puppetRoot.addChild(body.core)
        addFeatures()
        addHitTargets()
        setUpCameraAndLights()
        apply(PuppetPose(), dt: 0)
    }

    // MARK: Pose

    func apply(_ pose: PuppetPose, dt: Float) {
        let bones = KoalaSkeleton.matrices(for: pose, joints: shape.joints)
        body.update(bones: bones, dt: dt)
        puppetRoot.orientation = simd_quatf(angle: pose.rootYaw, axis: [0, 1, 0])

        for feature in features {
            var position = feature.position
            var scale = feature.scale
            if feature.isEye {
                position += feature.orientation.act(SIMD3(pose.eyeLook.x * 0.006, pose.eyeLook.y * 0.005, 0))
                scale.y *= max(pose.eyeOpen, 0.08)
            }
            let local = Transform(scale: scale, rotation: feature.orientation, translation: position).matrix
            var transform = Transform(matrix: bones[feature.bone.rawValue] * local)
            transform.translation += body.sim.wobble(at: feature.anchor)
            feature.entity.transform = transform
        }

        if pose.mouth != currentMouth {
            mouths[currentMouth]?.isEnabled = false
            mouths[pose.mouth]?.isEnabled = true
            currentMouth = pose.mouth
        }

        hitRoot.transform = Transform(matrix: bones[KoalaBone.hips.rawValue])

        rimLight.light.color = UIColor(red: CGFloat(pose.rimColor.x), green: CGFloat(pose.rimColor.y),
                                       blue: CGFloat(pose.rimColor.z), alpha: 1)
        rimLight.light.intensity = 4000 + 16000 * pose.rimStrength

        // The camera leans a few degrees toward the finger.
        let azimuth = 0.28 + pose.eyeLook.x * 0.06, elevation = 0.12 + pose.eyeLook.y * 0.04
        let distance: Float = 1.95
        camera.position = Self.lookTarget + SIMD3(sin(azimuth) * cos(elevation), sin(elevation), cos(azimuth) * cos(elevation)) * distance
        camera.look(at: Self.lookTarget, from: camera.position, relativeTo: nil)
    }

    /// The translucent-shell experiment: see-through jelly over a glowing core.
    func setTranslucent(_ translucent: Bool) {
        body.entity.model?.materials = [KoalaMaterials.jelly(translucent: translucent)]
        body.core.isEnabled = translucent
    }

    // MARK: Features

    private func addFeatures() {
        let sphere = MeshResource.generateSphere(radius: 1)
        let featureMaterial = KoalaMaterials.feature()

        func place(_ name: String, from origin: SIMD3<Float>, sink: Float, scale: SIMD3<Float>, bone: KoalaBone,
                   material: some RealityKit.Material, isEye: Bool = false) -> Entity {
            let hit = shape.surfacePoint(from: origin, direction: [0, 0, 1])
            let entity = ModelEntity(mesh: sphere, materials: [material])
            entity.name = name
            puppetRoot.addChild(entity)
            features.append(Feature(entity: entity, bone: bone, position: hit.point - hit.normal * sink,
                                    orientation: simd_quatf(from: [0, 0, 1], to: hit.normal), scale: scale,
                                    anchor: body.sim.nearestVertex(to: hit.point), isEye: isEye))
            return entity
        }

        for x: Float in [-0.042, 0.042] {
            let eye = place("eye", from: [x, 0.303, 0], sink: 0.002, scale: [0.0135, 0.016, 0.008], bone: .head,
                            material: featureMaterial, isEye: true)
            let glint = ModelEntity(mesh: sphere, materials: [KoalaMaterials.highlight()])
            glint.scale = [0.3, 0.26, 0.4]
            glint.position = [0.35, 0.4, 0.75]
            eye.addChild(glint)
        }
        _ = place("nose", from: [0, 0.289, 0], sink: 0.006, scale: [0.018, 0.022, 0.015], bone: .head,
                  material: KoalaMaterials.feature(lightness: 0.13))
        for (x, bone) in [(Float(-0.094), KoalaBone.leftEar), (0.094, .rightEar)] {
            _ = place("innerEar", from: [x, 0.362, -0.012], sink: 0.004, scale: [0.031, 0.03, 0.008], bone: bone,
                      material: KoalaMaterials.innerEar())
        }

        // Mouth expressions on one anchor, swapped per frame.
        let mouthHit = shape.surfacePoint(from: [0, 0.252, 0], direction: [0, 0, 1])
        let mouthAnchor = Entity()
        puppetRoot.addChild(mouthAnchor)
        features.append(Feature(entity: mouthAnchor, bone: .head, position: mouthHit.point + mouthHit.normal * 0.0008,
                                orientation: simd_quatf(from: [0, 0, 1], to: mouthHit.normal), scale: [1, 1, 1],
                                anchor: body.sim.nearestVertex(to: mouthHit.point)))
        let thickness: Float = 0.0026
        let shapes: [(MouthShape, Float, Float, Float)] = [
            (.smile, 0.016, 1.2 * .pi, 1.8 * .pi),
            (.bigSmile, 0.019, 1.12 * .pi, 1.88 * .pi),
            (.flat, 0.3, 1.5 * .pi - 0.05, 1.5 * .pi + 0.05),
            (.frown, 0.016, 0.2 * .pi, 0.8 * .pi),
        ]
        for (mouth, radius, start, end) in shapes {
            let group = Entity()
            if let tube = try? MeshFactory.arcTube(radius: radius, from: start, to: end, thickness: thickness) {
                group.addChild(ModelEntity(mesh: tube.mesh, materials: [featureMaterial]))
                for point in [tube.ends.0, tube.ends.1] {
                    let cap = ModelEntity(mesh: .generateSphere(radius: thickness), materials: [featureMaterial])
                    cap.position = point
                    group.addChild(cap)
                }
            }
            group.isEnabled = mouth == .smile
            mouthAnchor.addChild(group)
            mouths[mouth] = group
        }
        let yawn = ModelEntity(mesh: sphere, materials: [featureMaterial])
        yawn.scale = [0.01, 0.013, 0.004]
        yawn.position = [0, -0.004, 0]
        yawn.isEnabled = false
        mouthAnchor.addChild(yawn)
        mouths[.yawn] = yawn
    }

    /// Two tap targets: the head and the belly. They move with the hips.
    private func addHitTargets() {
        puppetRoot.addChild(hitRoot)
        for (name, center, radius) in [("head", SIMD3<Float>(0, 0.3, 0.004), Float(0.115)), ("belly", [0, 0.14, 0], 0.13)] {
            let target = Entity()
            target.name = name
            target.position = center
            target.components.set(CollisionComponent(shapes: [.generateSphere(radius: radius)]))
            target.components.set(InputTargetComponent())
            hitRoot.addChild(target)
        }
    }

    // MARK: Camera, lights, environment

    private func setUpCameraAndLights() {
        camera.camera.fieldOfViewInDegrees = 30
        scene.addChild(camera)

        let key = DirectionalLight()
        key.light.intensity = 2400
        key.look(at: [0, 0.15, 0], from: [-0.6, 1.1, 0.9], relativeTo: nil)
        scene.addChild(key)

        let fill = PointLight()
        fill.light.intensity = 9000
        fill.light.attenuationRadius = 3
        fill.position = [0.7, 0.3, 0.8]
        scene.addChild(fill)

        rimLight.light.attenuationRadius = 2
        rimLight.position = [0.1, 0.55, -0.45]
        scene.addChild(rimLight)

        if let image = Self.studioEnvironmentImage(), let environment = try? EnvironmentResource(equirectangular: image) {
            scene.components.set(ImageBasedLightComponent(source: .single(environment), intensityExponent: 0.6))
            var receivers: [Entity] = [body.entity, body.core]
            for feature in features {
                receivers.append(feature.entity)
                receivers += feature.entity.children
            }
            for group in mouths.values { receivers += group.children }
            for entity in receivers {
                entity.components.set(ImageBasedLightReceiverComponent(imageBasedLight: scene))
            }
        }
    }

    /// A soft studio: bright top, gray horizon, darker floor, and broad soft lights for wide, gentle highlights.
    private static func studioEnvironmentImage() -> CGImage? {
        let width = 512, height = 256
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let colors = [CGColor(gray: 0.32, alpha: 1), CGColor(gray: 0.62, alpha: 1), CGColor(gray: 0.92, alpha: 1)] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 0.5, 1]) {
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: height), options: [])
        }
        let soft = [CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0)] as CFArray
        if let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: soft, locations: [0, 1]) {
            for (center, radius) in [(CGPoint(x: 330, y: 190), CGFloat(70)), (CGPoint(x: 140, y: 170), CGFloat(45))] {
                context.drawRadialGradient(glow, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
            }
        }
        return context.makeImage()
    }
}
