# Builds the props Ascend Mountain scatters beside its stairs - a pine and a boulder - and writes
# them as flat-shaded triangle lists the app bakes into each course piece.
#
#   /Applications/Blender.app/Contents/MacOS/Blender -b --python scripts/mountain-art/build-mountain-props.py -- \
#     --out AscendApp/Features/AscendMountain/Resources
#
# The pine is modelled here: a tapered trunk under seven drooping, star-shaped tiers. The boulder
# is Poly Haven's CC0 boulder_01 scan, fetched with curl and reduced to a few hundred triangles.
# Output: `ascend-mountain-props.json` (which props, where) and `ascend-mountain-props.bin`
# (per triangle: three corners, x y z each, then the part index, all float32). Model space is
# metres, +Y up, the prop standing on y = 0.

import argparse
import json
import math
import os
import random
import struct
import subprocess
import sys
import tempfile

import bmesh
import bpy
import mathutils

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
parser = argparse.ArgumentParser()
parser.add_argument("--out", required=True)
args = parser.parse_args(argv)

Vector = mathutils.Vector


def pine():
    """A conifer about 3.6 m tall: part 0 is foliage, part 1 the trunk."""
    rng = random.Random(7)
    triangles = []

    def tri(a, b, c, part):
        triangles.append((a, b, c, part))

    # Trunk: a tapered seven-sided column.
    sides, height = 7, 1.5
    for i in range(sides):
        a0, a1 = 2 * math.pi * i / sides, 2 * math.pi * (i + 1) / sides
        b0, b1 = Vector((math.cos(a0) * 0.13, 0, math.sin(a0) * 0.13)), Vector((math.cos(a1) * 0.13, 0, math.sin(a1) * 0.13))
        t0, t1 = Vector((math.cos(a0) * 0.07, height, math.sin(a0) * 0.07)), Vector((math.cos(a1) * 0.07, height, math.sin(a1) * 0.07))
        tri(b0, t0, t1, 1)
        tri(b0, t1, b1, 1)

    # Tiers: star-shaped skirts, widest at the bottom, each point drooping below its base.
    tiers = 7
    for tier in range(tiers):
        f = tier / (tiers - 1)
        base = 0.62 + tier * 0.42
        radius = 1.08 * (1 - f * 0.78)
        rise = 0.78 - f * 0.18
        points = 11 - tier // 2
        spin = rng.random() * 2 * math.pi
        apex = Vector((0, base + rise, 0))
        centre = Vector((0, base + 0.08, 0))
        outer, inner = [], []
        for p in range(points):
            a = spin + 2 * math.pi * (p + rng.uniform(-0.12, 0.12)) / points
            r = radius * rng.uniform(0.88, 1.08)
            outer.append(Vector((math.cos(a) * r, base - 0.16 * rng.uniform(0.7, 1.2), math.sin(a) * r)))
            b = spin + 2 * math.pi * (p + 0.5) / points
            inner.append(Vector((math.cos(b) * radius * 0.62, base + 0.05, math.sin(b) * radius * 0.62)))
        for p in range(points):
            o, i, o2 = outer[p], inner[p], outer[(p + 1) % points]
            tri(o, apex, i, 0)
            tri(i, apex, o2, 0)
            tri(o, i, centre, 0)
            tri(i, o2, centre, 0)
    tip = Vector((0, 0.62 + tiers * 0.42 + 0.55, 0))
    top = 0.62 + (tiers - 1) * 0.42 + 0.35
    for p in range(5):
        a0, a1 = 2 * math.pi * p / 5, 2 * math.pi * (p + 1) / 5
        tri(Vector((math.cos(a0) * 0.16, top, math.sin(a0) * 0.16)), tip, Vector((math.cos(a1) * 0.16, top, math.sin(a1) * 0.16)), 0)
    return triangles


def boulder(workdir):
    """Poly Haven's boulder_01, reduced, about a metre across and sunk a fifth into the ground."""
    info = json.loads(subprocess.run(["curl", "-fsSL", "https://api.polyhaven.com/files/boulder_01"], capture_output=True, check=True).stdout)
    gltf = info["gltf"]["1k"]["gltf"]
    path = os.path.join(workdir, "boulder_01.gltf")
    subprocess.run(["curl", "-fsSL", "-o", path, gltf["url"]], check=True)
    for rel, item in gltf["include"].items():
        target = os.path.join(workdir, rel)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        subprocess.run(["curl", "-fsSL", "-o", target, item["url"]], check=True)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    rock = max((o for o in bpy.data.objects if o.type == "MESH"), key=lambda o: len(o.data.polygons))
    bm = bmesh.new()
    bm.from_mesh(rock.data)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    world = rock.matrix_world
    # Blender is Z-up; the app is Y-up.
    points = [world @ v.co for v in bm.verts]
    points = [Vector((p.x, p.z, -p.y)) for p in points]
    lo = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    hi = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    size = max(hi.x - lo.x, hi.z - lo.z)
    scale = 1.0 / size
    centre = Vector(((lo.x + hi.x) / 2, lo.y, (lo.z + hi.z) / 2))
    sink = 0.2 * (hi.y - lo.y) * scale
    points = [(p - centre) * scale - Vector((0, sink, 0)) for p in points]

    # Vertex clustering: every point snaps to its cell's average, and triangles that collapse go.
    cell = 1.0 / 7.5
    cluster_of, sums = [], {}
    for p in points:
        key = (math.floor(p.x / cell), math.floor(p.y / cell), math.floor(p.z / cell))
        cluster_of.append(key)
        total, count = sums.get(key, (Vector(), 0))
        sums[key] = (total + p, count + 1)
    centres = {key: total / count for key, (total, count) in sums.items()}
    seen, triangles = set(), []
    for face in bm.faces:
        keys = [cluster_of[v.index] for v in face.verts]
        if len(set(keys)) < 3:
            continue
        ordered = tuple(sorted(keys))
        if ordered in seen:
            continue
        seen.add(ordered)
        triangles.append((centres[keys[0]], centres[keys[1]], centres[keys[2]], 0))
    bm.free()
    return triangles


with tempfile.TemporaryDirectory() as workdir:
    props = {"pine": pine(), "boulder": boulder(workdir)}

floats = []
header = {"format": "ascend-props-v1", "props": []}
for name, triangles in props.items():
    header["props"].append({"name": name, "firstTriangle": len(floats) // 10, "triangleCount": len(triangles)})
    for a, b, c, part in triangles:
        floats.extend([a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z, float(part)])
header["license"] = "pine modelled by this script; boulder from Poly Haven boulder_01, CC0 1.0"
os.makedirs(args.out, exist_ok=True)
with open(os.path.join(args.out, "ascend-mountain-props.json"), "w") as f:
    json.dump(header, f, indent=1)
    f.write("\n")
with open(os.path.join(args.out, "ascend-mountain-props.bin"), "wb") as f:
    f.write(struct.pack(f"<{len(floats)}f", *floats))
print("props:", {p["name"]: p["triangleCount"] for p in header["props"]})
