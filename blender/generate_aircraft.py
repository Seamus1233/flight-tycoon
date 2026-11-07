"""
Procedural Blender generator for every aircraft in data/aircraft.json.

Runs either inside Blender:
    blender --background --python blender/generate_aircraft.py -- [options]
or with the standalone `bpy` module:
    python -m pip install bpy   (Python 3.11)
    python blender/generate_aircraft.py [options]

Options:
    --only f22,p51     build only these ids
    --no-export        skip FBX/OBJ export
    --sheet PATH       render a contact sheet of all aircraft to PATH (PNG)
    --hero ID PATH     render a single close-up render

Output (per aircraft) in models/<id>/:
    <id>.fbx   - three meshes: Body, Canopy, Detail (import into Roblox Studio)
    <id>.obj   - same geometry as OBJ + MTL
    <id>.blend - the editable source

Coordinate convention: nose points +Y, up is +Z, right wing is +X. The FBX
exporter maps +Y -> -Z, which is Roblox's forward (LookVector) direction.
"""
import json
import math
import os
import sys

import bpy  # must be imported before bmesh/mathutils when using the bpy module
import bmesh
from mathutils import Matrix, Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ----------------------------------------------------------------------------- helpers

def argv():
    a = sys.argv
    return a[a.index("--") + 1:] if "--" in a else a[1:]


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name, rgb, metallic=0.3, rough=0.45, alpha=1.0, emission=None):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    p = m.node_tree.nodes.get("Principled BSDF")
    p.inputs["Base Color"].default_value = (*rgb, 1)
    p.inputs["Metallic"].default_value = metallic
    p.inputs["Roughness"].default_value = rough
    if alpha < 1:
        p.inputs["Alpha"].default_value = alpha
    if emission:
        p.inputs["Emission Color"].default_value = (*emission, 1)
        p.inputs["Emission Strength"].default_value = 3.0
    m.diffuse_color = (*rgb, 1)
    return m


class Builder:
    """Accumulates geometry into three bmeshes (body, canopy, detail)."""

    def __init__(self):
        self.bm = {"Body": bmesh.new(), "Canopy": bmesh.new(), "Detail": bmesh.new()}

    # --- primitives -----------------------------------------------------------
    def loft(self, part, rings, cap_start=True, cap_end=True):
        """rings: list of lists of Vector (same count). Builds a closed tube."""
        bm = self.bm[part]
        vrings = [[bm.verts.new(v) for v in ring] for ring in rings]
        n = len(rings[0])
        for a, b in zip(vrings, vrings[1:]):
            for i in range(n):
                j = (i + 1) % n
                bm.faces.new((a[i], a[j], b[j], b[i]))
        if cap_start:
            bm.faces.new(list(reversed(vrings[0])))
        if cap_end:
            bm.faces.new(vrings[-1])

    def box_panel(self, part, root_le, root_chord, tip_le, tip_chord, root_t, tip_t, up=Vector((0, 0, 1))):
        """Tapered aerofoil-ish slab. root_le/tip_le are leading-edge points;
        chord runs toward -Y. `up` is the thickness direction."""
        def section(le, chord, t):
            te = le + Vector((0, -chord, 0))
            mid = le + Vector((0, -chord * 0.3, 0))
            return [le, mid + up * (t / 2), te, mid - up * (t / 2)]
        self.loft(part, [section(root_le, root_chord, root_t), section(tip_le, tip_chord, tip_t)])

    def fin(self, part, base_le, root_chord, tip_chord, height, sweep_deg, thick, cant_deg=0.0, side=1):
        """Vertical (or canted) tail fin rising from base_le."""
        cant = math.radians(cant_deg) * side
        upv = Vector((math.sin(cant), 0, math.cos(cant)))
        tip_le = base_le + upv * height + Vector((0, -height * math.tan(math.radians(sweep_deg)), 0))
        sidev = Vector((math.cos(cant), 0, -math.sin(cant)))
        def section(le, chord, t):
            te = le + Vector((0, -chord, 0))
            mid = le + Vector((0, -chord * 0.35, 0))
            return [le, mid + sidev * (t / 2), te, mid - sidev * (t / 2)]
        self.loft(part, [section(base_le, root_chord, thick), section(tip_le, tip_chord, thick * 0.5)])

    def cylinder(self, part, start, end, r0, r1=None, segs=12, cap=True):
        r1 = r0 if r1 is None else r1
        axis = (end - start).normalized()
        ref = Vector((0, 0, 1)) if abs(axis.z) < 0.9 else Vector((1, 0, 0))
        u = axis.cross(ref).normalized()
        v = axis.cross(u).normalized()
        def ring(c, r):
            return [c + (u * math.cos(a) + v * math.sin(a)) * r
                    for a in (2 * math.pi * i / segs for i in range(segs))]
        self.loft(part, [ring(start, r0), ring(end, r1)], cap, cap)

    def ellipsoid(self, part, center, rx, ry, rz, segs=12, rings=8):
        bm = self.bm[part]
        geom = bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0)
        verts = geom["verts"]
        bmesh.ops.transform(bm, matrix=Matrix.Translation(center) @ Matrix.Diagonal((rx, ry, rz, 1)), verts=verts)

    def propeller(self, center, radius, blades=3):
        self.ellipsoid("Detail", center + Vector((0, radius * 0.08, 0)), radius * 0.14, radius * 0.28, radius * 0.14)
        for b in range(blades):
            a = 2 * math.pi * b / blades
            d = Vector((math.cos(a), 0, math.sin(a)))
            w = Vector((-math.sin(a), 0, math.cos(a)))
            p0 = center + d * radius * 0.12
            p1 = center + d * radius
            bm = self.bm["Detail"]
            q = [p0 + w * radius * 0.07, p1 + w * radius * 0.04, p1 - w * radius * 0.04, p0 - w * radius * 0.07]
            front = [bm.verts.new(x + Vector((0, 0.03 * radius, 0))) for x in q]
            back = [bm.verts.new(x - Vector((0, 0.03 * radius, 0))) for x in q]
            bm.faces.new(front)
            bm.faces.new(list(reversed(back)))
            for i in range(4):
                j = (i + 1) % 4
                bm.faces.new((front[i], back[i], back[j], front[j]))

    # --- output ---------------------------------------------------------------
    def to_objects(self, name, mats):
        objs = []
        for part, bm in self.bm.items():
            if not bm.verts:
                continue
            bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
            me = bpy.data.meshes.new(f"{name}_{part}")
            bm.to_mesh(me)
            bm.free()
            for poly in me.polygons:
                poly.use_smooth = part != "Detail"
            ob = bpy.data.objects.new(part, me)
            ob.data.materials.append(mats[part])
            bpy.context.scene.collection.objects.link(ob)
            objs.append(ob)
        return objs


# ----------------------------------------------------------------------------- aircraft

def fuselage_profile(t, nose):
    """Radius factor along the fuselage, t = 0 tail .. 1 nose."""
    if t < 0.12:
        r = 0.55 + 0.45 * (t / 0.12)
    elif t < 0.62:
        r = 1.0
    else:
        k = (t - 0.62) / 0.38
        if nose == "pointed":
            r = 1.0 - 0.95 * k ** 1.6
        elif nose == "chine":
            r = 1.0 - 0.97 * k ** 1.3
        elif nose == "intake":
            r = 1.0 - 0.25 * k
        elif nose == "blunt":
            r = 1.0 - 0.55 * k ** 3
        else:  # prop / round
            r = math.sqrt(max(0.0, 1.0 - max(0.0, k - 0.55) ** 2 / 0.45 ** 2)) * 0.9 + 0.1 * (1 - k)
    return max(r, 0.04)


def build_fuselage(b, a, L, R, y0=None, length=None):
    length = length or L
    y0 = -length / 2 if y0 is None else y0
    chine = a["nose"] == "chine" or a["special"] == "stealth_facet"
    segs = 6 if a["special"] == "stealth_facet" else (10 if chine else 14)
    sx, sz = (1.45, 0.62) if chine else (1.0, 1.0)
    rings = []
    steps = 22
    for i in range(steps + 1):
        t = i / steps
        r = R * fuselage_profile(t, a["nose"])
        y = y0 + t * length
        # nose droops slightly, tail rises slightly
        zc = R * 0.15 * (t - 0.5) * (-1 if a["props"] == 0 else 0)
        ring = []
        for s in range(segs):
            ang = 2 * math.pi * s / segs + (math.pi / segs if a["special"] == "stealth_facet" else 0)
            ring.append(Vector((math.cos(ang) * r * sx, y, zc + math.sin(ang) * r * sz)))
        rings.append(ring)
    b.loft("Body", rings)
    return y0, length


def wing_geometry(a, L, R):
    S = a["S"]
    taper = a["taper"]
    delta = taper < 0.15
    half = S / 2
    exposed = half - R * 0.5
    if delta:
        c_root = L * (0.48 if a["tail"] in ("delta", "none") else 0.40)
    else:
        mean = S / 6.2 if a["props"] or a["sweep"] < 15 else S / 4.0
        c_root = min(L * 0.38, 2 * mean / (1 + taper))
    c_tip = c_root * taper
    return half, exposed, c_root, c_tip


def build_wings(b, a, L, R, root_le_y):
    half, exposed, c_root, c_tip = wing_geometry(a, L, R)
    z = {"low": -R * 0.55, "mid": 0.0, "high": R * 0.6}[a["wing"]]
    sweep = math.radians(a["sweep"])
    dih = math.radians(a["dihedral"])
    t_root = max(c_root * 0.07, R * 0.12)
    gull = a["id"] == "f4u"
    for side in (1, -1):
        root = Vector((side * R * 0.5, root_le_y, z))
        if gull:  # inverted gull: down then up
            kink = root + Vector((side * exposed * 0.33, -exposed * 0.33 * math.tan(sweep), -R * 0.45))
            k_chord = c_root - (c_root - c_tip) * 0.33
            tip = kink + Vector((side * exposed * 0.67, -exposed * 0.67 * math.tan(sweep), exposed * 0.67 * math.sin(math.radians(9))))
            b.box_panel("Body", root, c_root, kink, k_chord, t_root, t_root * 0.8)
            b.box_panel("Body", kink, k_chord, tip, c_tip, t_root * 0.8, t_root * 0.45)
        else:
            tip = root + Vector((side * exposed, -exposed * math.tan(sweep), exposed * math.sin(dih)))
            b.box_panel("Body", root, c_root, tip, max(c_tip, 0.15), t_root, t_root * 0.4)
    return dict(half=half, exposed=exposed, c_root=c_root, c_tip=c_tip, z=z, root_le_y=root_le_y,
                sweep=sweep, dih=dih)


def wing_point(w, side, frac):
    """Leading-edge point at fraction of exposed span (side=+1 right)."""
    d = w["exposed"] * frac
    chord = w["c_root"] + (w["c_tip"] - w["c_root"]) * frac
    p = Vector((side * (d + 0.0), w["root_le_y"] - d * math.tan(w["sweep"]), w["z"] + d * math.sin(w["dih"])))
    return p, chord


def build_tail(b, a, L, R, tail_y, cfg_sweep):
    tail = a["tail"]
    if tail == "none":
        return
    fin_h = L * (0.17 if a["props"] == 0 else 0.15)
    fin_root = L * 0.17
    fin_sweep = max(25, a["sweep"] + 8) if a["props"] == 0 else 20
    thick = fin_root * 0.08
    top = R * 0.75
    if tail in ("conv", "t", "delta"):
        b.fin("Body", Vector((0, tail_y + fin_root, top * 0.8)), fin_root, fin_root * 0.4, fin_h, fin_sweep, thick)
    elif tail in ("twin", "canted"):
        cant = 22 if tail == "canted" else 4
        for side in (1, -1):
            b.fin("Body", Vector((side * R * 0.85, tail_y + fin_root, top * 0.6)), fin_root * 0.95, fin_root * 0.35,
                  fin_h * 0.85, fin_sweep, thick, cant, side)
    if tail == "delta":
        return
    hs_half = a["S"] * (0.20 if a["props"] else 0.24)
    hs_chord = fin_root * 0.85
    hs_sweep = math.radians(max(0, a["sweep"] * 0.9 if a["props"] == 0 else 2))
    if a["special"] == "stealth_facet":
        return
    if tail == "t":
        z = top * 0.8 + fin_h
        le_y = tail_y + fin_root - fin_h * math.tan(math.radians(fin_sweep))
    else:
        z = 0.1 * R
        le_y = tail_y + hs_chord
    for side in (1, -1):
        root = Vector((side * R * 0.3, le_y, z))
        tip = root + Vector((side * hs_half, -hs_half * math.tan(hs_sweep), 0))
        b.box_panel("Body", root, hs_chord, tip, hs_chord * 0.45, hs_chord * 0.08, hs_chord * 0.05)
    if tail == "hbox":  # A-10 style fins on the stabiliser tips
        for side in (1, -1):
            base = Vector((side * (R * 0.3 + hs_half), le_y - hs_half * math.tan(hs_sweep), z - fin_h * 0.35))
            b.fin("Body", base, hs_chord * 0.9, hs_chord * 0.7, fin_h * 0.9, 5, thick)


def build_canopy(b, a, L, R, y_front_frac=0.30):
    if a["special"] == "flying_wing":
        return
    bomber = "Bomber" in a["role"] or a["L"] > 22
    if bomber:
        cy = L / 2 - L * 0.10
        b.ellipsoid("Canopy", Vector((0, cy, R * 0.55)), R * 0.55, L * 0.06, R * 0.38)
    else:
        cy = L / 2 - L * y_front_frac
        k = 1.35 if a["props"] else 1.0
        b.ellipsoid("Canopy", Vector((0, cy, R * 0.7)), R * 0.36 * k, L * 0.075 * k, R * 0.38 * k)


def build_aircraft(a):
    L = a["L"]
    S = a["S"]
    big = a["L"] > 22 or "Bomber" in a["role"]
    R = L * (0.072 if a["props"] else (0.058 if big else 0.062))
    if a["id"] in ("p47", "f4u", "fw190"):
        R *= 1.12
    b = Builder()
    special = a["special"]

    if special == "flying_wing":
        # One big swept wing with a blended centre body and sawtooth trailing edge.
        c_root = L
        half = S / 2
        sweep = math.radians(a["sweep"])
        t = c_root * 0.11
        for side in (1, -1):
            root = Vector((0, L / 2, 0))
            mid = root + Vector((side * half * 0.35, -half * 0.35 * math.tan(sweep), 0))
            tip = root + Vector((side * half, -half * math.tan(sweep), 0))
            b.box_panel("Body", root, c_root, mid, c_root * 0.42, t, t * 0.45)
            b.box_panel("Body", mid, c_root * 0.42, tip, c_root * 0.08, t * 0.45, t * 0.15)
        b.ellipsoid("Body", Vector((0, L * 0.12, t * 0.3)), half * 0.13, L * 0.38, t * 0.75)
        b.ellipsoid("Canopy", Vector((0, L * 0.34, t * 0.75)), half * 0.05, L * 0.05, t * 0.18)
        for side in (1, -1):  # dorsal engine intakes
            b.ellipsoid("Detail", Vector((side * half * 0.1, L * 0.05, t * 0.55)), half * 0.035, L * 0.1, t * 0.2)
        if a["canard"]:
            pass
        return b

    if special == "twin_boom":
        boom_x = S * 0.17
        # central nacelle
        build_fuselage(b, a, L, R * 0.85, y0=-L * 0.05, length=L * 0.55)
        w = build_wings(b, a, L, R * 0.85, root_le_y=L * 0.12)
        for side in (1, -1):
            x = side * boom_x
            b.cylinder("Body", Vector((x, L * 0.42, 0)), Vector((x, -L / 2 + L * 0.06, 0.1)), R * 0.62, R * 0.25, 12)
            b.ellipsoid("Body", Vector((x, L * 0.42, 0)), R * 0.62, R * 0.9, R * 0.62)
            b.propeller(Vector((x, L * 0.42 + R * 0.95, 0)), S * 0.11)
            b.fin("Body", Vector((x, -L / 2 + L * 0.22, R * 0.2)), L * 0.17, L * 0.12, L * 0.17, 10, L * 0.012)
        b.box_panel("Body", Vector((-boom_x, -L / 2 + L * 0.2, 0.1)), L * 0.12,
                    Vector((boom_x, -L / 2 + L * 0.2, 0.1)), L * 0.12, L * 0.012, L * 0.012,
                    up=Vector((0, 0, 1)))
        b.ellipsoid("Canopy", Vector((0, L * 0.3, R * 0.65)), R * 0.45, L * 0.07, R * 0.45)
        return b

    y0, length = build_fuselage(b, a, L, R)

    # wing placement
    half, exposed, c_root, c_tip = wing_geometry(a, L, R)
    if c_root > L * 0.35:      # delta: wing runs to the tail
        root_le_y = -L / 2 + c_root + L * 0.04
    elif a["props"]:
        root_le_y = L * 0.22
    else:
        root_le_y = c_root * 0.5 + L * 0.02
    w = build_wings(b, a, L, R, root_le_y)

    # chines / blackbird body
    if special == "blackbird":
        for side in (1, -1):
            root = Vector((side * R * 0.9, L * 0.45, 0))
            tip = Vector((side * (R * 0.9 + S * 0.05), w["root_le_y"], 0))
            b.box_panel("Body", root, L * 0.05, tip, (L * 0.45 - w["root_le_y"]) + L * 0.05, R * 0.12, R * 0.12)
            # nacelles mid-wing with canted fins
            nx = side * S * 0.24
            ny0 = w["root_le_y"] - (S * 0.24) * math.tan(w["sweep"]) + L * 0.12
            b.cylinder("Body", Vector((nx, ny0, 0)), Vector((nx, -L / 2 + L * 0.02, 0)), R * 0.75, R * 0.6, 14)
            b.ellipsoid("Detail", Vector((nx, ny0, 0)), R * 0.3, R * 1.2, R * 0.3)
            b.fin("Body", Vector((nx, -L / 2 + L * 0.2, R * 0.6)), L * 0.14, L * 0.07, L * 0.12, 40, L * 0.01, 15, -side)
    elif a["nose"] == "chine":
        for side in (1, -1):
            root = Vector((side * R * 0.8, L * 0.38, 0))
            tip = Vector((side * R * 1.25, w["root_le_y"], 0))
            b.box_panel("Body", root, L * 0.02, tip, L * 0.38 - w["root_le_y"] + L * 0.02, R * 0.08, R * 0.08)

    # canards
    if a["canard"]:
        cy = L * 0.22
        for side in (1, -1):
            root = Vector((side * R * 0.75, cy, R * 0.2))
            tip = root + Vector((side * S * 0.16, -S * 0.16 * math.tan(math.radians(48)), S * 0.01))
            b.box_panel("Body", root, L * 0.1, tip, L * 0.03, L * 0.008, L * 0.005)

    tail_y = -L / 2 + L * 0.02
    build_tail(b, a, L, R, tail_y, a["sweep"])
    build_canopy(b, a, L, R, 0.22 if a["props"] else 0.25)

    # propellers
    if a["props"] == 1:
        b.propeller(Vector((0, L / 2 + R * 0.05, 0)), S * 0.17 if a["id"] != "f4u" else S * 0.2)
    elif a["props"] >= 2:
        fracs = [0.28, 0.58] if a["props"] == 4 else [0.3]
        for side in (1, -1):
            for fr in fracs:
                p, chord = wing_point(w, side, fr)
                start = p + Vector((0, chord * 0.55, -R * 0.05))
                b.cylinder("Body", start, p + Vector((0, -chord * 0.8, 0)), R * 0.42, R * 0.25, 12)
                b.propeller(start + Vector((0, R * 0.1, 0)), S * 0.065)

    # podded jets under wings
    if a["pods"] and special != "blackbird":
        if a["pods"] == 2:
            fracs = [0.32] if a["id"] != "b1b" else [0.12]
        else:
            fracs = [0.25, 0.55]
        for side in (1, -1):
            for fr in fracs:
                p, chord = wing_point(w, side, fr)
                pr = R * (0.42 if a["L"] < 20 else 0.33)
                if a["id"] == "b1b":
                    pr = R * 0.75
                drop = Vector((0, 0, -pr * 1.4))
                front = p + Vector((0, chord * 0.35, 0)) + drop
                back = p + Vector((0, -chord * 0.75, 0)) + drop
                b.cylinder("Body", front, back, pr, pr * 0.8, 12)
                b.cylinder("Detail", back, back + Vector((0, -pr * 0.3, 0)), pr * 0.7, pr * 0.6, 12)

    # rear fuselage pods (A-10)
    if special == "rear_pods":
        for side in (1, -1):
            c = Vector((side * R * 1.4, -L * 0.22, R * 1.0))
            b.cylinder("Body", c + Vector((0, L * 0.12, 0)), c - Vector((0, L * 0.1, 0)), R * 0.55, R * 0.5, 12)
            b.cylinder("Detail", c + Vector((0, L * 0.122, 0)), c + Vector((0, L * 0.124, 0)), R * 0.5, R * 0.5, 12)
        b.cylinder("Detail", Vector((0, L / 2, -R * 0.35)), Vector((0, L / 2 + L * 0.04, -R * 0.35)), R * 0.08, R * 0.08, 8)

    # jet nozzles
    if a["jets"] == 1:
        b.cylinder("Detail", Vector((0, -L / 2 + 0.01, 0)), Vector((0, -L / 2 - L * 0.03, 0)), R * 0.5, R * 0.45, 14)
    elif a["jets"] == 2:
        for side in (1, -1):
            x = side * R * 0.5
            b.cylinder("Detail", Vector((x, -L / 2 + 0.01, 0)), Vector((x, -L / 2 - L * 0.03, 0)), R * 0.42, R * 0.38, 14)
        # side intakes for twin-engine jets
        if a["nose"] != "intake":
            for side in (1, -1):
                ix = side * R * 1.0
                b.cylinder("Body", Vector((ix, L * 0.18, -R * 0.15)), Vector((ix, -L * 0.25, -R * 0.1)), R * 0.42, R * 0.5, 10)
    if a["nose"] == "intake":
        b.cylinder("Detail", Vector((0, L / 2 - 0.02, 0)), Vector((0, L / 2 - L * 0.05, 0)), R * 0.62, R * 0.62, 14, cap=True)

    return b


def build_into_scene(a, offset=Vector((0, 0, 0)), scale=1.0):
    body_rgb = tuple(a["color"])
    mats = {
        "Body": material(f"Body_{a['id']}", body_rgb, 0.35, 0.4),
        "Canopy": material("Canopy", (0.05, 0.12, 0.2), 0.6, 0.08),
        "Detail": material("Detail", (0.12, 0.12, 0.13), 0.7, 0.35),
    }
    b = build_aircraft(a)
    objs = b.to_objects(a["id"], mats)
    for ob in objs:
        ob.scale = (scale, scale, scale)
        ob.location = offset
        ob.name = f"{a['id']}_{ob.name}"
    return objs


# ----------------------------------------------------------------------------- export / render

def export_aircraft(a, outdir):
    reset_scene()
    objs = build_into_scene(a)
    for ob in objs:
        ob.name = ob.name.split("_", 1)[1]  # Body / Canopy / Detail
    d = os.path.join(outdir, a["id"])
    os.makedirs(d, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.fbx(filepath=os.path.join(d, f"{a['id']}.fbx"), use_selection=True,
                             axis_forward="-Z", axis_up="Y", apply_unit_scale=True,
                             mesh_smooth_type="FACE", add_leaf_bones=False, bake_anim=False)
    bpy.ops.wm.obj_export(filepath=os.path.join(d, f"{a['id']}.obj"), export_selected_objects=True,
                          forward_axis="NEGATIVE_Z", up_axis="Y", export_materials=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(d, f"{a['id']}.blend"))
    tris = sum(sum(len(p.vertices) - 2 for p in ob.data.polygons) for ob in objs)
    return tris


def setup_render(res_x, res_y, samples=24):
    scn = bpy.context.scene
    scn.render.engine = "CYCLES"
    scn.cycles.device = "CPU"
    scn.cycles.samples = samples
    scn.cycles.use_denoising = False
    scn.render.resolution_x = res_x
    scn.render.resolution_y = res_y
    scn.render.film_transparent = False
    world = bpy.data.worlds.new("W")
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.62, 0.70, 0.80, 1)
    bg.inputs["Strength"].default_value = 0.45
    scn.world = world
    sun = bpy.data.lights.new("Sun", "SUN")
    sun.energy = 2.2
    sun_ob = bpy.data.objects.new("Sun", sun)
    sun_ob.rotation_euler = (math.radians(40), math.radians(15), math.radians(30))
    scn.collection.objects.link(sun_ob)


def add_camera(location, target, ortho_scale=None, lens=50):
    cam = bpy.data.cameras.new("Cam")
    if ortho_scale:
        cam.type = "ORTHO"
        cam.ortho_scale = ortho_scale
    else:
        cam.lens = lens
    ob = bpy.data.objects.new("Cam", cam)
    ob.location = location
    direction = Vector(target) - Vector(location)
    ob.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.scene.camera = ob


def add_label(text, loc, size):
    cu = bpy.data.curves.new("txt", "FONT")
    cu.body = text
    cu.size = size
    cu.align_x = "CENTER"
    ob = bpy.data.objects.new("txt", cu)
    ob.location = loc
    ob.data.materials.append(material("Label", (0.02, 0.02, 0.03), 0, 1))
    bpy.context.scene.collection.objects.link(ob)


def render_sheet(aircraft, path, cols=8):
    reset_scene()
    cell = 14.0
    rows = math.ceil(len(aircraft) / cols)
    for i, a in enumerate(aircraft):
        c, r = i % cols, i // cols
        size = max(a["L"], a["S"])
        s = 11.0 / size
        x = (c - (cols - 1) / 2) * cell
        y = ((rows - 1) / 2 - r) * cell
        build_into_scene(a, Vector((x, y + 1.0, 0)), s)
        add_label(a["name"] + (" ★" if a["premium"] else ""), Vector((x, y - 6.0, 0)), 0.95)
    ground = bpy.data.meshes.new("g")
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=cols * cell)
    bm.to_mesh(ground)
    g = bpy.data.objects.new("ground", ground)
    g.location.z = -3
    g.data.materials.append(material("Ground", (0.85, 0.87, 0.9), 0, 0.9))
    bpy.context.scene.collection.objects.link(g)
    setup_render(2400, int(2400 * rows / cols), 16)
    add_camera((0, 0, 200), (0, 0, 0), ortho_scale=cols * cell)
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def render_hero(a, path):
    reset_scene()
    s = 12.0 / max(a["L"], a["S"])
    build_into_scene(a, Vector((0, 0, 0)), s)
    setup_render(1200, 800, 32)
    add_camera((9, 11, 6), (0, 0, 0), lens=40)
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def main():
    args = argv()
    with open(os.path.join(ROOT, "data", "aircraft.json")) as f:
        data = json.load(f)
    aircraft = data["aircraft"]
    if "--only" in args:
        ids = set(args[args.index("--only") + 1].split(","))
        aircraft = [a for a in aircraft if a["id"] in ids]
    if "--no-export" not in args:
        out = os.path.join(ROOT, "models")
        for a in aircraft:
            tris = export_aircraft(a, out)
            print(f"exported {a['id']:12s} {tris:6d} tris")
    if "--sheet" in args:
        render_sheet(aircraft, os.path.abspath(args[args.index("--sheet") + 1]))
    if "--hero" in args:
        i = args.index("--hero")
        hid, path = args[i + 1], os.path.abspath(args[i + 2])
        render_hero(next(a for a in data["aircraft"] if a["id"] == hid), path)


if __name__ == "__main__":
    main()
