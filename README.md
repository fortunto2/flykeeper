# Flykeeper

A fly you keep, whose behaviour comes out of a simulation of a real fly brain, running on the
phone. No account, no network, nothing leaves the device.

The brain is the FlyWire FAFB v783 connectome: **138 584 neurons and 3 732 460 connections**
of an adult female *Drosophila melanogaster*, stepped as leaky integrate-and-fire cells at
1 ms in Rust, about 1000 steps a second on a laptop. What the fly then does — walk, groom,
startle, sleep — is our reading of that activity, and the app says so on screen rather than
pretending otherwise.

<img src="docs/screenshots/full-brain.png" width="280" alt="The full brain, heat-mapped by firing rate, above the fly">

## What is real and what is ours

| | |
|---|---|
| **Measured** | which neuron connects to which, how many synapses, where each cell body sits |
| **Ours** | that 7% of cells firing means "turn", that a touch is 8.0 into every tenth neuron, every number behind hunger, sleep and mood |

Every assumption is written down in [`docs/sensory-map.md`](docs/sensory-map.md) with the
measurement that produced it. A receipt on screen carries the neuron and edge count, the real
steps per second, and the words `SYNTHETIC WIRING` whenever the brain is not the real one —
because a simulation reporting zero spikes and one that never started look identical unless
the run says which happened.

## The eye

Tap **Eye** and the camera drives the fly's own 10 629 photoreceptors, each at the point on
its retina that cell looks from — the map comes from the cells' positions in the export, not
from a texture. Photoreceptors adapt, so a static scene fades and movement lights them up.
Frames are sampled and dropped: nothing is recorded or sent, and the camera is never started
until you ask for it.

## Layout

```
Sources/FlyKit/          domain: behaviour readout, motion, vitals — no platform, no engine
Sources/Flykeeper/       the app: RealityKit scene, heat-map shaders, the engine actor
Resources/               the packed connectome, the fly model, the brain surface, the icon
scripts/                 FlyWire import, skeleton decimation, glTF→USDZ, icon generation
docs/                    what every number means and where each asset came from
```

The simulation engine itself lives in a separate workspace
(`superduper-dsp/connectome-core` and `mobile/fly-ios`) and reaches the app as
`FlyBrain.xcframework`; `make engine` rebuilds it.

## Build

```bash
cp Makefile.local.example Makefile.local    # put your Apple team id in it
make engine                                  # build the Rust engine into Vendor/
make run                                     # simulator
make run TIER=full                           # start on the real brain
make device                                  # your iPhone
make verify                                  # Rust tests, Swift tests, app build
```

## Data and licences

- **Code** in this repository: MIT, see [`LICENSE`](LICENSE).
- **Connectome** (`Resources/fafb-v783*`): FlyWire FAFB v783, **CC BY 4.0** — Dorkenwald et
  al., *Nature* 2024 and Schlegel et al., *Nature* 2024, via
  [codex.flywire.ai](https://codex.flywire.ai). Redistributed here under that licence; the
  app shows the credit wherever the brain is on screen.
- **Brain surface** (`Resources/BrainShell.usdz`): the FLYWIRE template mesh from
  [navis-flybrains](https://github.com/navis-org/navis-flybrains), same credit.
- **Fly model** (`Resources/Fly.usdz`): "Fly" by Kohyzazi, **CC0**, via
  [poly.pizza](https://poly.pizza/m/kCLW4c0kGx).

Details of every conversion, with the exact commands: [`docs/assets.md`](docs/assets.md).

## Privacy

[`PRIVACY.md`](PRIVACY.md) — the app collects nothing and sends nothing. There is no
networking code in it at all.
