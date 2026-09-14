import Foundation

/// What the keeper can do for the fly.
public enum Care: String, Sendable, CaseIterable, Codable {
    case feed
    case pet
    case lightsOff
    case lightsOn
}

public enum Mood: String, Sendable, Codable {
    case happy
    case content
    case hungry
    case tired
    case asleep
}

/// The fly's needs, and the one number they turn into: the brain's background drive.
///
/// Nothing here is biology. It is the tamagotchi contract — food and energy drain, care
/// refills them — expressed so that neglect reaches the simulation instead of a label: a
/// hungry, tired fly gets a lower `noise`, and the readout then sees a quieter brain.
/// Bands measured in `connectome-core/examples/noise_sweep.rs`; see `docs/sensory-map.md`.
public struct Vitals: Sendable, Equatable, Codable {
    public struct Rates: Sendable, Equatable, Codable {
        /// Seconds for food to go from full to empty.
        public var foodLifetime: Double
        /// Seconds of wakefulness before the fly must sleep.
        public var energyLifetime: Double
        /// Seconds of sleep to restore energy fully.
        public var sleepLifetime: Double
        /// Seconds for the glow of being petted to fade (mood).
        public var affectionLifetime: Double
        /// Seconds for the brain's excitement after a touch to fade — shorter than the mood,
        /// or the whole brain burns white for two minutes after one pat.
        public var excitementLifetime: Double
        /// Seconds of eating to refill food from empty.
        public var eatDuration: Double

        public init(foodLifetime: Double = 600, energyLifetime: Double = 900,
                    sleepLifetime: Double = 240, affectionLifetime: Double = 120,
                    excitementLifetime: Double = 20, eatDuration: Double = 8) {
            self.foodLifetime = foodLifetime
            self.energyLifetime = energyLifetime
            self.sleepLifetime = sleepLifetime
            self.affectionLifetime = affectionLifetime
            self.excitementLifetime = excitementLifetime
            self.eatDuration = eatDuration
        }

        public static let `default` = Rates()
    }

    /// The noise levels a brain needs for silence, the walk band and the turn band. They are
    /// a property of the wiring, not of the fly: the real connectome self-sustains more than
    /// random wiring, so it needs less to be quiet and more to be excited. Both rows measured
    /// (`noise_sweep.rs`, `real_sweep.rs`), see docs/sensory-map.md.
    public struct Arousal: Sendable, Equatable, Codable {
        public var asleep: Float
        public var awake: Float
        /// Added on top of `awake` right after being petted.
        public var excited: Float

        public init(asleep: Float, awake: Float, excited: Float) {
            self.asleep = asleep
            self.awake = awake
            self.excited = excited
        }

        /// Synthetic wiring, gain 0.15: 1.0 silent · 3.5 walk · 6.5 turn.
        public static let synthetic = Arousal(asleep: 1.0, awake: 3.5, excited: 3.0)
        /// FlyWire FAFB v783, gain 0.02: 0.5 silent · 3.5 walk (4.9%) · 8.0 turn (7.0%).
        public static let flywire = Arousal(asleep: 0.5, awake: 3.5, excited: 4.5)
    }

    public var arousal: Arousal = .synthetic

    public static var awakeNoise: Float { Arousal.synthetic.awake }
    public static var asleepNoise: Float { Arousal.synthetic.asleep }

    public var food: Double = 1
    public var energy: Double = 1
    public var affection: Double = 0
    /// The brain's short-lived arousal after a touch; drives `noise`, not the mood.
    public var excitement: Double = 0
    public var lightsOn: Bool = true
    /// Set when energy runs out; cleared when it is back above `wakeEnergy`.
    public private(set) var isSleeping: Bool = false
    public var rates: Rates

    private let sleepEnergy = 0.1
    private let wakeEnergy = 0.9

    public init(rates: Rates = .default) {
        self.rates = rates
    }

    public var isAwake: Bool { lightsOn && !isSleeping }

    public var mood: Mood {
        if !isAwake { return .asleep }
        if affection > 0.5 { return .happy }
        if food < 0.3 { return .hungry }
        if energy < 0.3 { return .tired }
        return .content
    }

    /// Background drive for the brain. Fed and rested: the walk band. Hungry or tired: down
    /// towards the groom and rest bands. Just petted: excited, the turn band. Asleep:
    /// silent, and a touch still wakes it.
    public var noise: Float {
        guard isAwake else { return arousal.asleep }
        let vigour = 0.4 + 0.6 * min(food, energy)
        return arousal.asleep + (arousal.awake - arousal.asleep) * Float(vigour)
            + arousal.excited * Float(excitement)
    }

    public mutating func apply(_ care: Care) {
        switch care {
        case .feed: food = 1
        case .pet: affection = 1; excitement = 1
        case .lightsOff: lightsOn = false
        case .lightsOn: lightsOn = true
        }
    }

    /// Replay `dt` seconds. Integrated piecewise up to each sleep/wake crossing, so one call
    /// for a day equals the same day replayed a frame at a time: a fly left overnight comes
    /// back rested, not asleep at zero.
    public mutating func advance(dt: Double) {
        guard dt > 0, dt.isFinite else { return }
        var remaining = dt
        while remaining > 0 {
            let step: Double
            if isAwake {
                step = min(remaining, max(0, energy - sleepEnergy) * rates.energyLifetime)
                energy = clamp(energy - step / rates.energyLifetime)
                if energy <= sleepEnergy + 1e-9 { isSleeping = true }
            } else if isSleeping {
                step = min(remaining, max(0, wakeEnergy - energy) * rates.sleepLifetime)
                energy = clamp(energy + step / rates.sleepLifetime)
                if energy >= wakeEnergy - 1e-9 { isSleeping = false }
            } else {
                step = remaining
                energy = clamp(energy + step / rates.sleepLifetime)
            }
            food = clamp(food - step / rates.foodLifetime)
            affection = clamp(affection - step / rates.affectionLifetime)
            excitement = clamp(excitement - step / rates.excitementLifetime)
            remaining -= step
            // A zero step with no mode change would loop forever; a mode change re-enters
            // the loop in the other branch and consumes time there.
            if step == 0 && (isAwake ? energy > sleepEnergy : !isSleeping) { break }
        }
    }

    /// A bite: `dt` seconds of eating.
    public mutating func eat(dt: Double) {
        food = clamp(food + dt / rates.eatDuration)
    }

    private func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
}
