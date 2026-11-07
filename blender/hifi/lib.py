"""
High-fidelity aircraft modelling library (Blender / bpy).

Aircraft are described the way a draughtsman would: fuselage cross-sections
at stations measured back from the nose, lifting surfaces as spanwise
sections carrying a real aerofoil, and bodies of revolution for nacelles,
spinners and wheels. Everything is in metres.

Coordinate frame used by the definitions (s, x, z):
    s : distance aft of the nose (m)
    x : to the right wing (m)
    z : up (m), 0 = fuselage datum
Blender frame on output: +Y = forward, +Z = up, +X = right, origin at mid-length.
"""
import math

import bpy  # noqa: F401  (must come before bmesh/mathutils with the bpy module)
import bmesh
import numpy as np
from mathutils import Matrix, Vector


# --------------------------------------------------------------------------- interpolation

def pchip(xs, ys, xq):
    """Shape-preserving cubic interpolation (no overshoot) - Fritsch-Carlson."""
    xs = np.asarray(xs, float)
    ys = np.asarray(ys, float)
    xq = np.asarray(xq, float)
    h = np.diff(xs)
    d = np.diff(ys) / h
    n = len(xs)
    m = np.zeros(n)
    if n == 2:
        m[:] = d[0]
    else:
        for k in range(1, n - 1):
            if d[k - 1] * d[k] <= 0:
                m[k] = 0
            else:
                w1 = 2 * h[k] + h[k - 1]
                w2 = h[k] + 2 * h[k - 1]
                m[k] = (w1 + w2) / (w1 / d[k - 1] + w2 / d[k])
        m[0] = d[0]
        m[-1] = d[-1]
    idx = np.clip(np.searchsorted(xs, xq) - 1, 0, n - 2)
    t = (xq - xs[idx]) / h[idx]
    h00 = 2 * t**3 - 3 * t**2 + 1
    h10 = t**3 - 2 * t**2 + t
    h01 = -2 * t**3 + 3 * t**2
    h11 = t**3 - t**2
    return h00 * ys[idx] + h10 * h[idx] * m[idx] + h01 * ys[idx + 1] + h11 * h[idx] * m[idx + 1]


def cosine_spacing(a, b, n, cluster="both"):
    t = np.linspace(0, 1, n)
    if cluster == "both":
        t = 0.5 - 0.5 * np.cos(np.pi * t)
    elif cluster == "start":
        t = 1 - np.cos(0.5 * np.pi * t)
    elif cluster == "end":
        t = np.sin(0.5 * np.pi * t)
    return a + (b - a) * t


# --------------------------------------------------------------------------- aerofoils

def naca4(t, m=0.0, p=0.4, n=28):
    """Closed NACA 4-digit aerofoil, unit chord. Returns list of (u, v) going
    TE -> upper -> LE -> lower -> TE (without duplicating the TE point).
    u = 0 at leading edge, 1 at trailing edge; v = up."""
    beta = np.linspace(0, np.pi, n)
    xc = 0.5 * (1 - np.cos(beta))
    yt = 5 * t * (0.2969 * np.sqrt(xc) - 0.1260 * xc - 0.3516 * xc**2 + 0.2843 * xc**3 - 0.1036 * xc**4)
    if m > 0:
        yc = np.where(xc < p, m / p**2 * (2 * p * xc - xc**2), m / (1 - p)**2 * ((1 - 2 * p) + 2 * p * xc - xc**2))
        dyc = np.where(xc < p, 2 * m / p**2 * (p - xc), 2 * m / (1 - p)**2 * (p - xc))
    else:
        yc = np.zeros_like(xc)
        dyc = np.zeros_like(xc)
    th = np.arctan(dyc)
    xu, yu = xc - yt * np.sin(th), yc + yt * np.cos(th)
    xl, yl = xc + yt * np.sin(th), yc - yt * np.cos(th)
    upper = list(zip(xu[::-1], yu[::-1]))       # TE -> LE
    lower = list(zip(xl[1:-1], yl[1:-1]))       # LE -> TE (exclusive)
    return upper + lower


def flat_plate(t, n=12):
    """Symmetric slab with rounded LE and sharp TE (fins, small surfaces)."""
    return naca4(t, 0, 0.4, n)


# --------------------------------------------------------------------------- mesh builder

class Mesh:
    """Collects geometry into named parts; each part becomes one Blender object."""

    def __init__(self, length):
        self.L = length
        self.parts = {}

    def bm(self, part):
        if part not in self.parts:
            self.parts[part] = bmesh.new()
        return self.parts[part]

    # convert (s, x, z) definition coords to Blender (x, y, z)
    def P(self, s, x, z):
        return Vector((x, self.L / 2 - s, z))

    def grid(self, part, rows, closed_u=True, cap_start=False, cap_end=False):
        """rows: list of lists of Vector; consecutive rows are joined with quads."""
        bm = self.bm(part)
        vr = [[bm.verts.new(v) for v in r] for r in rows]
        n = len(rows[0])
        last = n if closed_u else n - 1
        for a, b in zip(vr, vr[1:]):
            for i in range(last):
                j = (i + 1) % n
                bm.faces.new((a[i], a[j], b[j], b[i]))
        if cap_start:
            self._cap(bm, vr[0], reverse=True)
        if cap_end:
            self._cap(bm, vr[-1], reverse=False)
        return vr

    @staticmethod
    def _cap(bm, ring, reverse):
        c = Vector((0, 0, 0))
        for v in ring:
            c += v.co
        c /= len(ring)
        cv = bm.verts.new(c)
        n = len(ring)
        for i in range(n):
            a, b = ring[i], ring[(i + 1) % n]
            bm.faces.new((cv, b, a) if reverse else (cv, a, b))

    # ------------------------------------------------------------------ fuselage
    def fuselage(self, part, st, n_ring=36, n_len=90, exp=None, close_nose=True, close_tail=True,
                 s_range=None):
        """st: dict of station arrays: s, hw (half width), top, bot, optional
        zw (z of maximum width, default mid) and e (super-ellipse exponent).
        Cross-section = super-ellipse upper half (top) + lower half (bot)."""
        s0, s1 = s_range or (st["s"][0], st["s"][-1])
        ss = cosine_spacing(s0, s1, n_len, "both")
        hw = np.maximum(pchip(st["s"], st["hw"], ss), 0.002)
        top = pchip(st["s"], st["top"], ss)
        bot = pchip(st["s"], st["bot"], ss)
        zw = pchip(st["s"], st["zw"], ss) if "zw" in st else (top + bot) / 2
        ee = pchip(st["s"], st["e"], ss) if "e" in st else np.full_like(ss, exp or 2.2)
        rows = []
        for k, s in enumerate(ss):
            ring = []
            for i in range(n_ring):
                a = 2 * math.pi * i / n_ring
                c, sn = math.cos(a), math.sin(a)
                e = ee[k]
                x = hw[k] * math.copysign(abs(c) ** (2 / e), c)
                h = (top[k] - zw[k]) if sn >= 0 else (zw[k] - bot[k])
                z = zw[k] + math.copysign(abs(sn) ** (2 / e), sn) * max(h, 0.002)
                ring.append(self.P(s, x, z))
            rows.append(ring)
        self.grid(part, rows, True, close_nose, close_tail)

    # ------------------------------------------------------------------ revolve
    def revolve(self, part, axis_start, axis_dir, profile, n=24, cap_start=True, cap_end=True, squash=(1, 1)):
        """profile: list of (distance along axis, radius). axis given in (s,x,z)."""
        o = self.P(*axis_start)
        d = (self.P(axis_start[0] + axis_dir[0], axis_start[1] + axis_dir[1], axis_start[2] + axis_dir[2]) - o).normalized()
        ref = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
        u = d.cross(ref).normalized()
        v = d.cross(u).normalized()
        rows = []
        for t, r in profile:
            c = o + d * t
            rows.append([c + (u * math.cos(a) * squash[0] + v * math.sin(a) * squash[1]) * max(r, 1e-4)
                         for a in (2 * math.pi * i / n for i in range(n))])
        self.grid(part, rows, True, cap_start, cap_end)

    def cylinder(self, part, a, b, r, n=16, r2=None):
        A, B = Vector(a), Vector(b)
        L = (B - A).length
        self.revolve(part, a, tuple((B - A) / L), [(0, r), (L, r if r2 is None else r2)], n)

    # ------------------------------------------------------------------ lifting surfaces
    def surface(self, part, sections, foil, vertical=False, mirror=True, cap_tip=True, cap_root=False,
                interp=6, cant=0.0):
        """sections: list of dicts with keys
             b   : spanwise station (m from centreline / from base for fins)
             le  : s of leading edge
             c   : chord
             z   : height of chord line (horizontal) | x offset (vertical)
             t   : thickness ratio (optional, overrides the foil default)
           foil: function(t) -> unit aerofoil points
           vertical: span runs up (+z) instead of out (+x)."""
        bs = [sec["b"] for sec in sections]
        fine = []
        for a, b in zip(sections, sections[1:]):
            for k in range(interp):
                f = k / interp
                fine.append({key: a[key] + (b[key] - a[key]) * f for key in a if key in b})
        fine.append(dict(sections[-1]))
        for side in ((1, -1) if mirror else (1,)):
            rows = []
            for sec in fine:
                pts = foil(sec.get("t", 0.12))
                row = []
                for u, v in pts:
                    s = sec["le"] + u * sec["c"]
                    thick = v * sec["c"]
                    if vertical:
                        x = sec.get("z", 0.0) + thick
                        z = sec["b"]
                        if cant:
                            x, z = (x + z * math.sin(math.radians(cant))) * side, z * math.cos(math.radians(cant))
                        else:
                            x *= side
                    else:
                        x = side * sec["b"]
                        z = sec.get("z", 0.0) + thick
                    row.append(self.P(s, x, z))
                if side == -1 and not vertical:
                    row = row[::-1]
                if side == -1 and vertical:
                    row = row[::-1]
                rows.append(row)
            self.grid(part, rows, True, cap_root, cap_tip)

    # ------------------------------------------------------------------ helpers
    def wheel(self, part, centre, r, width, n=20):
        s, x, z = centre
        prof = [(-width / 2, r * 0.55), (-width / 2, r * 0.9), (-width * 0.35, r), (width * 0.35, r),
                (width / 2, r * 0.9), (width / 2, r * 0.55)]
        self.revolve(part, (s, x, z), (0, 1, 0), [(w, rr) for w, rr in prof], n)

    def strut(self, part, a, b, r=0.05):
        self.cylinder(part, a, b, r, 10)

    # ------------------------------------------------------------------ output
    def build(self, name, materials, sharp_angle=40):
        objs = []
        for part, bm in self.parts.items():
            bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
            for f in bm.faces:
                f.smooth = True
            for e in bm.edges:
                if len(e.link_faces) == 2:
                    ang = e.link_faces[0].normal.angle(e.link_faces[1].normal, 0)
                    e.smooth = ang < math.radians(sharp_angle)
                else:
                    e.smooth = False
            me = bpy.data.meshes.new(f"{name}_{part}")
            bm.to_mesh(me)
            bm.free()
            ob = bpy.data.objects.new(part, me)
            ob.data.materials.append(materials[part])
            bpy.context.scene.collection.objects.link(ob)
            objs.append(ob)
        self.parts = {}
        return objs


def material(name, rgb, metallic=0.2, rough=0.5, alpha=1.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    p = m.node_tree.nodes.get("Principled BSDF")
    p.inputs["Base Color"].default_value = (*rgb, 1)
    p.inputs["Metallic"].default_value = metallic
    p.inputs["Roughness"].default_value = rough
    if alpha < 1:
        p.inputs["Alpha"].default_value = alpha
        p.inputs["Transmission Weight"].default_value = 0.6
    m.diffuse_color = (*rgb, 1)
    return m


def triangles(objs):
    return sum(sum(len(p.vertices) - 2 for p in ob.data.polygons) for ob in objs)


def _blade_rows(m, hub, radius, chords, betas, root_r, t_root=0.12, t_tip=0.06, n_r=10):
    """Rows for one propeller blade lying along local +z of the prop disc."""
    rows = []
    rs = np.linspace(root_r, radius, n_r)
    rr = np.linspace(0, 1, len(chords))
    ch = np.interp(np.linspace(0, 1, n_r), rr, chords)
    be = np.interp(np.linspace(0, 1, n_r), rr, betas)
    for k, r in enumerate(rs):
        t = t_root + (t_tip - t_root) * k / (n_r - 1)
        pts = naca4(t, 0.02, 0.4, 14)
        b = math.radians(be[k])
        row = []
        for u, v in pts:
            # chord runs tangentially (x) rotated toward the axis (s) by the blade angle
            cu = (u - 0.35) * ch[k]
            cv = v * ch[k]
            x = cu * math.cos(b) - cv * math.sin(b)
            s = cu * math.sin(b) + cv * math.cos(b)
            row.append((s, x, r))
        rows.append(row)
    return rows


def propeller(m, part, hub, radius, blades, chords, betas, root_r, tip_part=None, tip_frac=0.92, phase=0.0):
    """Builds `blades` blades around the axis through hub (s, x, z), axis along s."""
    hs, hx, hz = hub
    for i in range(blades):
        a = phase + 2 * math.pi * i / blades
        rows = _blade_rows(m, hub, radius, chords, betas, root_r)
        world = []
        for row in rows:
            wr = []
            for s, x, r in row:
                # rotate the (x, r) pair about the axis by a
                X = x * math.cos(a) - r * math.sin(a)
                Z = x * math.sin(a) + r * math.cos(a)
                wr.append(m.P(hs + s, hx + X, hz + Z))
            world.append(wr)
        n_tip = max(1, int(len(world) * (1 - tip_frac)))
        if tip_part:
            m.grid(part, world[: len(world) - n_tip + 1], True, True, False)
            m.grid(tip_part, world[len(world) - n_tip:], True, False, True)
        else:
            m.grid(part, world, True, True, True)
