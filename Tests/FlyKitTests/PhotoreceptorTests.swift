import Testing
@testable import FlyKit

// The whole reason the eye works at all: photoreceptors answer change, not level. A steady
// light measured 0.000 at the descending neurons, so a receptor that reported brightness
// would be feeding the brain a number it cannot use.

@Test func aStaticSceneFadesToNothing() {
    var p = Photoreceptors(count: 4)
    let wall: [Float] = [0.2, 0.8, 0.5, 0.9]
    var r = p.respond(to: wall, dt: 0.016)
    // First sight of it is a change from the resting mean, so it does fire.
    #expect(r.contains { $0 > 0 })
    for _ in 0..<200 { r = p.respond(to: wall, dt: 0.016) }   // ~3 s, about 9 tau
    #expect(r.allSatisfy { $0 < 0.1 }, "a fly staring at a wall should see nothing: \(r)")
}

@Test func aMovingEdgeDrivesHard() {
    var p = Photoreceptors(count: 2)
    for _ in 0..<200 { p.respond(to: [0.5, 0.5], dt: 0.016) }
    let r = p.respond(to: [1.0, 0.0], dt: 0.016)
    #expect(r[0] > p.gain * 0.9, "a bright edge should drive nearly full: \(r[0])")
    #expect(r[1] > p.gain * 0.9, "and a dark one just as hard — OFF is a pathway too")
}

@Test func theResponseSaturatesRatherThanRunningAway() {
    var p = Photoreceptors(count: 1)
    let r = p.respond(to: [1.0], dt: 0.016)
    #expect(r[0] <= p.gain)
}

@Test func closingTheEyeStopsTheDriveAndForgetsTheScene() {
    var p = Photoreceptors(count: 2)
    for _ in 0..<200 { p.respond(to: [1.0, 0.0], dt: 0.016) }
    p.rest()
    #expect(p.response.allSatisfy { $0 == 0 })
    // Opening it again on the same scene should register it as new, not as already adapted.
    let r = p.respond(to: [1.0, 0.0], dt: 0.016)
    #expect(r.allSatisfy { $0 > 0 })
}

@Test func aMismatchedFrameIsIgnoredRatherThanCrashing() {
    var p = Photoreceptors(count: 3)
    let before = p.response
    #expect(p.respond(to: [0.5], dt: 0.016) == before)
}
