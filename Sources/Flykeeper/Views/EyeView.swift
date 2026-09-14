import SwiftUI

/// What the fly sees: one dot per photoreceptor, at the place on its eye that cell looks
/// from, lit by how hard that cell is being driven. Not a picture of the camera frame —
/// a picture of the retina's response to it, which is a different and more honest thing.
struct EyeView: View {
    let retina: Retina
    let response: [Float]
    let gain: Float

    var body: some View {
        Canvas(rendersAsynchronously: true) { ctx, size in
            let gap: CGFloat = 6
            let w = (size.width - gap) / 2
            var k = 0
            for (eye, origin) in [(retina.left, CGFloat(0)), (retina.right, w + gap)] {
                var dots = Path()
                var lit = Path()
                let r = max(1.1, min(w, size.height) / 90)
                for i in 0..<eye.cells.count {
                    guard k < response.count else { break }
                    let p = CGPoint(x: origin + CGFloat(eye.u[i]) * w,
                                    y: (1 - CGFloat(eye.v[i])) * size.height)
                    let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
                    if response[k] > gain * 0.12 { lit.addEllipse(in: rect) } else { dots.addEllipse(in: rect) }
                    k += 1
                }
                ctx.fill(dots, with: .color(.white.opacity(0.07)))
                ctx.fill(lit, with: .color(Color(red: 1, green: 0.86, blue: 0.5)))
            }
        }
        .background(.black, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityLabel("What the fly sees")
    }
}
