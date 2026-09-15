# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy"]
# ///
"""Where each photoreceptor looks, so a camera image can be shown to the fly.

    uv run scripts/retina.py data/fafb-v783

A retina is a curved sheet of cells, and the export gives every cell body's position. Its two
dominant directions *are* its two retinal axes, so projecting onto them recovers a map that
is spatially ordered — neighbouring ommatidia stay neighbours — which is all an image needs
to sweep across the population the way a real scene does. It is not calibrated optics: this
does not claim to reproduce a fly's 270° field or its ommatidial angles, only its order.

Writes `retina.frt` next to brain.fcb:
    "FRT1" u32 nLeft u32 nRight · then each side: (u32 cellIndex, f32 u, f32 v) …
with u, v in 0…1 across that eye.
"""
import csv
import struct
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))
from flywire_io import open_any


def main(dir_: Path):
    f, _ = open_any(dir_, "positions")
    with f:
        rows = list(csv.DictReader(f))
    order = {int(r["root_id"]): i for i, r in enumerate(rows)}
    xyz = np.array([[float(r["x_um"]), float(r["y_um"]), float(r["z_um"])] for r in rows])

    sides: dict[str, list[int]] = {"left": [], "right": []}
    f, _ = open_any(dir_, "classification")
    with f:
        for row in csv.DictReader(f):
            if row["sub_class"] == "photo_receptor" and row["side"] in sides:
                i = order.get(int(row["root_id"]))
                if i is not None:
                    sides[row["side"]].append(i)

    packed = {}
    for side, idx in sides.items():
        cells = np.array(sorted(idx))
        pts = xyz[cells]
        # Trim the furthest 1%: a handful of stray somas otherwise stretch the whole map.
        keep = np.linalg.norm(pts - np.median(pts, 0), axis=1) < np.percentile(
            np.linalg.norm(pts - np.median(pts, 0), axis=1), 99)
        cells, pts = cells[keep], pts[keep]
        centred = pts - pts.mean(0)
        _, _, vt = np.linalg.svd(centred, full_matrices=False)
        uv = centred @ vt[:2].T
        lo, hi = np.percentile(uv, 1, axis=0), np.percentile(uv, 99, axis=0)
        uv = np.clip((uv - lo) / (hi - lo), 0, 1)
        # The two eyes look outwards, so one of them sees the world mirrored; flip the right
        # so that "u rising" means the same direction in the world for both.
        if side == "right":
            uv[:, 0] = 1 - uv[:, 0]
        packed[side] = (cells, uv.astype(np.float32))
        print(f"{side}: {len(cells)} photoreceptors mapped")

    out = dir_ / "retina.frt"
    with out.open("wb") as f:
        f.write(b"FRT1")
        f.write(struct.pack("<II", len(packed["left"][0]), len(packed["right"][0])))
        for side in ("left", "right"):
            cells, uv = packed[side]
            for c, (u, v) in zip(cells, uv):
                f.write(struct.pack("<Iff", int(c), float(u), float(v)))
    print(f"wrote {out} · {out.stat().st_size / 1024:.0f} KB")


if __name__ == "__main__":
    main(Path(sys.argv[1]))
