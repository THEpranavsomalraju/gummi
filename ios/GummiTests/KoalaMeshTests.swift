import Foundation
import simd
import Testing
@testable import Gummi

@Suite("Koala jelly pieces")
struct KoalaMeshTests {
    private static let shape = KoalaShape.standard
    private static let meshes: [String: SurfaceMesh] = Dictionary(
        uniqueKeysWithValues: shape.pieces.map { ($0.name, SurfaceNets.mesh(piece: $0)) })
    nonisolated private static let pieceNames = ["torso", "head", "leftArm", "rightArm", "leftLeg", "rightLeg"]

    @Test(arguments: pieceNames)
    func pieceIsAClosedSurfaceFacingOut(name: String) throws {
        let piece = try #require(Self.shape.piece(named: name))
        let mesh = try #require(Self.meshes[name])
        #expect(mesh.positions.count > 300)
        let worst = mesh.positions.map { abs(piece.distance($0)) }.max() ?? 1
        #expect(worst < 0.0015)

        var outward = 0, triangles = 0
        var edges: [UInt64: Int] = [:]
        let indices = mesh.indices
        for t in stride(from: 0, to: indices.count, by: 3) {
            let a = mesh.positions[Int(indices[t])], b = mesh.positions[Int(indices[t + 1])], c = mesh.positions[Int(indices[t + 2])]
            if simd_dot(simd_cross(b - a, c - a), piece.gradient((a + b + c) / 3)) > 0 { outward += 1 }
            triangles += 1
            for (i, j) in [(indices[t], indices[t + 1]), (indices[t + 1], indices[t + 2]), (indices[t + 2], indices[t])] {
                edges[UInt64(min(i, j)) << 32 | UInt64(max(i, j)), default: 0] += 1
            }
        }
        #expect(Double(outward) / Double(triangles) > 0.995)
        #expect(Double(edges.values.filter { $0 == 2 }.count) / Double(edges.count) > 0.999)

        // Nothing is clipped by the meshing box.
        let lo = mesh.positions.reduce(SIMD3<Float>(repeating: .infinity)) { simd_min($0, $1) }
        let hi = mesh.positions.reduce(SIMD3<Float>(repeating: -.infinity)) { simd_max($0, $1) }
        #expect(all(lo .> piece.boundsMin + piece.cell))
        #expect(all(hi .< piece.boundsMax - piece.cell))
    }

    @Test(arguments: ["leftArm", "rightArm"])
    func armsHangFreeBelowTheShoulder(name: String) throws {
        let torso = try #require(Self.shape.piece(named: "torso"))
        let mesh = try #require(Self.meshes[name])
        let lowerArm = mesh.positions.filter { $0.y < 0.17 }
        #expect(!lowerArm.isEmpty)
        #expect(lowerArm.allSatisfy { torso.distance($0) > 0.002 })
        // The rounded shoulder tucks into the torso, so the arm never looks detached.
        #expect(mesh.positions.contains { torso.distance($0) < 0 })
    }

    @Test func headAndLegsTuckIntoTheTorso() throws {
        let torso = try #require(Self.shape.piece(named: "torso"))
        for name in ["head", "leftLeg", "rightLeg"] {
            let mesh = try #require(Self.meshes[name])
            #expect(mesh.positions.contains { torso.distance($0) < -0.01 }, "\(name) should tuck in")
        }
        let feet = ["leftLeg", "rightLeg"].compactMap { Self.meshes[$0]?.positions.map(\.y).min() }
        #expect(feet.allSatisfy { abs($0) < 0.004 })
    }

    @Test func skinWeightsStayWithinEachPiece() throws {
        let allowed: [String: Set<KoalaBone>] = [
            "torso": [.hips, .chest], "head": [.head, .leftEar, .rightEar],
            "leftArm": [.leftArm], "rightArm": [.rightArm], "leftLeg": [.leftLeg], "rightLeg": [.rightLeg],
        ]
        for piece in Self.shape.pieces {
            let sim = JellySim(mesh: try #require(Self.meshes[piece.name]), piece: piece)
            #expect(sim.boneWeights.allSatisfy { abs($0.sum() - 1) < 0.001 })
            for (weights, bones) in zip(sim.boneWeights, sim.boneIndices) {
                for lane in 0..<4 where weights[lane] > 0.001 {
                    #expect(allowed[piece.name]?.contains(KoalaBone(rawValue: Int(bones[lane])) ?? .hips) == true)
                }
            }
        }
        let head = try #require(Self.shape.piece(named: "head"))
        let sim = JellySim(mesh: try #require(Self.meshes["head"]), piece: head)
        func dominant(near point: SIMD3<Float>) -> KoalaBone? {
            let v = sim.nearestVertex(to: point)
            let lane = (0..<4).max { sim.boneWeights[v][$0] < sim.boneWeights[v][$1] } ?? 0
            return KoalaBone(rawValue: Int(sim.boneIndices[v][lane]))
        }
        #expect(dominant(near: [0, 0.41, 0.006]) == .head)
        #expect(dominant(near: [-0.14, 0.39, -0.012]) == .leftEar)
        #expect(dominant(near: [0.14, 0.39, -0.012]) == .rightEar)
    }

    @Test func restPoseKeepsTheMeshAndJellyCatchesUp() throws {
        let torso = try #require(Self.shape.piece(named: "torso"))
        var sim = JellySim(mesh: try #require(Self.meshes["torso"]), piece: torso)
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
