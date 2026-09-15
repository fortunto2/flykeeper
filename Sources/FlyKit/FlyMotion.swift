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

    /// Seconds left in the current saccade, and which way it goes. A fly does not turn
    /// smoothly: it runs straight and then flicks, and this is that flick in progress.
    public var saccadeLeft: Double = 0
    public var saccadeDirection: Double = 0

    public var isAirborne: Bool { z > 0.001 }
    public var isTurning: Bool { saccadeLeft > 0 }
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
    /// A saccade: how long the flick lasts and how fast it turns while it does. Real fly
    /// body saccades are short and fast rather than a steady drift; ours are the same shape.
    public var saccadeDuration: Double
    public var saccadeRate: Double
    /// Steering command that triggers one.
    public var saccadeThreshold: Double

    public init(walkSpeed: Double = 0.12, startleSpeed: Double = 0.9, turnCreep: Double = 0.15,
                turnRate: Double = 2.5, gaitRate: Double = 9, groomRate: Double = 14,
                startleGaitBoost: Double = 2, wingDecay: Double = 4,
                climbRate: Double = 1.2, sinkRate: Double = 0.35, flightSpeed: Double = 0.5,
                wanderRate: Double = 0.9, saccadeDuration: Double = 0.12,
                saccadeRate: Double = 6.5, saccadeThreshold: Double = 0.3) {
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
        self.saccadeDuration = saccadeDuration
        self.saccadeRate = saccadeRate
        self.saccadeThreshold = saccadeThreshold
    }

    /// Move the fly. `command` is what its brain is telling the body — `drive` how hard,
    /// `steer` which way — and `behaviour` is what that reads as. One entry point: the
    /// synthetic readout produces a command too, so "which readout made this" is settled
    /// where the command is built and travels no further.
    ///
    /// `toward`: a point in the arena the fly is heading for; when set the heading turns
    /// towards it instead of wandering. Locomotion still comes from the behaviour — a brain
    /// that says rest keeps a hungry fly sitting next to its food.
    ///
    /// Turning comes out as saccades — a straight run, then a fast flick — because that is
    /// the shape of a walking fly's path, and a heading that eases round a curve reads as a
    /// toy however right the speed is.
    public func advance(_ pose: FlyPose, command: MotorCommand, behaviour: Behaviour,
                        dt: Double, toward: (x: Double, y: Double)? = nil) -> FlyPose {
        var next = pose
        if next.saccadeLeft > 0 {
            next.saccadeLeft = max(0, next.saccadeLeft - dt)
            next.heading += next.saccadeDirection * saccadeRate * dt
        } else if abs(command.steer) >= saccadeThreshold, !pose.isAirborne, behaviour != .sleep {
            next.saccadeLeft = saccadeDuration
            // Positive steer is more drive on the right, which turns the fly right; in the
            // arena's frame (y down the screen) that is a positive heading change.
            next.saccadeDirection = command.steer > 0 ? 1 : -1
        }

        let speed: Double
        if behaviour == .startle {
            // Take off: up and away. Drive does not scale an escape — that is the point of one.
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
            // Legs keep pace with the body: a fly barely being driven steps slowly, and a
            // gait that runs at one rate under every drive is the tell of an animation
            // rather than a walk.
            (speed, gait) = switch behaviour {
            case .rest, .sleep, .startle: (0, 0)
            case .walk: (walkSpeed * command.drive, gaitRate * command.drive)
            case .turn: (walkSpeed * turnCreep * command.drive, gaitRate * command.drive)
            case .groom: (0, groomRate)
            }
            // A saccade already owns the heading; a `.turn` outside one still swings.
            if behaviour == .turn, next.saccadeLeft <= 0 { next.heading += turnRate * dt }
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
            next.x = next.x.clamped(to: 0...1)
        }
        if next.y < 0 || next.y > 1 {
            next.heading = -next.heading
            next.y = next.y.clamped(to: 0...1)
        }
        next.z = next.z.clamped(to: 0...1)
        return next
    }
}
