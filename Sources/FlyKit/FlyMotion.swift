import Foundation

/// Where the fly is in a unit-square arena and how its limbs are posed. Normalised so the
/// view can be any size and the domain never sees points.
public struct FlyPose: Sendable, Equatable {
    public var x: Double
    public var y: Double
    /// Height, 0 on the floor, 1 at the ceiling of a unit cube.
    public var z: Double
    /// Radians, 0 points along +x.
    public var heading: Double
    /// Advances while legs move; the view turns it into a gait.
    public var legPhase: Double
    /// Above zero while the wings are beating (startle and flight). Decays back to zero.
    public var wingBeat: Double

    public init(x: Double, y: Double, z: Double = 0, heading: Double, legPhase: Double = 0, wingBeat: Double = 0) {
        self.x = x
        self.y = y
        self.z = z
        self.heading = heading
        self.legPhase = legPhase
        self.wingBeat = wingBeat
    }

    public var isAirborne: Bool { z > 0.001 }
}

/// Turns a behaviour into a displacement. Like `BehaviourReadout`, every number here is a
/// choice of ours, not a measurement of a fly — see `docs/sensory-map.md`.
public struct FlyMotion: Sendable, Equatable {
    /// Arena widths per second.
    public var walkSpeed: Double
    public var startleSpeed: Double
    /// Fraction of walkSpeed a turning fly still creeps forward.
    public var turnCreep: Double
    /// Radians per second.
    public var turnRate: Double
    public var gaitRate: Double
    public var groomRate: Double
    public var startleGaitBoost: Double
    public var wingDecay: Double
    /// Flight, in cube heights per second: a startle climbs, then the fly glides forward and
    /// sinks back to the floor. Airborne it keeps flying whatever the readout says, because
    /// a fly does not stop mid-air when its brain goes quiet — it lands first.
    public var climbRate: Double
    public var sinkRate: Double
    public var flightSpeed: Double
    /// Radians per second of slow heading drift while walking, so a walk is a wander and
    /// not a straight line from wall to wall.
    public var wanderRate: Double

    public init(walkSpeed: Double = 0.12, startleSpeed: Double = 0.9, turnCreep: Double = 0.15,
                turnRate: Double = 2.5, gaitRate: Double = 9, groomRate: Double = 14,
                startleGaitBoost: Double = 2, wingDecay: Double = 4,
                climbRate: Double = 1.2, sinkRate: Double = 0.35, flightSpeed: Double = 0.5,
                wanderRate: Double = 0.9) {
        self.walkSpeed = walkSpeed
        self.startleSpeed = startleSpeed
        self.turnCreep = turnCreep
        self.turnRate = turnRate
        self.gaitRate = gaitRate
        self.groomRate = groomRate
        self.startleGaitBoost = startleGaitBoost
        self.wingDecay = wingDecay
        self.climbRate = climbRate
        self.sinkRate = sinkRate
        self.flightSpeed = flightSpeed
        self.wanderRate = wanderRate
    }

    /// `toward`: a point in the arena the fly is heading for; when set, the heading turns
    /// towards it (at `turnRate`) instead of wandering. Locomotion itself still comes from
    /// the behaviour — a brain that says rest keeps a hungry fly sitting next to its food.
    public func advance(_ pose: FlyPose, behaviour: Behaviour, dt: Double, toward: (x: Double, y: Double)? = nil) -> FlyPose {
        var next = pose
        let speed: Double
        if behaviour == .startle {
            // Take off: up and away.
            speed = startleSpeed
            next.z += climbRate * dt
            next.wingBeat = 1
            next.legPhase += gaitRate * startleGaitBoost * dt
        } else if pose.isAirborne {
            // Glide down along the heading, wings beating, a slow curve so it is not a line.
            speed = flightSpeed
            next.z -= sinkRate * dt
            next.heading += turnRate * 0.3 * dt
            next.wingBeat = 1
        } else {
            next.wingBeat = max(0, next.wingBeat - wingDecay * dt)
            let gait: Double
            (speed, gait) = switch behaviour {
            case .rest, .sleep, .startle: (0, 0)
            case .walk: (walkSpeed, gaitRate)
            case .turn: (walkSpeed * turnCreep, gaitRate)
            case .groom: (0, groomRate)
            }
            if behaviour == .turn { next.heading += turnRate * dt }
            if let toward, speed > 0 {
                let want = atan2(toward.y - next.y, toward.x - next.x)
                var delta = want - next.heading
                delta = atan2(sin(delta), cos(delta))   // shortest way round
                next.heading += max(-turnRate * dt, min(turnRate * dt, delta))
            } else if behaviour == .walk {
                // Deterministic drift keyed on the gait, so the path curves and the tests
                // still repeat.
                next.heading += wanderRate * sin(next.legPhase * 0.11) * dt
            }
            next.legPhase += gait * dt
        }
        next.x += cos(next.heading) * speed * dt
        next.y += sin(next.heading) * speed * dt
        // Reflect off the walls; the floor and ceiling clamp. A fly that leaves the cube is
        // a fly nobody can see.
        if next.x < 0 || next.x > 1 {
            next.heading = .pi - next.heading
            next.x = min(max(next.x, 0), 1)
        }
        if next.y < 0 || next.y > 1 {
            next.heading = -next.heading
            next.y = min(max(next.y, 0), 1)
        }
        next.z = min(max(next.z, 0), 1)
        return next
    }
}
