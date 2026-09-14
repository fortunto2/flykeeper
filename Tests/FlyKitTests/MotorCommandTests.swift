import Testing
@testable import FlyKit

// The readout's whole job is to turn two numbers into "how hard" and "which way". These pin
// the parts that are easy to get backwards, with the levels measured on FAFB v783: resting
// asymmetry about +0.015 (the right side sits higher with no input), a touch moving it by
// about ±0.015.

private let rest = (left: 0.1342, right: 0.1392)   // measured baseline, noise 1.0

private func settled(_ r: inout DescendingReadout) {
    for _ in 0..<2000 { _ = r.command(left: rest.left, right: rest.right, dt: 0.016) }
}

@Test func theWiringsRestingBiasIsNotMistakenForSteering() {
    // Raw asymmetry at rest is +0.018. Reported as steering it would be a fly that circles
    // for ever without being touched.
    var r = DescendingReadout()
    settled(&r)
    let c = r.command(left: rest.left, right: rest.right, dt: 0.016)
    #expect(abs(c.steer) < 0.05, "resting bias leaked into steering: \(c.steer)")
}

@Test func moreActivityOnTheRightSteersRight() {
    var r = DescendingReadout()
    settled(&r)
    // Measured shift for a right-side touch: asymmetry +0.017 above rest.
    let c = r.command(left: 0.1383, right: 0.1484, dt: 0.016, settled: false)
    #expect(c.steer > 0.5, "expected a right turn, got \(c.steer)")
}

@Test func moreActivityOnTheLeftSteersLeft() {
    var r = DescendingReadout()
    settled(&r)
    let c = r.command(left: 0.1484, right: 0.1383, dt: 0.016, settled: false)
    #expect(c.steer < -0.5, "expected a left turn, got \(c.steer)")
}

@Test func steeringSaturatesRatherThanRunningAway() {
    var r = DescendingReadout()
    settled(&r)
    let c = r.command(left: 0.05, right: 0.30, dt: 0.016, settled: false)
    #expect(c.steer <= 1.0 && c.steer >= -1.0)
}

@Test func aSilentBrainCommandsNothingAndTheFlySleeps() {
    var r = DescendingReadout()
    let c = r.command(left: 0, right: 0, dt: 0.016)
    #expect(c == .still)
    #expect(r.behaviour(c, recentTouch: false) == .sleep)
}

@Test func aTouchedBusyBrainStartlesAndAnUntouchedOneDoesNot() {
    let r = DescendingReadout()
    let busy = MotorCommand(drive: 0.8, steer: 0.1)
    #expect(r.behaviour(busy, recentTouch: true) == .startle)
    #expect(r.behaviour(busy, recentTouch: false) != .startle)
}

@Test func aHardTurnCommandReadsAsTurningEvenWhileWalking() {
    let r = DescendingReadout()
    #expect(r.behaviour(MotorCommand(drive: 0.5, steer: 0.8), recentTouch: false) == .turn)
    #expect(r.behaviour(MotorCommand(drive: 0.5, steer: 0.1), recentTouch: false) == .walk)
}

@Test func theBaselineFollowsARealChangeInArousalButNotAStimulus() {
    var r = DescendingReadout()
    settled(&r)
    // A stimulus is held: the baseline must not chase it, or the turn fades while the finger
    // is still on the fly.
    var steer = 0.0
    for _ in 0..<300 { steer = r.command(left: 0.1383, right: 0.1484, dt: 0.016, settled: false).steer }
    #expect(steer > 0.5, "steering decayed under a held stimulus: \(steer)")
    // A genuine change in resting level, with nothing applied, is learned away.
    for _ in 0..<3000 { _ = r.command(left: 0.20, right: 0.21, dt: 0.016) }
    let c = r.command(left: 0.20, right: 0.21, dt: 0.016)
    #expect(abs(c.steer) < 0.3, "new resting level not learned: \(c.steer)")
}

// Saccades: a walking fly runs straight and flicks, it does not ease round a curve.

@Test func aSteerCommandTurnsInAFlickNotASlide() {
    let m = FlyMotion()
    var pose = FlyPose(x: 0.5, y: 0.5, heading: 0)
    let hard = MotorCommand(drive: 0.6, steer: 0.9)
    var turning = 0, straight = 0
    var lastHeading = pose.heading
    for _ in 0..<200 {
        pose = m.advance(pose, command: hard, behaviour: .walk, dt: 0.016)
        if abs(pose.heading - lastHeading) > 1e-9 { turning += 1 } else { straight += 1 }
        lastHeading = pose.heading
    }
    #expect(turning > 0, "it never turned")
    #expect(straight > 0, "it turned continuously — that is a slide, not a saccade")
}

@Test func aSaccadeIsShortAndFastRatherThanSlowAndLong() {
    let m = FlyMotion()
    var pose = FlyPose(x: 0.5, y: 0.5, heading: 0)
    pose = m.advance(pose, command: MotorCommand(drive: 0.6, steer: 0.9), behaviour: .walk, dt: 0.016)
    #expect(pose.isTurning)
    var steps = 0
    while pose.isTurning && steps < 100 {
        pose = m.advance(pose, command: .still, behaviour: .walk, dt: 0.016)
        steps += 1
    }
    let seconds = Double(steps) * 0.016
    #expect(seconds > 0.05 && seconds < 0.25, "a saccade should last about 0.12 s, took \(seconds)")
    #expect(abs(pose.heading) > 0.4, "and should actually turn the fly: \(pose.heading)")
}

@Test func steeringRightAndLeftGoOppositeWays() {
    let m = FlyMotion()
    let start = FlyPose(x: 0.5, y: 0.5, heading: 0)
    var r = start, l = start
    for _ in 0..<12 {
        r = m.advance(r, command: MotorCommand(drive: 0.6, steer: 0.9), behaviour: .walk, dt: 0.016)
        l = m.advance(l, command: MotorCommand(drive: 0.6, steer: -0.9), behaviour: .walk, dt: 0.016)
    }
    #expect(r.heading > 0 && l.heading < 0, "right \(r.heading), left \(l.heading)")
}

@Test func driveSetsHowFastItWalks() {
    let m = FlyMotion()
    let start = FlyPose(x: 0.5, y: 0.5, heading: 0)
    let slow = m.advance(start, command: MotorCommand(drive: 0.2, steer: 0), behaviour: .walk, dt: 0.1)
    let fast = m.advance(start, command: MotorCommand(drive: 1.0, steer: 0), behaviour: .walk, dt: 0.1)
    #expect(fast.x - start.x > (slow.x - start.x) * 2)
    #expect(fast.legPhase > slow.legPhase, "faster legs when it walks faster")
}

@Test func aCommandedFlyStaysInTheArena() {
    let m = FlyMotion()
    var pose = FlyPose(x: 0.9, y: 0.9, heading: 0.4)
    for i in 0..<3000 {
        let c = MotorCommand(drive: 0.9, steer: i % 90 == 0 ? 0.9 : 0.0)
        pose = m.advance(pose, command: c, behaviour: i % 300 == 0 ? .startle : .walk, dt: 0.02)
        #expect((0...1).contains(pose.x) && (0...1).contains(pose.y) && (0...1).contains(pose.z),
                "escaped: \(pose)")
    }
}

@Test func driveIsTheAbsoluteLevel_soSleepAndWalkingAreTellableApart() {
    // Measured: a silent brain reads 0.000, an awake one 0.137, a touched one about 0.15.
    // The level is the signal — a learned baseline here would make a sleeping fly "normal"
    // after a few seconds of sleeping.
    var r = DescendingReadout()
    let asleep = r.command(left: 0.0002, right: 0.0002, dt: 0.016)
    #expect(r.behaviour(asleep, recentTouch: false) == .sleep)
    var awake = DescendingReadout()
    settled(&awake)
    let walking = awake.command(left: rest.left, right: rest.right, dt: 0.016)
    #expect(walking.drive > 0.35 && walking.drive < 0.7, "resting drive should amble: \(walking.drive)")
    #expect(awake.behaviour(walking, recentTouch: false) == .walk)
    let hard = awake.command(left: 0.30, right: 0.31, dt: 0.016, settled: false)
    #expect(hard.drive > walking.drive, "a harder driven brain must push harder")
    #expect(hard.drive <= 1)
}

@Test func aLongSleepDoesNotBecomeTheNewNormal() {
    var r = DescendingReadout()
    var c = MotorCommand.still
    for _ in 0..<4000 { c = r.command(left: 0.0002, right: 0.0002, dt: 0.016) }
    #expect(r.behaviour(c, recentTouch: false) == .sleep, "still asleep after a minute of it")
}
