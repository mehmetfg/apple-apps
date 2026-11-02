#!/usr/bin/env python3
"""Draws every keyframe of moves.json on one contact sheet (PNG), with the same kinematics as Figure.swift.
Use it to check a pose before it goes to the phone.

    python3 veri/preview.py [out.png]
"""
import json
import math
import pathlib
import sys

from PIL import Image, ImageDraw

HERE = pathlib.Path(__file__).resolve().parent
MOVES = HERE.parent / "ios" / "Gece" / "moves.json"

# Segment lengths (keep equal to Figure.swift)
TORSO, NECK, HEAD_R, UPPER_ARM, FOREARM, THIGH, SHIN, FOOT = 0.52, 0.07, 0.10, 0.30, 0.28, 0.42, 0.42, 0.13


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
    nose = (head[0] + HEAD_R * fx, head[1] + HEAD_R * fy)
    j = {"hip": (hx, hy), "sh": sh, "neck": neck, "head": head, "nose": nose}
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
    # spine control point: bend > 0 bulges to the back (torso + 90·facing)
    bx, by = unit(p["torso"] + 90 * fac)
    mid = ((hx + sh[0]) / 2 + p.get("bend", 0) * 2 * bx, (hy + sh[1]) / 2 + p.get("bend", 0) * 2 * by)
    j["spine"] = mid
    return j


def draw(d, p, props, ox, oy, s):
    def P(pt):
        return (ox + pt[0] * s, oy - pt[1] * s)
    j = joints(p)
    d.line([P((-0.6, 0)), P((1.3, 0))], fill=(150, 150, 150), width=2)
    if props.get("wall"):
        wx = props["wall"]
        d.line([P((wx, 0)), P((wx, 1.3))], fill=(150, 150, 150), width=3)
    if props.get("seat"):
        d.rectangle([P((-0.2, 0.40)), P((0.5, 0))], outline=(150, 150, 150), width=2)
    far, near = (120, 140, 190), (40, 60, 120)
    for side, col in (("F", far), ("N", near)):
        if side == "N":
            pts = [P(j["hip"])] + [P(bez(j["hip"], j["spine"], j["sh"], t / 10)) for t in range(1, 11)]
            d.line(pts, fill=near, width=9)
            d.line([P(j["sh"]), P(j["neck"])], fill=near, width=6)
            r = HEAD_R * s
            hx, hy = P(j["head"])
            d.ellipse([hx - r, hy - r, hx + r, hy + r], outline=near, width=4)
            nx, ny = P(j["nose"])
            d.ellipse([nx - 3, ny - 3, nx + 3, ny + 3], fill=(200, 80, 60))
        d.line([P(j["hip"]), P(j["knee" + side]), P(j["ankle" + side]), P(j["toe" + side])], fill=col, width=7)
        d.line([P(j["sh"]), P(j["elbow" + side]), P(j["hand" + side])], fill=col, width=6)
    if props.get("towel"):
        d.line([P(j["handN"]), P(j["toeN"])], fill=(200, 150, 60), width=2)


def bez(a, c, b, t):
    return ((1 - t) ** 2 * a[0] + 2 * (1 - t) * t * c[0] + t * t * b[0],
            (1 - t) ** 2 * a[1] + 2 * (1 - t) * t * c[1] + t * t * b[1])


def main():
    data = json.loads(MOVES.read_text(encoding="utf-8"))
    rows = data["moves"]
    cols = max(len(m["frames"]) for m in rows)
    W, H, s = 300, 260, 140
    img = Image.new("RGB", (cols * W, len(rows) * H), "white")
    d = ImageDraw.Draw(img)
    for r, m in enumerate(rows):
        for c, f in enumerate(m["frames"]):
            draw(d, pose_of(f, data["bases"]), m.get("props", {}), c * W + 90, r * H + 220, s)
            d.text((c * W + 6, r * H + 4), f"{m['id']} #{c}", fill=(0, 0, 0))
    out = sys.argv[1] if len(sys.argv) > 1 else "/tmp/gece-preview.png"
    img.save(out)
    print(out)


if __name__ == "__main__":
    main()
