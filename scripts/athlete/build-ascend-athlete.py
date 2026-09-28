# Builds the Ascend Mountain athlete from Quaternius's CC0 Universal Base Characters.
#
#   /Applications/Blender.app/Contents/MacOS/Blender -b --python scripts/athlete/build-ascend-athlete.py -- \
#     --pack "<dir>/Universal Base Characters[Standard]" \
#     --out AscendApp/Features/AscendMountain/Resources
#
# The pack is the free Standard edition (CC0 1.0), downloaded from
# https://quaternius.itch.io/universal-base-characters with "Download Now" and a price of $0;
# itch.io serves it only through a browser. Blender 5.2 or later.
#
# The script models the Ascend kit - a fitted tank, running shorts and trainers - out of the
# body's own surface, so every garment is skinned to the same skeleton and bends with it, then
# writes `ascend-athlete.json` (skeleton, parts, materials, poser roles), `ascend-athlete.bin`
# (interleaved vertices and indices) and the textures `MountainAthleteAsset` reads.
#
# Model space is metres, +Y up, the athlete standing on y = 0 and facing +Z. Vertices are in the
# rest pose and every inverse bind matrix is the inverse of its joint's rest frame.

import argparse
import json
import math
import os
import struct
import sys

import bmesh
import bpy
import mathutils
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
parser = argparse.ArgumentParser()
parser.add_argument("--pack", required=True)
parser.add_argument("--out", required=True)
parser.add_argument("--body", default="male", choices=["male", "female"])
parser.add_argument("--hair", default=None)
args = parser.parse_args(argv)

BODY = {
    "male": {"file": "Superhero_Male_FullBody.gltf", "skin": "T_Superhero_Male_Dark.png", "normal": "T_Superhero_Male_Normal.png",
             "roughness": "T_Superhero_Male_Roughness.png", "hair": "Hair_SimpleParted"},
    "female": {"file": "Superhero_Female_FullBody.gltf", "skin": "T_Superhero_Female_Dark_BaseColor.png", "normal": "T_Superhero_Female_Normal.png",
               "roughness": "T_Superhero_Female_Roughness.png", "hair": "Hair_Long"},
}[args.body]
HAIR = args.hair or BODY["hair"]
BASE_DIR = os.path.join(args.pack, "Base Characters", "Godot - UE")
HAIR_DIR = os.path.join(args.pack, "Hairstyles", "Rigged to Head Bone", "glTF (Godot -Unreal)")
OPENGL_NORMALS = os.path.join(args.pack, "Base Characters", "Textures", "Normals Unity - Godot")

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=os.path.join(BASE_DIR, BODY["file"]))
bpy.ops.import_scene.gltf(filepath=os.path.join(HAIR_DIR, HAIR + ".gltf"))

armatures = [o for o in bpy.data.objects if o.type == "ARMATURE"]
armature = next(a for a in armatures if any(c.type == "MESH" and c.name.lower().startswith("superhero") for c in a.children))
body = next(o for o in armature.children if o.type == "MESH" and o.name.lower().startswith("superhero"))
eyes = next(o for o in armature.children if o.type == "MESH" and o.name.startswith("Eyes"))
brows = next(o for o in armature.children if o.type == "MESH" and o.name.startswith("Eyebrows"))
hair = next(o for o in bpy.data.objects if o.type == "MESH" and o.name.startswith(HAIR))

# The hair arrives on its own copy of the skeleton; move it onto the body's.
world = hair.matrix_world.copy()
hair.parent = armature
hair.matrix_world = world
for modifier in hair.modifiers:
    if modifier.type == "ARMATURE":
        modifier.object = armature

bones = list(armature.data.bones)
bone_index = {b.name: i for i, b in enumerate(bones)}


def dominant_bones(obj):
    """Each vertex's heaviest bone name."""
    names = {g.index: g.name for g in obj.vertex_groups}
    result = []
    for v in obj.data.vertices:
        best = max(v.groups, key=lambda g: g.weight, default=None)
        result.append(names.get(best.group) if best else None)
    return result


# ---------- the kit, modelled from the body's surface ----------

_skin = bmesh.new()
_skin.from_mesh(body.data)
SKIN = BVHTree.FromBMesh(_skin)


def garment(name, keep_face, offset, cuts=(), shape=None, over=None):
    """Copies the body faces `keep_face` accepts into a new skinned mesh, trims it with straight
    `cuts` (point, normal: everything on the normal's side goes), smooths its edges, and pushes
    it out along the surface by `offset` metres so it sits on the skin without touching it."""
    dominant = dominant_bones(body)
    mesh = body.data.copy()
    obj = body.copy()
    obj.data = mesh
    obj.name = name
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if not keep_face(f, dominant)], context="FACES")
    # The body is split along its texture seams; a garment has no texture, so weld it whole.
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-5)
    for point, normal in cuts:
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        bmesh.ops.bisect_plane(bm, geom=geom, plane_co=point, plane_no=normal, clear_outer=True)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    # Sawtooth left by whole-triangle selection becomes a clean seam.
    for _ in range(12):
        moves = {}
        for v in bm.verts:
            if not v.is_boundary:
                continue
            ring = [e.other_vert(v) for e in v.link_edges if e.is_boundary]
            if len(ring) == 2:
                moves[v] = v.co * 0.5 + (ring[0].co + ring[1].co) * 0.25
        for v, co in moves.items():
            v.co = co
    bm.normal_update()
    for v in bm.verts:
        v.co += v.normal * offset
    if shape:
        shape(bm)
    # Nothing may sink back under the skin: push every point out to at least most of the offset.
    for v in bm.verts:
        hit, normal, _, _ = SKIN.find_nearest(v.co)
        if hit is not None:
            gap = (v.co - hit).dot(normal)
            if gap < offset * 0.8:
                v.co += normal * (offset * 0.8 - gap)
    if over is not None:
        # A layer worn over another garment clears it, not just the skin.
        under = bmesh.new()
        under.from_mesh(over.data)
        tree = BVHTree.FromBMesh(under)
        for v in bm.verts:
            hit, normal, _, _ = tree.find_nearest(v.co, 0.03)
            if hit is not None:
                gap = (v.co - hit).dot(normal)
                if gap < 0.004:
                    v.co += normal * (0.004 - gap)
        under.free()
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.clear()
    return obj


def centre(face):
    return sum((v.co for v in face.verts), mathutils.Vector()) / len(face.verts)


ARM_BONES = {"upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r", "hand_l", "hand_r"}
TORSO_BONES = {"pelvis", "spine_01", "spine_02", "spine_03", "clavicle_l", "clavicle_r", "neck_01"}
LEG_BONES = {"thigh_l", "thigh_r"}
FOOT_BONES = {"foot_l", "foot_r", "ball_l", "ball_r", "ball_leaf_l", "ball_leaf_r", "calf_l", "calf_r"}

# Heights on the 1.81 m male base; scaled for any other body.
height = max(v.co.z for v in body.data.vertices)
k = height / 1.81
V = mathutils.Vector


def tank(face, dominant):
    c = centre(face)
    names = {dominant[v.index] for v in face.verts}
    if names & ARM_BONES or not names <= (TORSO_BONES | LEG_BONES | {"root"}):
        return False
    if c.z < 0.90 * k or c.z > 1.50 * k:
        return False
    ax = abs(c.x)
    # A scooped neckline front and back, straps over the shoulders, deep armholes.
    if c.z > 1.37 * k and ax < 0.072:
        return False
    if c.z > 1.29 * k and ax > 0.150:
        return False
    return True


def shorts(face, dominant):
    c = centre(face)
    names = {dominant[v.index] for v in face.verts}
    return names <= (LEG_BONES | {"pelvis", "spine_01"}) and 0.60 * k < c.z < 1.08 * k


def flare(bm):
    """Running shorts hang loose below the hip."""
    for v in bm.verts:
        drop = max(0.0, 0.86 * k - v.co.z)
        if drop > 0:
            side = 1 if v.co.x > 0 else -1
            axis = V((side * 0.10 * k, 0.0, v.co.z))
            out = (v.co - axis)
            out.z = 0
            if out.length > 1e-6:
                v.co += out.normalized() * drop * 0.16


def trainers():
    """A trainer is the smooth closed shell around each foot - its convex hull, rounded and
    given a flat sole - so no toe can show through, skinned from the nearest foot vertex."""
    dominant = dominant_bones(body)
    groups = {g.index: g.name for g in body.vertex_groups}
    mesh = bpy.data.meshes.new("Shoes")
    obj = bpy.data.objects.new("Shoes", mesh)
    bpy.context.collection.objects.link(obj)
    obj.parent = armature
    for g in body.vertex_groups:
        obj.vertex_groups.new(name=g.name)
    obj.modifiers.new("Armature", "ARMATURE").object = armature
    out = bmesh.new()
    deform = out.verts.layers.deform.verify()
    for side in ("l", "r"):
        bones_here = {f"foot_{side}", f"ball_{side}", f"ball_leaf_{side}", f"calf_{side}"}
        source = [v for v in body.data.vertices if dominant[v.index] in bones_here and v.co.z < 0.115 * k]
        tree = KDTree(len(source))
        for i, v in enumerate(source):
            tree.insert(v.co, i)
        tree.balance()
        hull = bmesh.new()
        for v in source:
            hull.verts.new(v.co)
        result = bmesh.ops.convex_hull(hull, input=hull.verts[:])
        bmesh.ops.delete(hull, geom=[g for g in result["geom_interior"] if isinstance(g, bmesh.types.BMVert)], context="VERTS")
        bmesh.ops.subdivide_edges(hull, edges=hull.edges[:], cuts=2, use_grid_fill=True)
        bmesh.ops.triangulate(hull, faces=hull.faces[:])
        for _ in range(4):
            bmesh.ops.smooth_vert(hull, verts=hull.verts[:], factor=0.6, use_axis_x=True, use_axis_y=True, use_axis_z=True)
        hull.normal_update()
        for v in hull.verts:
            v.co += v.normal * 0.006
            if v.co.z < 0.02 * k:
                v.co.z = -0.004
        for v in hull.verts:
            hit, normal, _, _ = SKIN.find_nearest(v.co)
            if hit is not None and (v.co - hit).dot(normal) < 0.006:
                v.co += normal * (0.006 - (v.co - hit).dot(normal))
        index_map = {}
        for v in hull.verts:
            nv = out.verts.new(v.co)
            _, nearest, _ = tree.find(v.co)
            for g in source[nearest].groups:
                nv[deform][g.group] = g.weight
            index_map[v] = nv
        for f in hull.faces:
            out.faces.new([index_map[v] for v in f.verts])
        hull.free()
    bmesh.ops.recalc_face_normals(out, faces=out.faces[:])
    out.to_mesh(mesh)
    out.free()
    for poly in mesh.polygons:
        poly.use_smooth = True
    return obj


bottom = garment("Shorts", shorts, 0.0075,
                 cuts=[(V((0, 0, 1.025 * k)), V((0, 0, 1))), (V((0, 0, 0.72 * k)), V((0, 0, -1)))], shape=flare)
top = garment("Top", tank, 0.011, cuts=[(V((0, 0, 0.985 * k)), V((0, 0, -1)))], over=bottom)
shoe = trainers()

# ---------- export ----------

AXES = mathutils.Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, -1, 0, 0), (0, 0, 0, 1)))  # Blender Z-up, -Y front -> +Y up, +Z front


def joint_frame(bone):
    m = AXES @ armature.matrix_world @ bone.matrix_local
    loc, rot, _ = m.decompose()
    return mathutils.Matrix.LocRotScale(loc, rot, None)


frames = [joint_frame(b) for b in bones]
joints = []
for i, bone in enumerate(bones):
    parent = bone_index[bone.parent.name] if bone.parent else -1
    local = frames[i] if parent < 0 else frames[parent].inverted() @ frames[i]
    loc, rot, _ = local.decompose()
    inverse = frames[i].inverted()
    joints.append({
        "name": bone.name,
        "parent": parent,
        "translation": [round(x, 6) for x in loc],
        "rotation": [round(rot.x, 6), round(rot.y, 6), round(rot.z, 6), round(rot.w, 6)],
        "scale": [1, 1, 1],
        # Column-major, as simd_float4x4 is built from columns.
        "inverseBind": [round(inverse[r][c], 6) for c in range(4) for r in range(4)],
    })

floats = []
indices = []
parts = []


def add_part(obj, slot, name, material_filter=None):
    mesh = obj.data
    mesh.calc_loop_triangles()
    uv_layer = mesh.uv_layers[0].data if mesh.uv_layers else None
    group_bone = {g.index: bone_index.get(g.name) for g in obj.vertex_groups}
    to_model = AXES @ obj.matrix_world
    normal_matrix = to_model.to_3x3().inverted().transposed()
    corner_normals = mesh.corner_normals
    vertex_start = len(floats) // 16
    index_start = len(indices)
    seen = {}
    for tri in mesh.loop_triangles:
        if material_filter is not None and not material_filter(tri):
            continue
        corners = []
        for loop_index, vertex_index in zip(tri.loops, tri.vertices):
            uv = tuple(uv_layer[loop_index].uv) if uv_layer else (0.0, 0.0)
            n = corner_normals[loop_index].vector
            key = (vertex_index, round(uv[0], 5), round(uv[1], 5), round(n.x, 3), round(n.y, 3), round(n.z, 3))
            if key not in seen:
                v = mesh.vertices[vertex_index]
                p = to_model @ v.co
                nn = (normal_matrix @ n).normalized()
                weights = sorted(((g.weight, group_bone.get(g.group)) for g in v.groups if group_bone.get(g.group) is not None and g.weight > 0),
                                 reverse=True)[:4]
                total = sum(w for w, _ in weights) or 1.0
                weights = [(w / total, b) for w, b in weights] + [(0.0, 0)] * (4 - len(weights))
                seen[key] = len(floats) // 16
                floats.extend([p.x, p.y, p.z, nn.x, nn.y, nn.z, uv[0], uv[1]])
                floats.extend([float(b) for _, b in weights])
                floats.extend([w for w, _ in weights])
            corners.append(seen[key])
        indices.extend(corners)
    parts.append({
        "name": name,
        "slot": slot,
        "vertexStart": vertex_start,
        "vertexCount": len(floats) // 16 - vertex_start,
        "indexStart": index_start,
        "indexCount": len(indices) - index_start,
    })


def sole(obj):
    mesh = obj.data
    return lambda tri: (AXES.to_3x3() @ (obj.matrix_world.to_3x3() @ tri.normal)).y < -0.55


add_part(body, "skin", "body")
add_part(eyes, "eyes", "eyes")
add_part(brows, "hair", "brows")
add_part(hair, "hair", "hair")
add_part(top, "top", "top")
add_part(bottom, "bottom", "shorts")
soles = sole(shoe)
add_part(shoe, "shoe", "shoe-upper", lambda tri: not soles(tri))
add_part(shoe, "shoeAccent", "shoe-sole", soles)

os.makedirs(args.out, exist_ok=True)


def save_texture(source, name, size, fmt):
    image = bpy.data.images.load(source)
    if image.size[0] > size:
        image.scale(size, size)
    image.filepath_raw = os.path.join(args.out, name)
    image.file_format = fmt
    if fmt == "JPEG":
        bpy.context.scene.render.image_settings.quality = 88
    image.save()
    return name


prefix = "ascend-athlete"
textures = {
    "skin": {
        "baseColor": save_texture(os.path.join(BASE_DIR, BODY["skin"]), f"{prefix}-skin.jpg", 1024, "JPEG"),
        "normal": save_texture(os.path.join(OPENGL_NORMALS, BODY["normal"]) if os.path.exists(os.path.join(OPENGL_NORMALS, BODY["normal"])) else os.path.join(BASE_DIR, BODY["normal"]), f"{prefix}-skin-normal.png", 1024, "PNG"),
        "roughness": save_texture(os.path.join(BASE_DIR, BODY["roughness"]), f"{prefix}-skin-roughness.jpg", 512, "JPEG"),
    },
    "hair": {"baseColor": save_texture(os.path.join(BASE_DIR, "T_Hair_1_BaseColor.png"), f"{prefix}-hair.png", 512, "PNG")},
    "eyes": {"baseColor": save_texture(os.path.join(BASE_DIR, "T_Eye_Brown.png"), f"{prefix}-eyes.jpg", 256, "JPEG")},
}

header = {
    "format": "ascend-athlete-v2",
    "license": "CC0 1.0 - Quaternius, Universal Base Characters (Standard); kit modelled by scripts/athlete/build-ascend-athlete.py",
    "source": "https://quaternius.itch.io/universal-base-characters",
    "body": args.body,
    "hairStyle": HAIR,
    "height": round(max(p for i, p in enumerate(floats) if i % 16 == 1), 6),
    "vertexLayout": "positions f32x3, normals f32x3, uv f32x2, joints f32x4, weights f32x4 (interleaved, 16 floats); indices u32 absolute",
    "vertexCount": len(floats) // 16,
    "indexCount": len(indices),
    "roles": {
        "body": "pelvis",
        "spine": ["spine_01", "spine_02", "spine_03"],
        "neck": "neck_01",
        "head": "Head",
        "legs": [["thigh_l", "calf_l", "foot_l"], ["thigh_r", "calf_r", "foot_r"]],
        "arms": [["upperarm_l", "lowerarm_l", "hand_l"], ["upperarm_r", "lowerarm_r", "hand_r"]],
    },
    "textures": textures,
    "joints": joints,
    "parts": parts,
}
with open(os.path.join(args.out, f"{prefix}.json"), "w") as f:
    json.dump(header, f, indent=1)
    f.write("\n")
with open(os.path.join(args.out, f"{prefix}.bin"), "wb") as f:
    f.write(struct.pack(f"<{len(floats)}f", *floats))
    f.write(struct.pack(f"<{len(indices)}I", *indices))
print("athlete:", header["vertexCount"], "vertices,", header["indexCount"] // 3, "triangles,", len(joints), "joints, height", header["height"])
