import simd

/// Keeps Gummi's arms from passing through his belly or head during dances and idles.
/// Each frame, sample spheres along each arm are checked against the torso and head shapes; any that sink in
/// swing the whole arm at the shoulder, just enough to slide along the surface. The correction is continuous,
/// so a point down and across the body passes in front of the stomach instead of through it.
nonisolated enum KoalaCollisions {
    /// Spheres along the right arm in rest space (mirrored for the left), from the upper arm down to the hand tip.
    /// The root at the shoulder is left out: it is meant to sink into the torso.
    static let rightArmSamples: [(center: SIMD3<Float>, radius: Float)] = [
        ([0.116, 0.166, 0.004], 0.026),
        ([0.124, 0.142, 0.007], 0.025),
        ([0.132, 0.119, 0.01], 0.023),
        ([0.134, 0.1, 0.01], 0.017),
    ]

    /// Extra space kept between a sample sphere and the body.
    static let margin: Float = 0.003

    static func samples(for bone: KoalaBone) -> [(center: SIMD3<Float>, radius: Float)] {
        let mirror: Float = bone == .leftArm ? -1 : 1
        return rightArmSamples.map { (SIMD3($0.center.x * mirror, $0.center.y, $0.center.z), $0.radius) }
    }

    /// Rotates the arm bones in `bones` out of the torso and head. Returns the largest correction angle applied.
    @discardableResult
    static func resolveArms(_ bones: inout [simd_float4x4], shape: KoalaShape) -> Float {
        guard let torso = shape.piece(named: "torso"), let head = shape.piece(named: "head") else { return 0 }
        let obstacles: [(piece: KoalaPiece, bone: KoalaBone)] = [(torso, .hips), (head, .head)]
        let inverses = obstacles.map { bones[$0.bone.rawValue].inverse }
        var largest: Float = 0

        for armBone in [KoalaBone.leftArm, .rightArm] {
            guard let joint = shape.joints[armBone] else { continue }
            var arm = bones[armBone.rawValue]
            let samples = samples(for: armBone)
            for _ in 0..<4 {
                var worst: (depth: Float, point: SIMD3<Float>, normal: SIMD3<Float>)?
                for sample in samples {
                    let p4 = arm * SIMD4(sample.center, 1)
                    let point = SIMD3(p4.x, p4.y, p4.z)
                    for (index, obstacle) in obstacles.enumerated() {
                        let q4 = inverses[index] * SIMD4(point, 1)
                        let q = SIMD3(q4.x, q4.y, q4.z)
                        let clearance = obstacle.piece.distance(q) - sample.radius
                        guard clearance < margin else { continue }
                        let depth = margin - clearance
                        let g = obstacle.piece.gradient(q)
                        let n4 = bones[obstacle.bone.rawValue] * SIMD4(g, 0)
                        let normal = simd_normalize(SIMD3(n4.x, n4.y, n4.z))
                        if worst == nil || depth > worst!.depth { worst = (depth, point, normal) }
                    }
                }
                guard let worst else { break }
                let s4 = arm * SIMD4(joint, 1)
                let shoulder = SIMD3(s4.x, s4.y, s4.z)
                let lever = simd_cross(worst.point - shoulder, worst.normal)
                let leverLength = simd_length(lever)
                guard leverLength > 1e-4 else { break }
                let angle = min(worst.depth * 1.1 / leverLength, 0.6)
                largest = max(largest, angle)
                let turn = KoalaSkeleton.translation(shoulder) * KoalaSkeleton.rotation(angle, lever / leverLength)
                    * KoalaSkeleton.translation(-shoulder)
                arm = turn * arm
            }
            bones[armBone.rawValue] = arm
        }
        return largest
    }
}
