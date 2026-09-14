# /// script
# requires-python = ">=3.11"
# ///
"""Turn a Codex (codex.flywire.ai) export into what the app loads.

    uv run scripts/flywire-import.py data/fafb-v783

Reads, gzipped or not, from that directory:
  connections.csv   pre_root_id, post_root_id, neuropil, syn_count, nt_type
  coordinates.csv   root_id, position "[x y z]" in nm, supervoxel_id   (one or more per cell)
Writes next to them:
  edges.csv         pre_id, post_id, syn_count — summed over neuropils, the loader's format
  positions.csv     root_id, x, y, z in µm — one row per cell (mean of its coordinates)
  brain.fcb         the same graph as CSR plus positions, little-endian, for the app bundle:
                    "FCB1" u32 n u32 e · ids u64[n] · row_start u32[n+1] · targets u32[e]
                    · weights u16[e] · positions f32[3n] (µm, index order) — ~10 bytes/edge
  import-receipt.txt  what went in and what came out, so a number on screen has a source

Licence of the source data: CC-BY 4.0, Dorkenwald et al. 2024 and Schlegel et al. 2024
(Nature). Cite them wherever the app shows the real brain.
"""
import csv
import gzip
import sys
from collections import defaultdict
from pathlib import Path


# Which (super_class, class) pairs become which population. Anything not here is left out:
# a group the app does not drive or read is weight in the file for nothing.
GROUP_OF = {
    ("sensory", "visual"): "visual",              # photoreceptors — the eyes
    ("sensory", "mechanosensory"): "mechano",     # bristles, wind and hearing — touch
    ("sensory", "olfactory"): "olfactory",        # antennal receptors — smell
    ("sensory", "gustatory"): "gustatory",        # taste, on the proboscis and legs
    ("descending", ""): "descending",             # brain → nerve cord: the motor command
    ("descending", "ocellar"): "descending",
    ("motor", "brain_motor_neuron"): "motor",     # proboscis and neck muscles
    ("visual_projection", ""): "visual_projection",
}


def open_any(dir_: Path, stem: str):
    for name in (f"{stem}.csv.gz", f"{stem}.csv"):
        p = dir_ / name
        if p.exists():
            return (gzip.open(p, "rt") if name.endswith(".gz") else p.open()), p
    sys.exit(f"missing {stem}.csv(.gz) in {dir_}")


def write_fcb(path: Path, edges: dict[tuple[int, int], int], sums: dict[int, list[float]]) -> None:
    """CSR by ascending root id, so the index order is reproducible from the ids alone."""
    import struct

    ids = sorted({a for a, _ in edges} | {b for _, b in edges})
    index = {rid: i for i, rid in enumerate(ids)}
    rows: list[list[tuple[int, int]]] = [[] for _ in ids]
    for (a, b), syn in edges.items():
        rows[index[a]].append((index[b], min(syn, 65535)))
    row_start = [0]
    targets: list[int] = []
    weights: list[int] = []
    for row in rows:
        row.sort()
        targets.extend(t for t, _ in row)
        weights.extend(w for _, w in row)
        row_start.append(len(targets))
    positions: list[float] = []
    for rid in ids:
        x, y, z, n = sums.get(rid, [0.0, 0.0, 0.0, 1])
        positions.extend((x / n / 1000, y / n / 1000, z / n / 1000))
    with path.open("wb") as f:
        f.write(b"FCB1")
        f.write(struct.pack("<II", len(ids), len(targets)))
        f.write(struct.pack(f"<{len(ids)}Q", *ids))
        f.write(struct.pack(f"<{len(row_start)}I", *row_start))
        f.write(struct.pack(f"<{len(targets)}I", *targets))
        f.write(struct.pack(f"<{len(weights)}H", *weights))
        f.write(struct.pack(f"<{len(positions)}f", *positions))


def write_populations(path: Path, dir_: Path, cells: set[int]) -> None:
    """Cell indices (fcb order = ascending root id) grouped into the populations the app
    actually drives and reads.

    Two sources, both already downloaded:
      * `connections.csv` nt_type — the predicted transmitter of a cell's output. "DA" is the
        786-cell dopaminergic reward population.
      * `classification.csv` — super_class, class, sub_class and **side** per cell. This is
        what turns the simulation from a blob into anatomy: light goes into photoreceptors of
        one eye, a touch into the bristles of one side, and the fly's steering is read off the
        left and right descending neurons, which are the cells that actually carry commands
        from the brain to the nerve cord.

    Keys are `group` or `group.side`, e.g. `visual.left`, `descending.right`, `mechano.left`.
    Without classification.csv only the transmitter groups are written, and the app falls back
    to its whole-brain readout — so the file is an upgrade, not a requirement.
    """
    import json

    ids = sorted(cells)
    index = {rid: i for i, rid in enumerate(ids)}
    groups: dict[str, list[int]] = defaultdict(list)

    nt: dict[int, str] = {}
    f, _ = open_any(dir_, "connections")
    with f:
        for row in csv.DictReader(f):
            rid = int(row["pre_root_id"])
            if rid in index and rid not in nt:
                nt[rid] = row["nt_type"]
    for rid, t in nt.items():
        groups[t].append(index[rid])

    try:
        f, _ = open_any(dir_, "classification")
    except SystemExit:
        print("no classification.csv — transmitter groups only, the app keeps its whole-brain readout")
    else:
        with f:
            for row in csv.DictReader(f):
                i = index.get(int(row["root_id"]))
                if i is None:
                    continue
                side = row["side"] if row["side"] in ("left", "right") else None
                name = GROUP_OF.get((row["super_class"], row["class"]))
                if name is None:
                    continue
                groups[name].append(i)
                if side:
                    groups[f"{name}.{side}"].append(i)

    for g in groups.values():
        g.sort()
    path.write_text(json.dumps({k: groups[k] for k in sorted(groups)}, separators=(",", ":")))
    print("populations: " + " · ".join(f"{k} {len(v)}" for k, v in sorted(groups.items())
                                       if "." not in k or k.endswith(".left")))


def main(dir_: Path):
    edges: dict[tuple[int, int], int] = defaultdict(int)
    f, src = open_any(dir_, "connections")
    with f:
        r = csv.DictReader(f)
        need = {"pre_root_id", "post_root_id", "syn_count"}
        if not need <= set(r.fieldnames or []):
            sys.exit(f"{src}: expected columns {sorted(need)}, got {r.fieldnames}")
        rows = 0
        for row in r:
            rows += 1
            edges[(int(row["pre_root_id"]), int(row["post_root_id"]))] += int(row["syn_count"])
    cells = {a for a, _ in edges} | {b for _, b in edges}
    with (dir_ / "edges.csv").open("w") as out:
        out.write("pre_id,post_id,syn_count\n")
        for (a, b), syn in sorted(edges.items()):
            out.write(f"{a},{b},{syn}\n")

    sums: dict[int, list[float]] = defaultdict(lambda: [0.0, 0.0, 0.0, 0])
    f, src = open_any(dir_, "coordinates")
    with f:
        r = csv.DictReader(f)
        for row in r:
            rid = int(row["root_id"])
            if rid not in cells:
                continue
            x, y, z = (float(v) for v in row["position"].strip("[] ").split())
            s = sums[rid]
            s[0] += x; s[1] += y; s[2] += z; s[3] += 1
    with (dir_ / "positions.csv").open("w") as out:
        out.write("root_id,x_um,y_um,z_um\n")
        for rid, (x, y, z, n) in sorted(sums.items()):
            out.write(f"{rid},{x / n / 1000:.3f},{y / n / 1000:.3f},{z / n / 1000:.3f}\n")

    write_fcb(dir_ / "brain.fcb", edges, sums)
    write_populations(dir_ / "populations.json", dir_, cells)
    strong = sum(1 for s in edges.values() if s >= 5)
    receipt = (
        f"source rows: {rows}\n"
        f"cells: {len(cells)} · with coordinates: {len(sums)} · missing: {len(cells) - len(sums)}\n"
        f"edges: {len(edges)} · at syn_count >= 5: {strong} · >= 10: {sum(1 for s in edges.values() if s >= 10)}\n"
        f"synapses total: {sum(edges.values())}\n"
    )
    (dir_ / "import-receipt.txt").write_text(receipt)
    print(receipt, end="")


if __name__ == "__main__":
    main(Path(sys.argv[1]))
