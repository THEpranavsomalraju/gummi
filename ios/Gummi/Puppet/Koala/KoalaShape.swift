import simd

/// Gummi's skeleton. Each bone moves one jelly piece (or part of the torso).
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

/// One ellipsoid of a piece's mold. Parts are smooth-unioned in order, so later parts melt into earlier ones.
nonisolated struct ShapePart: Sendable {
    let bone: KoalaBone
    let center: SIMD3<Float>
    let radii: SIMD3<Float>
    /// Tilt about z (arms hang slightly outward).
    var roll: Float = 0
    /// Smooth-union radius when joining the piece so far, in meters. Bigger melts more.
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

/// One separately molded jelly piece: the torso, the head (with its ears), an arm, or a leg.
/// Pieces tuck into each other at soft joints, like a vinyl toy made of gummy.
nonisolated struct KoalaPiece: Sendable {
    let name: String
    let parts: [ShapePart]
    let boundsMin: SIMD3<Float>
    let boundsMax: SIMD3<Float>
    /// Meshing resolution: smaller pieces get finer cells.
    let cell: Float
    /// Center used to scale the glowing core inside a translucent piece.
    let center: SIMD3<Float>

    func distance(_ p: SIMD3<Float>) -> Float {
        var d = parts[0].distance(p)
        for part in parts.dropFirst() {
            d = KoalaShape.smoothMin(d, part.distance(p), part.blend)
        }
        return d
    }

    func gradient(_ p: SIMD3<Float>, epsilon e: Float = 0.0005) -> SIMD3<Float> {
        SIMD3(distance(p + [e, 0, 0]) - distance(p - [e, 0, 0]),
              distance(p + [0, e, 0]) - distance(p - [0, e, 0]),
              distance(p + [0, 0, e]) - distance(p - [0, 0, e])) / (2 * e)
    }

    /// Where a ray from `origin` (inside the piece) along `direction` leaves the surface, with the outward normal.
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
}

/// Gummi standing about 42 cm tall, feet at y = 0, facing +z: a round head with koala ears on a pear body,
/// with separate arms and stubby legs that tuck in at the shoulders and hips.
nonisolated struct KoalaShape: Sendable {
    let pieces: [KoalaPiece]
    /// Joint pivots in model space.
    let joints: [KoalaBone: SIMD3<Float>]

    func piece(named name: String) -> KoalaPiece? { pieces.first { $0.name == name } }

    static let standard: KoalaShape = {
        func arm(_ side: Float, _ bone: KoalaBone) -> KoalaPiece {
            // A rounded shoulder tucks into the torso; the arm hangs from it with a gap down the side.
            KoalaPiece(name: side < 0 ? "leftArm" : "rightArm", parts: [
                ShapePart(bone: bone, center: [side * 0.1, 0.232, 0.004], radii: [0.032, 0.03, 0.032], softness: 0.4),
                ShapePart(bone: bone, center: [side * 0.132, 0.172, 0.008], radii: [0.034, 0.074, 0.035], roll: side * 0.2, blend: 0.022, softness: 0.55),
                ShapePart(bone: bone, center: [side * 0.148, 0.104, 0.014], radii: [0.036, 0.034, 0.036], blend: 0.016, softness: 0.65),
            ], boundsMin: [side < 0 ? -0.2 : 0.05, 0.04, -0.06], boundsMax: [side < 0 ? -0.05 : 0.2, 0.28, 0.07],
            cell: 0.005, center: [side * 0.138, 0.14, 0.01])
        }
        func leg(_ side: Float, _ bone: KoalaBone) -> KoalaPiece {
            KoalaPiece(name: side < 0 ? "leftLeg" : "rightLeg", parts: [
                ShapePart(bone: bone, center: [side * 0.048, 0.046, 0.008], radii: [0.04, 0.046, 0.041], softness: 0.2),
                ShapePart(bone: bone, center: [side * 0.048, 0.022, 0.03], radii: [0.039, 0.024, 0.042], blend: 0.016, softness: 0.3),
            ], boundsMin: [side * 0.048 - 0.06, -0.015, -0.05], boundsMax: [side * 0.048 + 0.06, 0.11, 0.09],
            cell: 0.005, center: [side * 0.048, 0.04, 0.012])
        }
        return KoalaShape(
            pieces: [
                KoalaPiece(name: "torso", parts: [
                    ShapePart(bone: .hips, center: [0, 0.135, 0], radii: [0.096, 0.104, 0.086], softness: 0.75),
                    ShapePart(bone: .chest, center: [0, 0.2, -0.004], radii: [0.084, 0.078, 0.076], blend: 0.04, softness: 0.5),
                ], boundsMin: [-0.12, 0.01, -0.11], boundsMax: [0.12, 0.3, 0.11], cell: 0.0065, center: [0, 0.16, 0]),
                KoalaPiece(name: "head", parts: [
                    ShapePart(bone: .head, center: [0, 0.31, 0.006], radii: [0.104, 0.097, 0.096], softness: 0.3),
                    ShapePart(bone: .leftEar, center: [-0.094, 0.375, -0.012], radii: [0.05, 0.048, 0.024], blend: 0.014, softness: 0.85),
                    ShapePart(bone: .rightEar, center: [0.094, 0.375, -0.012], radii: [0.05, 0.048, 0.024], blend: 0.014, softness: 0.85),
                ], boundsMin: [-0.17, 0.2, -0.11], boundsMax: [0.17, 0.44, 0.12], cell: 0.006, center: [0, 0.31, 0.006]),
                arm(-1, .leftArm), arm(1, .rightArm),
                leg(-1, .leftLeg), leg(1, .rightLeg),
            ],
            joints: [
                .hips: [0, 0.075, 0], .chest: [0, 0.17, 0], .head: [0, 0.25, 0.004],
                .leftEar: [-0.072, 0.358, -0.012], .rightEar: [0.072, 0.358, -0.012],
                .leftArm: [-0.112, 0.238, 0.004], .rightArm: [0.112, 0.238, 0.004],
                .leftLeg: [-0.048, 0.085, 0.008], .rightLeg: [0.048, 0.085, 0.008],
            ])
    }()

    /// Polynomial smooth minimum.
    static func smoothMin(_ a: Float, _ b: Float, _ k: Float) -> Float {
        guard k > 0 else { return min(a, b) }
        let h = max(k - abs(a - b), 0) / k
        return min(a, b) - h * h * k * 0.25
    }
}
