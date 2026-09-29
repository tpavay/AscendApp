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
import subprocess
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
parser.add_argument("--size", default="regular", choices=["slim", "regular", "solid", "big"])
parser.add_argument("--definition", default="defined", choices=["smooth", "some", "defined"])
# The app's runtime pack: one mesh per body and size with no hair, plus one hair pack per body
# (scripts/athlete/build-ascend-athlete-pack.sh). The default writes one complete athlete.
parser.add_argument("--name", default="ascend-athlete", help="prefix of the .json and .bin written")
parser.add_argument("--texture-prefix", default=None, help="prefix of the textures written; the name by default")
parser.add_argument("--no-hair", action="store_true", help="leave the hair out; the app adds it from the hair pack")
parser.add_argument("--hair-pack", action="store_true", help="write every hairstyle as its own part, and nothing else")
args = parser.parse_args(argv)

BODY = {
    "male": {"file": "Superhero_Male_FullBody.gltf", "skin": "T_Superhero_Male_Dark.png", "normal": "T_Superhero_Male_Normal.png",
             "roughness": "T_Superhero_Male_Roughness.png", "hair": "Hair_SimpleParted",
             "skinLight": "T_Superhero_Male_Ligh.png", "browsSlot": "hair"},
    "female": {"file": "Superhero_Female_FullBody.gltf", "skin": "T_Superhero_Female_Dark_BaseColor.png", "normal": "T_Superhero_Female_Normal.png",
               "roughness": "T_Superhero_Female_Roughness.png", "hair": "Hair_Long",
               "skinLight": "T_Superhero_Female_Light_BaseColor.png", "browsSlot": "hair2"},
}[args.body]
HAIR = args.hair or BODY["hair"]
# The styles the editor offers, by the name the app stores, and the texture each is drawn from:
# the pack paints parted, buzzed and short from one hair texture, long and buns from the other.
HAIR_STYLES = {"parted": "Hair_SimpleParted", "long": "Hair_Long", "buns": "Hair_Buns",
               "buzzed": "Hair_Buzzed", "short": "Hair_BuzzedFemale"}
HAIR_SLOT = {"Hair_SimpleParted": "hair", "Hair_Buzzed": "hair", "Hair_BuzzedFemale": "hair",
             "Hair_Long": "hair2", "Hair_Buns": "hair2"}
TEXTURE_PREFIX = args.texture_prefix or args.name
BASE_DIR = os.path.join(args.pack, "Base Characters", "Godot - UE")
HAIR_DIR = os.path.join(args.pack, "Hairstyles", "Rigged to Head Bone", "glTF (Godot -Unreal)")
OPENGL_NORMALS = os.path.join(args.pack, "Base Characters", "Textures", "Normals Unity - Godot")

BODY_FILES = ["Superhero_Male_FullBody.gltf", "Superhero_Female_FullBody.gltf"]


def head_shape(body_file):
    """The body's skin as seen by the hair: its surface, where its Head joint sits, and the box
    round the points the head alone carries."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(BASE_DIR, body_file))
    skeleton = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    skin = next(o for o in skeleton.children if o.type == "MESH" and o.name.lower().startswith("superhero"))
    bm = bmesh.new()
    bm.from_mesh(skin.data)
    bm.transform(skin.matrix_world)
    bm.normal_update()
    group = skin.vertex_groups["Head"].index
    points = [skin.matrix_world @ v.co for v in skin.data.vertices
              if any(g.group == group and g.weight > 0.9 for g in v.groups)]
    return {
        "surface": BVHTree.FromBMesh(bm),
        "joint": skeleton.matrix_world @ skeleton.data.bones["Head"].head_local,
        "low": mathutils.Vector([min(p[i] for p in points) for i in range(3)]),
        "high": mathutils.Vector([max(p[i] for p in points) for i in range(3)]),
    }


# Each hairstyle is modelled on one body's head - parted and buzzed on the male, the rest on the
# female - so wearing it on the other body means refitting it to that head.
HEADS = {f: head_shape(f) for f in BODY_FILES}

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=os.path.join(BASE_DIR, BODY["file"]))
HAIR_FILES = list(HAIR_STYLES.values()) if args.hair_pack else ([] if args.no_hair else [HAIR])
for hair_file in HAIR_FILES:
    bpy.ops.import_scene.gltf(filepath=os.path.join(HAIR_DIR, hair_file + ".gltf"))

armatures = [o for o in bpy.data.objects if o.type == "ARMATURE"]
armature = next(a for a in armatures if any(c.type == "MESH" and c.name.lower().startswith("superhero") for c in a.children))
body = next(o for o in armature.children if o.type == "MESH" and o.name.lower().startswith("superhero"))
eyes = next(o for o in armature.children if o.type == "MESH" and o.name.startswith("Eyes"))
brows = next(o for o in armature.children if o.type == "MESH" and o.name.startswith("Eyebrows"))
# Exact names: "Hair_Buzzed" is a prefix of "Hair_BuzzedFemale".
hairs = {hair_file: next(o for o in bpy.data.objects
                         if o.type == "MESH" and o.name.split(".")[0] == hair_file and o.parent is not armature)
         for hair_file in HAIR_FILES}

HAIR_NEAR, HAIR_LOOSE = 0.015, 0.03  # metres off the scalp: held to it, and free of it


def refit_hair(hair, source, target):
    """Moves a hairstyle from the head it was modelled on to another: the heads' boxes are
    matched (crown to crown, the height scaled like the width and depth), then every strand near
    the scalp is set back to the distance it sat from the scalp it was made for, so a cap never
    sinks into the new head or lifts off it. That correction is feathered out to the loose ends
    and smoothed along the hair, so no strand kinks where it stops."""
    scale = [(target["high"][i] - target["low"][i]) / (source["high"][i] - source["low"][i]) for i in range(2)]
    scale.append(sum(scale) / 2)
    source_centre = (source["low"] + source["high"]) / 2
    target_centre = (target["low"] + target["high"]) / 2
    source_centre.z, target_centre.z = source["high"].z, target["high"].z

    to_world = hair.matrix_world.copy()
    mesh = hair.data
    # Hair is split along its texture seams; points that share a place move together.
    keys = [(round(v.co.x, 5), round(v.co.y, 5), round(v.co.z, 5)) for v in mesh.vertices]
    places = {k: to_world @ mesh.vertices[i].co for i, k in enumerate(keys)}
    moved, correction = {}, {}
    for k, p in places.items():
        q = target_centre + mathutils.Vector([(p[i] - source_centre[i]) * scale[i] for i in range(3)])
        hit, normal, _, _ = source["surface"].find_nearest(p)
        clearance = (p - hit).dot(normal)
        hold = min(max((HAIR_LOOSE - clearance) / (HAIR_LOOSE - HAIR_NEAR), 0.0), 1.0)
        if hold > 0:
            hit, normal, _, _ = target["surface"].find_nearest(q)
            correction[k] = normal * ((clearance - (q - hit).dot(normal)) * hold)
        moved[k] = q
    neighbours = {k: set() for k in places}
    for e in mesh.edges:
        a, b = keys[e.vertices[0]], keys[e.vertices[1]]
        if a != b:
            neighbours[a].add(b)
            neighbours[b].add(a)
    for _ in range(3):
        correction = {k: (correction.get(k, mathutils.Vector()) +
                          sum((correction.get(n, mathutils.Vector()) for n in neighbours[k]), mathutils.Vector())
                          / max(len(neighbours[k]), 1)) / 2
                      for k in places}
    from_world = to_world.inverted()
    for i, v in enumerate(mesh.vertices):
        v.co = from_world @ (moved[keys[i]] + correction[keys[i]])


def own_head(hair):
    skeleton = next(m.object for m in hair.modifiers if m.type == "ARMATURE")
    joint = skeleton.matrix_world @ skeleton.data.bones["Head"].head_local
    return next(f for f in BODY_FILES if (HEADS[f]["joint"] - joint).length < 0.001)


for hair in hairs.values():
    made_for = own_head(hair)
    if made_for != BODY["file"]:
        refit_hair(hair, HEADS[made_for], HEADS[BODY["file"]])

# Each hairstyle arrives on its own copy of the skeleton; move it onto the body's.
for hair in hairs.values():
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

# ---------- body size ----------

# Metres each part of the body swells per step of size, by bone; hands, feet and head stay put.
CARRY = {
    "pelvis": 0.022, "spine_01": 0.026, "spine_02": 0.018, "spine_03": 0.012, "neck_01": 0.007,
    "clavicle_l": 0.008, "clavicle_r": 0.008, "upperarm_l": 0.011, "upperarm_r": 0.011,
    "lowerarm_l": 0.006, "lowerarm_r": 0.006, "thigh_l": 0.02, "thigh_r": 0.02, "calf_l": 0.009, "calf_r": 0.009,
}
SIZE_STEPS = {"slim": -0.9, "regular": 0.0, "solid": 1.0, "big": 2.2}


def shape_body(steps):
    """Slims or fills out the body along its surface, carried by each point's bone weights so
    no seam opens where one limb hands over to the next; the front of the belly fills most."""
    if steps == 0:
        return
    mesh = body.data
    scale = max(v.co.z for v in mesh.vertices) / 1.81
    names = {g.index: g.name for g in body.vertex_groups}
    # The body is split along its texture seams; points that share a place share a normal.
    shared = {}
    for v in mesh.vertices:
        key = (round(v.co.x, 5), round(v.co.y, 5), round(v.co.z, 5))
        shared[key] = shared.get(key, mathutils.Vector()) + v.normal
    moves = []
    for v in mesh.vertices:
        carry = sum(g.weight * CARRY.get(names.get(g.group), 0.0) for g in v.groups)
        if carry == 0:
            continue
        normal = shared[(round(v.co.x, 5), round(v.co.y, 5), round(v.co.z, 5))].normalized()
        push = carry * steps
        if steps > 0 and normal.y < -0.25 and 0.9 * scale < v.co.z < 1.3 * scale:
            push *= 1 + 1.4 * (-normal.y)
        moves.append((v, normal * push))
    for v, move in moves:
        v.co += move
    if steps > 0:
        smooth_contours(mesh, names, iterations=int(round(4 * steps)))


def smooth_contours(mesh, names, iterations):
    """A fuller body hides the base body's sculpted muscle: relax the carrying parts toward
    their neighbours, on points shared across texture seams so nothing cracks open."""
    def key(v):
        return (round(v.co.x, 5), round(v.co.y, 5), round(v.co.z, 5))
    keys = [key(v) for v in mesh.vertices]
    points = {k: mesh.vertices[i].co.copy() for i, k in enumerate(keys)}
    weight = {}
    for i, v in enumerate(mesh.vertices):
        carry = sum(g.weight * CARRY.get(names.get(g.group), 0.0) for g in v.groups)
        weight[keys[i]] = max(weight.get(keys[i], 0.0), min(carry / 0.026, 1.0))
    neighbours = {k: set() for k in points}
    for e in mesh.edges:
        a, b = keys[e.vertices[0]], keys[e.vertices[1]]
        if a != b:
            neighbours[a].add(b)
            neighbours[b].add(a)
    for _ in range(iterations):
        moved = {}
        for k, p in points.items():
            w = weight.get(k, 0.0)
            if w == 0 or not neighbours[k]:
                continue
            average = sum((points[n] for n in neighbours[k]), mathutils.Vector()) / len(neighbours[k])
            moved[k] = p + (average - p) * 0.45 * w
        points.update(moved)
    for i, v in enumerate(mesh.vertices):
        v.co = points[keys[i]]


shape_body(SIZE_STEPS[args.size])

_skin = bmesh.new()
_skin.from_mesh(body.data)
_skin.normal_update()
SKIN = BVHTree.FromBMesh(_skin)


def keep_beneath(bm, points, clearance, rounds=4):
    """Lifts the garment in `bm` until every (point, normal) under it sits at least `clearance`
    beneath the fabric that faces the same way. Points by an opening are left alone."""
    for _ in range(rounds):
        bm.normal_update()
        bm.faces.ensure_lookup_table()
        tree = BVHTree.FromBMesh(bm)
        lift = {}
        for point, point_normal in points:
            hit, normal, index, _ = tree.find_nearest(point, 0.03)
            if hit is None:
                continue
            face = bm.faces[index]
            if any(e.is_boundary for e in face.edges) or face.normal.dot(point_normal) < 0.5:
                continue
            through = (point - hit).dot(normal) + clearance
            if through > 0:
                for v in face.verts:
                    lift[v] = max(lift.get(v, 0.0), through)
        if not lift:
            return
        for v, amount in lift.items():
            v.co += v.normal * amount


def garment(name, keep_face, offset, cuts=(), shape=None, over=None, relax=0):
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
    # The skin this garment is cut from, by index into the body - the copy shares its numbering.
    source = sorted({v.index for f in bm.faces if keep_face(f, dominant) for v in f.verts})
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if not keep_face(f, dominant)], context="FACES")
    # The body is split along its texture seams; a garment has no texture, so weld it whole. The
    # seams do not quite meet everywhere - the female chest is off by up to half a millimetre - and
    # an unwelded seam cracks open when the garment is pushed out along its normals.
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=5e-4)
    for point, normal in cuts:
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        bmesh.ops.bisect_plane(bm, geom=geom, plane_co=point, plane_no=normal, clear_outer=True)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    # Sawtooth left by whole-triangle selection becomes a clean seam.
    for _ in range(20):
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
    # Skin that follows the arm moves under the garment when the arm swings, so the garment sits
    # further off it there - up to three times as far where the arm carries the skin fully.
    deform = bm.verts.layers.deform.active
    arm_groups = {g.index for g in obj.vertex_groups if g.name in ARM_BONES}
    for v in bm.verts:
        arm = sum(w for gi, w in v[deform].items() if gi in arm_groups) if deform else 0.0
        v.co += v.normal * offset * (1 + 2 * min(arm, 1.0))
    # Pushed out along its normals, the surface folds over itself wherever the skin curves in -
    # between the breasts, under the arm. Fabric bridges those hollows instead; relaxing it does
    # the same, and the push-out below keeps it clear of the skin. Shorts stay unrelaxed, which
    # would pull them off the inner thigh.
    inside = [v for v in bm.verts if not v.is_boundary]
    for _ in range(relax):
        bmesh.ops.smooth_vert(bm, verts=inside, factor=0.5, use_axis_x=True, use_axis_y=True, use_axis_z=True)
    if shape:
        shape(bm)
    # Nothing may sink back under the skin: push every point out to at least most of the offset.
    for v in bm.verts:
        hit, normal, _, _ = SKIN.find_nearest(v.co)
        if hit is not None:
            gap = (v.co - hit).dot(normal)
            if gap < offset * 0.8:
                v.co += normal * (offset * 0.8 - gap)
    # And the other way round: fabric spans a small bump - a nipple - with a flat triangle, so the
    # bump's tip can come through between the garment's own points. Every point of the skin the
    # garment was cut from must stay half the offset beneath the fabric that faces the same way;
    # other skin - the neck, an arm, the opposite thigh - is not under it.
    _skin.verts.ensure_lookup_table()
    keep_beneath(bm, [(_skin.verts[i].co.copy(), _skin.verts[i].normal.copy()) for i in source], offset * 0.5)
    if over is not None:
        # A layer worn over another garment clears it the same two ways: its own points, then the
        # points of the layer beneath - a waistband would otherwise show through the hem.
        under = bmesh.new()
        under.from_mesh(over.data)
        under.normal_update()
        tree = BVHTree.FromBMesh(under)
        for v in bm.verts:
            hit, normal, _, _ = tree.find_nearest(v.co, 0.03)
            if hit is not None:
                gap = (v.co - hit).dot(normal)
                if gap < 0.004:
                    v.co += normal * (0.004 - gap)
        keep_beneath(bm, [(v.co.copy(), v.normal.copy()) for v in under.verts], 0.004)
        under.free()
    bm.to_mesh(mesh)
    bm.free()
    # The copy carries the body's imported custom normals, which no longer match the moved
    # surface - at the chest and the armpit they face away and shade as dark specks. A garment
    # shades from its own shape.
    if "custom_normal" in mesh.attributes:
        mesh.attributes.remove(mesh.attributes["custom_normal"])
    for poly in mesh.polygons:
        poly.use_smooth = True
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

# Where this body's arms and neck begin, measured at this size: the tank's armholes and neckline
# are cut to its own shoulders, so a narrower or fuller body gets a tank that fits it.
_dominant = dominant_bones(body)
ARM_START = min(abs(v.co.x) for v in body.data.vertices
                if _dominant[v.index] in ("upperarm_l", "upperarm_r") and 1.30 * k < v.co.z < 1.50 * k)
NECK_HALF_WIDTH = max(abs(v.co.x) for v in body.data.vertices
                      if _dominant[v.index] == "neck_01" and 1.50 * k < v.co.z < 1.60 * k)
# Heights (on the 1.81 m scale) where the neckline, front and back, and the armholes begin. The
# female base texture paints a sports bra, so her tank is cut higher to cover it.
TANK_CUT = {"male": {"front": 1.37, "back": 1.47, "armhole": 1.29},
            "female": {"front": 1.41, "back": 1.48, "armhole": 1.39}}[args.body]


def tank(face, dominant):
    c = centre(face)
    ax = abs(c.x)
    names = {dominant[v.index] for v in face.verts}
    if not names <= (TORSO_BONES | LEG_BONES | ARM_BONES | {"root"}):
        return False
    # The side of the chest can be weighted to the upper arm; dropping it would leave holes. A face
    # out past where the arm begins is the arm itself, unless it faces outward, as the side of the
    # torso under the armpit does, and has not yet reached the arm.
    if names & ARM_BONES and ax > 0.89 * ARM_START:
        facing_out = face.normal.x * (1 if c.x > 0 else -1)
        if facing_out < 0.5 or ax > ARM_START + 0.02:
            return False
    if c.z < 0.90 * k or "neck_01" in names:
        return False
    # A scooped neckline, lower in front than behind; deep armholes; and between them a strap
    # that runs up and over the top of each shoulder, where the body sits at about 1.52-1.56 m.
    back = c.y > 0
    if c.z > (TANK_CUT["back"] if back else TANK_CUT["front"]) * k and ax < 0.78 * NECK_HALF_WIDTH:
        return False
    if c.z > TANK_CUT["armhole"] * k and ax > 0.89 * ARM_START:
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
            v.co += v.normal * 0.009
            if v.co.z < 0.02 * k:
                v.co.z = -0.004
        for v in hull.verts:
            hit, normal, _, _ = SKIN.find_nearest(v.co)
            if hit is not None and (v.co - hit).dot(normal) < 0.01:
                v.co += normal * (0.01 - (v.co - hit).dot(normal))
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


if not args.hair_pack:
    bottom = garment("Shorts", shorts, 0.0075,
                     cuts=[(V((0, 0, 1.025 * k)), V((0, 0, 1))), (V((0, 0, 0.72 * k)), V((0, 0, -1)))], shape=flare)
    top = garment("Top", tank, 0.011, cuts=[(V((0, 0, 0.985 * k)), V((0, 0, -1)))], over=bottom, relax=3)
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


if args.hair_pack:
    for style, hair_file in HAIR_STYLES.items():
        add_part(hairs[hair_file], HAIR_SLOT[hair_file], f"hair.{style}")
else:
    add_part(body, "skin", "body")
    add_part(eyes, "eyes", "eyes")
    add_part(brows, BODY["browsSlot"], "brows")
    for hair_file, hair in hairs.items():
        add_part(hair, HAIR_SLOT.get(hair_file, "hair"), "hair")
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


prefix = TEXTURE_PREFIX


def defined_skin(source, name, size, fmt):
    """The skin textures carry the base body's baked muscle detail; a softer definition blurs
    that detail back toward flat before saving."""
    if args.definition == "defined":
        return save_texture(source, name, size, fmt)
    blur, keep = {"some": (4, 0.6), "smooth": (11, 0.3)}[args.definition]
    staged = os.path.join(args.out, f".{name}.staged.png")
    if "normal" in name:
        # Toward a flat normal map: less relief for the light to catch.
        subprocess.run(["magick", source, "-resize", f"{size}x{size}", "-blur", f"0x{blur}",
                        "(", "+clone", "-fill", "rgb(128,128,255)", "-colorize", "100", ")",
                        "-compose", "blend", "-define", f"compose:args={int(keep * 100)}", "-composite", staged], check=True)
    else:
        # Toward a blurred copy: the skin tone stays, the shading in the creases softens.
        subprocess.run(["magick", source, "-resize", f"{size}x{size}",
                        "(", "+clone", "-blur", f"0x{blur * 2}", ")",
                        "-compose", "blend", "-define", f"compose:args={int((1 - keep) * 100)}", "-composite", staged], check=True)
    result = save_texture(staged, name, size, fmt)
    os.remove(staged)
    return result


if args.hair_pack:
    textures = {
        "hair": {"baseColor": save_texture(os.path.join(BASE_DIR, "T_Hair_1_BaseColor.png"), f"{prefix}-hair.png", 512, "PNG")},
        "hair2": {"baseColor": save_texture(os.path.join(BASE_DIR, "T_Hair_2_BaseColor.png"), f"{prefix}-hair-2.png", 512, "PNG")},
    }
else:
    skin_normal = defined_skin(os.path.join(OPENGL_NORMALS, BODY["normal"]) if os.path.exists(os.path.join(OPENGL_NORMALS, BODY["normal"])) else os.path.join(BASE_DIR, BODY["normal"]), f"{prefix}-skin-normal.png", 1024, "PNG")
    skin_roughness = save_texture(os.path.join(BASE_DIR, BODY["roughness"]), f"{prefix}-skin-roughness.jpg", 512, "JPEG")
    textures = {
        "skin": {
            "baseColor": defined_skin(os.path.join(BASE_DIR, BODY["skin"]), f"{prefix}-skin.jpg", 1024, "JPEG"),
            "normal": skin_normal,
            "roughness": skin_roughness,
        },
        # The pack's lighter skin, on the same normal and roughness: the base for the lighter tones.
        "skinLight": {
            "baseColor": defined_skin(os.path.join(args.pack, "Base Characters", "Textures", BODY["skinLight"]), f"{prefix}-skin-light.jpg", 1024, "JPEG"),
            "normal": skin_normal,
            "roughness": skin_roughness,
        },
        "hair": {"baseColor": save_texture(os.path.join(BASE_DIR, "T_Hair_1_BaseColor.png"), f"{prefix}-hair.png", 512, "PNG")},
        "hair2": {"baseColor": save_texture(os.path.join(BASE_DIR, "T_Hair_2_BaseColor.png"), f"{prefix}-hair-2.png", 512, "PNG")},
        "eyes": {"baseColor": save_texture(os.path.join(BASE_DIR, "T_Eye_Brown.png"), f"{prefix}-eyes.jpg", 256, "JPEG")},
    }

header = {
    "format": "ascend-athlete-v2",
    "license": "CC0 1.0 - Quaternius, Universal Base Characters (Standard); kit modelled by scripts/athlete/build-ascend-athlete.py",
    "source": "https://quaternius.itch.io/universal-base-characters",
    "body": args.body,
    "hairStyle": "pack" if args.hair_pack else (None if args.no_hair else HAIR),
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
with open(os.path.join(args.out, f"{args.name}.json"), "w") as f:
    json.dump(header, f, indent=1)
    f.write("\n")
with open(os.path.join(args.out, f"{args.name}.bin"), "wb") as f:
    f.write(struct.pack(f"<{len(floats)}f", *floats))
    f.write(struct.pack(f"<{len(indices)}I", *indices))
print("athlete:", header["vertexCount"], "vertices,", header["indexCount"] // 3, "triangles,", len(joints), "joints, height", header["height"])
