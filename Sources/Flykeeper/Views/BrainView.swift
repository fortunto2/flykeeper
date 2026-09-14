import SwiftUI
import FlyKit
import OSLog

// A screenshot shows a number on a screen; it does not show the number came from the
// simulation. The receipt goes to the log every second so a run can be verified from
// outside the app, by a script, without a human looking at a phone.
private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "flykeeper", category: "sim")

/// The fly on top, its needs in the middle, the receipt underneath. The numbers stay on
/// screen on purpose: a decorated fly on top of a dead engine looks exactly like a decorated
/// fly on top of a live one.
struct BrainView: View {
    @Environment(\.scenePhase) private var scenePhase
    // FLY_TIER=eco|standard|full picks the starting tier: `make run TIER=full`, and a way to
    // put a screenshot of the full brain on record without driving the picker by hand.
    @State private var tier: SimulationTier =
        SimulationTier(rawValue: ProcessInfo.processInfo.environment["FLY_TIER"] ?? "") ?? .eco
    @State private var fly = Fly(vitals: FlyStore().load())
    @State private var frame: EngineFrame?
    @State private var positions: [SIMD3<Float>] = []
    /// The engine fell back to synthetic wiring because a packed tier failed to load. This is
    /// the only thing that may claim the export is missing — the receipt being synthetic is a
    /// fact about the brain, not about the load, and on the eco tier it is simply true.
    @State private var fellBack = false
    @State private var showAbout = false
    @State private var receipt: SimulationReceipt = .empty
    @State private var pendingTouch: TouchSide?
    /// Time scale: multiplies the brain's steps per frame and the fly's needs, not the
    /// animation. 64× at eco is ~1000 steps a frame, well inside the budget on a phone.
    @State private var speed = 1
    private let speeds = [1, 4, 16, 64]
    private let store = FlyStore()

    /// 16 steps per frame at dt = 1 ms: realtime at 60 fps.
    private let stepsPerFrame = 16
    private let framePeriod: Duration = .milliseconds(16)
    /// Receipt on screen and in the log once a second; per-frame it only churns layout.
    private let receiptEvery = 60

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text((fly.isEating ? "eat" : fly.behaviour.rawValue).uppercased())
                        .font(.system(.title2, design: .monospaced, weight: .bold))
                    Text(moodLine).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { showAbout = true } label: {
                    Image(systemName: "info.circle").font(.title3)
                }
                .accessibilityIdentifier("about")
                .accessibilityLabel("About")
            }
            Picker("Tier", selection: $tier) {
                ForEach(SimulationTier.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("tier")

            FlyArena3DView(pose: fly.pose, behaviour: fly.behaviour,
                           spikes: frame?.spikes ?? [], neurons: frame?.neurons ?? 0,
                           food: fly.food, positions: positions, rates: frame?.rates ?? [],
                           lightsOn: fly.vitals.lightsOn,
                           // Where you tap decides which side's bristles fire, and the fly
                           // turns away through the real wiring, not through a rule of ours.
                           onTouch: { pendingTouch = $0 })
                .aspectRatio(0.9, contentMode: .fit)

            VitalsView(vitals: fly.vitals, activity: frame?.activity ?? 0)

            // Fast-forward. Segmented, so the speed is one tap and always visible.
            Picker("Speed", selection: $speed) {
                ForEach(speeds, id: \.self) { Text("\($0)×").tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("speed")

            HStack(spacing: 12) {
                Button { feed() } label: { Label("Feed", systemImage: "leaf.fill") }
                    .accessibilityIdentifier("feed")
                Button { care(fly.vitals.lightsOn ? .lightsOff : .lightsOn) } label: {
                    Label(fly.vitals.lightsOn ? "Lights off" : "Lights on",
                          systemImage: fly.vitals.lightsOn ? "moon.fill" : "sun.max.fill")
                }
                .accessibilityIdentifier("lights")
            }
            .buttonStyle(.bordered)

            VStack(spacing: 4) {
                Text(receipt.summary)
                if frame == nil {
                    Text("Loading the brain…").foregroundStyle(.secondary)
                } else if fellBack {
                    Text("Brain export missing — running synthetic wiring instead")
                        .foregroundStyle(.orange)
                } else if receipt.isSynthetic {
                    Text("Wiring is synthetic — not a fly yet").foregroundStyle(.orange)
                } else if let credit = tier.attribution {
                    Text(credit).foregroundStyle(.secondary)
                }
            }
            .font(.system(.caption, design: .monospaced))
            .multilineTextAlignment(.center)
        }
        .padding()
        .sheet(isPresented: $showAbout) { AboutView() }
        // One trigger, one lifetime: the loop owns its engine, so a tier change cannot leave
        // the loop stepping an engine the view has already replaced.
        .task(id: tier) {
            // Off the main actor: the full brain is 25 MB of CSR to unpack.
            let tier = tier
            let engine = await Task.detached { FlyBrainEngine(tier: tier) }.value
            await loop(engine)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.save(fly.vitals) }
        }
    }

    private var moodLine: String {
        switch fly.vitals.mood {
        case .happy: "happy · petted"
        case .content: "content"
        case .hungry: "hungry · feed me"
        case .tired: "tired · lights off?"
        case .asleep: "asleep · touch to wake"
        }
    }

    /// Food is a thing on the floor, not a bar that jumps to full: the fly has to go there.
    private func feed() {
        let morsel = Food(x: .random(in: 0.15...0.85), y: .random(in: 0.15...0.85))
        fly.dropFood(at: morsel)
        log.notice("care feed · morsel at \(morsel.x, format: .fixed(precision: 2), privacy: .public),\(morsel.y, format: .fixed(precision: 2), privacy: .public)")
    }

    private func care(_ c: Care) {
        fly.vitals.apply(c)
        store.save(fly.vitals)
        log.notice("care \(c.rawValue, privacy: .public) · mood \(fly.vitals.mood.rawValue, privacy: .public)")
    }

    private func loop(_ engine: FlyBrainEngine) async {
        frame = nil
        receipt = .empty
        // FLY_FEED=1 drops a morsel at launch: `make run FEED=1`, for screenshots and checks
        // that do not depend on driving a button.
        let env = ProcessInfo.processInfo.environment
        if env["FLY_FEED"] != nil, fly.food == nil {
            fly.dropFood(at: Food(x: 0.75, y: 0.3))
        }
        if env["FLY_LIGHTS"] == "off" { fly.vitals.apply(.lightsOff) }
        log.notice("loop start · tier \(engine.tier.rawValue, privacy: .public) · fly at \(fly.pose.x, format: .fixed(precision: 2), privacy: .public),\(fly.pose.y, format: .fixed(precision: 2), privacy: .public)")
        positions = await engine.positions()
        // A fallback engine runs synthetic wiring whatever the tier says.
        fellBack = engine.fellBack
        fly.vitals.arousal = engine.fellBack ? .synthetic : tier.arousal
        let clock = ContinuousClock()
        var next = clock.now
        var last = next
        var count = 0
        var noise: Float = -1
        while !Task.isCancelled {
            if let side = pendingTouch {
                pendingTouch = nil
                fly.pet()
                if fly.vitals.isSleeping || !fly.vitals.lightsOn { fly.vitals.apply(.lightsOn) }
                let at = await engine.touch(side: side)
                log.notice("touch \(String(describing: side), privacy: .public) at step \(at, privacy: .public)")
            }
            if fly.isEating {
                // Reward: the fly's dopaminergic cells fire while it eats. On FlyWire these
                // are the 786 cells predicted DA (PAM/PPL clusters around the mushroom body);
                // on synthetic wiring a stand-in block. Re-armed every frame; expires with
                // the meal.
                await engine.drive(population: "DA", current: 6.0, steps: UInt64(stepsPerFrame * speed * 3))
            }
            if fly.vitals.noise != noise {
                noise = fly.vitals.noise
                await engine.setNoise(noise)
            }
            let f = await engine.frame(steps: stepsPerFrame * speed)
            // The old loop may be here when a tier switch cancels it; its frame must not
            // land on top of the new engine's state.
            if Task.isCancelled { return }
            let now = clock.now
            let dt = min(seconds(last.duration(to: now)), 0.1)
            last = now
            let hadFood = fly.food
            // A real brain is read off its descending neurons; synthetic wiring has none, so
            // it keeps the whole-brain average and the app does not pretend otherwise.
            let signal: BrainSignal = f.descending.map {
                .descending(left: $0.left, right: $0.right, touched: f.touched)
            } ?? .activity(f.activity, touched: f.touched)
            fly.advance(signal, dt: dt, timeScale: Double(speed))
            if hadFood != nil && fly.food == nil {
                log.notice("morsel gone · fly at \(fly.pose.x, format: .fixed(precision: 2), privacy: .public),\(fly.pose.y, format: .fixed(precision: 2), privacy: .public) · food \(fly.vitals.food, format: .fixed(precision: 2), privacy: .public) · dt \(dt, format: .fixed(precision: 3), privacy: .public)")
            }
            frame = f
            count += 1
            // The first frame too: a receipt reading "0 neurons" under a brain that is plainly
            // on screen is the exact false statement this receipt exists to prevent.
            if count == 1 || count % receiptEvery == 0 {
                receipt = f.receipt
                log.notice("receipt \(f.receipt.summary, privacy: .public) · activity \(f.activity, format: .fixed(precision: 3), privacy: .public) · behaviour \(fly.behaviour.rawValue, privacy: .public) · mood \(fly.vitals.mood.rawValue, privacy: .public) · drive \(fly.command.drive, format: .fixed(precision: 2), privacy: .public) · steer \(fly.command.steer, format: .fixed(precision: 2), privacy: .public) · noise \(noise, format: .fixed(precision: 2), privacy: .public) · speed \(speed, privacy: .public)× · food \(fly.food.map { "\($0.x),\($0.y)" } ?? "none", privacy: .public) · eating \(fly.isEating, privacy: .public) · at \(fly.pose.x, format: .fixed(precision: 2), privacy: .public),\(fly.pose.y, format: .fixed(precision: 2), privacy: .public)")
            }
            // Deadline, not "sleep after work", and re-based on overrun: a slow tier drops
            // frames instead of accruing debt, and a resume from background is not 30 s of
            // catch-up frames.
            next = max(next + framePeriod, now)
            try? await clock.sleep(until: next)
        }
    }

    private func seconds(_ d: Duration) -> Double {
        Double(d.components.seconds) + Double(d.components.attoseconds) * 1e-18
    }
}

/// Food, energy and the brain's activity, as bars. Bars rather than numbers because the
/// keeper glances; the receipt underneath is where the numbers live.
private struct VitalsView: View {
    let vitals: Vitals
    let activity: Double

    var body: some View {
        VStack(spacing: 6) {
            Bar(label: "food", value: vitals.food, tint: .green)
            Bar(label: "energy", value: vitals.energy, tint: .yellow)
            Bar(label: "brain", value: min(activity * 10, 1), tint: .cyan)
        }
        .font(.system(.caption2, design: .monospaced))
    }

    private struct Bar: View {
        let label: String
        let value: Double
        let tint: Color

        var body: some View {
            HStack(spacing: 8) {
                Text(label).frame(width: 48, alignment: .trailing)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule().fill(tint).frame(width: max(2, geo.size.width * value))
                    }
                }
                .frame(height: 8)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(label) \(Int(value * 100)) percent")
        }
    }
}
