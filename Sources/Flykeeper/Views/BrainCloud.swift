import RealityKit
import Metal
import UIKit

/// The real brain as a heat map: one triangle per cell at its FlyWire coordinates, coloured
/// and sized by that cell's running firing rate. Positions and corner offsets are written
/// once; every frame only rewrites one byte of heat per vertex, and a Metal surface shader
/// (Shaders/Brain.metal) turns heat into colour and size on the GPU.
@MainActor
final class BrainCloud {
    let root = Entity()
    /// The one drawable, so the scene can order it against the glass shell.
    private(set) var model: ModelEntity?
    private let mesh: LowLevelMesh
    private let count: Int
    /// The µm → scene mapping used for the cells, so anything else in the same frame (the
    /// brain surface) lands in the same place: scene = centre + (p - mid) * scale, y flipped.
    let mid: SIMD3<Float>
    let scale: Float
    let centre: SIMD3<Float>
    /// Firing rate that reads as white-hot. Cells fire at most every ~3 steps (refractory),
    /// so 0.25 is a cell going nearly flat out.
    private static let hotRate: Float = 0.25
    private var tick = 0

    /// Interleaved vertex: position, corner offset, heat as a normalised byte (r channel).
    private struct Vertex {
        var position: SIMD3<Float>
        var corner: SIMD2<Float>
        var heat: SIMD4<UInt8>
    }

    /// `positions` in µm, any orientation; the cloud is centred and scaled to `extent`.
    init?(positions: [SIMD3<Float>], extent: Float, centre: SIMD3<Float>) {
        guard !positions.isEmpty, let device = MTLCreateSystemDefaultDevice(),
              let library = device.makeDefaultLibrary() else { return nil }
        var lo = positions[0], hi = positions[0]
        for p in positions { lo = min(lo, p); hi = max(hi, p) }
        let size = hi - lo
        let scale = extent / max(size.x, size.y, size.z, 1)
        let mid = (lo + hi) / 2
        self.mid = mid
        self.scale = scale
        self.centre = centre
        count = positions.count

        do {
            var desc = LowLevelMesh.Descriptor()
            desc.vertexCapacity = count * 3
            desc.indexCapacity = count * 3
            desc.vertexAttributes = [
                .init(semantic: .position, format: .float3, offset: MemoryLayout<Vertex>.offset(of: \.position)!),
                .init(semantic: .uv0, format: .float2, offset: MemoryLayout<Vertex>.offset(of: \.corner)!),
                .init(semantic: .color, format: .uchar4Normalized, offset: MemoryLayout<Vertex>.offset(of: \.heat)!),
            ]
            desc.vertexLayouts = [.init(bufferIndex: 0, bufferStride: MemoryLayout<Vertex>.stride)]
            desc.indexType = .uint32
            mesh = try LowLevelMesh(descriptor: desc)
            mesh.withUnsafeMutableIndices { raw in
                let idx = raw.bindMemory(to: UInt32.self)
                for i in 0..<(count * 3) { idx[i] = UInt32(i) }
            }
            // An equilateral triangle that contains the unit disc the shader draws in.
            let corners: [SIMD2<Float>] = [[-1.732, -1], [1.732, -1], [0, 2]]
            mesh.withUnsafeMutableBytes(bufferIndex: 0) { raw in
                let v = raw.bindMemory(to: Vertex.self)
                for (i, p) in positions.enumerated() {
                    // FlyWire: x lateral, y dorsal→ventral (down), z anterior→posterior.
                    let q = (p - mid) * scale
                    let sp = centre + SIMD3(q.x, -q.y, q.z)
                    for k in 0..<3 {
                        v[i * 3 + k] = Vertex(position: sp, corner: corners[k], heat: [0, 0, 0, 255])
                    }
                }
            }
            let bounds = BoundingBox(min: centre - extent, max: centre + extent)
            mesh.parts.replaceAll([.init(indexOffset: 0, indexCount: count * 3, topology: .triangle,
                                         materialIndex: 0, bounds: bounds)])

            var material = try CustomMaterial(
                surfaceShader: .init(named: "brainSurface", in: library),
                geometryModifier: .init(named: "brainGeometry", in: library),
                lightingModel: .unlit)
            material.faceCulling = .none
            // Glow, not paint: blended, and without depth writes so 138k overlapping discs
            // need no sorting — a cell behind another still adds its light.
            material.blending = .transparent(opacity: .init(floatLiteral: 1.0))
            material.writesDepth = false
            let entity = ModelEntity(mesh: try MeshResource(from: mesh), materials: [material])
            root.addChild(entity)
            model = entity
        } catch {
            return nil
        }
    }

    /// Write this frame's firing rates as heat. Every second frame is plenty for a 100 ms
    /// window, and halves the 1.6 MB of vertex writes per second of animation.
    func update(rates: [Float]) {
        tick += 1
        guard tick % 2 == 0, rates.count == count else { return }
        let hot = Self.hotRate
        mesh.withUnsafeMutableBytes(bufferIndex: 0) { raw in
            let v = raw.bindMemory(to: Vertex.self)
            for i in 0..<count {
                let h = UInt8(min(rates[i] / hot, 1) * 255)
                let heat = SIMD4<UInt8>(h, 0, 0, 255)
                v[i * 3].heat = heat
                v[i * 3 + 1].heat = heat
                v[i * 3 + 2].heat = heat
            }
        }
    }
}
