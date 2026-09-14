import Foundation

/// What the brain is telling the body, read off the descending neurons — the ~1300 cells that
/// actually carry commands from a fly's brain to its nerve cord. This replaces reading one
/// number for the whole brain, which could say "busy" but never "left".
public struct MotorCommand: Sendable, Equatable {
    /// How hard both sides are pushing, 0...1 after the resting level is removed.
    public var drive: Double
    /// Turn command, −1 hard left … +1 hard right, after the wiring's own bias is removed.
    public var steer: Double

    public init(drive: Double, steer: Double) {
        self.drive = drive
        self.steer = steer
    }

    public static let still = MotorCommand(drive: 0, steer: 0)
}

/// Turns left and right descending firing rates into a motor command.
///
/// **Two measured facts shape this** (`connectome-core/examples/descending.rs`, FAFB v783):
///
/// 1. The two halves are not equal at rest. With no input at all the right descending
///    population sits 1.3–1.8% above the left. Whether that is real anatomy or uneven
///    proofreading, raw asymmetry is not steering — the resting difference has to be
///    subtracted, and it is learned rather than hardcoded so a different export still works.
/// 2. A touch moves it by about ±0.015 in the right direction: left bristles shift the
///    balance left, right bristles right. That is the full scale this maps to ±1.
///
/// Light does not appear here on purpose. Driving 5 486 photoreceptors of one eye, at any
/// strength up to ten times a touch, whole eye or a patch, moves the descending neurons by
/// 0.000. That is not only attenuation over four synapses: a steady light is not a steering
/// cue for a fly either, whose visual system reads motion and contrast. The eyes are in the
/// simulation and they fire; they do not drive the body, and the app says so rather than
/// inventing a response.
public struct DescendingReadout: Sendable, Equatable {
    /// Asymmetry that counts as a full turn command.
    public var steerScale: Double
    /// Descending firing rate that counts as full drive. Measured: an awake brain rests at
    /// 0.137 and a touch takes it to about 0.15, so 0.30 leaves a walking fly at about half
    /// throttle with room above it. Absolute, not learned — unlike steering, the *level* is
    /// the signal here, and it is what separates a sleeping fly from a walking one.
    public var fullDrive: Double
    /// Seconds for the learned resting asymmetry to follow a change.
    public var baselineTau: Double

    /// Learned resting asymmetry; nil until the first frame.
    private var restAsymmetry: Double?

    public init(steerScale: Double = 0.015, fullDrive: Double = 0.30, baselineTau: Double = 6) {
        self.steerScale = steerScale
        self.fullDrive = fullDrive
        self.baselineTau = baselineTau
    }

    /// `left` and `right` are the mean firing rates of each side's descending population.
    /// `settled` is false while a stimulus is applied, which freezes the baseline — otherwise
    /// the resting level chases the very signal it exists to remove.
    public mutating func command(left: Double, right: Double, dt: Double, settled: Bool = true) -> MotorCommand {
        let sum = left + right
        guard sum > 0 else { return .still }
        let asym = (right - left) / sum
        let drive = sum / 2

        if restAsymmetry == nil { restAsymmetry = asym }
        if settled, dt > 0 {
            restAsymmetry! += (asym - restAsymmetry!) * min(dt / max(baselineTau, 1e-6), 1)
        }
        return MotorCommand(drive: (drive / max(fullDrive, 1e-9)).clamped(to: 0...1),
                            steer: ((asym - restAsymmetry!) / steerScale).clamped(to: -1...1))
    }

    /// What the fly does, from the command it is actually being given.
    public func behaviour(_ c: MotorCommand, recentTouch: Bool) -> Behaviour {
        if c.drive <= 0.03 { return .sleep }
        if recentTouch && c.drive >= 0.5 { return .startle }
        if abs(c.steer) >= 0.45 { return .turn }
        if c.drive >= 0.35 { return .walk }
        if c.drive >= 0.12 { return .groom }
        return .rest
    }
}

extension Comparable {
    func clamped(to r: ClosedRange<Self>) -> Self { min(max(self, r.lowerBound), r.upperBound) }
}
