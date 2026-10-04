import simd

/// A triangle mesh with one normal per vertex.
nonisolated struct SurfaceMesh: Sendable {
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var indices: [UInt32] = []
}

/// Naive surface nets: turns a signed-distance shape into a smooth mesh without lookup tables.
/// One vertex per grid cell that the surface crosses (the average of its edge crossings, then projected
/// onto the surface); one quad per grid edge that the surface crosses.
nonisolated enum SurfaceNets {
    static func mesh(shape: KoalaShape, cell: Float) -> SurfaceMesh {
        let lo = shape.boundsMin
        let counts = SIMD3<Int>(((shape.boundsMax - lo) / cell).rounded(.up)) &+ 1
        let nx = counts.x, ny = counts.y, nz = counts.z
        @inline(__always) func node(_ i: Int, _ j: Int, _ k: Int) -> Int { i + nx * (j + ny * k) }
        @inline(__always) func cellIndex(_ i: Int, _ j: Int, _ k: Int) -> Int { i + (nx - 1) * (j + (ny - 1) * k) }
        @inline(__always) func position(_ i: Int, _ j: Int, _ k: Int) -> SIMD3<Float> {
            lo + SIMD3(Float(i), Float(j), Float(k)) * cell
        }

        var samples = [Float](repeating: 0, count: nx * ny * nz)
        for k in 0..<nz { for j in 0..<ny { for i in 0..<nx {
            samples[node(i, j, k)] = shape.distance(position(i, j, k))
        } } }

        // The 12 cube edges as corner pairs; corner c = dx + 2 dy + 4 dz.
        var edges: [(Int, Int)] = []
        for a in 0..<8 { for bit in [1, 2, 4] where a & bit == 0 { edges.append((a, a | bit)) } }

        var mesh = SurfaceMesh()
        var cellVertex = [Int32](repeating: -1, count: (nx - 1) * (ny - 1) * (nz - 1))
        for k in 0..<(nz - 1) { for j in 0..<(ny - 1) { for i in 0..<(nx - 1) {
            var corner = [Float](repeating: 0, count: 8)
            var inside = 0
            for c in 0..<8 {
                let value = samples[node(i + (c & 1), j + ((c >> 1) & 1), k + ((c >> 2) & 1))]
                corner[c] = value
                if value < 0 { inside += 1 }
            }
            guard inside > 0, inside < 8 else { continue }
            var sum = SIMD3<Float>(repeating: 0)
            var crossings: Float = 0
            for (a, b) in edges where (corner[a] < 0) != (corner[b] < 0) {
                let t = corner[a] / (corner[a] - corner[b])
                let pa = SIMD3(Float(a & 1), Float((a >> 1) & 1), Float((a >> 2) & 1))
                let pb = SIMD3(Float(b & 1), Float((b >> 1) & 1), Float((b >> 2) & 1))
                sum += pa + (pb - pa) * t
                crossings += 1
            }
            var p = position(i, j, k) + sum / crossings * cell
            for _ in 0..<4 {
                let g = shape.gradient(p)
                p -= shape.distance(p) * g / max(simd_length_squared(g), 1e-8)
            }
            cellVertex[cellIndex(i, j, k)] = Int32(mesh.positions.count)
            mesh.positions.append(p)
            mesh.normals.append(simd_normalize(shape.gradient(p)))
        } } }

        func addQuad(_ cells: [(Int, Int, Int)]) {
            var v: [UInt32] = []
            for (i, j, k) in cells {
                let index = cellVertex[cellIndex(i, j, k)]
                guard index >= 0 else { return }
                v.append(UInt32(index))
            }
            // Split along the shorter diagonal, then face each triangle outward.
            let d02 = simd_distance(mesh.positions[Int(v[0])], mesh.positions[Int(v[2])])
            let d13 = simd_distance(mesh.positions[Int(v[1])], mesh.positions[Int(v[3])])
            let triangles = d02 <= d13 ? [(v[0], v[1], v[2]), (v[0], v[2], v[3])] : [(v[0], v[1], v[3]), (v[1], v[2], v[3])]
            for (a, b, c) in triangles {
                let pa = mesh.positions[Int(a)], pb = mesh.positions[Int(b)], pc = mesh.positions[Int(c)]
                let faceNormal = simd_cross(pb - pa, pc - pa)
                let outward = mesh.normals[Int(a)] + mesh.normals[Int(b)] + mesh.normals[Int(c)]
                mesh.indices += simd_dot(faceNormal, outward) >= 0 ? [a, b, c] : [a, c, b]
            }
        }

        for k in 0..<nz { for j in 0..<ny { for i in 0..<nx {
            let here = samples[node(i, j, k)] < 0
            if i < nx - 1, j > 0, k > 0, j < ny - 1, k < nz - 1, here != (samples[node(i + 1, j, k)] < 0) {
                addQuad([(i, j - 1, k - 1), (i, j, k - 1), (i, j, k), (i, j - 1, k)])
            }
            if j < ny - 1, i > 0, k > 0, i < nx - 1, k < nz - 1, here != (samples[node(i, j + 1, k)] < 0) {
                addQuad([(i - 1, j, k - 1), (i - 1, j, k), (i, j, k), (i, j, k - 1)])
            }
            if k < nz - 1, i > 0, j > 0, i < nx - 1, j < ny - 1, here != (samples[node(i, j, k + 1)] < 0) {
                addQuad([(i - 1, j - 1, k), (i, j - 1, k), (i, j, k), (i - 1, j, k)])
            }
        } } }
        return mesh
    }
}
