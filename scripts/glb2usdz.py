# /// script
# requires-python = ">=3.11"
# dependencies = ["usd-core>=24.11", "numpy"]
# ///
"""Convert a small glTF binary (positions, normals, indices, base-colour materials) into a
USDZ that RealityKit loads. Deliberately narrow: no textures, no skins, no animation — the
fly's motion comes from the simulation, so a separable wing mesh is all the file needs.

    uv run scripts/glb2usdz.py in.glb out.usdz [--split Wings] [--up z]

`--split NAME` cuts that primitive into NAME_L / NAME_R by the sign of each triangle's
centroid on the model's sideways axis, so each half can rotate about its own root.
"""
import json
import struct
import sys
from pathlib import Path

import numpy as np
from pxr import Gf, Sdf, Usd, UsdGeom, UsdShade, UsdUtils

CTYPE = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def read_glb(path: Path):
    b = path.read_bytes()
    # Header, then the JSON chunk, then the binary chunk. Only the lengths are needed: the
    # chunk types are fixed by the spec for a .glb with one of each.
    jl = struct.unpack("<I", b[12:16])[0]
    doc = json.loads(b[20 : 20 + jl])
    off = 20 + jl
    bl = struct.unpack("<I", b[off : off + 4])[0]
    return doc, b[off + 8 : off + 8 + bl]


def accessor(doc, bin_, idx):
    a = doc["accessors"][idx]
    v = doc["bufferViews"][a["bufferView"]]
    start = v.get("byteOffset", 0) + a.get("byteOffset", 0)
    n = NCOMP[a["type"]]
    dt = np.dtype("<" + CTYPE[a["componentType"]])
    count = a["count"] * n
    arr = np.frombuffer(bin_, dtype=dt, count=count, offset=start)
    return arr.reshape(a["count"], n) if n > 1 else arr


def face_normals(pos, tris):
    """Per-vertex normals averaged from the faces, for meshes exported without any."""
    n = np.zeros_like(pos)
    a, b, c = pos[tris[:, 0]], pos[tris[:, 1]], pos[tris[:, 2]]
    fn = np.cross(b - a, c - a)
    for k in range(3):
        np.add.at(n, tris[:, k], fn)
    lens = np.linalg.norm(n, axis=1, keepdims=True)
    return (n / np.maximum(lens, 1e-12)).astype(np.float32)


def add_mesh(stage, parent, name, pos, nrm, tris, rgba):
    mesh = UsdGeom.Mesh.Define(stage, f"{parent}/{name}")
    mesh.CreatePointsAttr([Gf.Vec3f(*map(float, p)) for p in pos])
    mesh.CreateNormalsAttr([Gf.Vec3f(*map(float, n)) for n in nrm])
    mesh.SetNormalsInterpolation(UsdGeom.Tokens.vertex)
    mesh.CreateFaceVertexCountsAttr([3] * len(tris))
    mesh.CreateFaceVertexIndicesAttr([int(i) for i in tris.reshape(-1)])
    mesh.CreateSubdivisionSchemeAttr(UsdGeom.Tokens.none)
    mat = UsdShade.Material.Define(stage, f"{parent}/Materials/{name}Mat")
    shader = UsdShade.Shader.Define(stage, f"{parent}/Materials/{name}Mat/Surface")
    shader.CreateIdAttr("UsdPreviewSurface")
    shader.CreateInput("diffuseColor", Sdf.ValueTypeNames.Color3f).Set(Gf.Vec3f(*rgba[:3]))
    shader.CreateInput("roughness", Sdf.ValueTypeNames.Float).Set(0.6)
    shader.CreateInput("metallic", Sdf.ValueTypeNames.Float).Set(0.0)
    if rgba[3] < 1.0:
        shader.CreateInput("opacity", Sdf.ValueTypeNames.Float).Set(float(rgba[3]))
    mat.CreateSurfaceOutput().ConnectToSource(shader.ConnectableAPI(), "surface")
    UsdShade.MaterialBindingAPI.Apply(mesh.GetPrim()).Bind(mat)
    return mesh


def main():
    args = sys.argv[1:]
    src, dst = Path(args[0]), Path(args[1])
    split = args[args.index("--split") + 1] if "--split" in args else None
    doc, bin_ = read_glb(src)
    stage = Usd.Stage.CreateNew(str(dst.with_suffix(".usda")))
    UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.y)
    UsdGeom.SetStageMetersPerUnit(stage, 1.0)
    root = UsdGeom.Xform.Define(stage, "/Fly")
    stage.SetDefaultPrim(root.GetPrim())
    lo, hi = np.full(3, np.inf), np.full(3, -np.inf)
    parts = []
    for mesh in doc["meshes"]:
        for prim in mesh["primitives"]:
            # A primitive may carry no material at all (trimesh exports of bare meshes).
            mat = doc.get("materials", [])[prim["material"]] if "material" in prim else {}
            name = mat.get("name", "Part").replace(" ", "")
            rgba = mat.get("pbrMetallicRoughness", {}).get("baseColorFactor", [0.8, 0.8, 0.8, 1])
            pos = accessor(doc, bin_, prim["attributes"]["POSITION"]).astype(np.float32)
            tris = accessor(doc, bin_, prim["indices"]).reshape(-1, 3)
            if "NORMAL" in prim["attributes"]:
                nrm = accessor(doc, bin_, prim["attributes"]["NORMAL"]).astype(np.float32)
            else:
                nrm = face_normals(pos, tris)
            parts.append((name, rgba, pos, nrm, tris))
    # Some exports are z-up despite the glTF spec. `--up z` rotates -90° about x so the app
    # sees y-up: (x, y, z) -> (x, z, -y).
    if "--up" in args and args[args.index("--up") + 1] == "z":
        def zup(v):
            return np.stack([v[:, 0], v[:, 2], -v[:, 1]], 1).astype(np.float32)
        parts = [(n, c, zup(pos), zup(nrm), tris) for n, c, pos, nrm, tris in parts]
        print("rotated z-up to y-up")
    # Face +x: the part named Eyes marks the head. A 180° turn about y keeps handedness, so
    # the app never needs to know which way the artist modelled it.
    eyes = next((p for p in parts if p[0] == "Eyes"), None)
    if eyes is not None and eyes[2].mean(0)[0] < 0:
        parts = [(n, c, pos * np.array([-1, 1, -1], np.float32), nrm * np.array([-1, 1, -1], np.float32), tris)
                 for n, c, pos, nrm, tris in parts]
        print("turned the model to face +x")
    for name, rgba, pos, nrm, tris in parts:
            lo, hi = np.minimum(lo, pos.min(0)), np.maximum(hi, pos.max(0))
            print(f"{name}: centroid {pos.mean(0).round(4).tolist()}")
            if name == split:
                # Sideways is the axis the wing pair is symmetric about: centroid nearest zero
                # relative to its spread. (Connected components fail here: a flat-shaded wing
                # sheet is two islands, top and bottom, and both wings share a root.)
                cens = pos[tris].mean(1)
                spread = np.maximum(cens.max(0) - cens.min(0), 1e-9)
                side = int(np.argmin(np.abs(cens.mean(0)) / spread))
                cen = cens[:, side]
                comp = [cen < 0, cen >= 0]
                print(f"split {name}: sideways axis {side}, pieces {[int(k.sum()) for k in comp]} tris")
                for tag, keep in (("L", comp[0]), ("R", comp[1])):
                    used = np.unique(tris[keep])
                    remap = {int(o): i for i, o in enumerate(used)}
                    sub = np.vectorize(remap.get)(tris[keep])
                    # Pivot at the wing root (the vertex nearest the body's midline): bake it
                    # as the prim's translation so rotating the prim flaps about the root.
                    rootpt = pos[used][np.argmin(np.abs(pos[used][:, side]))]
                    m = add_mesh(stage, "/Fly", f"{name}_{tag}", pos[used] - rootpt, nrm[used], sub, rgba)
                    m.AddTranslateOp().Set(Gf.Vec3d(*map(float, rootpt)))
            else:
                add_mesh(stage, "/Fly", name, pos, nrm, tris, rgba)
            print(f"{name}: {len(pos)} verts, {len(tris)} tris, colour {rgba[:3]}")
    stage.GetRootLayer().Save()
    print(f"bbox min {lo.round(3).tolist()} max {hi.round(3).tolist()} size {(hi - lo).round(3).tolist()}")
    ok = UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(dst.with_suffix(".usda"))), str(dst))
    print("usdz", "ok" if ok else "FAILED", dst, dst.stat().st_size if dst.exists() else "")


if __name__ == "__main__":
    main()
