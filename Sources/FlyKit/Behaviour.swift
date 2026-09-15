import Foundation

/// What the fly is doing. Deliberately a small closed set: these are the behaviours a
/// descending-neuron readout can actually distinguish, not everything a fly can do.
public enum Behaviour: String, Sendable, CaseIterable {
    case rest
    case walk
    case turn
    case groom
    case startle
    case sleep
}

/// Turns a spike rate into a behaviour.
///
/// **This mapping is ours, not biology.** The connectome says which neurons connect to
/// which; it does not say that "7% of neurons firing" means turning. Every threshold here
/// is an assumption, measured against the synthetic engine's arousal bands
/// (`connectome-core/examples/noise_sweep.rs`, `touch_sweep.rs`) and documented in
/// `docs/sensory-map.md`.
public struct BehaviourReadout: Sendable, Equatable {
    public var startleRate: Double
    public var turnRate: Double
    public var walkRate: Double
    public var groomRate: Double
    public var sleepRate: Double

    public init(startleRate: Double = 0.07, turnRate: Double = 0.07, walkRate: Double = 0.04,
                groomRate: Double = 0.012, sleepRate: Double = 0.003) {
        self.startleRate = startleRate
        self.turnRate = turnRate
        self.walkRate = walkRate
        self.groomRate = groomRate
        self.sleepRate = sleepRate
    }

    /// `activity` is the mean fraction of neurons firing per step over the last frame
    /// (0...1). A frame mean, not a single step: one 1 ms sample of a 700-cell population
    /// flips the label at frame rate.
    /// The same command shape the descending readout produces, so the rest of the app has
    /// one way to be told what the fly is doing rather than two. Synthetic wiring has no
    /// sides to compare, so it can say how hard but never which way.
    public func command(activity: Double) -> MotorCommand {
        MotorCommand(drive: (activity / max(turnRate, 1e-9)).clamped(to: 0...1), steer: 0)
    }

    public func behaviour(activity: Double, recentTouch: Bool) -> Behaviour {
        if recentTouch && activity >= startleRate { return .startle }
        if activity >= turnRate { return .turn }
        if activity >= walkRate { return .walk }
        if activity >= groomRate { return .groom }
        if activity <= sleepRate { return .sleep }
        return .rest
    }
}
