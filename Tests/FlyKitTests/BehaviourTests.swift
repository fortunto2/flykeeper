import Testing
@testable import FlyKit

// The readout thresholds are assumptions, so they get tests that say what each one claims.
// A test here does not prove the fly behaves this way; it proves the app behaves the way
// `docs/sensory-map.md` says it does. The activities are the measured bands of the
// synthetic engine: idle awake ≤ 0.056, touched ≈ 0.09, asleep ≈ 0.

@Test func touchWithHighActivityStartles() {
    let r = BehaviourReadout()
    #expect(r.behaviour(activity: 0.09, recentTouch: true) == .startle)
}

@Test func highActivityWithoutTouchTurnsRatherThanStartles() {
    // Startle is reserved for touch. Without it, the same activity is just a turn — so a
    // busy brain cannot be reported as a fright that never happened.
    let r = BehaviourReadout()
    #expect(r.behaviour(activity: 0.09, recentTouch: false) == .turn)
}

@Test func theIdleAwakeBandWalksAndNeverStartles() {
    // 0.056 is the highest frame mean an untouched awake brain produced on any tier.
    let r = BehaviourReadout()
    #expect(r.behaviour(activity: 0.056, recentTouch: true) != .startle)
    #expect(r.behaviour(activity: 0.047, recentTouch: false) == .walk)
}

@Test func aQuietBrainSleeps() {
    let r = BehaviourReadout()
    #expect(r.behaviour(activity: 0.001, recentTouch: false) == .sleep)
}

@Test func everyBehaviourIsReachableFromSomeActivity() {
    // A closed set whose members cannot all occur is a lie in the type system. Walk the
    // range and assert each case appears; `rest` and `groom` in particular sit in a narrow
    // band and are the ones a threshold change silently removes.
    let r = BehaviourReadout()
    var seen = Set<Behaviour>()
    for i in 0...1000 {
        let a = Double(i) / 1000.0 * 0.2
        seen.insert(r.behaviour(activity: a, recentTouch: false))
        seen.insert(r.behaviour(activity: a, recentTouch: true))
    }
    #expect(seen.count == Behaviour.allCases.count,
            "unreachable behaviours: \(Set(Behaviour.allCases).subtracting(seen))")
}

@Test func anInconclusiveReceiptIsNotPresentedAsACalmFly() {
    // Zero spikes means the run concluded nothing. It must not read as a resting brain,
    // and the synthetic label must not hide the marker: the app runs synthetic today.
    let dead = SimulationReceipt(neurons: 700, edges: 8400, steps: 100, spikes: 0,
                                 stepsPerSecond: 900, isSynthetic: true)
    #expect(!dead.isConclusive)
    #expect(dead.summary.contains("no spikes"))
    #expect(dead.summary.contains("SYNTHETIC"))

    let alive = SimulationReceipt(neurons: 700, edges: 8400, steps: 100, spikes: 4200,
                                  stepsPerSecond: 900, isSynthetic: false)
    #expect(alive.isConclusive)
    #expect(!alive.summary.contains("no spikes"))
}

@Test func syntheticWiringSaysSoInEveryReceipt() {
    // The app can run before the real connectome is licensed. It may never present random
    // wiring as a fly, so the label travels with the numbers rather than with a screen.
    let r = SimulationReceipt(neurons: 2700, edges: 54000, steps: 1000, spikes: 391020,
                              stepsPerSecond: 1544, isSynthetic: true)
    #expect(r.summary.contains("SYNTHETIC"))
}
