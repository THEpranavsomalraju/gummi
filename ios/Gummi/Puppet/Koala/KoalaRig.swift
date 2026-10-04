import CoreGraphics
import RealityKit
import simd
import UIKit

/// Gummi as a koala, built in code from soft ellipsoids. About 35 cm tall, sitting with legs out and arms at his sides.
/// Faces +z. The root sits at the seat, so squash and stretch pivot from where he sits.
@MainActor
final class KoalaRig {
    /// Everything RealityView adds: camera, lights, environment, and Gummi.
    let scene = Entity()
    let camera = PerspectiveCamera()
    /// Gummi's root: taps hit its collision shape.
    let root = Entity()

    private let bodyPivot = Entity()
    private let body: ModelEntity
    private let core: ModelEntity
    private let headPivot = Entity()
    private let leftEar = Entity(), rightEar = Entity()
    private let leftArm = Entity(), rightArm = Entity()
    private let leftEye: ModelEntity, rightEye: ModelEntity
    private var mouths: [MouthShape: Entity] = [:]
    private var currentMouth: MouthShape = .smile
    private let rimLight = PointLight()
    private var jellyParts: [ModelEntity] = []

    static let eyeScale = SIMD3<Float>(0.0135, 0.016, 0.008)
    static let restArmRoll: Float = 0.2
    static let lookTarget = SIMD3<Float>(0, 0.165, 0.03)

    init() {
        let jelly = KoalaMaterials.jelly()
        let sphere = MeshResource.generateSphere(radius: 1)

        func part(_ name: String, _ material: some RealityKit.Material, scale: SIMD3<Float>, at position: SIMD3<Float>,
                  parent: Entity) -> ModelEntity {
            let entity = ModelEntity(mesh: sphere, materials: [material])
            entity.name = name
            entity.scale = scale
            entity.position = position
            parent.addChild(entity)
            return entity
        }

        scene.addChild(root)
        root.addChild(bodyPivot)

        // Body: a soft pear, slightly wider at the bottom.
        body = part("body", jelly, scale: [0.088, 0.098, 0.078], at: [0, 0.088, 0], parent: bodyPivot)
        core = part("core", KoalaMaterials.core(), scale: [0.07, 0.08, 0.06], at: [0, 0.088, 0], parent: bodyPivot)
        core.isEnabled = false
        _ = part("belly", jelly, scale: [0.075, 0.06, 0.07], at: [0, 0.05, 0.012], parent: bodyPivot)

        // Legs straight out front, slightly apart, with round feet and paw pads.
        for side: Float in [-1, 1] {
            let hip = Entity()
            hip.position = [side * 0.046, 0.034, 0.02]
            hip.orientation = simd_quatf(angle: side * 0.16, axis: [0, 1, 0])
            bodyPivot.addChild(hip)
            _ = part("leg", jelly, scale: [0.036, 0.033, 0.066], at: [0, 0, 0.055], parent: hip)
            _ = part("foot", jelly, scale: [0.038, 0.043, 0.03], at: [0, 0.014, 0.112], parent: hip)
            _ = part("pad", KoalaMaterials.innerEar(), scale: [0.022, 0.026, 0.006], at: [0, 0.016, 0.139], parent: hip)
        }

        // Arms hang at the sides, hands resting by the hips.
        for (side, arm) in [(Float(-1), leftArm), (Float(1), rightArm)] {
            arm.position = [side * 0.074, 0.142, 0.008]
            bodyPivot.addChild(arm)
            _ = part("arm", jelly, scale: [0.029, 0.062, 0.03], at: [0, -0.056, 0.008], parent: arm)
        }

        // Head: big and round (chibi), on a neck pivot.
        headPivot.position = [0, 0.158, 0.004]
        bodyPivot.addChild(headPivot)
        _ = part("head", jelly, scale: [0.116, 0.103, 0.099], at: [0, 0.087, 0], parent: headPivot)

        // Ears: round, a little flattened, with lighter inner discs. Pivot near the head so they can droop and wobble.
        for (side, ear) in [(Float(-1), leftEar), (Float(1), rightEar)] {
            ear.position = [side * 0.082, 0.132, -0.012]
            headPivot.addChild(ear)
            _ = part("ear", jelly, scale: [0.061, 0.059, 0.028], at: [side * 0.03, 0.026, 0], parent: ear)
            _ = part("innerEar", KoalaMaterials.innerEar(), scale: [0.038, 0.037, 0.01], at: [side * 0.03, 0.026, 0.02], parent: ear)
        }

        // Face: glossy oval nose, dark eyes with highlights.
        let feature = KoalaMaterials.feature()
        _ = part("nose", KoalaMaterials.feature(lightness: 0.13), scale: [0.019, 0.024, 0.016], at: [0, 0.08, 0.097], parent: headPivot)
        leftEye = part("eye", feature, scale: Self.eyeScale, at: [-0.047, 0.1, 0.085], parent: headPivot)
        rightEye = part("eye", feature, scale: Self.eyeScale, at: [0.047, 0.1, 0.085], parent: headPivot)
        for eye in [leftEye, rightEye] {
            let glint = ModelEntity(mesh: sphere, materials: [KoalaMaterials.highlight()])
            glint.scale = [0.3, 0.26, 0.4]
            glint.position = [0.35, 0.4, 0.75]
            eye.addChild(glint)
        }

        jellyParts = [body] + bodyPivot.descendants(named: ["belly", "leg", "foot", "arm", "head", "ear"])

        // Mouth expressions, prebuilt and swapped.
        let mouthAnchor = Entity()
        mouthAnchor.position = [0, 0.04, 0.088]
        headPivot.addChild(mouthAnchor)
        let thickness: Float = 0.0026
        let shapes: [(MouthShape, Float, Float, Float)] = [
            (.smile, 0.017, 1.2 * .pi, 1.8 * .pi),
            (.bigSmile, 0.02, 1.12 * .pi, 1.88 * .pi),
            (.flat, 0.3, 1.5 * .pi - 0.055, 1.5 * .pi + 0.055),
            (.frown, 0.017, 0.2 * .pi, 0.8 * .pi),
        ]
        for (shape, radius, start, end) in shapes {
            let group = Entity()
            if let tube = try? MeshFactory.arcTube(radius: radius, from: start, to: end, thickness: thickness) {
                group.addChild(ModelEntity(mesh: tube.mesh, materials: [feature]))
                for point in [tube.ends.0, tube.ends.1] {
                    let cap = ModelEntity(mesh: .generateSphere(radius: thickness), materials: [feature])
                    cap.position = point
                    group.addChild(cap)
                }
            }
            group.isEnabled = shape == .smile
            mouthAnchor.addChild(group)
            mouths[shape] = group
        }
        let yawn = ModelEntity(mesh: sphere, materials: [feature])
        yawn.scale = [0.011, 0.014, 0.004]
        yawn.position = [0, -0.004, 0]
        yawn.isEnabled = false
        mouthAnchor.addChild(yawn)
        mouths[.yawn] = yawn

        // Taps: one soft box around the whole koala.
        root.components.set(CollisionComponent(shapes: [ShapeResource.generateBox(size: [0.26, 0.38, 0.3])
            .offsetBy(translation: [0, 0.17, 0.05])]))
        root.components.set(InputTargetComponent())

        setUpCameraAndLights()
    }

    // MARK: Pose

    func apply(_ pose: PuppetPose) {
        root.position = pose.rootOffset
        root.orientation = simd_quatf(angle: pose.rootYaw, axis: [0, 1, 0])
        root.scale = pose.rootScale

        bodyPivot.orientation = simd_quatf(angle: pose.bodyPitch, axis: [1, 0, 0]) * simd_quatf(angle: pose.bodyRoll, axis: [0, 0, 1])
        body.scale = SIMD3(0.088, 0.098, 0.078) * pose.bodyScale

        headPivot.orientation = simd_quatf(angle: pose.headYaw, axis: [0, 1, 0])
            * simd_quatf(angle: pose.headPitch, axis: [1, 0, 0])
            * simd_quatf(angle: pose.headRoll, axis: [0, 0, 1])

        leftEar.orientation = simd_quatf(angle: pose.leftEarRoll, axis: [0, 0, 1])
        rightEar.orientation = simd_quatf(angle: pose.rightEarRoll, axis: [0, 0, 1])

        leftArm.orientation = simd_quatf(angle: -Self.restArmRoll + pose.leftArmRoll, axis: [0, 0, 1])
            * simd_quatf(angle: pose.leftArmPitch, axis: [1, 0, 0])
        rightArm.orientation = simd_quatf(angle: Self.restArmRoll + pose.rightArmRoll, axis: [0, 0, 1])
            * simd_quatf(angle: pose.rightArmPitch, axis: [1, 0, 0])

        let look = SIMD3(pose.eyeLook.x * 0.007, pose.eyeLook.y * 0.006, 0)
        for (eye, x) in [(leftEye, Float(-0.047)), (rightEye, Float(0.047))] {
            eye.position = SIMD3(x, 0.1, 0.085) + look
            eye.scale = SIMD3(Self.eyeScale.x, Self.eyeScale.y * max(pose.eyeOpen, 0.08), Self.eyeScale.z)
        }

        if pose.mouth != currentMouth {
            mouths[currentMouth]?.isEnabled = false
            mouths[pose.mouth]?.isEnabled = true
            currentMouth = pose.mouth
        }

        rimLight.light.color = UIColor(red: CGFloat(pose.rimColor.x), green: CGFloat(pose.rimColor.y),
                                       blue: CGFloat(pose.rimColor.z), alpha: 1)
        rimLight.light.intensity = 4000 + 16000 * pose.rimStrength

        // The camera leans a few degrees toward the finger.
        let azimuth = 0.3 + pose.eyeLook.x * 0.07, elevation = 0.17 + pose.eyeLook.y * 0.05
        let distance: Float = 1.45
        camera.position = Self.lookTarget + SIMD3(sin(azimuth) * cos(elevation), sin(elevation), cos(azimuth) * cos(elevation)) * distance
        camera.look(at: Self.lookTarget, from: camera.position, relativeTo: nil)
    }

    /// The translucent-shell experiment: see-through jelly over a darker core.
    func setTranslucent(_ translucent: Bool) {
        let material = KoalaMaterials.jelly(translucent: translucent)
        for part in jellyParts { part.model?.materials = [material] }
        core.isEnabled = translucent
    }

    // MARK: Camera, lights, environment

    private func setUpCameraAndLights() {
        camera.camera.fieldOfViewInDegrees = 30
        scene.addChild(camera)

        let key = DirectionalLight()
        key.light.intensity = 2600
        key.look(at: [0, 0, 0], from: [-0.6, 1.1, 0.9], relativeTo: nil)
        scene.addChild(key)

        let fill = PointLight()
        fill.light.intensity = 9000
        fill.light.attenuationRadius = 3
        fill.position = [0.7, 0.3, 0.8]
        scene.addChild(fill)

        rimLight.light.attenuationRadius = 2
        rimLight.position = [0.1, 0.5, -0.45]
        scene.addChild(rimLight)

        if let image = Self.studioEnvironmentImage(),
           let environment = try? EnvironmentResource(equirectangular: image) {
            scene.components.set(ImageBasedLightComponent(source: .single(environment), intensityExponent: 0.6))
            for model in root.descendants(named: nil) {
                model.components.set(ImageBasedLightReceiverComponent(imageBasedLight: scene))
            }
        }
    }

    /// A soft studio: bright top, gray horizon, darker floor, and two softboxes for glossy highlights.
    private static func studioEnvironmentImage() -> CGImage? {
        let width = 512, height = 256
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let colors = [CGColor(gray: 0.3, alpha: 1), CGColor(gray: 0.62, alpha: 1), CGColor(gray: 0.95, alpha: 1)] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 0.5, 1]) {
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: height), options: [])
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 300, y: 170, width: 90, height: 50))
        context.fill(CGRect(x: 120, y: 150, width: 50, height: 40))
        return context.makeImage()
    }
}

private extension Entity {
    /// Descendants, optionally filtered by name.
    func descendants(named names: Set<String>?) -> [ModelEntity] {
        var found: [ModelEntity] = []
        for child in children {
            if let model = child as? ModelEntity, names?.contains(model.name) ?? true { found.append(model) }
            found += child.descendants(named: names)
        }
        return found
    }
}
