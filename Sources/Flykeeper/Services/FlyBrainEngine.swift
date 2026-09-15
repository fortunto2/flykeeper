import Foundation
import FlyKit

/// One fly's brain this frame. The colony shares one connectome — 31 MB of wiring carried
/// once — and each fly differs only in its state, about 2.8 MB on the full brain.
struct FlyFrame: Sendable {
    /// Mean fraction of this brain's cells firing per step over the frame.
    let activity: Double
    /// A stimulus is still being applied to this fly.
    let touched: Bool
    /// Mean rate of its left and right descending populations, when the brain has them named.
    let descending: (left: Double, right: Double)?
}

/// One frame's worth of simulation, for the whole colony.
struct EngineFrame: Sendable {
    let neurons: Int
    /// One entry per fly, in the order they were added.
    let flies: [FlyFrame]
    /// Spikes and firing rates of the fly whose brain is on show — drawing every colony
    /// member's 138 584 cells at once would be a smear rather than a picture.
    let spikes: [UInt32]
    let rates: [Float]
    let receipt: SimulationReceipt
}

/// Owns the Rust simulation and steps it. An actor because the C engine is a single mutable
/// object and nothing else may touch it concurrently — Swift 6 strict concurrency makes that
/// a compile error rather than a Tuesday crash.
actor FlyBrainEngine {
    /// The view draws at most this many dots a frame, so copying more out of Rust is waste:
    /// at the full tier the uncapped buffer is 557 KB per frame.
    static let spikeLimit = 4096

    /// Owns the C pointer and frees it. It lives outside the actor because Swift 6 forbids a
    /// nonisolated `deinit` from touching actor-isolated, non-Sendable state — and the fix
    /// that matters is not silencing that error but giving the pointer one owner whose
    /// lifetime is the pointer's lifetime. Unchecked Sendable is accurate here: the handle is
    /// only ever reached from inside the actor, and only the deinit runs elsewhere.
    private final class Handle: @unchecked Sendable {
        let ptr: OpaquePointer?
        /// Step at which this fly's stimulus expires; nil when none is applied. On the handle
        /// rather than in a parallel array, so adding and removing a fly cannot leave the two
        /// out of step.
        var endsAt: UInt64?
        init(_ ptr: OpaquePointer?) { self.ptr = ptr }
        deinit { if let ptr { fly_destroy(ptr) } }
    }

    /// One handle per fly. The first owns the wiring; the rest share it.
    private var handles: [Handle]
    private var brain: OpaquePointer? { handles.first?.ptr }
    /// How many flies are alive.
    var colony: Int { handles.count }
    /// Most this tier should carry. The graph is shared, so this is a CPU limit, not memory:
    /// the full brain is already below realtime on its own.
    var colonyLimit: Int {
        switch tier {
        case .eco: 12
        case .standard: 4
        case .full: 2
        }
    }
    let tier: SimulationTier
    /// Cells actually loaded — from the engine, not the tier, so a failed load cannot
    /// claim a brain it does not have.
    let neurons: Int
    /// True when a packed tier failed to load and the engine fell back to synthetic wiring.
    let fellBack: Bool
    private var spikeBuffer: [UInt32]
    private var rateBuffer: [Float]
    private let created = ContinuousClock.now
    private var lastNoise: Float = 3.5

    init(tier: SimulationTier = .eco, seed: UInt64 = 1) {
        self.tier = tier
        var ptr: OpaquePointer?
        var fellBack = false
        switch tier.source {
        case .synthetic(let n, let fanOut):
            ptr = fly_create_synthetic(UInt32(n), UInt32(fanOut), seed)
        case .packed(let resource, let threshold):
            if let url = Bundle.main.url(forResource: resource, withExtension: "fcb") {
                ptr = fly_create_from_fcb(url.path, UInt32(threshold), seed)
            }
            if ptr == nil {
                // A missing or corrupt export must not become an empty screen — but the
                // receipt says SYNTHETIC, so it cannot be mistaken for the fly either.
                fellBack = true
                ptr = fly_create_synthetic(700, 12, seed)
            }
        }
        self.handles = [Handle(ptr)]
        self.fellBack = fellBack
        self.neurons = ptr.map { Int(fly_neurons($0)) } ?? 0
        self.spikeBuffer = [UInt32](repeating: 0, count: max(1, min(neurons, Self.spikeLimit)))
        self.rateBuffer = [Float](repeating: 0, count: max(1, neurons))
    }

    /// Cells grouped by predicted neurotransmitter ("DA", "SER", "GABA", …), by index. From
    /// the export's populations file; a synthetic brain gets a stand-in block so the eco tier
    /// shows the mechanism too, labelled synthetic like everything else about it.
    lazy var populations: [String: [Int]] = {
        if case .packed(let resource, _) = tier.source, !fellBack,
           let url = Bundle.main.url(forResource: "\(resource)-populations", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let groups = try? JSONDecoder().decode([String: [Int]].self, from: data) {
            return groups
        }
        // Synthetic: the last 5% of cells stand in for the dopaminergic ones.
        return ["DA": Array(max(0, neurons - neurons / 20)..<neurons)]
    }()

    /// Index lists resolved once: looking them up in a dictionary every frame, for a value
    /// that never changes, is the kind of waste that only shows up on the full brain.
    private lazy var descendingLeft: [Int] = populations["descending.left"] ?? []
    private lazy var descendingRight: [Int] = populations["descending.right"] ?? []
    /// Mechanosensory cells per side, resolved once for the same reason: `jostle` asks for
    /// them every frame and the answer never changes.
    private lazy var bristles: [TouchSide: [UInt32]] = [
        .left: (populations["mechano.left"] ?? []).map(UInt32.init),
        .right: (populations["mechano.right"] ?? []).map(UInt32.init),
        .both: (populations["mechano"] ?? []).map(UInt32.init),
    ]
    /// Scratch for bulk stimulus calls, grown once rather than allocated per call.
    private var currents: [Float] = []

    /// Mean of `rates` over a set of cells.
    private func mean(_ cells: [Int], _ rates: [Float]) -> Double {
        guard !cells.isEmpty else { return 0 }
        var sum = 0.0
        for i in cells where i < rates.count { sum += Double(rates[i]) }
        return sum / Double(cells.count)
    }

    /// Drive a population for as long as the caller keeps calling (re-armed each frame, so
    /// it ends with the behaviour that caused it, not on a timer).
    func drive(population name: String, current: Float, steps: UInt64, fly: Int = 0) {
        guard let cells = populations[name], !cells.isEmpty else { return }
        apply(TouchStimulus(neurons: cells, current: current, durationSteps: steps), fly: fly)
    }

    /// Cell positions in µm, index order; empty for synthetic wiring. Static, so read once.
    func positions() -> [SIMD3<Float>] {
        guard let brain, neurons > 0 else { return [] }
        var flat = [Float](repeating: 0, count: neurons * 3)
        let n = flat.withUnsafeMutableBufferPointer { buf in
            fly_copy_positions(brain, buf.baseAddress, UInt32(buf.count))
        }
        guard n == UInt32(neurons * 3) else { return [] }
        return stride(from: 0, to: flat.count, by: 3).map { SIMD3(flat[$0], flat[$0 + 1], flat[$0 + 2]) }
    }

    /// Another fly over the same wiring. Its own seed, so it has its own life rather than
    /// being a second copy of the first one's.
    @discardableResult
    func addFly(seed: UInt64 = UInt64.random(in: 1...1_000_000)) -> Bool {
        guard let brain, handles.count < colonyLimit,
              let ptr = fly_create_shared(brain, seed) else { return false }
        fly_set_noise(ptr, lastNoise)
        handles.append(Handle(ptr))
        return true
    }

    func removeFly() {
        guard handles.count > 1 else { return }
        handles.removeLast()
    }

    /// Advance by `count` steps and report everything a frame needs. Stepping in a batch
    /// keeps a 1 ms model in step with a 16 ms frame; returning one value keeps the render
    /// loop to one hop per frame.
    func frame(steps count: Int) -> EngineFrame {
        guard let lead = brain, count > 0 else {
            return EngineFrame(neurons: 0, flies: [], spikes: [], rates: [], receipt: .empty)
        }
        var flies = [FlyFrame](repeating: FlyFrame(activity: 0, touched: false, descending: nil),
                               count: handles.count)
        // The lead goes last on purpose: its firing rates are what the heat map draws, and
        // stepping it last leaves them in `rateBuffer` already. Copying 138 584 floats a
        // second time was 554 KB a frame for nothing.
        for f in handles.indices.reversed() {
            let handle = handles[f]
            guard let b = handle.ptr else { continue }
            var fired: UInt64 = 0
            for _ in 0..<count { fired += UInt64(fly_step(b)) }
            let steps = fly_steps(b)
            if let end = handle.endsAt, steps >= end {
                fly_clear_stimulus(b)
                handle.endsAt = nil
            }
            var descending: (left: Double, right: Double)?
            if !descendingLeft.isEmpty && !descendingRight.isEmpty {
                let n = rateBuffer.withUnsafeMutableBufferPointer { buf in
                    fly_copy_rates(b, buf.baseAddress, UInt32(buf.count))
                }
                if Int(n) == neurons {
                    descending = (mean(descendingLeft, rateBuffer), mean(descendingRight, rateBuffer))
                }
            }
            flies[f] = FlyFrame(activity: Double(fired) / Double(count * max(neurons, 1)),
                                touched: handle.endsAt != nil,
                                descending: descending)
        }

        let n = spikeBuffer.withUnsafeMutableBufferPointer { buf in
            fly_copy_spikes(lead, buf.baseAddress, UInt32(buf.count))
        }
        // Only refill when the loop above never did — a brain with no named descending
        // population copies no rates at all.
        var rates = rateBuffer
        if descendingLeft.isEmpty || descendingRight.isEmpty {
            let r = rateBuffer.withUnsafeMutableBufferPointer { buf in
                fly_copy_rates(lead, buf.baseAddress, UInt32(buf.count))
            }
            rates = Int(r) == neurons ? rateBuffer : []
        }
        let elapsed = created.duration(to: .now)
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18
        let steps = fly_steps(lead)
        return EngineFrame(
            neurons: neurons,
            flies: flies,
            spikes: Array(spikeBuffer.prefix(Int(n))),
            rates: rates,
            receipt: SimulationReceipt(
                neurons: Int(fly_neurons(lead)),
                edges: Int(fly_edges(lead)),
                steps: steps,
                spikes: fly_total_spikes(lead),
                stepsPerSecond: seconds > 0 ? Double(steps) / seconds : 0,
                isSynthetic: fly_is_synthetic(lead) != 0
            )
        )
    }

    /// Apply a stimulus; it expires after `durationSteps` simulation steps, so a slow tier
    /// gets the same touch as a fast one. Returns the step it was applied at, for the log.
    @discardableResult
    func apply(_ stimulus: TouchStimulus, fly: Int = 0) -> UInt64 {
        guard let handle = handles[safe: fly], let b = handle.ptr else { return 0 }
        drive(cells: stimulus.neurons.map(UInt32.init), current: stimulus.current, on: b)
        let at = fly_steps(b)
        handle.endsAt = at + stimulus.durationSteps
        return at
    }

    /// Current onto a set of cells, reusing one scratch buffer. `jostle` can call this a
    /// dozen times a frame with 1 358 cells each; allocating two arrays per call was 24 heap
    /// allocations a frame on a full colony.
    private func drive(cells: [UInt32], current: Float, on brain: OpaquePointer) {
        guard !cells.isEmpty else { return }
        if currents.count < cells.count { currents = [Float](repeating: 0, count: cells.count) }
        for i in 0..<cells.count { currents[i] = current }
        cells.withUnsafeBufferPointer { c in
            currents.withUnsafeMutableBufferPointer { v in
                fly_set_stimulus_many(brain, c.baseAddress, v.baseAddress, UInt32(c.count))
            }
        }
    }

    /// A touch, on the side the keeper tapped. On a real brain that is the mechanosensory
    /// bristles of that side — measured to move the descending balance by about 0.015 in the
    /// matching direction, which is the whole reason the app can be steered by touch. On
    /// synthetic wiring there is nothing to aim at, so it falls back to every tenth cell.
    @discardableResult
    func touch(side: TouchSide = .both, fly: Int = 0) -> UInt64 {
        guard let handle = handles[safe: fly], let b = handle.ptr else { return 0 }
        let named = bristles[side] ?? []
        guard !named.isEmpty else { return apply(.touch(neurons: neurons), fly: fly) }
        drive(cells: named, current: TouchStimulus.touchCurrent, on: b)
        let at = fly_steps(b)
        handle.endsAt = at + TouchStimulus.touchSteps
        return at
    }

    /// Every contact of one frame in a single hop. `jostle` used to await twice per touching
    /// pair inside its inner loop: up to 132 round trips a frame on a full colony.
    func touch(_ contacts: [Contact]) {
        for c in contacts { touch(side: c.side, fly: c.fly) }
    }

    /// Where this brain's photoreceptors look, when it has any. Loaded once.
    lazy var retina: Retina? = {
        guard case .packed(let resource, _) = tier.source, !fellBack,
              let url = Bundle.main.url(forResource: "\(resource)-retina", withExtension: "frt")
        else { return nil }
        return Retina(url: url)
    }()

    /// Show the eye a frame: current per photoreceptor, in the order `Retina` lists them.
    /// Set every frame and never expired — an eye that is open stays open.
    /// The eye belongs to the fly on show: one camera, one viewpoint, one pair of eyes.
    func look(cells: [UInt32], currents: [Float]) {
        guard let brain, cells.count == currents.count, !cells.isEmpty else { return }
        cells.withUnsafeBufferPointer { c in
            currents.withUnsafeBufferPointer { v in
                fly_set_stimulus_many(brain, c.baseAddress, v.baseAddress, UInt32(c.count))
            }
        }
    }

    /// Background drive — the fly's state reaching the brain.
    /// Arousal is the colony's, not one fly's: they share a keeper, a room and a light.
    func setNoise(_ noise: Float) {
        lastNoise = noise
        for h in handles { if let p = h.ptr { fly_set_noise(p, noise) } }
    }
}


private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
