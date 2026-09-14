# Assets — where the models come from and how they get into the app

RealityKit loads USDZ and `.reality` only. Everything else is converted with
`scripts/glb2usdz.py` (a uv script: `usd-core` + `numpy`, no Blender, no Reality Converter)
and committed as the converted file, so a clone builds without the toolchain.

## Fly.usdz

| | |
|---|---|
| Source | "Fly" by Kohyzazi, https://poly.pizza/m/kCLW4c0kGx |
| Licence | CC0 (public domain) — no attribution required; credited here anyway |
| Original | GLB, 87 KB, 1 mesh, 3 materials (Body, Eyes, Wings), no animation, z-up |
| Converted | `uv run scripts/glb2usdz.py fly.glb Resources/Fly.usdz --split Wings --up z` |
| Result | prims `/Fly/Body`, `/Fly/Eyes`, `/Fly/Wings_L`, `/Fly/Wings_R`; faces +x; ~0.045 units long |

The converter turns the model to face +x (the prim named `Eyes` marks the head) and splits
the wing pair on its symmetry axis, baking each wing's root as the prim's translation, so
the app flaps a wing by rotating the prim about the body's long axis. Wing beat, eye colour
and bob come from the simulation (`FlyArena3DView.ArenaScene.apply`); the file carries no
animation on purpose.

If the USDZ fails to load, the scene keeps a procedural fly (spheres and boxes) so a broken
asset is a plainer fly, not an empty cube.

## Where to look for more

- **poly.pizza** — low-poly, CC0/CC-BY, direct `.glb` on `static.poly.pizza`; the fastest.
- **Sketchfab** — filter Downloadable; licences vary (CC-BY needs a credit line in-app);
  offers USDZ export itself. The CT-scanned *Drosophila* by etainproject (CC-BY) is real
  anatomy if the app ever wants a specimen rather than a pet.
- **Meshy / Tripo** — text-to-3D; export USDZ directly. Good for a one-off prop (a banana
  for Feed), check the licence tier before shipping.
- Room/AR later: LiDAR mesh comes from ARKit scene reconstruction, not from an asset.

## fafb-v783.fcb — the real brain

| | |
|---|---|
| Source | FlyWire FAFB v783 via codex.flywire.ai → Download Data: "Connections (Filtered)" and "Marked Neuron Coordinates" |
| Licence | CC BY 4.0 — cite Dorkenwald et al. 2024 and Schlegel et al. 2024 (Nature); the app shows the credit line under the receipt |
| Converted | `uv run scripts/flywire-import.py data/fafb-v783` → `brain.fcb`, copied to `Resources/fafb-v783.fcb` (25.7 MB) |
| Content | 138,584 cells with coordinates, 3,732,460 edges (syn_count ≥ 5), 50,666,648 synapses — matches the paper |

Raw exports stay in `data/` (gitignored, needs a Codex login to fetch). The importer's
`import-receipt.txt` is the number to compare against: Codex updates the live files, so a
different count means a different snapshot.

## BrainShell.usdz — the brain surface

| | |
|---|---|
| Source | `flybrains.FLYWIRE.mesh` from the navis-flybrains package (25 047 vertices), the FlyWire template brain surface in the same nm frame as the cells |
| Licence | navis-flybrains is GPL-3 code; the mesh data is FlyWire's (CC BY 4.0), same credit line |
| Converted | trimesh export to GLB in µm (vertices / 1000), then `uv run scripts/glb2usdz.py brain_shell.glb Resources/BrainShell.usdz` |
| In the app | placed with the cell cloud's own µm → scene mapping (`BrainCloud.mid/scale/centre`, y flipped), painted as 10% glass |

Cells sit up to ~100 µm outside the surface on each side (somas in the rind); that is the
data, not a misalignment.

### The look, and what it would take to go further

The cells render as soft discs sized and coloured by firing rate (`Shaders/Brain.metal`).
The FlyWire gallery look — every neuron's arbor — needs skeletons: Codex "Neuron Skeletons"
is 13 GB. A phone can carry a decimated subset (a few thousand neurons, ~50 segments each, as
line lists) and colour each arbor by its cell's heat. Not done yet; needs that download under
a Codex login.

## fafb-v783-populations.json — who is dopaminergic

Cell indices (fcb order) grouped by the predicted neurotransmitter of their output, read from
the `nt_type` column of the same connections export: ACH 94 160 · GLUT 22 657 · GABA 18 374 ·
SER 1 435 · DA 786 · OCT 106. The app drives the 786 DA cells (current 6.0) while the fly
eats: reward on the real reward population. Synthetic wiring uses the last 5% of cells as a
stand-in.

## fafb-v783-skeletons.fsk — arbors of a subset

| | |
|---|---|
| Source | Codex "Neuron Skeletons" (`sk_lod1_783_healed.zip`, 13.9 GB, 139 273 SWC files in nm, LOD1) |
| Converted | `uv run scripts/flywire-skeletons.py data/fafb-v783 ~/Downloads/sk_lod1_783_healed.zip --neurons 8000 --segments 60` |
| Content | every DA cell plus a seeded random sample to 8 000 cells, ≤60 segments each (root, branch points, leaves, every k-th node) |
| In the app | `BrainWires`: one line list, hue per cell, brightness and alpha by the cell's firing rate |

Read straight out of the zip; the zip itself stays in Downloads and is not part of the repo.
