"""Renders the photo strip of every move: a wooden artist's mannequin posed by moves.json, two or three key
frames per move, studio light, 3/4 side view. Same kinematics as Figure.swift and preview.py.

    /Applications/Blender.app/Contents/MacOS/Blender -b -P veri/photos.py -- [move_id ...]

Writes ios/Gece/Photos/<id>-<n>.jpg (n = 1, 2, 3) and ios/Gece/Photos/photos.json (which frames were used).
"""
import json
import math
import pathlib
import sys

import bpy
from mathutils import Vector

HERE = pathlib.Path(__file__).resolve().parent
GECE = HERE.parent / "ios" / "Gece"
MOVES = GECE / "moves.json"
OUT = GECE / "Photos"

TORSO, NECK, HEAD_R, UPPER_ARM, FOREARM, THIGH, SHIN, FOOT = 0.52, 0.07, 0.10, 0.30, 0.28, 0.42, 0.42, 0.13
SHOULDER_HALF, HIP_HALF = 0.165, 0.085      # depth offsets of the near/far limbs (near = toward the camera)
W, H = 900, 640
SAMPLES = 96


# ---------- kinematics (same as preview.py) ----------

def pose_of(frame, bases):
    p = dict(bases[frame["base"]]) if "base" in frame else {}
    p.update({k: v for k, v in frame.items() if k not in ("base", "d")})
    return p


def unit(a):
    r = math.radians(a)
    return math.cos(r), math.sin(r)


def joints(p):
    sc = p.get("scale", {})
    fac = p.get("facing", 1)
    hx, hy = p["hip"]
    tx, ty = unit(p["torso"])
    sh = (hx + TORSO * tx, hy + TORSO * ty)
    gx, gy = unit(p["head"])
    neck = (sh[0] + NECK * gx, sh[1] + NECK * gy)
    head = (neck[0] + HEAD_R * gx, neck[1] + HEAD_R * gy)
    fx, fy = unit(p["head"] - 90 * fac)
    j = {"hip": (hx, hy), "sh": sh, "neck": neck, "head": head, "face": (fx, fy)}
    for side in "NF":
        a = p["arm" + side]
        s = sc.get("arm" + side, [1, 1])
        e = (sh[0] + UPPER_ARM * s[0] * unit(a[0])[0], sh[1] + UPPER_ARM * s[0] * unit(a[0])[1])
        h = (e[0] + FOREARM * s[1] * unit(a[1])[0], e[1] + FOREARM * s[1] * unit(a[1])[1])
        l = p["leg" + side]
        s = sc.get("leg" + side, [1, 1])
        k = (hx + THIGH * s[0] * unit(l[0])[0], hy + THIGH * s[0] * unit(l[0])[1])
        an = (k[0] + SHIN * s[1] * unit(l[1])[0], k[1] + SHIN * s[1] * unit(l[1])[1])
        fa = p.get("foot" + side, l[1] + 90 * fac)
        toe = (an[0] + FOOT * unit(fa)[0], an[1] + FOOT * unit(fa)[1])
        j.update({"elbow" + side: e, "hand" + side: h, "knee" + side: k, "ankle" + side: an, "toe" + side: toe})
    bx, by = unit(p["torso"] + 90 * fac)
    j["spine"] = ((hx + sh[0]) / 2 + p.get("bend", 0) * 2 * bx, (hy + sh[1]) / 2 + p.get("bend", 0) * 2 * by)
    j["back"] = (bx, by)
    return j


def bez(a, c, b, t):
    return ((1 - t) ** 2 * a[0] + 2 * (1 - t) * t * c[0] + t * t * b[0],
            (1 - t) ** 2 * a[1] + 2 * (1 - t) * t * c[1] + t * t * b[1])


def V(pt, y=0.0):
    """Figure (x, up) → Blender (x, depth, z). Depth −y is toward the camera."""
    return Vector((pt[0], y, pt[1]))


# ---------- scene ----------

def material(name, color, rough=0.5, sheen=0.0, coat=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = rough
    if coat:
        b.inputs["Coat Weight"].default_value = coat
    if sheen:
        b.inputs["Sheen Weight"].default_value = sheen
    return m


def wood():
    m = bpy.data.materials.new("wood")
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Roughness"].default_value = 0.42
    b.inputs["Coat Weight"].default_value = 0.25
    tex = nt.nodes.new("ShaderNodeTexWave")
    tex.wave_type = "RINGS"
    tex.inputs["Scale"].default_value = 2.2
    tex.inputs["Distortion"].default_value = 6
    tex.inputs["Detail"].default_value = 3
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (0.50, 0.31, 0.17, 1)
    ramp.color_ramp.elements[1].color = (0.60, 0.40, 0.23, 1)
    nt.links.new(tex.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], b.inputs["Base Color"])
    return m


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = SAMPLES
    sc.cycles.use_denoising = True
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = "METAL"
        prefs.get_devices()
        for d in prefs.devices:
            d.use = True
        sc.cycles.device = "GPU"
    except Exception:
        pass
    sc.render.resolution_x, sc.render.resolution_y = W, H
    sc.render.image_settings.file_format = "JPEG"
    sc.render.image_settings.quality = 82
    sc.view_settings.view_transform = "AgX"
    sc.view_settings.look = "AgX - Medium High Contrast"
    world = bpy.data.worlds.new("w")
    sc.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.012, 0.016, 0.035, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
    return sc


def cap(a, b, r, mat, r2=None):
    """A tapered limb between two points: a cone/cylinder plus round ends."""
    a, b = Vector(a), Vector(b)
    d = b - a
    L = d.length
    if L < 1e-4:
        return
    bpy.ops.mesh.primitive_cone_add(vertices=32, radius1=r, radius2=r2 or r, depth=L, location=(a + b) / 2)
    o = bpy.context.object
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = d.to_track_quat("Z", "Y")
    o.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    for p, rr in ((a, r), (b, r2 or r)):
        ball(p, rr * 1.0, mat)


def ball(p, r, mat, scale=(1, 1, 1), rot=None):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, radius=r, location=p)
    o = bpy.context.object
    o.scale = scale
    if rot is not None:
        o.rotation_mode = "QUATERNION"
        o.rotation_quaternion = rot
    o.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    return o


def joint(p, r, mat):
    ball(p, r, mat)


def box(lo, hi, mat, bevel=0.03):
    lo, hi = Vector(lo), Vector(hi)
    bpy.ops.mesh.primitive_cube_add(location=(lo + hi) / 2)
    o = bpy.context.object
    o.scale = (hi - lo) / 2
    bpy.ops.object.transform_apply(scale=True)
    m = o.modifiers.new("b", "BEVEL")
    m.width = bevel
    m.segments = 4
    o.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    return o


def figure(j, mats, towel=False):
    w, jt = mats["wood"], mats["joint"]
    # spine: chest and pelvis as ellipsoids along the curve, a waist between
    pts = [bez(j["hip"], j["spine"], j["sh"], t / 12) for t in range(13)]
    def along(i):
        a, b = Vector((pts[max(0, i - 1)][0], 0, pts[max(0, i - 1)][1])), Vector((pts[min(12, i + 1)][0], 0, pts[min(12, i + 1)][1]))
        return (b - a).to_track_quat("Z", "Y")
    pel = pts[2]
    ball(V(pel), 0.085, w, scale=(1.0, 1.6, 1.15), rot=along(2))
    ch = pts[9]
    ball(V(ch), 0.10, w, scale=(1.0, 1.55, 1.55), rot=along(9))
    for i in range(3, 8):
        ball(V(pts[i]), 0.068, w, scale=(1, 1.7, 1), rot=along(i))
    # neck and head
    cap(V(j["sh"]), V(j["neck"]), 0.04, w)
    hdir = V(j["head"]) - V(j["neck"])
    ball(V(j["head"]), HEAD_R * 0.95, w, scale=(0.92, 0.88, 1.15), rot=hdir.to_track_quat("Z", "Y"))
    # nose hint: a tiny bump so the face direction reads
    f = j["face"]
    ball(V((j["head"][0] + f[0] * HEAD_R * 0.95, j["head"][1] + f[1] * HEAD_R * 0.95)), 0.022, w)
    # limbs, far side first
    for side, y in (("F", 1), ("N", -1)):
        sy, hy = SHOULDER_HALF * y, HIP_HALF * y
        shp = V(j["sh"], sy * 0.85)
        joint(shp, 0.05, jt)
        cap(shp, V(j["elbow" + side], sy), 0.043, w, 0.036)
        joint(V(j["elbow" + side], sy), 0.037, jt)
        cap(V(j["elbow" + side], sy), V(j["hand" + side], sy), 0.034, w, 0.027)
        ball(V(j["hand" + side], sy), 0.045, w, scale=(1, 0.6, 1))
        hp = V(j["hip"], hy)
        joint(hp, 0.07, jt)
        cap(hp, V(j["knee" + side], hy), 0.065, w, 0.048)
        joint(V(j["knee" + side], hy), 0.05, jt)
        cap(V(j["knee" + side], hy), V(j["ankle" + side], hy), 0.046, w, 0.034)
        joint(V(j["ankle" + side], hy), 0.035, jt)
        cap(V(j["ankle" + side], hy), V(j["toe" + side], hy), 0.035, w, 0.028)
    if towel:
        cap(V(j["handN"], -SHOULDER_HALF), V(j["toeN"], -HIP_HALF), 0.012, mats["towel"])
        cap(V(j["handF"], SHOULDER_HALF), V(j["toeN"], -HIP_HALF), 0.012, mats["towel"])


def props_and_room(props, mats, xr):
    x0, x1 = xr
    # floor mat on a dark floor, a soft backdrop far behind
    box((x0 - 3, -3, -0.05), (x1 + 3, 4, 0.0), mats["floor"], bevel=0.0)
    if not props.get("seat"):
        box((x0 - 0.25, -0.45, 0.0), (x1 + 0.25, 0.45, 0.012), mats["mat"], bevel=0.006)
    if props.get("seat"):   # the edge of the bed
        box((-1.1, -0.9, 0.0), (0.42, 1.0, 0.40), mats["bed"], bevel=0.06)
    if props.get("cushion"):
        box((-0.05, -0.25, 0.0), (0.22, 0.25, 0.06), mats["cushion"], bevel=0.025)
    if props.get("wall"):
        wx = props["wall"]
        box((wx, -0.7, 0.0), (wx + 0.25, 2.5, 2.4), mats["wall"], bevel=0.0)
    box((x0 - 4, 1.6, 0.0), (x1 + 4, 1.8, 3.0), mats["back"], bevel=0.0)


def lights(center):
    def area(loc, energy, size, color=(1, 1, 1)):
        bpy.ops.object.light_add(type="AREA", location=loc)
        l = bpy.context.object
        l.data.energy = energy
        l.data.size = size
        l.data.color = color
        d = Vector(center) - Vector(loc)
        l.rotation_mode = "QUATERNION"
        l.rotation_quaternion = d.to_track_quat("-Z", "Y")
    c = Vector(center)
    area(c + Vector((-1.6, -2.4, 2.2)), 140, 2.2, (1.0, 0.86, 0.70))     # warm key, front-left
    area(c + Vector((2.2, -1.2, 1.0)), 30, 2.5, (0.70, 0.80, 1.0))      # cool fill
    area(c + Vector((0.6, 2.0, 2.4)), 110, 1.5, (0.75, 0.80, 1.0))       # rim from behind


def camera(bmin, bmax, flip=False):
    c = (bmin + bmax) / 2
    span_x, span_z = bmax.x - bmin.x, bmax.z - bmin.z
    aspect = W / H
    size = max(span_x, span_z * aspect) * 1.18 + 0.15
    cam = bpy.data.cameras.new("cam")
    cam.type = "ORTHO"
    cam.ortho_scale = size
    o = bpy.data.objects.new("cam", cam)
    bpy.context.scene.collection.objects.link(o)
    az, el = math.radians(22 if flip else -22), math.radians(14)
    dist = 8
    loc = c + Vector((math.sin(az) * dist * math.cos(el) * -1, -math.cos(az) * dist * math.cos(el), math.sin(el) * dist))
    o.location = loc
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = (c - loc).to_track_quat("-Z", "Y")
    bpy.context.scene.camera = o
    return c


# ---------- frame choice ----------

def flat(p):
    j = joints(p)
    return [v for k, pt in j.items() if k not in ("face", "back") for v in pt]


def pick(frames_p, n=3):
    """Farthest-point choice of key frames, then put back in loop order."""
    if len(frames_p) <= n:
        return list(range(len(frames_p)))
    vs = [flat(p) for p in frames_p]
    def d(a, b):
        return math.sqrt(sum((x - y) ** 2 for x, y in zip(vs[a], vs[b])))
    chosen = [0]
    while len(chosen) < n:
        best = max((i for i in range(len(vs)) if i not in chosen), key=lambda i: min(d(i, c) for c in chosen))
        if min(d(best, c) for c in chosen) < 0.06:
            break
        chosen.append(best)
    return sorted(chosen)


def main():
    data = json.loads(MOVES.read_text(encoding="utf-8"))
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    OUT.mkdir(exist_ok=True)
    index_path = OUT / "photos.json"
    index = json.loads(index_path.read_text()) if index_path.exists() else {}
    for m in data["moves"]:
        if only and m["id"] not in only:
            continue
        poses = [pose_of(f, data["bases"]) for f in m["frames"]]
        keys = m.get("photoFrames") or pick(poses, 3)
        # one framing for the whole strip so the frames line up
        allj = [joints(poses[k]) for k in keys]
        pts = [V(pt) for jj in allj for k, pt in jj.items() if k not in ("face", "back", "spine")]
        bmin = Vector((min(p.x for p in pts) - 0.15, 0, min(0.0, min(p.z for p in pts)) - 0.02))
        bmax = Vector((max(p.x for p in pts) + 0.15, 0, max(p.z for p in pts) + 0.14))
        props = m.get("props", {})
        if props.get("wall"):
            bmax.x = max(bmax.x, props["wall"] + 0.1)
        for n, k in enumerate(keys, 1):
            reset()
            mats = {
                "wood": wood(), "joint": material("joint", (0.30, 0.18, 0.10), 0.35, coat=0.3),
                "floor": material("floor", (0.02, 0.022, 0.035), 0.8), "mat": material("mat", (0.05, 0.11, 0.22), 0.9, sheen=0.4),
                "bed": material("bed", (0.16, 0.17, 0.22), 0.95, sheen=0.8), "cushion": material("cushion", (0.5, 0.42, 0.62), 0.9, sheen=0.6),
                "wall": material("wall", (0.20, 0.22, 0.28), 0.9), "back": material("back", (0.02, 0.025, 0.05), 1.0),
                "towel": material("towel", (0.85, 0.62, 0.25), 0.9),
            }
            props_and_room(props, mats, (bmin.x, bmax.x))
            figure(allj[n - 1], mats, towel=props.get("towel", False))
            c = camera(bmin, bmax, flip=bool(props.get("wall")))
            lights(c)
            bpy.context.scene.render.filepath = str(OUT / f"{m['id']}-{n}.jpg")
            bpy.ops.render.render(write_still=True)
        index[m["id"]] = {"frames": keys, "count": len(keys)}
        print("rendered", m["id"], keys, flush=True)
    index_path.write_text(json.dumps(index, indent=1, ensure_ascii=False))


main()
