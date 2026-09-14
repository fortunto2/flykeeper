import RealityKit
import Metal
import UIKit

/// A subset of neurons drawn as their arbors: line segments from the decimated FlyWire
/// skeletons (`scripts/flywire-skeletons.py`). Each vertex carries its cell's heat and a
/// per-cell hue, so an arbor lights along its whole length when its cell fires.
@MainActor
final class BrainWires {
    let root = Entity()
    private(set) var model: ModelEntity?
    private let mesh: LowLevelMesh
    /// Cell index per vertex, for the per-frame heat write.
    private let cellOfVertex: [Int32]
    private var tick = 0
    private static let hotRate: Float = 0.25

    private struct Vertex {
        var position: SIMD3<Float>
        /// r = heat, g = hue, both 0...255.
        var color: SIMD4<UInt8>
    }

    /// `url`: the .fsk file. Positions are mapped with the cloud's µm → scene transform.
    init?(url: URL, mid: SIMD3<Float>, scale: Float, centre: SIMD3<Float>) {
        guard let data = try? Data(contentsOf: url), data.count > 8, data.prefix(4) == Data("FSK1".utf8),
              let device = MTLCreateSystemDefaultDevice(), let library = device.makeDefaultLibrary() else { return nil }
        var positions: [SIMD3<Float>] = []
        var cells: [Int32] = []
        data.withUnsafeBytes { raw in
            var o = 4
            func u32() -> UInt32 { defer { o += 4 }; return raw.loadUnaligned(fromByteOffset: o, as: UInt32.self) }
            func f32() -> Float { defer { o += 4 }; return raw.loadUnaligned(fromByteOffset: o, as: Float.self) }
            let neurons = Int(u32())
            positions.reserveCapacity(neurons * 100)
            for _ in 0..<neurons {
                let cell = Int32(u32())
                let segments = Int(u32())
                for _ in 0..<segments {
                    for _ in 0..<2 {
                        let p = SIMD3(f32(), f32(), f32())
                        let q = (p - mid) * scale
                        positions.append(centre + SIMD3(q.x, -q.y, q.z))
                        cells.append(cell)
                    }
                }
            }
        }
        guard !positions.isEmpty else { return nil }
        cellOfVertex = cells
        do {
            var desc = LowLevelMesh.Descriptor()
            desc.vertexCapacity = positions.count
            desc.indexCapacity = positions.count
            desc.vertexAttributes = [
                .init(semantic: .position, format: .float3, offset: MemoryLayout<Vertex>.offset(of: \.position)!),
                .init(semantic: .color, format: .uchar4Normalized, offset: MemoryLayout<Vertex>.offset(of: \.color)!),
            ]
            desc.vertexLayouts = [.init(bufferIndex: 0, bufferStride: MemoryLayout<Vertex>.stride)]
            desc.indexType = .uint32
            mesh = try LowLevelMesh(descriptor: desc)
            mesh.withUnsafeMutableIndices { raw in
                let idx = raw.bindMemory(to: UInt32.self)
                for i in 0..<positions.count { idx[i] = UInt32(i) }
            }
            mesh.withUnsafeMutableBytes(bufferIndex: 0) { raw in
                let v = raw.bindMemory(to: Vertex.self)
                for (i, p) in positions.enumerated() {
                    // Hue from the cell index: neighbours in the file get different colours.
                    let hue = UInt8(truncatingIfNeeded: Int(cells[i]) &* 97)
                    v[i] = Vertex(position: p, color: [0, hue, 0, 255])
                }
            }
            let bounds = BoundingBox(min: centre - 1, max: centre + 1)
            mesh.parts.replaceAll([.init(indexOffset: 0, indexCount: positions.count, topology: .line,
                                         materialIndex: 0, bounds: bounds)])
            var material = try CustomMaterial(surfaceShader: .init(named: "wireSurface", in: library),
                                              lightingModel: .unlit)
            material.blending = .transparent(opacity: .init(floatLiteral: 1))
            material.writesDepth = false
            let entity = ModelEntity(mesh: try MeshResource(from: mesh), materials: [material])
            root.addChild(entity)
            model = entity
        } catch {
            return nil
        }
    }

    /// Heat per vertex, every fourth frame: 877k vertices is a lot of bytes to touch, and
    /// a 100 ms rate window does not change faster than that anyway.
    func update(rates: [Float]) {
        tick += 1
        guard tick % 4 == 1, !rates.isEmpty else { return }
        let scale = 255 / Self.hotRate
        let n = rates.count
        rates.withUnsafeBufferPointer { r in
            cellOfVertex.withUnsafeBufferPointer { cells in
                mesh.withUnsafeMutableBytes(bufferIndex: 0) { raw in
                    let v = raw.bindMemory(to: Vertex.self)
                    for i in 0..<cells.count {
                        let c = Int(cells[i])
                        if c < n {
                            v[i].color.x = UInt8(min(r[c] * scale, 255))
                        }
                    }
                }
            }
        }
    }
}
