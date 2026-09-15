# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy"]
# ///
"""Pick a subset of FlyWire skeletons and decimate them into a line list the app can draw.

    uv run scripts/flywire-skeletons.py data/fafb-v783 ~/Downloads/sk_lod1_783_healed.zip \
        --neurons 8000 --segments 60 [--seed 1]

Reads SWC files straight out of the Codex "Neuron Skeletons" zip (no 33 GB extraction) and
writes `skeletons.fsk` next to brain.fcb:
  "FSK1" u32 neurons · per neuron: u32 cell_index u32 segments · segments × 6 f32 (µm, a b)
Cell indices are the fcb order (ascending root id), so a segment's heat is rates[index].

Which neurons: every dopaminergic cell (populations.json "DA") plus a seeded random sample of
the rest, so the reward population is always drawn in full. Decimation keeps the root, every
branch point and leaf, and every k-th node along a path, k chosen so a neuron stays under
`--segments`; each kept node links to its nearest kept ancestor.
"""
import json
import random
import struct
import sys
import zipfile
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))
from flywire_io import read_fcb_ids


def decimate(text: str, max_segments: int) -> np.ndarray:
    """SWC → (segments, 6) float32 in µm."""
    ids, xyz, parent = [], [], []
    for line in text.splitlines():
        if not line or line[0] == "#":
            continue
        c = line.split()
        if len(c) < 7:
            continue
        ids.append(int(c[0]))
        xyz.append((float(c[2]), float(c[3]), float(c[4])))
        parent.append(int(c[6]))
    n = len(ids)
    if n < 2:
        return np.zeros((0, 6), np.float32)
    index = {i: k for k, i in enumerate(ids)}
    par = np.array([index.get(p, -1) for p in parent])
    pts = np.array(xyz, np.float32) / 1000.0
    children = np.zeros(n, int)
    for p in par:
        if p >= 0:
            children[p] += 1
    k = max(1, -(-n // max_segments))
    # Depth along the path so "every k-th node" is measured from the root, not by file order.
    order = sorted(range(n), key=lambda i: 0)  # SWC parents precede children in these files
    depth = np.zeros(n, int)
    for i in order:
        if par[i] >= 0:
            depth[i] = depth[par[i]] + 1
    keep = (par < 0) | (children != 1) | (depth % k == 0)
    nearest = np.full(n, -1)
    for i in range(n):
        p = par[i]
        while p >= 0 and not keep[p]:
            p = par[p]
        nearest[i] = p
    segs = [(pts[nearest[i]], pts[i]) for i in range(n) if keep[i] and nearest[i] >= 0]
    if len(segs) > max_segments:
        segs = segs[:: -(-len(segs) // max_segments)][:max_segments]
    return np.array([np.concatenate(s) for s in segs], np.float32) if segs else np.zeros((0, 6), np.float32)


def main():
    args = sys.argv[1:]
    dir_, zpath = Path(args[0]), Path(args[1])
    want = int(args[args.index("--neurons") + 1]) if "--neurons" in args else 8000
    max_segments = int(args[args.index("--segments") + 1]) if "--segments" in args else 60
    seed = int(args[args.index("--seed") + 1]) if "--seed" in args else 1

    ids = read_fcb_ids(dir_ / "brain.fcb")
    pops = json.loads((dir_ / "populations.json").read_text())
    z = zipfile.ZipFile(zpath)
    have = {int(Path(n).stem): n for n in z.namelist() if n.endswith(".swc")}
    chosen = {i for i in pops.get("DA", []) if ids[i] in have}
    rest = [i for i in range(len(ids)) if ids[i] in have and i not in chosen]
    random.Random(seed).shuffle(rest)
    chosen |= set(rest[: max(0, want - len(chosen))])

    out = dir_ / "skeletons.fsk"
    total = 0
    with out.open("wb") as f:
        f.write(b"FSK1")
        f.write(struct.pack("<I", len(chosen)))
        for n, i in enumerate(sorted(chosen)):
            segs = decimate(z.read(have[ids[i]]).decode(), max_segments)
            f.write(struct.pack("<II", i, len(segs)))
            f.write(segs.tobytes())
            total += len(segs)
            if n % 1000 == 0:
                print(f"{n}/{len(chosen)} neurons, {total} segments", flush=True)
    print(f"wrote {out} · {len(chosen)} neurons · {total} segments · {out.stat().st_size / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
