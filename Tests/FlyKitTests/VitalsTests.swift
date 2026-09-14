import Testing
@testable import FlyKit

// The tamagotchi layer: what the keeper does and how the fly's state turns into the brain's
// background drive. Rates are ours (docs/sensory-map.md); these pin that the dial moves the
// way the doc says, not that a fly lives this way.

@Test func aFreshFlyIsAwakeFedAndInTheWalkBand() {
    let v = Vitals()
    #expect(v.isAwake)
    #expect(v.mood == .content)
    #expect(v.noise >= 3.0 && v.noise <= 4.0, "fresh fly should drive the walk band, got \(v.noise)")
}

@Test func foodDrainsAndFeedingRefills() {
    var v = Vitals()
    v.advance(dt: Vitals.Rates.default.foodLifetime / 2)
    #expect(v.food < 0.6 && v.food > 0.4)
    v.apply(.feed)
    #expect(v.food == 1)
}

@Test func aHungryFlyIsSluggishAndTheDialSaysSo() {
    var v = Vitals()
    let fed = v.noise
    v.advance(dt: Vitals.Rates.default.foodLifetime)
    #expect(v.food == 0)
    #expect(v.mood == .hungry)
    #expect(v.noise < fed)
}

@Test func lightsOffPutsTheFlyToSleepAndSleepRestoresEnergy() {
    var v = Vitals()
    v.advance(dt: Vitals.Rates.default.energyLifetime / 2)
    let tired = v.energy
    v.apply(.lightsOff)
    #expect(!v.isAwake)
    #expect(v.noise <= 1.0, "asleep must be silent for the brain: \(v.noise)")
    v.advance(dt: 60)
    #expect(v.energy > tired)
}

@Test func anExhaustedFlyFallsAsleepOnItsOwnAndWakesRested() {
    var v = Vitals()
    v.advance(dt: Vitals.Rates.default.energyLifetime * 1.1)
    #expect(!v.isAwake, "energy ran out, the fly must sleep even with the lights on")
    v.advance(dt: Vitals.Rates.default.sleepLifetime * 1.1)
    // It woke at 0.9 and has been awake since; awake, and well above the sleep threshold.
    #expect(v.isAwake)
    #expect(v.energy > 0.5)
}

@Test func pettingLiftsTheMoodAndItFadesAgain() {
    var v = Vitals()
    v.advance(dt: Vitals.Rates.default.foodLifetime * 0.7)   // a bit hungry, so not content
    #expect(v.mood != .happy)
    v.apply(.pet)
    #expect(v.mood == .happy)
    v.advance(dt: Vitals.Rates.default.affectionLifetime * 1.5)
    #expect(v.mood != .happy)
}

@Test func catchingUpAfterALongAbsenceClampsRatherThanExplodes() {
    // Offline-first: the app comes back after a day and replays the elapsed time. Nothing
    // may go negative, above one, or NaN.
    var v = Vitals()
    v.advance(dt: 86_400)
    for x in [v.food, v.energy, v.affection] {
        #expect(x >= 0 && x <= 1, "out of range: \(x)")
    }
    #expect(v.noise.isFinite)
}

@Test func oneLongCatchUpEqualsTheSameTimeInSmallSteps() {
    // The app replays the time it was closed in one call. That call must land where a
    // frame-by-frame replay would: through the sleep and wake it contains, not stuck in
    // the mode the fly started in.
    var big = Vitals()
    big.advance(dt: 2000)
    var small = Vitals()
    for _ in 0..<2000 { small.advance(dt: 1) }
    #expect(big.isAwake == small.isAwake)
    #expect(abs(big.energy - small.energy) < 0.02, "\(big.energy) vs \(small.energy)")
    #expect(abs(big.food - small.food) < 0.02)
}

@Test func pettingExcitesTheBrainIntoTheTurnBand() {
    var v = Vitals()
    v.apply(.pet)
    #expect(v.noise >= 6.0, "excited drive should reach the turn band: \(v.noise)")
}

@Test func theRealBrainSleepsQuieterAndExcitesHarder() {
    // Measured ladders differ between wirings; the profile carries that, not the fly.
    var v = Vitals()
    v.arousal = .flywire
    #expect(v.noise == 3.5)
    v.apply(.lightsOff)
    #expect(v.noise == 0.5, "0.5 is silence on FlyWire; 1.0 still fires 3% of cells")
    v.apply(.lightsOn)
    v.apply(.pet)
    #expect(v.noise == 8.0, "8.0 is the turn band on FlyWire")
    #expect(SimulationTier.full.arousal == .flywire)
    #expect(SimulationTier.eco.arousal == .synthetic)
}
