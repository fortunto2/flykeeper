import SwiftUI

/// Who made this and what else he made. Also the place the data credits live in full — the
/// short FlyWire line stays on the main screen, where the brain it refers to is on show.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    /// The other apps, by App Store id. Only the ones actually live on the store — audited
    /// with `asc apps published`, so an unreleased app cannot leave a dead link here.
    private static let apps: [(name: String, id: String)] = [
        ("Starlapse", "6801191027"),
        ("Life2Film", "6761656888"),
        ("SuperDuper Terminal", "6758515520"),
        ("Live2play", "6794370589"),
        ("Photo and Storage Sweep", "6794369239"),
        ("Caretta Friends", "6794324877"),
        ("FaceAlarm — Face Yoga Tracker", "6758454962"),
        ("CurrencyPals", "6759005730"),
        ("Jaw Harp Synth", "6758465213"),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Flykeeper")
                            .font(.system(.title2, design: .monospaced, weight: .bold))
                        Text("A fly whose behaviour comes from a simulation of a real fly brain, "
                             + "running on the phone. No account, no network, nothing leaves the device.")
                        Text("Version \(version)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Made by") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Rustam Salavatov")
                            .font(.headline)
                        Text("Solo developer. I build small offline-first apps that do one thing "
                             + "and keep your data on your device.")
                            .font(.callout)
                    }
                    .padding(.vertical, 4)
                    Link("superduperai.co", destination: URL(string: "https://superduperai.co")!)
                    Link("info@superduperai.co", destination: URL(string: "mailto:info@superduperai.co")!)
                }

                Section("My other apps") {
                    ForEach(Self.apps, id: \.id) { app in
                        Link(destination: URL(string: "https://apps.apple.com/app/id\(app.id)")!) {
                            HStack {
                                Text(app.name).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Data and credits") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Connectome").font(.headline)
                        Text("FlyWire FAFB v783 — 138 584 neurons and 3 732 460 connections of an "
                             + "adult female *Drosophila melanogaster*. Licensed CC BY 4.0.")
                            .font(.callout)
                        Text("Dorkenwald et al., Nature 2024 · Schlegel et al., Nature 2024 · "
                             + "codex.flywire.ai")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Fly model").font(.headline)
                        Text("\"Fly\" by Kohyzazi, public domain (CC0), via poly.pizza.")
                            .font(.callout)
                    }
                    .padding(.vertical, 4)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What is ours").font(.headline)
                        Text("The wiring is measured; how spikes become walking, grooming or a "
                             + "startle is our assumption, and so is every number behind hunger "
                             + "and sleep.")
                            .font(.callout)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
