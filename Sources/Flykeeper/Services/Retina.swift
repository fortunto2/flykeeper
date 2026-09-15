import Foundation
import FlyKit

/// Where each photoreceptor looks, loaded from `retina.frt` (`scripts/retina.py`).
///
/// It is a map, not an optical model: neighbouring ommatidia stay neighbours, which is what
/// lets a moving scene sweep across the population the way a real one does. It makes no claim
/// about a fly's 270° field or its ommatidial angles.
///
/// One flat list rather than two eyes to walk: the order photoreceptors are listed in is the
/// order everything downstream indexes by, and two consumers each re-deriving it is two
/// chances to light the wrong cells with nothing to say so.
struct Retina {
    struct Ommatidium {
        let cell: UInt32
        /// Where it looks, 0…1 across its own eye.
        let u: Float
        let v: Float
        let isRight: Bool
    }

    let ommatidia: [Ommatidium]
    /// Cell indices in the brain's own order, for the bulk stimulus call.
    let cells: [UInt32]
    var count: Int { ommatidia.count }

    init?(url: URL) {
        guard let reader = PackedReader(url: url, magic: "FRT1"),
              let nl = reader.u32(), let nr = reader.u32() else { return nil }
        var all: [Ommatidium] = []
        all.reserveCapacity(Int(nl) + Int(nr))
        for (n, isRight) in [(nl, false), (nr, true)] {
            for _ in 0..<n {
                guard let c = reader.u32(), let u = reader.f32(), let v = reader.f32() else { return nil }
                all.append(Ommatidium(cell: c, u: u, v: v, isRight: isRight))
            }
        }
        guard !all.isEmpty else { return nil }
        ommatidia = all
        cells = all.map(\.cell)
    }
}

/// Turns a camera frame into current for every photoreceptor.
///
/// What a photoreceptor *does* — adapt, and answer change — is `FlyKit.Photoreceptors`, where
/// the other model assumptions live and are tested. What is left here is where each one looks
/// and where the camera puts it, which is the app's business. The grid index of every cell is
/// worked out once: it depends only on the retina and the camera's fixed grid, and computing
/// it 10 629 times a frame was 638 000 multiplications a second for a constant.
final class EyeSampler {
    let retina: Retina
    private(set) var cells: [UInt32]
    private let gridIndex: [Int32]
    private var luminance: [Float]
    private(set) var photoreceptors: Photoreceptors

    var response: [Float] { photoreceptors.response }
    var litThreshold: Float { photoreceptors.litThreshold }

    init(retina: Retina, width: Int, height: Int) {
        self.retina = retina
        cells = retina.cells
        gridIndex = retina.ommatidia.map { o in
            // Each eye reads its own half of the frame, so turning the phone sweeps one eye
            // before the other, as a fly's overlapping fields would.
            let x = Int((Double(o.u) * 0.5 + (o.isRight ? 0.5 : 0)) * Double(width - 1))
            let y = Int((1 - Double(o.v)) * Double(height - 1))
            return Int32(y * width + x)
        }
        luminance = [Float](repeating: 0.5, count: retina.count)
        photoreceptors = Photoreceptors(count: retina.count)
    }

    /// `grid` is the camera's luminance, row-major, the size this sampler was built for.
    @discardableResult
    func look(dt: Double, grid: [Float]) -> [Float] {
        grid.withUnsafeBufferPointer { g in
            for i in gridIndex.indices {
                let k = Int(gridIndex[i])
                luminance[i] = k < g.count ? g[k] : 0.5
            }
        }
        return photoreceptors.respond(to: luminance, dt: dt)
    }

    func rest() { photoreceptors.rest() }
}
