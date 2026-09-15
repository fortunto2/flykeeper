import Foundation

/// Photoreceptor light adaptation.
///
/// A real photoreceptor answers *change* in light, not its level — which is exactly why a
/// steady light measures 0.000 at the descending neurons, and why feeding raw brightness
/// would be both useless and unfaithful. Each cell keeps a running mean of what it has been
/// seeing and is driven by how far the scene departs from it, so a static wall produces
/// almost nothing and a moving edge a lot.
///
/// Here rather than beside the camera because it is a model assumption of the same kind as
/// the readout thresholds, and belongs where those are documented and tested. Where each
/// photoreceptor *looks* is the app's business; what a photoreceptor *does* is this.
/// The adaptation is real biology; `tau`, `contrastScale` and `gain` are ours.
public struct Photoreceptors: Sendable {
    /// Seconds for a cell to stop noticing an unchanging scene.
    public var tau: Double
    /// Contrast that produces full drive.
    public var contrastScale: Float
    /// Current a fully driven cell injects.
    public var gain: Float
    /// Response above which the app draws a cell as lit.
    public var litThreshold: Float { gain * 0.12 }

    private var adapted: [Float]
    /// The last response, so a caller can draw it without asking for it twice.
    public private(set) var response: [Float]

    public init(count: Int, tau: Double = 0.35, contrastScale: Float = 0.25, gain: Float = 14) {
        self.tau = tau
        self.contrastScale = contrastScale
        self.gain = gain
        adapted = [Float](repeating: 0.5, count: count)
        response = [Float](repeating: 0, count: count)
    }

    /// `luminance` is 0…1 per cell, in the caller's own order.
    @discardableResult
    public mutating func respond(to luminance: [Float], dt: Double) -> [Float] {
        guard luminance.count == adapted.count else { return response }
        let a = Float(min(dt / max(tau, 1e-6), 1))
        let scale = 1 / max(contrastScale, 1e-6)
        for i in adapted.indices {
            let lum = luminance[i]
            adapted[i] += (lum - adapted[i]) * a
            // Either way: an edge going dark excites a fly's OFF pathway as much as one going
            // bright excites ON.
            response[i] = min(abs(lum - adapted[i]) * scale, 1) * gain
        }
        return response
    }

    /// Eye closed: nothing driven, and the adaptation forgets the last scene.
    public mutating func rest() {
        for i in response.indices { response[i] = 0; adapted[i] = 0.5 }
    }
}
