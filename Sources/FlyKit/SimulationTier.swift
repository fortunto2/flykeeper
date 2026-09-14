import Foundation

/// How much brain to run. Eco is synthetic wiring for a phone that must never stutter; the
/// other two are the real FlyWire FAFB v783 connectome at different synapse thresholds —
/// the same cells, fewer edges, so the lighter one is the same brain seen through a coarser
/// sieve rather than a different animal.
public enum SimulationTier: String, Sendable, CaseIterable, Identifiable {
    case eco        // synthetic 700 cells, fan-out 12
    case standard   // FlyWire, edges with ≥ 20 synapses
    case full       // FlyWire, edges with ≥ 5 synapses (the published filtered set)

    public var id: String { rawValue }

    public enum Source: Sendable, Equatable {
        case synthetic(neurons: Int, fanOut: Int)
        /// A packed export bundled with the app, loaded with this synapse threshold.
        case packed(resource: String, threshold: Int)
    }

    public var source: Source {
        switch self {
        case .eco: .synthetic(neurons: 700, fanOut: 12)
        case .standard: .packed(resource: "fafb-v783", threshold: 20)
        case .full: .packed(resource: "fafb-v783", threshold: 5)
        }
    }

    public var title: String {
        switch self {
        case .eco: "Eco"
        case .standard: "Brain ≥20"
        case .full: "Full brain"
        }
    }

    /// The noise levels this tier's wiring needs to sleep, walk and get excited.
    public var arousal: Vitals.Arousal {
        switch source {
        case .synthetic: .synthetic
        case .packed: .flywire
        }
    }

    /// Credit line the app must show whenever this tier's brain is on screen.
    public var attribution: String? {
        switch self {
        case .eco: nil
        case .standard, .full: "FlyWire FAFB v783 · CC BY 4.0 · Dorkenwald et al. 2024, Schlegel et al. 2024"
        }
    }
}

/// A run's own account of itself, mirroring `connectome_core::Receipt`.
///
/// The app shows these numbers rather than a tier label, for the reason the Rust side
/// carries the same type: a simulation reporting zero spikes and one that never started are
/// indistinguishable unless the run says which happened.
public struct SimulationReceipt: Sendable, Equatable {
    public let neurons: Int
    public let edges: Int
    public let steps: UInt64
    public let spikes: UInt64
    /// Cumulative: steps over wall-clock time since the engine was created, as
    /// `connectome_core::Receipt` defines it — not the burst rate of one batch.
    public let stepsPerSecond: Double
    public let isSynthetic: Bool

    public init(neurons: Int, edges: Int, steps: UInt64, spikes: UInt64,
                stepsPerSecond: Double, isSynthetic: Bool) {
        self.neurons = neurons
        self.edges = edges
        self.steps = steps
        self.spikes = spikes
        self.stepsPerSecond = stepsPerSecond
        self.isSynthetic = isSynthetic
    }

    /// Before the first frame: nothing measured, and honest about it.
    public static let empty = SimulationReceipt(neurons: 0, edges: 0, steps: 0, spikes: 0,
                                                stepsPerSecond: 0, isSynthetic: true)

    /// False when nothing was measured. A UI must not present an inconclusive run as a calm fly.
    public var isConclusive: Bool { steps > 0 && spikes > 0 }

    /// The synthetic label and the inconclusive marker are independent facts and both must
    /// show: a synthetic brain that has not fired is still not a calm fly.
    public var summary: String {
        var parts = ["\(neurons) neurons · \(edges) edges · \(Int(stepsPerSecond)) steps/s"]
        if isSynthetic { parts.append("SYNTHETIC WIRING") }
        if !isConclusive { parts.append("no spikes yet") }
        return parts.joined(separator: " · ")
    }
}
