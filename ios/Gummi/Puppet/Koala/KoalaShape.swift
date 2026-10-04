import simd

/// Gummi's skeleton. Each bone moves part of the one-piece jelly body.
nonisolated enum KoalaBone: Int, CaseIterable, Sendable {
    case hips, chest, head, leftEar, rightEar, leftArm, rightArm, leftLeg, rightLeg

    var parent: KoalaBone? {
        switch self {
        case .hips, .leftLeg, .rightLeg: nil
        case .chest: .hips
        case .head, .leftArm, .rightArm: .chest
        case .leftEar, .rightEar: .head
        }
    }
}

/// One ellipsoid of the mold. Parts are smooth-unioned in order, so later parts melt into earlier ones.
nonisolated struct ShapePart: Sendable {
    let bone: KoalaBone
    let center: SIMD3<Float>
    let radii: SIMD3<Float>
    /// Tilt about z (arms hang slightly outward).
    var roll: Float = 0
    /// Smooth-union radius when joining the shape so far, in meters. Bigger melts more.
    var blend: Float = 0.02
    /// Jelly softness 0 (firm) to 1 (wobbly).
    var softness: Float = 0.4

    func distance(_ p: SIMD3<Float>) -> Float {
        var local = p - center
        if roll != 0 {
            let c = cos(-roll), s = sin(-roll)
            local = SIMD3(c * local.x - s * local.y, s * local.x + c * local.y, local.z)
        }
        return Self.ellipsoid(local, radii)
    }

    /// Inigo Quilez's ellipsoid distance bound.
    static func ellipsoid(_ p: SIMD3<Float>, _ r: SIMD3<Float>) -> Float {
        let k0 = simd_length(p / r)
        let k1 = simd_length(p / (r * r))
        return k1 > 0 ? k0 * (k0 - 1) / k1 : -r.min()
    }
}

/// Gummi as a signed-distance shape: one molded jelly koala, standing about 40 cm tall, feet at y = 0, facing +z.
/// Proportions sit about halfway between the original chibi koala and a bean-shaped mascot:
/// the head sinks into a pear body, arms hang long from the upper sides, legs are short stubs.
nonisolated struct KoalaShape: Sendable {
    let parts: [ShapePart]
    /// Joint pivots in model space.
    let joints: [KoalaBone: SIMD3<Float>]
    let boundsMin = SIMD3<Float>(-0.19, -0.012, -0.14)
    let boundsMax = SIMD3<Float>(0.19, 0.43, 0.14)

    static let standard = KoalaShape(
        parts: [
            ShapePart(bone: .leftLeg, center: [-0.045, 0.04, 0.008], radii: [0.037, 0.04, 0.039], softness: 0.15),
            ShapePart(bone: .rightLeg, center: [0.045, 0.04, 0.008], radii: [0.037, 0.04, 0.039], blend: 0.012, softness: 0.15),
            ShapePart(bone: .hips, center: [0, 0.135, 0], radii: [0.1, 0.104, 0.088], blend: 0.03, softness: 0.75),
            ShapePart(bone: .chest, center: [0, 0.205, -0.004], radii: [0.088, 0.08, 0.078], blend: 0.04, softness: 0.5),
            ShapePart(bone: .head, center: [0, 0.295, 0.004], radii: [0.106, 0.093, 0.092], blend: 0.05, softness: 0.35),
            ShapePart(bone: .leftEar, center: [-0.094, 0.362, -0.012], radii: [0.05, 0.048, 0.024], blend: 0.014, softness: 0.85),
            ShapePart(bone: .rightEar, center: [0.094, 0.362, -0.012], radii: [0.05, 0.048, 0.024], blend: 0.014, softness: 0.85),
            ShapePart(bone: .leftArm, center: [-0.112, 0.168, 0.006], radii: [0.031, 0.072, 0.033], roll: -0.22, blend: 0.02, softness: 0.6),
            ShapePart(bone: .rightArm, center: [0.112, 0.168, 0.006], radii: [0.031, 0.072, 0.033], roll: 0.22, blend: 0.02, softness: 0.6),
            ShapePart(bone: .leftArm, center: [-0.127, 0.1, 0.012], radii: [0.032, 0.03, 0.032], blend: 0.014, softness: 0.7),
            ShapePart(bone: .rightArm, center: [0.127, 0.1, 0.012], radii: [0.032, 0.03, 0.032], blend: 0.014, softness: 0.7),
        ],
        joints: [
            .hips: [0, 0.075, 0], .chest: [0, 0.17, 0], .head: [0, 0.24, 0],
            .leftEar: [-0.07, 0.345, -0.012], .rightEar: [0.07, 0.345, -0.012],
            .leftArm: [-0.09, 0.235, 0], .rightArm: [0.09, 0.235, 0],
            .leftLeg: [-0.045, 0.075, 0.004], .rightLeg: [0.045, 0.075, 0.004],
        ])

    func distance(_ p: SIMD3<Float>) -> Float {
        var d = parts[0].distance(p)
        for part in parts.dropFirst() {
            d = Self.smoothMin(d, part.distance(p), part.blend)
        }
        return d
    }

    func gradient(_ p: SIMD3<Float>, epsilon e: Float = 0.0005) -> SIMD3<Float> {
        SIMD3(distance(p + [e, 0, 0]) - distance(p - [e, 0, 0]),
              distance(p + [0, e, 0]) - distance(p - [0, e, 0]),
              distance(p + [0, 0, e]) - distance(p - [0, 0, e])) / (2 * e)
    }

    /// Where a ray from `origin` (inside the shape) along `direction` leaves the surface, with the outward normal.
    func surfacePoint(from origin: SIMD3<Float>, direction: SIMD3<Float>) -> (point: SIMD3<Float>, normal: SIMD3<Float>) {
        var inside: Float = 0, outside: Float = 0.3
        var t: Float = 0
        while t < 0.3 {
            if distance(origin + direction * t) > 0 {
                outside = t
                break
            }
            inside = t
            t += 0.002
        }
        for _ in 0..<24 {
            let mid = (inside + outside) / 2
            if distance(origin + direction * mid) > 0 { outside = mid } else { inside = mid }
        }
        let point = origin + direction * ((inside + outside) / 2)
        return (point, simd_normalize(gradient(point)))
    }

    /// Polynomial smooth minimum.
    static func smoothMin(_ a: Float, _ b: Float, _ k: Float) -> Float {
        guard k > 0 else { return min(a, b) }
        let h = max(k - abs(a - b), 0) / k
        return min(a, b) - h * h * k * 0.25
    }
}
