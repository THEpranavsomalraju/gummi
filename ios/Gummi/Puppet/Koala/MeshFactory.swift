import RealityKit
import simd

/// Procedural meshes RealityKit doesn't ship: a curved tube for Gummi's mouth.
enum MeshFactory {
    /// A tube along an arc in the XY plane, centered so the arc's midpoint sits at the origin.
    /// Angles in radians. Returns the mesh and the two end points (for round caps).
    static func arcTube(radius: Float, from start: Float, to end: Float, thickness: Float,
                        segments: Int = 24, sides: Int = 10) throws -> (mesh: MeshResource, ends: (SIMD3<Float>, SIMD3<Float>)) {
        let mid = (start + end) / 2
        let offset = -SIMD3(radius * cos(mid), radius * sin(mid), 0)
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        for i in 0...segments {
            let theta = start + (end - start) * Float(i) / Float(segments)
            let radial = SIMD3(cos(theta), sin(theta), 0)
            let center = radial * radius + offset
            for j in 0..<sides {
                let phi = 2 * Float.pi * Float(j) / Float(sides)
                let direction = radial * cos(phi) + SIMD3(0, 0, 1) * sin(phi)
                positions.append(center + direction * thickness)
                normals.append(direction)
            }
        }
        var indices: [UInt32] = []
        for i in 0..<segments {
            for j in 0..<sides {
                let a = UInt32(i * sides + j), b = UInt32(i * sides + (j + 1) % sides)
                let c = UInt32((i + 1) * sides + j), d = UInt32((i + 1) * sides + (j + 1) % sides)
                indices += [a, b, c, b, d, c]
            }
        }
        var descriptor = MeshDescriptor(name: "arcTube")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        let mesh = try MeshResource.generate(from: [descriptor])
        let first = SIMD3(radius * cos(start), radius * sin(start), 0) + offset
        let last = SIMD3(radius * cos(end), radius * sin(end), 0) + offset
        return (mesh, (first, last))
    }
}
