import Foundation
import FlyKit

/// The fly between launches. Offline-first and tiny: vitals plus when they were true, so the
/// time the app was closed is replayed on the next launch instead of forgotten.
struct FlyStore {
    private struct Saved: Codable {
        var vitals: Vitals
        var savedAt: Date
    }

    private let key = "fly.vitals"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// Vitals as they are now: what was saved, advanced by the time since.
    func load(now: Date = Date()) -> Vitals {
        guard let data = defaults.data(forKey: key),
              let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return Vitals() }
        var vitals = saved.vitals
        vitals.advance(dt: now.timeIntervalSince(saved.savedAt))
        return vitals
    }

    func save(_ vitals: Vitals, now: Date = Date()) {
        if let data = try? JSONEncoder().encode(Saved(vitals: vitals, savedAt: now)) {
            defaults.set(data, forKey: key)
        }
    }
}
