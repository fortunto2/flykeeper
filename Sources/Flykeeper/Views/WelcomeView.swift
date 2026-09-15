import SwiftUI
import FlyKit

/// What this is, before the fly appears.
///
/// Not decoration: the one thing that makes this app unlike anything else is a measured
/// connectome running on the phone, and until now that was behind a segmented control a
/// person might never tap. Someone opening the app saw a cartoon fly in a box. This says what
/// they are looking at first, and the brain loads behind it while they read — so the speed
/// shown here is the real one, measured on this device in the seconds it took to get here.
struct WelcomeView: View {
    /// Live from the engine loading behind this screen; 0 until it has run.
    let stepsPerSecond: Double
    let onStart: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 10) {
                    Text("Flykeeper")
                        .font(.system(.largeTitle, design: .monospaced, weight: .bold))
                    Text("A fly whose behaviour comes out of a **real fly brain**, simulated on this phone.")
                        .font(.title3)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 8)

                VStack(spacing: 12) {
                    Fact("138,584", "neurons, each at the position it has in the animal")
                    Fact("3,732,460", "connections, measured synapse by synapse")
                    Fact(stepsPerSecond > 0 ? "\(Int(stepsPerSecond))" : "…",
                         stepsPerSecond > 0
                         ? "brain steps a second, on your device, right now"
                         : "measuring the speed on your device…")
                }
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 14) {
                    Unique("hand.tap.fill",
                           "Touch it and its real bristles fire. It turns away through the measured wiring, not through a rule we wrote.")
                    Unique("eye.fill",
                           "Show it the camera and 10,629 photoreceptors see it, each looking where that cell looks on the real retina.")
                    Unique("brain",
                           "Watch the whole brain heat up while it walks, eats and sleeps — every neuron a point where it truly sits.")
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label {
                        Text("The wiring is **measured** — FlyWire FAFB v783, an adult fruit fly mapped by electron microscopy and published in *Nature* in 2024.")
                    } icon: { Image(systemName: "checkmark.seal.fill").foregroundStyle(.green) }
                    Label {
                        Text("What it **means** is ours: that a burst of firing is a turn, that hunger makes it restless. Every one of those numbers is written down.")
                    } icon: { Image(systemName: "pencil.circle.fill").foregroundStyle(.orange) }
                }
                .font(.callout)

                Button(action: onStart) {
                    Text("Meet your fly")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("start")

                Text("Nothing leaves this device. No account, no network, no tracking.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }

    /// One thing this app does that nothing else does, said as the thing rather than as a claim.
    private struct Unique: View {
        let icon: String
        let what: String
        init(_ icon: String, _ what: String) {
            self.icon = icon
            self.what = what
        }

        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                Text(what).font(.callout)
            }
        }
    }

    private struct Fact: View {
        let value: String
        let what: String
        init(_ value: String, _ what: String) {
            self.value = value
            self.what = what
        }

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(value)
                    .font(.system(.title3, design: .monospaced, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: 132, alignment: .trailing)
                    .contentTransition(.numericText())
                Text(what).font(.footnote).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
        }
    }
}
