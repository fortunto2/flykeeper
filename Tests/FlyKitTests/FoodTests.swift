import Testing
@testable import FlyKit

// Food is the first thing the fly *does*: it has to walk there and eat. These pin that the
// goal steers the heading, that arrival refills food over time, and that the brain still
// decides whether the legs move at all.

@Test func aWalkingFlyTurnsTowardsItsFoodAndArrives() {
    var fly = Fly(pose: FlyPose(x: 0.2, y: 0.5, heading: .pi))   // facing away from the food
    fly.dropFood(at: Food(x: 0.8, y: 0.5))
    var steps = 0
    while !fly.isEating && steps < 3000 {
        fly.advance(activity: 0.05, touched: false, dt: 0.016)
        steps += 1
    }
    #expect(fly.isEating, "should reach the food while walking; got to \(fly.pose)")
    #expect(steps < 1200, "a 0.6 crossing at 0.12/s is ~5 s, not \(Double(steps) * 0.016) s")
}

@Test func eatingRefillsFoodAndTheMorselDisappearsWhenFull() {
    var fly = Fly(pose: FlyPose(x: 0.5, y: 0.5, heading: 0))
    fly.vitals.advance(dt: Vitals.Rates.default.foodLifetime * 0.9)   // hungry
    fly.dropFood(at: Food(x: 0.5, y: 0.5))
    let before = fly.vitals.food
    fly.advance(activity: 0.05, touched: false, dt: 1)
    #expect(fly.isEating)
    #expect(fly.vitals.food > before)
    #expect(fly.pose.x == 0.5 && fly.pose.y == 0.5, "eating, not walking")
    for _ in 0..<6 { fly.advance(activity: 0.05, touched: false, dt: 1) }
    #expect(fly.food != nil, "a morsel lasts eatDuration (8 s); 7 s in it is still there")
    for _ in 0..<3 { fly.advance(activity: 0.05, touched: false, dt: 1) }
    #expect(fly.vitals.food > 0.95)
    #expect(fly.food == nil, "the morsel is gone once it is eaten")
}

@Test func aSleepingBrainDoesNotWalkToFood() {
    var fly = Fly(pose: FlyPose(x: 0.2, y: 0.5, heading: 0))
    fly.dropFood(at: Food(x: 0.8, y: 0.5))
    for _ in 0..<300 { fly.advance(activity: 0.0, touched: false, dt: 0.016) }
    #expect(!fly.isEating)
    #expect(fly.pose.x == 0.2, "the brain says sleep; the goal must not move the fly")
}

@Test func excitementFadesFasterThanTheMood() {
    var v = Vitals()
    v.apply(.pet)
    v.advance(dt: 60)
    #expect(v.excitement == 0, "the brain calms within a minute")
    #expect(v.affection > 0, "the mood still remembers the pat")
    #expect(v.noise <= v.arousal.awake, "no excitement left in the drive")
}

@Test func walkingWandersInsteadOfGoingStraight() {
    let motion = FlyMotion()
    var pose = FlyPose(x: 0.5, y: 0.5, heading: 0)
    for _ in 0..<200 { pose = motion.advance(pose, command: .full, behaviour: .walk, dt: 0.05) }
    #expect(pose.heading != 0, "a walk should curve")
}

@Test func foodAcrossTheArenaTakesSecondsToReachNotOneFrame() {
    var fly = Fly()   // centre, facing -y
    fly.dropFood(at: Food(x: 0.75, y: 0.3))
    var frames = 0
    while fly.food != nil && frames < 3000 {
        fly.advance(activity: 0.048, touched: false, dt: 0.016)
        frames += 1
    }
    #expect(frames > 120, "0.32 across at 0.12/s is ~2.7 s, but the morsel vanished after \(frames) frames at \(fly.pose)")
}

@Test func aFullFlyStillNibblesTheWholeMorsel() {
    var fly = Fly(pose: FlyPose(x: 0.5, y: 0.5, heading: 0))
    fly.dropFood(at: Food(x: 0.5, y: 0.5))
    fly.advance(activity: 0.05, touched: false, dt: 1)
    #expect(fly.isEating)
    #expect(fly.food != nil, "full or not, eating takes its time and the keeper gets to watch")
}
