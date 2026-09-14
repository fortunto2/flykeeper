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
    /// The colony. `flies[0]` is the one whose brain is drawn and whose eye the camera feeds;
    /// the rest share its wiring and live their own lives over it.
    @State private var flies = [Fly(vitals: FlyStore().load())]
    @State private var frame: EngineFrame?
    @State private var positions: [SIMD3<Float>] = []
    /// The engine fell back to synthetic wiring because a packed tier failed to load. This is
    /// the only thing that may claim the export is missing — the receipt being synthetic is a
    /// fact about the brain, not about the load, and on the eco tier it is simply true.
    @State private var fellBack = false
    @State private var showAbout = false
    @State private var receipt: SimulationReceipt = .empty
    @State private var pendingTouch: TouchSide?
    /// The eye: the camera shown to the fly's own photoreceptors. Off by default, and only
    /// offered on a real brain — synthetic wiring has no retina to look through.
    @State private var eyeOn = false
    @State private var eyeFailure: EyeCamera.Failure?
    @State private var eyeResponse: [Float] = []
    @State private var retina: Retina?
    @State private var engine0: FlyBrainEngine?
    @State private var colonyLimit = 1
    /// Contacts since the last receipt, so a colony's jostling is a number on the record
    /// rather than something you have to watch for.
    @State private var bumps = 0
    private let camera = EyeCamera()
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
    /// Two fly bodies wide, in arena units. The model is 0.15 across.
    private static let contactRadius = 0.11

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text((flies[0].isEating ? "eat" : flies[0].behaviour.rawValue).uppercased())
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

            FlyArena3DView(poses: flies.map(\.pose), behaviour: flies[0].behaviour,
                           spikes: frame?.spikes ?? [], neurons: frame?.neurons ?? 0,
                           food: flies[0].food, positions: positions, rates: frame?.rates ?? [],
                           lightsOn: flies[0].vitals.lightsOn,
                           // Where you tap decides which side's bristles fire, and the fly
                           // turns away through the real wiring, not through a rule of ours.
                           onTouch: { pendingTouch = $0 })
                .aspectRatio(0.9, contentMode: .fit)

            if eyeOn, let retina, !eyeResponse.isEmpty {
                EyeView(retina: retina, response: eyeResponse, gain: 14)
                    .frame(height: 96)
                    .transition(.opacity)
            }

            VitalsView(vitals: flies[0].vitals, activity: frame?.flies.first?.activity ?? 0)

            // Fast-forward. Segmented, so the speed is one tap and always visible.
            Picker("Speed", selection: $speed) {
                ForEach(speeds, id: \.self) { Text("\($0)×").tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("speed")

            HStack(spacing: 10) {
                Button { feed() } label: { Label("Feed", systemImage: "leaf.fill") }
                    .accessibilityIdentifier("feed")
                Button {
                    Task {
                        if await engine0?.addFly() == true { flies.append(newFly()) }
                    }
                } label: { Image(systemName: "plus.circle") }
                    .accessibilityIdentifier("addFly")
                    .accessibilityLabel("Add a fly")
                    .disabled(flies.count >= colonyLimit)
                if flies.count > 1 {
                    Button {
                        Task { await engine0?.removeFly(); if flies.count > 1 { flies.removeLast() } }
                    } label: { Image(systemName: "minus.circle") }
                        .accessibilityIdentifier("removeFly")
                        .accessibilityLabel("Remove a fly")
                }
                if retina != nil {
                    Button { eyeOn.toggle() } label: {
                        Label(eyeOn ? "Eye on" : "Eye", systemImage: eyeOn ? "eye.fill" : "eye")
                    }
                    .accessibilityIdentifier("eye")
                    .tint(eyeOn ? .orange : nil)
                }
                Button { care(flies[0].vitals.lightsOn ? .lightsOff : .lightsOn) } label: {
                    Label(flies[0].vitals.lightsOn ? "Lights off" : "Lights on",
                          systemImage: flies[0].vitals.lightsOn ? "moon.fill" : "sun.max.fill")
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
                } else if let eyeFailure {
                Text(eyeFailure == .denied
                     ? "The eye needs camera access — nothing else in the app does"
                     : "No camera on this device, so there is nothing to show the fly")
                    .foregroundStyle(.orange)
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
            if phase != .active { store.save(flies[0].vitals) }
        }
    }

    private var moodLine: String {
        switch flies[0].vitals.mood {
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
        for i in flies.indices { flies[i].dropFood(at: morsel) }
        log.notice("care feed · morsel at \(morsel.x, format: .fixed(precision: 2), privacy: .public),\(morsel.y, format: .fixed(precision: 2), privacy: .public)")
    }

    /// A new colony member starts where the keeper is not looking and hungry in its own way,
    /// so it does not walk in lockstep with the first.
    private func newFly() -> Fly {
        // The emptiest of a few candidate spots, so a colony spreads out instead of piling up
        // on the one place `random` happened to like.
        let spot = (0..<8).map { _ in (x: Double.random(in: 0.12...0.88), y: Double.random(in: 0.12...0.88)) }
            .max { a, b in
                let d = { (p: (x: Double, y: Double)) in
                    flies.map { hypot($0.pose.x - p.x, $0.pose.y - p.y) }.min() ?? 1
                }
                return d(a) < d(b)
            }!
        var f = Fly(pose: FlyPose(x: spot.x, y: spot.y, heading: .random(in: 0...(2 * .pi))),
                    vitals: flies[0].vitals)
        f.vitals.food = .random(in: 0.5...1)
        return f
    }

    private func care(_ c: Care) {
        flies[0].vitals.apply(c)
        store.save(flies[0].vitals)
        log.notice("care \(c.rawValue, privacy: .public) · mood \(flies[0].vitals.mood.rawValue, privacy: .public)")
    }

    private func loop(_ engine: FlyBrainEngine) async {
        frame = nil
        receipt = .empty
        // FLY_FEED=1 drops a morsel at launch: `make run FEED=1`, for screenshots and checks
        // that do not depend on driving a button.
        let env = ProcessInfo.processInfo.environment
        if env["FLY_FEED"] != nil, flies[0].food == nil {
            for i in flies.indices { flies[i].dropFood(at: Food(x: 0.75, y: 0.3)) }
        }
        if env["FLY_LIGHTS"] == "off" { for i in flies.indices { flies[i].vitals.apply(.lightsOff) } }
        // FLY_COLONY=n opens with a colony, for screenshots and checks.
        if let n = env["FLY_COLONY"].flatMap(Int.init) {
            while flies.count < n, await engine.addFly() { flies.append(newFly()) }
        }
        engine0 = engine
        colonyLimit = await engine.colonyLimit
        log.notice("loop start · tier \(engine.tier.rawValue, privacy: .public) · fly at \(flies[0].pose.x, format: .fixed(precision: 2), privacy: .public),\(flies[0].pose.y, format: .fixed(precision: 2), privacy: .public)")
        positions = await engine.positions()
        retina = await engine.retina
        let sampler = await engine.retina.map(EyeSampler.init)
        // A fallback engine runs synthetic wiring whatever the tier says.
        fellBack = engine.fellBack
        flies[0].vitals.arousal = engine.fellBack ? .synthetic : tier.arousal
        let clock = ContinuousClock()
        var next = clock.now
        var last = next
        var count = 0
        var noise: Float = -1
        while !Task.isCancelled {
            // Measured at the top: the eye needs it to adapt before the step it feeds, and a
            // frame's own duration is not known until after that step has run.
            let now = clock.now
            let dt = min(seconds(last.duration(to: now)), 0.1)
            last = now
            if let side = pendingTouch {
                pendingTouch = nil
                flies[0].pet()
                if flies[0].vitals.isSleeping || !flies[0].vitals.lightsOn { flies[0].vitals.apply(.lightsOn) }
                let at = await engine.touch(side: side)
                log.notice("touch \(String(describing: side), privacy: .public) at step \(at, privacy: .public)")
            }
            if flies[0].isEating {
                // Reward: the fly's dopaminergic cells fire while it eats. On FlyWire these
                // are the 786 cells predicted DA (PAM/PPL clusters around the mushroom body);
                // on synthetic wiring a stand-in block. Re-armed every frame; expires with
                // the meal.
                await engine.drive(population: "DA", current: 6.0, steps: UInt64(stepsPerFrame * speed * 3))
            }
            if eyeOn, let sampler {
                if !camera.isRunning {
                    eyeFailure = await camera.start()
                    if eyeFailure != nil { eyeOn = false }
                }
                if camera.isRunning {
                    let grid = camera.frame()
                    // Each eye reads its own half of the frame, so a turn sweeps one before
                    // the other, the way a fly's overlapping fields do.
                    let r = sampler.look(dt: dt) { u, v, isRight in
                        let x = (Double(u) * 0.5 + (isRight ? 0.5 : 0)) * Double(EyeCamera.width - 1)
                        let y = (1 - Double(v)) * Double(EyeCamera.height - 1)
                        return grid[Int(y) * EyeCamera.width + Int(x)]
                    }
                    await engine.look(cells: sampler.cells, currents: r)
                    eyeResponse = r
                }
            } else if camera.isRunning {
                camera.stop()
                sampler?.rest()
                if let sampler { await engine.look(cells: sampler.cells, currents: sampler.response) }
                eyeResponse = []
            }
            if flies[0].vitals.noise != noise {
                noise = flies[0].vitals.noise
                await engine.setNoise(noise)
            }
            let f = await engine.frame(steps: stepsPerFrame * speed)
            // The old loop may be here when a tier switch cancels it; its frame must not
            // land on top of the new engine's state.
            if Task.isCancelled { return }
            let hadFood = flies[0].food
            // A real brain is read off its descending neurons; synthetic wiring has none, so
            // it keeps the whole-brain average and the app does not pretend otherwise.
            for i in flies.indices where i < f.flies.count {
                let ff = f.flies[i]
                let signal: BrainSignal = ff.descending.map {
                    .descending(left: $0.left, right: $0.right, touched: ff.touched)
                } ?? .activity(ff.activity, touched: ff.touched)
                flies[i].advance(signal, dt: dt, timeScale: Double(speed))
            }
            // Flies that walk into each other feel it, on the side they were touched. This is
            // the one sense measured to reach the descending neurons, so a colony jostles
            // through the real wiring rather than through a rule of ours.
            await jostle(engine)
            if hadFood != nil && flies[0].food == nil {
                log.notice("morsel gone · fly at \(flies[0].pose.x, format: .fixed(precision: 2), privacy: .public),\(flies[0].pose.y, format: .fixed(precision: 2), privacy: .public) · food \(flies[0].vitals.food, format: .fixed(precision: 2), privacy: .public) · dt \(dt, format: .fixed(precision: 3), privacy: .public)")
            }
            frame = f
            count += 1
            // The first frame too: a receipt reading "0 neurons" under a brain that is plainly
            // on screen is the exact false statement this receipt exists to prevent.
            if count == 1 || count % receiptEvery == 0 {
                receipt = f.receipt
                defer { bumps = 0 }
                log.notice("receipt \(f.receipt.summary, privacy: .public) · activity \(f.flies.first?.activity ?? 0, format: .fixed(precision: 3), privacy: .public) · colony \(flies.count, privacy: .public) · bumps \(bumps, privacy: .public) · behaviour \(flies[0].behaviour.rawValue, privacy: .public) · mood \(flies[0].vitals.mood.rawValue, privacy: .public) · drive \(flies[0].command.drive, format: .fixed(precision: 2), privacy: .public) · steer \(flies[0].command.steer, format: .fixed(precision: 2), privacy: .public) · eye \(eyeOn ? "on" : "off", privacy: .public) · noise \(noise, format: .fixed(precision: 2), privacy: .public) · speed \(speed, privacy: .public)× · food \(flies[0].food.map { "\($0.x),\($0.y)" } ?? "none", privacy: .public) · eating \(flies[0].isEating, privacy: .public) · at \(flies[0].pose.x, format: .fixed(precision: 2), privacy: .public),\(flies[0].pose.y, format: .fixed(precision: 2), privacy: .public)")
            }
            // Deadline, not "sleep after work", and re-based on overrun: a slow tier drops
            // frames instead of accruing debt, and a resume from background is not 30 s of
            // catch-up frames.
            next = max(next + framePeriod, now)
            try? await clock.sleep(until: next)
        }
    }

    /// Pairwise contact. The distance is two half-bodies, not the reach used for food: a fly
    /// eats at arm's length and collides at its own width, and using the eating radius meant
    /// two flies could stand touching and register nothing.
    private func jostle(_ engine: FlyBrainEngine) async {
        guard flies.count > 1 else { return }
        for i in flies.indices {
            for j in (i + 1)..<flies.count {
                let a = flies[i].pose, b = flies[j].pose
                let dx = b.x - a.x, dy = b.y - a.y
                guard hypot(dx, dy) < Self.contactRadius, abs(a.z - b.z) < 0.1 else { continue }
                // Which side of me is it on: the sign of the cross product with my heading.
                let across = cos(a.heading) * dy - sin(a.heading) * dx
                bumps += 1
                await engine.touch(side: across > 0 ? .right : .left, fly: i)
                let backAcross = cos(b.heading) * -dy - sin(b.heading) * -dx
                await engine.touch(side: backAcross > 0 ? .right : .left, fly: j)
            }
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
