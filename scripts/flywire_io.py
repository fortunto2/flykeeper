"""Shared readers for the files this project's scripts pass between each other.

Written once because it was written four times: `open_any` had already been copied and had
already diverged (one version returning a handle, another a pair), and the `.fcb` header was
being hand-parsed in three places.
"""
import gzip
import struct
import sys
from pathlib import Path


def open_any(dir_: Path, stem: str, required: bool = True):
    """`<stem>.csv` or `<stem>.csv.gz`, whichever is there. Returns (handle, path)."""
    for name in (f"{stem}.csv.gz", f"{stem}.csv"):
        p = dir_ / name
        if p.exists():
            return (gzip.open(p, "rt") if name.endswith(".gz") else p.open()), p
    if required:
        sys.exit(f"missing {stem}.csv(.gz) in {dir_}")
    return None, None


def read_fcb_ids(path: Path) -> list[int]:
    """The neuron ids of a packed brain, in the index order everything else uses."""
    with path.open("rb") as f:
        if f.read(4) != b"FCB1":
            sys.exit(f"{path} is not an FCB1 file")
        n, _ = struct.unpack("<II", f.read(8))
        return list(struct.unpack(f"<{n}Q", f.read(8 * n)))
