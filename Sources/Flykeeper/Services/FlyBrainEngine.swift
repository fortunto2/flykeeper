import Foundation
import FlyKit

/// Which side of the fly the keeper touched.
enum TouchSide: Sendable { case left, right, both }

/// One frame's worth of simulation, returned in a single actor hop.
struct EngineFrame: Sendable {
    let neurons: Int
    /// Mean fraction of neurons firing per step over the frame (0...1).
    let activity: Double
    /// Indices that fired on the last step, sampled across the range when over
    /// `FlyBrainEngine.spikeLimit`.
    let spikes: [UInt32]
    /// A stimulus is still being applied.
    let touched: Bool
    /// Running firing rate per cell (0...1, ~100 ms window), index order: the heat map.
    let rates: [Float]
    /// Mean firing rate of the left and right descending populations, when the loaded brain
    /// has them named. Nil on synthetic wiring, which has no anatomy to read.
    let descending: (left: Double, right: Double)?
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
        init(_ ptr: OpaquePointer?) { self.ptr = ptr }
        deinit { if let ptr { fly_destroy(ptr) } }
    }

    private let handle: Handle
    private var brain: OpaquePointer? { handle.ptr }
    let tier: SimulationTier
    /// Cells actually loaded — from the engine, not the tier, so a failed load cannot
    /// claim a brain it does not have.
    let neurons: Int
    /// True when a packed tier failed to load and the engine fell back to synthetic wiring.
    let fellBack: Bool
    private var spikeBuffer: [UInt32]
    private var rateBuffer: [Float]
    private let created = ContinuousClock.now
    /// Step at which the current stimulus expires; nil when none is applied.
    private var stimulusEndsAt: UInt64?

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
        self.handle = Handle(ptr)
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

    /// Mean of `rates` over a set of cells.
    private func mean(_ cells: [Int], _ rates: [Float]) -> Double {
        guard !cells.isEmpty else { return 0 }
        var sum = 0.0
        for i in cells where i < rates.count { sum += Double(rates[i]) }
        return sum / Double(cells.count)
    }

    /// Drive a population for as long as the caller keeps calling (re-armed each frame, so
    /// it ends with the behaviour that caused it, not on a timer).
    func drive(population name: String, current: Float, steps: UInt64) {
        guard let brain, let cells = populations[name] else { return }
        for i in cells { fly_set_stimulus(brain, UInt32(i), current) }
        stimulusEndsAt = fly_steps(brain) + steps
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

    /// Advance by `count` steps and report everything a frame needs. Stepping in a batch
    /// keeps a 1 ms model in step with a 16 ms frame; returning one value keeps the render
    /// loop to one hop per frame.
    func frame(steps count: Int) -> EngineFrame {
        guard let brain, count > 0 else {
            return EngineFrame(neurons: 0, activity: 0, spikes: [], touched: false, rates: [],
                               descending: nil, receipt: .empty)
        }
        var fired: UInt64 = 0
        for _ in 0..<count { fired += UInt64(fly_step(brain)) }

        let steps = fly_steps(brain)
        if let end = stimulusEndsAt, steps >= end {
            fly_clear_stimulus(brain)
            stimulusEndsAt = nil
        }
        let n = spikeBuffer.withUnsafeMutableBufferPointer { buf in
            fly_copy_spikes(brain, buf.baseAddress, UInt32(buf.count))
        }
        let r = rateBuffer.withUnsafeMutableBufferPointer { buf in
            fly_copy_rates(brain, buf.baseAddress, UInt32(buf.count))
        }
        let elapsed = created.duration(to: .now)
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18
        return EngineFrame(
            neurons: neurons,
            activity: Double(fired) / Double(count * max(neurons, 1)),
            spikes: Array(spikeBuffer.prefix(Int(n))),
            touched: stimulusEndsAt != nil,
            rates: Int(r) == neurons ? rateBuffer : [],
            descending: descendingLeft.isEmpty || descendingRight.isEmpty || Int(r) != neurons ? nil
                : (mean(descendingLeft, rateBuffer), mean(descendingRight, rateBuffer)),
            receipt: SimulationReceipt(
                neurons: Int(fly_neurons(brain)),
                edges: Int(fly_edges(brain)),
                steps: steps,
                spikes: fly_total_spikes(brain),
                stepsPerSecond: seconds > 0 ? Double(steps) / seconds : 0,
                isSynthetic: fly_is_synthetic(brain) != 0
            )
        )
    }

    /// Apply a stimulus; it expires after `durationSteps` simulation steps, so a slow tier
    /// gets the same touch as a fast one. Returns the step it was applied at, for the log.
    @discardableResult
    func apply(_ stimulus: TouchStimulus) -> UInt64 {
        guard let brain else { return 0 }
        for neuron in stimulus.neurons {
            fly_set_stimulus(brain, UInt32(neuron), stimulus.current)
        }
        let at = fly_steps(brain)
        stimulusEndsAt = at + stimulus.durationSteps
        return at
    }

    /// A touch, on the side the keeper tapped. On a real brain that is the mechanosensory
    /// bristles of that side — measured to move the descending balance by about 0.015 in the
    /// matching direction, which is the whole reason the app can be steered by touch. On
    /// synthetic wiring there is nothing to aim at, so it falls back to every tenth cell.
    @discardableResult
    func touch(side: TouchSide = .both) -> UInt64 {
        let named = side == .left ? populations["mechano.left"]
                  : side == .right ? populations["mechano.right"]
                  : populations["mechano"]
        guard let named, !named.isEmpty else { return apply(.touch(neurons: neurons)) }
        return apply(TouchStimulus(neurons: named, current: 8.0, durationSteps: 250))
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
    func look(cells: [UInt32], currents: [Float]) {
        guard let brain, cells.count == currents.count, !cells.isEmpty else { return }
        cells.withUnsafeBufferPointer { c in
            currents.withUnsafeBufferPointer { v in
                fly_set_stimulus_many(brain, c.baseAddress, v.baseAddress, UInt32(c.count))
            }
        }
    }

    /// Background drive — the fly's state reaching the brain.
    func setNoise(_ noise: Float) {
        guard let brain else { return }
        fly_set_noise(brain, noise)
    }
}
