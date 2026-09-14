import Testing
@testable import FlyKit

// `Fly` is the one step from brain activity to a pose. These pin that the readout and the
// motion are wired together the way docs/sensory-map.md says.

@Test func aTouchedBusyBrainMakesTheFlyJump() {
    var fly = Fly()
    let before = fly.pose
    fly.advance(activity: 0.09, touched: true, dt: 0.1)
    #expect(fly.behaviour == .startle)
    #expect(fly.pose.wingBeat > 0)
    #expect(fly.pose != before)
}

@Test func theSameBrainWithoutTouchOnlyTurns() {
    var fly = Fly()
    fly.advance(activity: 0.09, touched: false, dt: 0.1)
    #expect(fly.behaviour == .turn)
    #expect(fly.pose.wingBeat == 0)
}

@Test func aSleepingFlyStaysPut() {
    var fly = Fly()
    let before = fly.pose
    for _ in 0..<50 { fly.advance(activity: 0.0, touched: false, dt: 0.1) }
    #expect(fly.behaviour == .sleep)
    #expect(fly.pose == before)
}

@Test func theTouchStimulusIsAFractionCountedInSteps() {
    // 250 steps at dt = 1 ms is the 250 ms the map documents; a slow tier keeps the same
    // number of steps. Every tenth neuron, so the touch is the same event on every tier.
    for n in [700, 6_000, 139_255] {
        let t = TouchStimulus.touch(neurons: n)
        #expect(t.durationSteps == 250)
        #expect(t.neurons.count == (n + 9) / 10, "tier \(n)")
    }
}

@Test func theFlysStateReachesTheBrainAsBackgroundDrive() {
    var fly = Fly()
    #expect(fly.vitals.noise == Vitals.awakeNoise)
    fly.pet()
    #expect(fly.vitals.noise > Vitals.awakeNoise, "petting must excite")
    fly.vitals.apply(.lightsOff)
    #expect(fly.vitals.noise == Vitals.asleepNoise)
}

@Test func timeScaleIsAFastForwardOfNeedsAndMotionAlike() {
    var slow = Fly()
    var fast = Fly()
    for _ in 0..<60 {
        slow.advance(activity: 0.05, touched: false, dt: 0.1)
        fast.advance(activity: 0.05, touched: false, dt: 0.1, timeScale: 16)
    }
    #expect(fast.vitals.food < slow.vitals.food, "needs must drain faster")
    #expect(fast.pose.legPhase > slow.pose.legPhase * 10, "the fly must move faster too")
}

@Test func aFastForwardedFrameStaysInsideTheCube() {
    // 64× at 16 ms is a second of fly time per frame; sub-stepping keeps every move small
    // enough for the wall reflection to work, so the fly never jumps out.
    var fly = Fly()
    for i in 0..<300 {
        fly.advance(activity: i % 50 == 0 ? 0.09 : 0.05, touched: i % 50 == 0, dt: 0.016, timeScale: 64)
        let p = fly.pose
        #expect((0...1).contains(p.x) && (0...1).contains(p.y) && (0...1).contains(p.z), "escaped: \(p)")
    }
}
