import RealityKit
import simd

/// Procedural meshes RealityKit doesn't ship, for Gummi's face: curved and bent tubes (mouths, brows, closed eyes)
/// and flat domed decals (eyes, blush, an open grin). Everything lies in the XY plane facing +z.
enum MeshFactory {
    /// A tube along an arc in the XY plane, centered so the arc's midpoint sits at the origin.
    /// Angles in radians. Returns the mesh and the two end points (for round caps).
    static func arcTube(radius: Float, from start: Float, to end: Float, thickness: Float,
                        segments: Int = 24, sides: Int = 10) throws -> (mesh: MeshResource, ends: (SIMD3<Float>, SIMD3<Float>)) {
        let mid = (start + end) / 2
        let offset = -SIMD3(radius * cos(mid), radius * sin(mid), 0)
        let points = (0...segments).map { i -> SIMD3<Float> in
            let theta = start + (end - start) * Float(i) / Float(segments)
            return SIMD3(radius * cos(theta), radius * sin(theta), 0) + offset
        }
        return try polylineTube(points, thickness: thickness, sides: sides)
    }

    /// A tube through points in the XY plane (bent shapes like "<", wavy lines). Returns the mesh and its end points.
    static func polylineTube(_ points: [SIMD3<Float>], thickness: Float, sides: Int = 10) throws
        -> (mesh: MeshResource, ends: (SIMD3<Float>, SIMD3<Float>)) {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        for (i, point) in points.enumerated() {
            let previous = points[max(i - 1, 0)], next = points[min(i + 1, points.count - 1)]
            let tangent = simd_normalize(next - previous)
            let side = SIMD3(-tangent.y, tangent.x, 0)
            for j in 0..<sides {
                let phi = 2 * Float.pi * Float(j) / Float(sides)
                let direction = side * cos(phi) + SIMD3(0, 0, 1) * sin(phi)
                positions.append(point + direction * thickness)
                normals.append(direction)
            }
        }
        var indices: [UInt32] = []
        for i in 0..<(points.count - 1) {
            for j in 0..<sides {
                let a = UInt32(i * sides + j), b = UInt32(i * sides + (j + 1) % sides)
                let c = UInt32((i + 1) * sides + j), d = UInt32((i + 1) * sides + (j + 1) % sides)
                indices += [a, b, c, b, d, c]
            }
        }
        var descriptor = MeshDescriptor(name: "tube")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        return (try MeshResource.generate(from: [descriptor]), (points.first!, points.last!))
    }

    /// A unit disc (radius 1) bulging toward +z like a lens: a glossy decal once scaled.
    /// `fromAngle`...`toAngle` cuts a wedge, so the lower half (pi to 2 pi) makes a "D" grin.
    static func domeDisc(dome: Float = 0.35, fromAngle: Float = 0, toAngle: Float = 2 * .pi,
                         rings: Int = 8, segments: Int = 32) throws -> MeshResource {
        var positions: [SIMD3<Float>] = [[0, 0, dome]]
        var normals: [SIMD3<Float>] = [[0, 0, 1]]
        let full = abs(toAngle - fromAngle - 2 * .pi) < 0.001
        let columns = full ? segments : segments + 1
        for ring in 1...rings {
            let r = Float(ring) / Float(rings)
            for s in 0..<columns {
                let angle = fromAngle + (toAngle - fromAngle) * Float(s) / Float(segments)
                let x = r * cos(angle), y = r * sin(angle)
                positions.append([x, y, dome * (1 - r * r)])
                normals.append(simd_normalize(SIMD3(2 * dome * x, 2 * dome * y, 1)))
            }
        }
        // For a wedge, the straight edge needs points along it too: they come from the ring columns at both ends.
        var indices: [UInt32] = []
        func vertex(_ ring: Int, _ s: Int) -> UInt32 {
            ring == 0 ? 0 : UInt32(1 + (ring - 1) * columns + (full ? s % segments : s))
        }
        for ring in 0..<rings {
            for s in 0..<segments {
                if ring == 0 {
                    indices += [0, vertex(1, s), vertex(1, s + 1)]
                } else {
                    let a = vertex(ring, s), b = vertex(ring, s + 1), c = vertex(ring + 1, s), d = vertex(ring + 1, s + 1)
                    indices += [a, c, b, b, c, d]
                }
            }
        }
        var descriptor = MeshDescriptor(name: "domeDisc")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }
}
