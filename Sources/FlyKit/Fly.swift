import Foundation

/// Current injected into a set of neurons for a while. A value, so the assumption of which
/// neurons a touch reaches lives here and in `docs/sensory-map.md`, not in a view.
public struct TouchStimulus: Sendable, Equatable {
    public var neurons: [Int]
    public var current: Float
    /// In simulation steps, not wall time: a slow tier must not get a shorter touch.
    public var durationSteps: UInt64

    public init(neurons: [Int], current: Float, durationSteps: UInt64) {
        self.neurons = neurons
        self.current = current
        self.durationSteps = durationSteps
    }

    /// Mechanosensory injection: 8.0 into every tenth neuron. A fraction rather than a fixed
    /// forty, so the touch is the same event on every tier — measured in
    /// `connectome-core/examples/touch_sweep.rs` to read ~0.09 through a frame mean on
    /// 700, 6 000 and 139 255 neurons, awake or asleep. On synthetic wiring the indices
    /// mean nothing; on the real export they must map to mechanosensory afferents.
    /// What a touch is, in one place: the app drives named bristles by index and cannot
    /// reach `touch(neurons:)`, so without these it re-typed the two constants.
    public static let touchCurrent: Float = 8.0
    public static let touchSteps: UInt64 = 250

    public static func touch(neurons: Int) -> TouchStimulus {
        TouchStimulus(neurons: Array(stride(from: 0, to: max(neurons, 0), by: 10)),
                      current: touchCurrent, durationSteps: touchSteps)
    }
}

/// A morsel on the arena floor. The keeper drops it; the fly has to get there.
public struct Food: Sendable, Equatable {
    public var x: Double
    public var y: Double
    /// What is left, 1 → 0. A morsel takes `Vitals.Rates.eatDuration` to finish whether
    /// the fly was hungry or not — a full fly still nibbles, and the keeper sees it eat.
    public var remaining: Double = 1
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// What the app managed to read out of the brain this frame. Two cases rather than one
/// number with a flag: a synthetic brain has no anatomy to name, and a real one should never
/// fall back to a whole-brain average by accident.
public enum BrainSignal: Sendable, Equatable {
    /// Fraction of all cells firing. Synthetic wiring: there is nothing else to read.
    case activity(Double, touched: Bool)
    /// Mean firing rate of the left and right descending populations — the cells that carry
    /// commands from a fly's brain to its nerve cord.
    case descending(left: Double, right: Double, touched: Bool)
}

/// The fly as seen: what it is doing and where it is. One pure step from the brain's
/// activity to a pose, so "spikes become a fly" is testable without a screen or an engine.
public struct Fly: Sendable, Equatable {
    public var pose: FlyPose
    public private(set) var behaviour: Behaviour
    public var vitals: Vitals
    public var readout: BehaviourReadout
    /// Used when the brain is real; nil is not an option, it is simply unused on synthetic
    /// wiring, where there are no descending neurons to read.
    public var descendingReadout = DescendingReadout()
    public var motion: FlyMotion
    /// The last command read off the descending neurons, for the screen to show.
    public private(set) var command: MotorCommand = .still
    /// Food on the floor, if any. Reached when within `eatRadius`.
    public private(set) var food: Food?
    public private(set) var isEating = false
    public static let eatRadius = 0.05

    public init(pose: FlyPose = FlyPose(x: 0.5, y: 0.5, heading: -.pi / 2), vitals: Vitals = Vitals(),
                readout: BehaviourReadout = BehaviourReadout(), motion: FlyMotion = FlyMotion()) {
        self.pose = pose
        self.behaviour = .rest
        self.vitals = vitals
        self.readout = readout
        self.motion = motion
    }

    /// `activity` is the mean fraction of neurons firing per step over the frame; `touched`
    /// is whether a stimulus is currently applied — the engine's word, not a timer of ours.
    /// `timeScale` is a fast-forward of everything: needs, and the fly itself. Motion is
    /// sub-stepped so a 64× frame is many small moves, not one jump through a wall.
    public mutating func advance(activity: Double, touched: Bool, dt: Double, timeScale: Double = 1) {
        advance(.activity(activity, touched: touched), dt: dt, timeScale: timeScale)
    }

    public mutating func advance(_ signal: BrainSignal, dt: Double, timeScale: Double = 1) {
        let scaled = dt * timeScale
        vitals.advance(dt: scaled)
        switch signal {
        case .activity(let a, let t):
            command = readout.command(activity: a)
            behaviour = readout.behaviour(activity: a, recentTouch: t)
        case .descending(let l, let r, let t):
            command = descendingReadout.command(left: l, right: r, dt: scaled, settled: !t)
            behaviour = descendingReadout.behaviour(command, recentTouch: t)
        }
        isEating = false
        if let f = food, !pose.isAirborne, hypot(f.x - pose.x, f.y - pose.y) <= Self.eatRadius,
           behaviour != .sleep, behaviour != .startle {
            // Arrived: eat instead of moving. Legs work (chewing), the body stays.
            isEating = true
            vitals.eat(dt: scaled)
            pose.legPhase += motion.groomRate * scaled
            food?.remaining -= scaled / vitals.rates.eatDuration
            if (food?.remaining ?? 0) <= 0 { food = nil }
            return
        }
        let goal = food.map { (x: $0.x, y: $0.y) }
        var remaining = scaled
        while remaining > 0 {
            let step = min(remaining, Self.motionSubstep)
            pose = motion.advance(pose, command: command, behaviour: behaviour, dt: step, toward: goal)
            remaining -= step
        }
    }

    /// Drop food at a point of the arena. One morsel at a time; a second drop moves it.
    public mutating func dropFood(at point: Food) {
        food = point
    }

    /// Largest single motion step, in seconds of fly time.
    public static let motionSubstep = 0.05

    /// Being touched is also being petted.
    public mutating func pet() { vitals.apply(.pet) }
}

