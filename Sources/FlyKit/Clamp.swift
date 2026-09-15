/// One clamp for the package. Five hand-rolled `min(max(…))` forms and a private `clamp` in
/// `Vitals` said the same thing five ways.
public extension Comparable {
    func clamped(to r: ClosedRange<Self>) -> Self { min(max(self, r.lowerBound), r.upperBound) }
}
