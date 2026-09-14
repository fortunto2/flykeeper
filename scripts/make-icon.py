#!/usr/bin/env python3
"""Build Resources/App.icon (Icon Composer layered format) and the legacy 1024 PNG.

    python3 scripts/make-icon.py [--render]

The mark: the fly seen from above, its head and thorax glowing with the same heat ramp the
brain uses in the app (violet → orange → white). Drawn here rather than in a GUI so the icon
is regenerated when the look changes, not redrawn from memory.

Format rules (measured, see the apple-app-icon skill's references/icon-json.md):
groups draw front to back, `fill` works on a layer and is ignored on a group, a colour is
`display-p3:r,g,b,a`, and the background belongs in the document's two-colour `fill` so the
system can dim it for Dark — a background *layer* it cannot dim, and the mark goes rainbow.
"""
import json
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
ICON = ROOT / "Resources" / "App.icon"
ICTOOL = pathlib.Path("/Applications/Xcode.app/Contents/Applications/Icon Composer.app"
                      "/Contents/Executables/ictool")
C = 1024.0


def ellipse(cx, cy, rx, ry, rot=0.0):
    """An ellipse as a path: two arcs. ictool fills contours and ignores strokes."""
    import math
    a = math.radians(rot)
    ca, sa = math.cos(a), math.sin(a)
    def p(dx, dy):
        return f"{cx + dx * ca - dy * sa:.1f},{cy + dx * sa + dy * ca:.1f}"
    return (f"M {p(-rx, 0)} A {rx:.1f},{ry:.1f} {rot:.1f} 1,0 {p(rx, 0)} "
            f"A {rx:.1f},{ry:.1f} {rot:.1f} 1,0 {p(-rx, 0)} Z")


def svg(paths: list[str], fill: str) -> str:
    body = "".join(f'<path d="{d}" fill="{fill}" fill-rule="evenodd"/>' for d in paths)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {C:.0f} {C:.0f}" '
            f'width="{C:.0f}" height="{C:.0f}">{body}</svg>')


# The fly head-on from above: two big red compound eyes with the brain glowing between them,
# which is where a fly's brain actually is. Eyes in front of everything — they are the one
# feature that reads as "fly" at 60 points.
HEAD = ellipse(512, 336, 196, 148)
THORAX = ellipse(512, 524, 152, 148)
ABDOMEN = ellipse(512, 748, 166, 200)
WINGS = [ellipse(292, 578, 208, 80, -34), ellipse(732, 578, 208, 80, 34)]
EYES = [ellipse(394, 320, 96, 116, -10), ellipse(630, 320, 96, 116, 10)]
# The brain, seen in the gap between the eyes and spreading back into the thorax.
GLOW_CORE = [ellipse(512, 344, 76, 98)]
GLOW_MID = [ellipse(512, 452, 116, 128)]

# Groups draw front to back, and a build fails above **four visible groups** ("Too many
# visible groups", from the asset compiler, not from ictool — which renders five happily).
# So the two glow layers share one group; layers inside a group draw front to back as well.
GROUPS = [
    ("Eyes", [("eyes.svg", EYES, "#FF2E2E", "Eyes")]),
    ("Brain", [("glow-core.svg", GLOW_CORE, "#FFF6DC", "Glow core"),
               ("glow-mid.svg", GLOW_MID, "#FF8A2A", "Glow")]),
    ("Body", [("body.svg", [HEAD, THORAX, ABDOMEN], "#241A2E", "Body")]),
    ("Wings", [("wings.svg", WINGS, "#CFE8FF", "Wings")]),
]

def main() -> None:
    if ICON.exists():
        shutil.rmtree(ICON)
    assets = ICON / "Assets"
    assets.mkdir(parents=True)
    groups = []
    for group, layers in GROUPS:
        entries = []
        for name, paths, fill, label in layers:
            (assets / name).write_text(svg(paths, fill))
            entries.append({"image-name": name, "name": label})
        groups.append({
            "layers": entries,
            "shadow": {"kind": "neutral", "opacity": 0.35 if group == "Body" else 0.0},
            "specular": group in ("Body", "Wings"),
            "translucency": {"enabled": False, "value": 0.0},
        })
    document = {
        # Two stops only, on purpose: the system can dim a document fill for Dark, and cannot
        # dim a background layer. Night sky, so the glow is the brightest thing on the tile.
        "fill": {"linear-gradient": ["display-p3:0.09,0.07,0.17,1", "display-p3:0.02,0.02,0.05,1"]},
        "groups": groups,
        "supported-platforms": {"squares": ["iOS", "macOS"]},
    }
    (ICON / "icon.json").write_text(json.dumps(document, indent=2))
    print(f"wrote {ICON.relative_to(ROOT)} · {len(groups)} groups")

    if "--render" in sys.argv:
        if not ICTOOL.exists():
            sys.exit(f"ictool not found at {ICTOOL}")
        out = ROOT / "build" / "icon-preview"
        out.mkdir(parents=True, exist_ok=True)
        for r in ("Default", "Dark", "TintedLight", "TintedDark", "ClearLight", "ClearDark"):
            f = out / f"{r}.png"
            subprocess.run([str(ICTOOL), str(ICON), "--export-image", "--output-file", str(f),
                            "--platform", "iOS", "--rendition", r,
                            "--width", "512", "--height", "512", "--scale", "1"], check=True)
        # The legacy 1024 for iOS < 26, which has no layered icon: same artwork, flattened.
        legacy = ROOT / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
        legacy.mkdir(parents=True, exist_ok=True)
        subprocess.run([str(ICTOOL), str(ICON), "--export-image",
                        "--output-file", str(legacy / "icon-1024.png"),
                        "--platform", "iOS", "--rendition", "Default",
                        "--width", "1024", "--height", "1024", "--scale", "1"], check=True)
        (legacy / "Contents.json").write_text(json.dumps({
            "images": [{"filename": "icon-1024.png", "idiom": "universal",
                        "platform": "ios", "size": "1024x1024"}],
            "info": {"author": "xcode", "version": 1},
        }, indent=2))
        (ROOT / "Resources" / "Assets.xcassets" / "Contents.json").write_text(json.dumps(
            {"info": {"author": "xcode", "version": 1}}, indent=2))
        print(f"rendered six appearances into {out.relative_to(ROOT)} and the legacy 1024")


if __name__ == "__main__":
    main()
