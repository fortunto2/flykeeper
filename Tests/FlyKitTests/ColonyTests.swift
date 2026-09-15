import Foundation
import Testing
@testable import FlyKit

// Contact and spawn used to live in the view, where nothing could check them and one of them
// was wrong for a week: a bump was measured at the *eating* reach, so two flies could stand
// touching and feel nothing.

private func at(_ x: Double, _ y: Double, heading: Double = 0, z: Double = 0) -> FlyPose {
    FlyPose(x: x, y: y, z: z, heading: heading)
}

@Test func fliesStandingApartDoNotTouch() {
    #expect(Colony.contacts([at(0.2, 0.5), at(0.8, 0.5)]).isEmpty)
    #expect(Colony.contacts([at(0.5, 0.5)]).isEmpty, "one fly cannot bump into itself")
    #expect(Colony.contacts([]).isEmpty)
}

@Test func fliesTouchingAtBodyWidthFeelIt() {
    // Two body widths is 0.11; the eating reach is 0.05, and using it here was the bug.
    let c = Colony.contacts([at(0.5, 0.5), at(0.58, 0.5)])
    #expect(c.count == 2, "both of them feel a bump, not just one")
    #expect(Set(c.map(\.fly)) == [0, 1])
    #expect(Colony.contacts([at(0.5, 0.5), at(0.56, 0.5)]).count == 2,
            "closer still counts")
}

@Test func eachFlyFeelsTheOtherOnTheSideItIsActuallyOn() {
    // Facing +x, with the other fly at +y: on its right in the arena's frame.
    let c = Colony.contacts([at(0.5, 0.5, heading: 0), at(0.5, 0.56, heading: 0)])
    #expect(c.first { $0.fly == 0 }?.side == .right)
    #expect(c.first { $0.fly == 1 }?.side == .left, "and the other one feels it on its own left")
}

@Test func turningAroundSwapsWhichSideTheBumpIsOn() {
    let facing = Colony.contacts([at(0.5, 0.5, heading: 0), at(0.5, 0.56)]).first { $0.fly == 0 }?.side
    let away = Colony.contacts([at(0.5, 0.5, heading: .pi), at(0.5, 0.56)]).first { $0.fly == 0 }?.side
    #expect(facing != away, "a fly that has turned round must feel the same neighbour elsewhere")
}

@Test func aFlyInTheAirDoesNotBumpOneOnTheFloor() {
    #expect(Colony.contacts([at(0.5, 0.5), at(0.52, 0.5, z: 0.4)]).isEmpty)
    #expect(Colony.contacts([at(0.5, 0.5, z: 0.4), at(0.52, 0.5, z: 0.42)]).count == 2,
            "two flying together still touch")
}

@Test func aCrowdReportsEveryPairOnceEachWay() {
    let crowd = [at(0.5, 0.5), at(0.55, 0.5), at(0.5, 0.55)]
    let c = Colony.contacts(crowd)
    #expect(c.count == 6, "three mutually touching flies are three pairs, two feelings each")
}

@Test func aNewFlyIsPutWhereTheOthersAreNot() {
    let crowd = (0..<6).map { _ in at(0.2, 0.2) }
    var rng = SystemRandomNumberGenerator()
    let p = Colony.spawn(among: crowd, candidates: 40, using: &rng)
    #expect(hypot(p.x - 0.2, p.y - 0.2) > 0.2, "spawned on top of the crowd: \(p)")
    #expect((0.1...0.9).contains(p.x) && (0.1...0.9).contains(p.y), "and inside the arena")
}
