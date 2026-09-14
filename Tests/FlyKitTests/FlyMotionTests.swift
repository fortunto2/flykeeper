import Testing
@testable import FlyKit

// Motion is the second layer of assumption on top of the readout: a behaviour label becomes
// a displacement. These tests pin what each label does on screen, not what a fly does.

private let motion = FlyMotion()
private let origin = FlyPose(x: 0.5, y: 0.5, heading: 0)

@Test func walkingMovesAlongTheHeading() {
    let next = motion.advance(origin, behaviour: .walk, dt: 0.1)
    #expect(next.x > origin.x)
    #expect(abs(next.y - origin.y) < 1e-9)
    #expect(next.legPhase > origin.legPhase, "legs must move when the fly walks")
}

@Test func turningRotatesWithoutLeavingTheSpot() {
    let next = motion.advance(origin, behaviour: .turn, dt: 0.1)
    #expect(next.heading != origin.heading)
    #expect(abs(next.x - origin.x) < 0.01)
}

@Test(arguments: [Behaviour.sleep, .rest])
func sleepingAndRestingChangeNothing(_ b: Behaviour) {
    #expect(motion.advance(origin, behaviour: b, dt: 0.5) == origin)
}

@Test func groomingMovesLegsButNotTheBody() {
    let next = motion.advance(origin, behaviour: .groom, dt: 0.1)
    #expect(next.x == origin.x && next.y == origin.y)
    #expect(next.legPhase > origin.legPhase)
}

@Test func startleIsAJumpFasterThanAWalkAndBeatsTheWings() {
    let walk = motion.advance(origin, behaviour: .walk, dt: 0.1)
    let jump = motion.advance(origin, behaviour: .startle, dt: 0.1)
    #expect(jump.x - origin.x > walk.x - origin.x)
    #expect(jump.wingBeat > 0)
    #expect(walk.wingBeat == 0)
}

@Test func wingsStopBeatingAfterTheStartle() {
    var pose = motion.advance(origin, behaviour: .startle, dt: 0.1)
    for _ in 0..<20 { pose = motion.advance(pose, behaviour: .walk, dt: 0.1) }
    #expect(pose.wingBeat == 0)
}

@Test(arguments: Array(stride(from: 0.0, to: 6.28, by: 0.7)))
func theFlyNeverLeavesTheArena(heading: Double) {
    // Walk straight for a long time; the pose must stay in the unit square.
    var pose = FlyPose(x: 0.5, y: 0.5, heading: heading)
    for _ in 0..<2000 {
        pose = motion.advance(pose, behaviour: .walk, dt: 0.05)
        #expect((0...1).contains(pose.x) && (0...1).contains(pose.y), "escaped: \(pose)")
    }
}

@Test func aStartleTakesOffAndTheFlyGlidesBackToTheFloor() {
    var pose = motion.advance(origin, behaviour: .startle, dt: 0.2)
    #expect(pose.isAirborne, "startle must lift off")
    #expect(pose.wingBeat == 1)
    // Airborne, the readout says rest; the fly still flies until it lands.
    let mid = motion.advance(pose, behaviour: .rest, dt: 0.1)
    #expect(mid.isAirborne && mid.wingBeat == 1)
    #expect(mid.x != pose.x || mid.y != pose.y, "it flies forward while gliding")
    for _ in 0..<200 { pose = motion.advance(pose, behaviour: .rest, dt: 0.05) }
    #expect(!pose.isAirborne, "it must land eventually: z \(pose.z)")
    #expect(pose.wingBeat == 0)
}

@Test func theFlyNeverLeavesTheCube() {
    var pose = FlyPose(x: 0.9, y: 0.9, heading: 0.3)
    for i in 0..<400 {
        pose = motion.advance(pose, behaviour: i % 40 == 0 ? .startle : .walk, dt: 0.05)
        #expect((0...1).contains(pose.x) && (0...1).contains(pose.y) && (0...1).contains(pose.z),
                "escaped: \(pose)")
    }
}
