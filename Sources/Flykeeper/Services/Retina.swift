import Foundation
import simd

/// Where each photoreceptor looks, loaded from `retina.frt` (`scripts/retina.py`).
///
/// It is a map, not an optical model: neighbouring ommatidia stay neighbours, which is what
/// lets a moving scene sweep across the population the way a real one does. It makes no claim
/// about a fly's 270° field or its ommatidial angles.
struct Retina {
    struct Eye {
        /// Cell index in the brain's own order.
        var cells: [UInt32]
        /// Where each of them looks, 0…1 across the eye.
        var u: [Float]
        var v: [Float]
    }

    let left: Eye
    let right: Eye
    var count: Int { left.cells.count + right.cells.count }

    init?(url: URL) {
        guard let data = try? Data(contentsOf: url), data.count > 12,
              data.prefix(4) == Data("FRT1".utf8) else { return nil }
        var eyes: [Eye] = []
        data.withUnsafeBytes { raw in
            let nl = Int(raw.loadUnaligned(fromByteOffset: 4, as: UInt32.self))
            let nr = Int(raw.loadUnaligned(fromByteOffset: 8, as: UInt32.self))
            var o = 12
            for n in [nl, nr] {
                var cells = [UInt32](); var us = [Float](); var vs = [Float]()
                cells.reserveCapacity(n); us.reserveCapacity(n); vs.reserveCapacity(n)
                for _ in 0..<n {
                    cells.append(raw.loadUnaligned(fromByteOffset: o, as: UInt32.self))
                    us.append(raw.loadUnaligned(fromByteOffset: o + 4, as: Float.self))
                    vs.append(raw.loadUnaligned(fromByteOffset: o + 8, as: Float.self))
                    o += 12
                }
                eyes.append(Eye(cells: cells, u: us, v: vs))
            }
        }
        guard eyes.count == 2, !eyes[0].cells.isEmpty else { return nil }
        left = eyes[0]
        right = eyes[1]
    }
}

/// Turns a camera frame into current for every photoreceptor.
///
/// **Photoreceptors adapt, and ours have to as well.** A real fly's photoreceptors respond to
/// *change* in light, not to its absolute level — which is why a steady light drives the
/// descending neurons by 0.000 (measured, `docs/sensory-map.md`) and why feeding raw
/// brightness would be both useless and unfaithful. Each cell here keeps a slow running mean
/// and is driven by how far the scene departs from it, so a static wall produces almost
/// nothing and a moving edge produces a lot. The time constant is ours, not measured.
final class EyeSampler {
    private let retina: Retina
    private var adapted: [Float]
    private(set) var response: [Float]
    /// Cell indices in one flat array, in the order `response` uses.
    let cells: [UInt32]
    /// Seconds for a cell to stop noticing an unchanging scene.
    var adaptationTau: Double = 0.35
    /// Contrast that produces the full drive below.
    var contrastScale: Float = 0.25
    var gain: Float = 14

    init(retina: Retina) {
        self.retina = retina
        cells = retina.left.cells + retina.right.cells
        adapted = [Float](repeating: 0.5, count: cells.count)
        response = [Float](repeating: 0, count: cells.count)
    }

    /// `sample(u, v, rightEye)` returns luminance 0…1 for a direction. Each eye reads its own
    /// half of the frame, so turning the phone sweeps one eye before the other, as a fly's
    /// overlapping fields would.
    func look(dt: Double, sample: (Float, Float, Bool) -> Float) -> [Float] {
        let a = Float(min(dt / max(adaptationTau, 1e-6), 1))
        var k = 0
        for (eye, isRight) in [(retina.left, false), (retina.right, true)] {
            for i in 0..<eye.cells.count {
                let lum = sample(eye.u[i], eye.v[i], isRight)
                adapted[k] += (lum - adapted[k]) * a
                // Departure from what this cell has got used to, either way: an edge going
                // dark excites a fly's OFF pathway as much as one going bright excites ON.
                response[k] = min(abs(lum - adapted[k]) / contrastScale, 1) * gain
                k += 1
            }
        }
        return response
    }

    func rest() {
        for i in response.indices { response[i] = 0 }
    }
}
