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

/// Gummi standing about 42 cm tall, feet at y = 0, facing +z: a round head with koala ears on a short pear body,
/// with separate short arms and stubby legs that tuck in at low shoulders and the hips.
nonisolated struct KoalaShape: Sendable {
    let pieces: [KoalaPiece]
    /// Joint pivots in model space.
    let joints: [KoalaBone: SIMD3<Float>]

    func piece(named name: String) -> KoalaPiece? { pieces.first { $0.name == name } }

    static let standard: KoalaShape = {
        func arm(_ side: Float, _ bone: KoalaBone) -> KoalaPiece {
            // No shoulder bump: the arm's top leans in and sinks into the upper torso, so the shoulder slopes
            // down from the body; the arm tapers to a smaller hand and hangs with a gap down the side.
            KoalaPiece(name: side < 0 ? "leftArm" : "rightArm", parts: [
                // Root: sunk into the upper torso, it widens the arm where it meets the body (a slope, not a bump).
                ShapePart(bone: bone, center: [side * 0.082, 0.204, 0.0], radii: [0.03, 0.028, 0.029], softness: 0.4),
                ShapePart(bone: bone, center: [side * 0.116, 0.166, 0.004], radii: [0.028, 0.05, 0.029], roll: side * 0.38, blend: 0.04, softness: 0.5),
                ShapePart(bone: bone, center: [side * 0.132, 0.119, 0.01], radii: [0.024, 0.025, 0.026], blend: 0.03, softness: 0.65),
            ], boundsMin: [side < 0 ? -0.19 : 0.04, 0.05, -0.06], boundsMax: [side < 0 ? -0.04 : 0.19, 0.26, 0.07],
            cell: 0.005, center: [side * 0.115, 0.15, 0.006])
        }
        func leg(_ side: Float, _ bone: KoalaBone) -> KoalaPiece {
            // Stubby legs; the torso and legs trade length so his total height stays the same.
            KoalaPiece(name: side < 0 ? "leftLeg" : "rightLeg", parts: [
                ShapePart(bone: bone, center: [side * 0.048, 0.056, 0.008], radii: [0.041, 0.052, 0.041], softness: 0.2),
                ShapePart(bone: bone, center: [side * 0.048, 0.029, 0.03], radii: [0.04, 0.026, 0.044], blend: 0.02, softness: 0.3),
            ], boundsMin: [side * 0.048 - 0.06, -0.015, -0.05], boundsMax: [side * 0.048 + 0.06, 0.13, 0.09],
            cell: 0.005, center: [side * 0.048, 0.06, 0.012])
        }
        return KoalaShape(
            pieces: [
                KoalaPiece(name: "torso", parts: [
                    ShapePart(bone: .hips, center: [0, 0.142, 0], radii: [0.086, 0.094, 0.079], softness: 0.75),
                    ShapePart(bone: .chest, center: [0, 0.207, -0.004], radii: [0.079, 0.064, 0.071], blend: 0.038, softness: 0.5),
                ], boundsMin: [-0.12, 0.02, -0.11], boundsMax: [0.12, 0.3, 0.11], cell: 0.0065, center: [0, 0.165, 0]),
                KoalaPiece(name: "head", parts: [
                    ShapePart(bone: .head, center: [0, 0.31, 0.006], radii: [0.104, 0.097, 0.096], softness: 0.3),
                    ShapePart(bone: .leftEar, center: [-0.094, 0.375, -0.012], radii: [0.05, 0.048, 0.024], blend: 0.014, softness: 0.85),
                    ShapePart(bone: .rightEar, center: [0.094, 0.375, -0.012], radii: [0.05, 0.048, 0.024], blend: 0.014, softness: 0.85),
                ], boundsMin: [-0.17, 0.2, -0.11], boundsMax: [0.17, 0.44, 0.12], cell: 0.006, center: [0, 0.31, 0.006]),
                arm(-1, .leftArm), arm(1, .rightArm),
                leg(-1, .leftLeg), leg(1, .rightLeg),
            ],
            joints: [
                .hips: [0, 0.085, 0], .chest: [0, 0.185, 0], .head: [0, 0.25, 0.004],
                .leftEar: [-0.072, 0.358, -0.012], .rightEar: [0.072, 0.358, -0.012],
                .leftArm: [-0.092, 0.208, 0.004], .rightArm: [0.092, 0.208, 0.004],
                .leftLeg: [-0.048, 0.095, 0.008], .rightLeg: [0.048, 0.095, 0.008],
            ])
    }()

    /// Polynomial smooth minimum.
    static func smoothMin(_ a: Float, _ b: Float, _ k: Float) -> Float {
        guard k > 0 else { return min(a, b) }
        let h = max(k - abs(a - b), 0) / k
        return min(a, b) - h * h * k * 0.25
    }
}
