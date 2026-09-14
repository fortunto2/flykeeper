"""The .fcb format is a contract between two languages: this writer and the Rust reader in
`connectome-core::Graph::from_fcb`. The Rust side's test builds the bytes by hand, so on its
own it pins the reader against a copy of the spec rather than against what we actually
write — a field reordered here would pass both suites and load a brain with scrambled
positions. These tests read the bytes back the way Rust does.
"""
import importlib.util
import struct
from pathlib import Path

SPEC = importlib.util.spec_from_file_location("flywire_import", Path(__file__).parent / "flywire-import.py")
fw = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(fw)


def unpack(path: Path):
    """Read an .fcb exactly as Graph::from_fcb does, offset by offset."""
    b = path.read_bytes()
    assert b[:4] == b"FCB1"
    n, e = struct.unpack("<II", b[4:12])
    o = 12
    ids = struct.unpack(f"<{n}Q", b[o:o + n * 8]); o += n * 8
    row_start = struct.unpack(f"<{n + 1}I", b[o:o + (n + 1) * 4]); o += (n + 1) * 4
    targets = struct.unpack(f"<{e}I", b[o:o + e * 4]); o += e * 4
    weights = struct.unpack(f"<{e}H", b[o:o + e * 2]); o += e * 2
    positions = struct.unpack(f"<{3 * n}f", b[o:o + 12 * n]); o += 12 * n
    assert o == len(b), f"{len(b) - o} trailing bytes: the reader would read past the end"
    return {"n": n, "e": e, "ids": ids, "row_start": row_start, "targets": targets,
            "weights": weights, "positions": positions}


def write(tmp_path, edges, sums):
    out = tmp_path / "brain.fcb"
    fw.write_fcb(out, edges, sums)
    return unpack(out)


def test_cells_are_indexed_by_ascending_root_id(tmp_path):
    # Index order is what ties a spike to a position, and the only thing that fixes it is
    # this sort — the edge dict's insertion order is not it.
    edges = {(300, 100): 7, (100, 200): 9}
    sums = {i: [float(i), 0.0, 0.0, 1] for i in (100, 200, 300)}
    got = write(tmp_path, edges, sums)
    assert got["ids"] == (100, 200, 300)
    assert got["n"] == 3 and got["e"] == 2


def test_csr_rows_hold_each_cell_s_own_out_edges(tmp_path):
    edges = {(100, 200): 5, (100, 300): 6, (300, 100): 7}
    sums = {i: [0.0, 0.0, 0.0, 1] for i in (100, 200, 300)}
    got = write(tmp_path, edges, sums)
    rs, t, w = got["row_start"], got["targets"], got["weights"]
    assert rs == (0, 2, 2, 3), "cell 0 has two out-edges, cell 1 none, cell 2 one"
    assert t[rs[0]:rs[1]] == (1, 2) and t[rs[2]:rs[3]] == (0,)
    assert w[rs[0]:rs[1]] == (5, 6)


def test_targets_within_a_row_are_sorted(tmp_path):
    # The parallel step finds the slice of a row landing in a destination chunk by binary
    # search; an unsorted row silently drops current on the floor.
    edges = {(100, 400): 1, (100, 200): 2, (100, 300): 3}
    sums = {i: [0.0, 0.0, 0.0, 1] for i in (100, 200, 300, 400)}
    got = write(tmp_path, edges, sums)
    row = got["targets"][got["row_start"][0]:got["row_start"][1]]
    assert list(row) == sorted(row)


def test_positions_are_the_mean_in_micrometres_in_index_order(tmp_path):
    # Codex gives nanometres and one row per marked coordinate; the app draws micrometres.
    edges = {(100, 200): 5}
    sums = {100: [3000.0, 6000.0, 9000.0, 3], 200: [1000.0, 1000.0, 1000.0, 1]}
    got = write(tmp_path, edges, sums)
    assert got["positions"][0:3] == (1.0, 2.0, 3.0)
    assert got["positions"][3:6] == (1.0, 1.0, 1.0)


def test_a_cell_without_coordinates_still_gets_a_slot(tmp_path):
    # Dropping it would shift every later index and put the whole cloud one cell out.
    edges = {(100, 200): 5}
    got = write(tmp_path, edges, {100: [1000.0, 2000.0, 3000.0, 1]})
    assert got["n"] == 2
    assert got["positions"][3:6] == (0.0, 0.0, 0.0)


def test_synapse_counts_saturate_rather_than_wrap(tmp_path):
    # Weights are u16. A pair with more than 65535 synapses must come back as the strongest
    # possible edge, not as a weak one.
    edges = {(100, 200): 70000}
    got = write(tmp_path, edges, {i: [0.0, 0.0, 0.0, 1] for i in (100, 200)})
    assert got["weights"] == (65535,)
