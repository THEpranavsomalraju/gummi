import Foundation
import simd
import Testing
@testable import Gummi

@Suite("Koala mesh and jelly")
struct KoalaMeshTests {
    private static let shape = KoalaShape.standard
    private static let mesh = SurfaceNets.mesh(shape: shape, cell: KoalaMeshCache.cellSize)

    @Test func meshSitsOnTheMoldedSurface() {
        let mesh = Self.mesh
        #expect(mesh.positions.count > 3_000 && mesh.positions.count < 20_000)
        #expect(mesh.indices.count.isMultiple(of: 3))
        let worst = mesh.positions.map { abs(Self.shape.distance($0)) }.max() ?? 1
        #expect(worst < 0.0015)
        #expect(mesh.normals.allSatisfy { abs(simd_length($0) - 1) < 0.001 })
        let feetY = mesh.positions.map(\.y).min() ?? 1
        #expect(abs(feetY) < 0.004)
    }

    @Test func trianglesFaceOutward() {
        let mesh = Self.mesh
        var outward = 0, total = 0
        for t in stride(from: 0, to: mesh.indices.count, by: 3) {
            let a = mesh.positions[Int(mesh.indices[t])], b = mesh.positions[Int(mesh.indices[t + 1])], c = mesh.positions[Int(mesh.indices[t + 2])]
            let face = simd_cross(b - a, c - a)
            if simd_dot(face, Self.shape.gradient((a + b + c) / 3)) > 0 { outward += 1 }
            total += 1
        }
        #expect(Double(outward) / Double(total) > 0.995)
    }

    @Test func surfaceIsClosed() {
        var edges: [UInt64: Int] = [:]
        let indices = Self.mesh.indices
        for t in stride(from: 0, to: indices.count, by: 3) {
            for (a, b) in [(indices[t], indices[t + 1]), (indices[t + 1], indices[t + 2]), (indices[t + 2], indices[t])] {
                edges[UInt64(min(a, b)) << 32 | UInt64(max(a, b)), default: 0] += 1
            }
        }
        let manifold = edges.values.filter { $0 == 2 }.count
        #expect(Double(manifold) / Double(edges.count) > 0.999)
    }

    @Test func skinWeightsFollowTheParts() {
        let sim = JellySim(mesh: Self.mesh, shape: Self.shape)
        #expect(sim.boneWeights.allSatisfy { abs($0.sum() - 1) < 0.001 })
        func dominantBone(near point: SIMD3<Float>) -> KoalaBone? {
            let v = sim.nearestVertex(to: point)
            let weights = sim.boneWeights[v], bones = sim.boneIndices[v]
            let lane = (0..<4).max { weights[$0] < weights[$1] } ?? 0
            return KoalaBone(rawValue: Int(bones[lane]))
        }
        #expect(dominantBone(near: [0, 0.4, 0.004]) == .head)
        #expect(dominantBone(near: [0.157, 0.1, 0.012]) == .rightArm)
        #expect(dominantBone(near: [-0.157, 0.1, 0.012]) == .leftArm)
        #expect(dominantBone(near: [0.045, 0, 0.01]) == .rightLeg)
        #expect(dominantBone(near: [-0.12, 0.38, -0.012]) == .leftEar)
    }

    @Test func restPoseKeepsTheMeshAndJellyCatchesUp() {
        var sim = JellySim(mesh: Self.mesh, shape: Self.shape)
        let rest = KoalaSkeleton.matrices(for: PuppetPose(), joints: Self.shape.joints)
        #expect(rest.allSatisfy { $0 == matrix_identity_float4x4 })
        sim.step(bones: rest, dt: 1 / 60)
        let drift = zip(sim.positions, sim.restPositions).map { simd_distance($0, $1) }.max() ?? 1
        #expect(drift < 0.0001)

        let lift = SIMD3<Float>(0, 0.05, 0)
        let lifted = [simd_float4x4](repeating: KoalaSkeleton.translation(lift), count: KoalaBone.allCases.count)
        sim.step(bones: lifted, dt: 1 / 60)
        let lag = zip(sim.positions, sim.restPositions).map { $0.y - $1.y }.reduce(0, +) / Float(sim.positions.count)
        #expect(lag < 0.05)
        for _ in 0..<180 { sim.step(bones: lifted, dt: 1 / 60) }
        let settled = zip(sim.positions, sim.restPositions).map { simd_distance($0, $1 + lift) }.max() ?? 1
        #expect(settled < 0.001)
    }
}
