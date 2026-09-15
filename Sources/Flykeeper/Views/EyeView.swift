import SwiftUI

/// What the fly sees: one dot per photoreceptor, at the place on its eye that cell looks
/// from, lit by how hard that cell is being driven. Not a picture of the camera frame —
/// a picture of the retina's response to it, which is a different and more honest thing.
struct EyeView: View {
    let sampler: EyeSampler

    /// The dim field never changes, so it is built once; only the lit cells are redrawn.
    /// Rebuilding both meant ~64 000 path elements a frame for a strip 96 points high.
    @State private var field: [(p: CGPoint, isRight: Bool)] = []

    var body: some View {
        Canvas(rendersAsynchronously: true) { ctx, size in
            let gap: CGFloat = 6
            let w = (size.width - gap) / 2
            let r = max(1.1, min(w, size.height) / 90)
            var dim = Path()
            var lit = Path()
            let threshold = sampler.litThreshold
            let response = sampler.response
            for (i, o) in sampler.retina.ommatidia.enumerated() {
                let x = (o.isRight ? w + gap : 0) + CGFloat(o.u) * w
                let y = (1 - CGFloat(o.v)) * size.height
                let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                if i < response.count, response[i] > threshold {
                    lit.addEllipse(in: rect)
                } else {
                    dim.addEllipse(in: rect)
                }
            }
            ctx.fill(dim, with: .color(.white.opacity(0.07)))
            ctx.fill(lit, with: .color(Color(red: 1, green: 0.86, blue: 0.5)))
        }
        .background(.black, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityLabel("What the fly sees")
    }
}
