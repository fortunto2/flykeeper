import Foundation

/// Which side of a fly something is on. Lives here rather than in the app because it is a
/// geometric fact about a body, and the app cannot express it without one.
public enum TouchSide: String, Sendable, Equatable, CaseIterable {
    case left, right, both
}

/// One contact between two flies: who felt it, and where.
public struct Contact: Sendable, Equatable {
    public let fly: Int
    public let side: TouchSide

    public init(fly: Int, side: TouchSide) {
        self.fly = fly
        self.side = side
    }
}

/// The spatial rules of a group of flies. Here rather than in the view for the reason the
/// wall reflections and the eating reach are here: they are rules about bodies in a space,
/// they are the kind of thing that goes wrong silently, and here they can be tested.
public enum Colony {
    /// How close two flies have to be to feel each other, in arena widths. **Two body
    /// widths, not the eating reach** — a fly eats at arm's length and collides at its own
    /// width, and using the eating radius meant two of them could stand touching and
    /// register nothing. The model is 0.15 arena units across.
    public static let contactRadius = 0.11
    /// Flies at different heights miss each other: one in the air is not bumping into one
    /// on the floor.
    public static let contactHeight = 0.1

    /// Every pair within reach, as the touch each of them feels. Pure, so the rule can be
    /// tested without an engine, a view or a frame.
    public static func contacts(_ poses: [FlyPose]) -> [Contact] {
        var out: [Contact] = []
        guard poses.count > 1 else { return out }
        let r2 = contactRadius * contactRadius
        for i in poses.indices {
            for j in (i + 1)..<poses.count {
                let a = poses[i], b = poses[j]
                let dx = b.x - a.x, dy = b.y - a.y
                // Squared: a bump is a comparison, not a distance anyone reads.
                guard dx * dx + dy * dy < r2, abs(a.z - b.z) < contactHeight else { continue }
                out.append(Contact(fly: i, side: side(of: a, towards: dx, dy)))
                out.append(Contact(fly: j, side: side(of: b, towards: -dx, -dy)))
            }
        }
        return out
    }

    /// Which side of `pose` a direction falls on: the sign of the cross product with its
    /// heading.
    static func side(of pose: FlyPose, towards dx: Double, _ dy: Double) -> TouchSide {
        cos(pose.heading) * dy - sin(pose.heading) * dx > 0 ? .right : .left
    }

    /// Where to put a new fly: the emptiest of a few candidates, so a colony spreads out
    /// instead of piling up wherever `random` happened to like. Deterministic given `rng`.
    public static func spawn(among poses: [FlyPose], candidates: Int = 8,
                             using rng: inout some RandomNumberGenerator) -> (x: Double, y: Double) {
        let margin = 0.12
        var best = (x: 0.5, y: 0.5)
        var bestGap = -1.0
        for _ in 0..<max(candidates, 1) {
            let p = (x: Double.random(in: margin...(1 - margin), using: &rng),
                     y: Double.random(in: margin...(1 - margin), using: &rng))
            let gap = poses.map { hypot($0.x - p.x, $0.y - p.y) }.min() ?? .infinity
            if gap > bestGap { bestGap = gap; best = p }
        }
        return best
    }

    public static func spawn(among poses: [FlyPose], candidates: Int = 8) -> (x: Double, y: Double) {
        var rng = SystemRandomNumberGenerator()
        return spawn(among: poses, candidates: candidates, using: &rng)
    }
}
