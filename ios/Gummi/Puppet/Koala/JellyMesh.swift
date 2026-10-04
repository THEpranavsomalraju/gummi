import RealityKit
import simd

/// Bone transforms for a pose: each bone's matrix maps the rest mesh to its posed place.
nonisolated enum KoalaSkeleton {
    static func matrices(for pose: PuppetPose, joints: [KoalaBone: SIMD3<Float>]) -> [simd_float4x4] {
        func joint(_ bone: KoalaBone) -> SIMD3<Float> { joints[bone] ?? .zero }
        func about(_ pivot: SIMD3<Float>, _ m: simd_float4x4) -> simd_float4x4 {
            translation(pivot) * m * translation(-pivot)
        }
        // The spin (rootYaw) is applied to the whole puppet by the rig, so the jelly doesn't smear during spins.
        let s = pose.squash
        let root = translation(pose.rootOffset) * scale([1 - 0.5 * s, 1 + s, 1 - 0.5 * s])
        let hips = root * about(joint(.hips), translation([pose.hipsShift, 0, 0])
            * rotation(pose.hipsPitch, [1, 0, 0]) * rotation(pose.hipsRoll, [0, 0, 1]))
        // Breathing and puffing scale the torso only; the head and arms ride the unscaled chest frame.
        let breathe = SIMD3(1 + pose.puff + pose.breath * 0.6, 1 + pose.puff * 0.6 + pose.breath, 1 + pose.puff + pose.breath * 0.6)
        let chestFrame = hips * about(joint(.chest), rotation(pose.chestYaw, [0, 1, 0]) * rotation(pose.chestPitch, [1, 0, 0]))
        let chest = chestFrame * about(joint(.chest), scale(breathe))
        let head = chestFrame * about(joint(.head), rotation(pose.headYaw, [0, 1, 0])
            * rotation(pose.headPitch, [1, 0, 0]) * rotation(pose.headRoll, [0, 0, 1]))
        func arm(_ bone: KoalaBone, yaw: Float, roll: Float, pitch: Float) -> simd_float4x4 {
            chestFrame * about(joint(bone), rotation(yaw, [0, 1, 0]) * rotation(roll, [0, 0, 1]) * rotation(pitch, [1, 0, 0]))
        }
        func leg(_ bone: KoalaBone, lift: Float, roll: Float, pitch: Float) -> simd_float4x4 {
            root * about(joint(bone), translation([0, lift, 0]) * rotation(roll, [0, 0, 1]) * rotation(pitch, [1, 0, 0]))
        }

        var bones = [simd_float4x4](repeating: matrix_identity_float4x4, count: KoalaBone.allCases.count)
        bones[KoalaBone.hips.rawValue] = hips
        bones[KoalaBone.chest.rawValue] = chest
        bones[KoalaBone.head.rawValue] = head
        bones[KoalaBone.leftEar.rawValue] = head * about(joint(.leftEar), rotation(pose.leftEarRoll, [0, 0, 1]))
        bones[KoalaBone.rightEar.rawValue] = head * about(joint(.rightEar), rotation(pose.rightEarRoll, [0, 0, 1]))
        bones[KoalaBone.leftArm.rawValue] = arm(.leftArm, yaw: pose.leftArmYaw, roll: pose.leftArmRoll, pitch: pose.leftArmPitch)
        bones[KoalaBone.rightArm.rawValue] = arm(.rightArm, yaw: pose.rightArmYaw, roll: pose.rightArmRoll, pitch: pose.rightArmPitch)
        bones[KoalaBone.leftLeg.rawValue] = leg(.leftLeg, lift: pose.leftLegLift, roll: pose.leftLegRoll, pitch: pose.leftLegPitch)
        bones[KoalaBone.rightLeg.rawValue] = leg(.rightLeg, lift: pose.rightLegLift, roll: pose.rightLegRoll, pitch: pose.rightLegPitch)
        return bones
    }

    static func translation(_ t: SIMD3<Float>) -> simd_float4x4 {
        var m = matrix_identity_float4x4
        m.columns.3 = SIMD4(t, 1)
        return m
    }

    static func rotation(_ angle: Float, _ axis: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(simd_quatf(angle: angle, axis: axis))
    }

    static func scale(_ s: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(diagonal: SIMD4(s, 1))
    }
}

/// The jelly body as plain data: rest mesh, soft skin weights, and one spring per vertex.
/// Each vertex chases its skinned position on an underdamped spring, so the body lags, ripples, and settles.
nonisolated struct JellySim: Sendable {
    let restPositions: [SIMD3<Float>]
    let restNormals: [SIMD3<Float>]
    let indices: [UInt32]
    let boneIndices: [SIMD4<Int32>]
    let boneWeights: [SIMD4<Float>]
    let stiffness: [Float]
    let damping: [Float]
    private(set) var positions: [SIMD3<Float>]
    private(set) var velocities: [SIMD3<Float>]
    private(set) var targets: [SIMD3<Float>]
    private(set) var normals: [SIMD3<Float>]

    static let maxStretch: Float = 0.035

    init(mesh: SurfaceMesh, piece: KoalaPiece) {
        restPositions = mesh.positions
        restNormals = mesh.normals
        indices = mesh.indices
        var boneIndices: [SIMD4<Int32>] = []
        var boneWeights: [SIMD4<Float>] = []
        var stiffness: [Float] = []
        var damping: [Float] = []
        let sigma: Float = 0.014
        for p in mesh.positions {
            var perBone = [Float](repeating: 0, count: KoalaBone.allCases.count)
            var softness: Float = 0, total: Float = 0
            for part in piece.parts {
                let influence = exp(-max(part.distance(p), 0) / sigma)
                perBone[part.bone.rawValue] = max(perBone[part.bone.rawValue], influence)
                softness += influence * part.softness
                total += influence
            }
            let top = perBone.enumerated().sorted { $0.element > $1.element }.prefix(4)
            let sum = top.reduce(0) { $0 + $1.element }
            var index = SIMD4<Int32>(repeating: 0), weight = SIMD4<Float>(repeating: 0)
            for (lane, entry) in top.enumerated() {
                index[lane] = Int32(entry.offset)
                weight[lane] = sum > 0 ? entry.element / sum : (lane == 0 ? 1 : 0)
            }
            boneIndices.append(index)
            boneWeights.append(weight)
            let soft = total > 0 ? softness / total : 0.4
            let k = 900 + (160 - 900) * soft
            stiffness.append(k)
            damping.append(2 * 0.32 * k.squareRoot())
        }
        self.boneIndices = boneIndices
        self.boneWeights = boneWeights
        self.stiffness = stiffness
        self.damping = damping
        positions = mesh.positions
        velocities = Array(repeating: .zero, count: mesh.positions.count)
        targets = mesh.positions
        normals = mesh.normals
    }

    /// Skins every vertex to the bones, then lets it spring toward that target.
    mutating func step(bones: [simd_float4x4], dt: Float) {
        let substeps = max(1, Int((dt * 120).rounded(.up)))
        let h = dt / Float(substeps)
        for v in restPositions.indices {
            let rest = SIMD4(restPositions[v], 1)
            let restNormal = SIMD4(restNormals[v], 0)
            let index = boneIndices[v], weight = boneWeights[v]
            var target = SIMD4<Float>(repeating: 0)
            var normal = SIMD4<Float>(repeating: 0)
            for lane in 0..<4 where weight[lane] > 0 {
                let m = bones[Int(index[lane])]
                target += weight[lane] * (m * rest)
                normal += weight[lane] * (m * restNormal)
            }
            let goal = SIMD3(target.x, target.y, target.z)
            var x = positions[v], velocity = velocities[v]
            let k = stiffness[v], c = damping[v]
            for _ in 0..<substeps {
                velocity += (k * (goal - x) - c * velocity) * h
                x += velocity * h
            }
            let stretch = x - goal
            let length = simd_length(stretch)
            if length > Self.maxStretch {
                x = goal + stretch / length * Self.maxStretch
                velocity *= 0.5
            }
            positions[v] = x
            velocities[v] = velocity
            targets[v] = goal
            normals[v] = simd_normalize(SIMD3(normal.x, normal.y, normal.z))
        }
    }

    /// How far the jelly at vertex `v` lags its skinned place: features ride this so they jiggle with the body.
    func wobble(at v: Int) -> SIMD3<Float> { positions[v] - targets[v] }

    func nearestVertex(to point: SIMD3<Float>) -> Int {
        restPositions.indices.min { simd_distance_squared(restPositions[$0], point) < simd_distance_squared(restPositions[$1], point) } ?? 0
    }
}

/// The jelly body on screen: JellySim written into a RealityKit LowLevelMesh every frame.
@MainActor
final class JellyBody {
    struct Vertex {
        var position: SIMD3<Float>
        var normal: SIMD3<Float>
    }

    let entity: ModelEntity
    /// A smaller, brighter copy inside the body for the translucent-shell experiment. Shares the same mesh.
    let core: ModelEntity
    private let mesh: LowLevelMesh
    private(set) var sim: JellySim

    private init(entity: ModelEntity, core: ModelEntity, mesh: LowLevelMesh, sim: JellySim) {
        self.entity = entity
        self.core = core
        self.mesh = mesh
        self.sim = sim
    }

    static func make(sim: JellySim, piece: KoalaPiece, material: some RealityKit.Material,
                     coreMaterial: some RealityKit.Material) async throws -> JellyBody {
        let attributes = [
            LowLevelMesh.Attribute(semantic: .position, format: .float3, offset: MemoryLayout<Vertex>.offset(of: \.position) ?? 0),
            LowLevelMesh.Attribute(semantic: .normal, format: .float3, offset: MemoryLayout<Vertex>.offset(of: \.normal) ?? 16),
        ]
        let descriptor = LowLevelMesh.Descriptor(vertexCapacity: sim.restPositions.count, vertexAttributes: attributes,
                                                 vertexLayouts: [LowLevelMesh.Layout(bufferIndex: 0, bufferStride: MemoryLayout<Vertex>.stride)],
                                                 indexCapacity: sim.indices.count)
        let mesh = try LowLevelMesh(descriptor: descriptor)
        mesh.withUnsafeMutableIndices { raw in
            let indices = raw.bindMemory(to: UInt32.self)
            for (i, index) in sim.indices.enumerated() { indices[i] = index }
        }
        // Bounds leave room for hops, spins, and wobble.
        mesh.parts.replaceAll([LowLevelMesh.Part(indexCount: sim.indices.count, topology: .triangle,
                                                 bounds: BoundingBox(min: piece.boundsMin - 0.25, max: piece.boundsMax + 0.25))])
        let resource = try await MeshResource(from: mesh)
        let entity = ModelEntity(mesh: resource, materials: [material])
        let core = ModelEntity(mesh: resource, materials: [coreMaterial])
        let coreScale: Float = 0.86
        core.scale = SIMD3(repeating: coreScale)
        core.position = piece.center * (1 - coreScale)
        core.isEnabled = false
        let body = JellyBody(entity: entity, core: core, mesh: mesh, sim: sim)
        body.upload()
        return body
    }

    func update(bones: [simd_float4x4], dt: Float) {
        sim.step(bones: bones, dt: dt)
        upload()
    }

    private func upload() {
        mesh.withUnsafeMutableBytes(bufferIndex: 0) { raw in
            let vertices = raw.bindMemory(to: Vertex.self)
            for v in sim.positions.indices {
                vertices[v] = Vertex(position: sim.positions[v], normal: sim.normals[v])
            }
        }
    }
}
