"""
Fairchild Republic A-10 Thunderbolt II.

Published data: length 16.26 m, span 17.53 m, height 4.47 m, wing area 47.0 m^2,
aerofoil NACA 6716 (root) / 6713 (tip), TF34 engines in pylon nacelles on the
rear fuselage, twin fins on the stabiliser tips, GAU-8/A in the nose.
Shapes traced from the public-domain US Army 3-view on Wikimedia Commons.
"""
from lib import Mesh, naca4, flat_plate, material

L = 16.26
GROUND = -1.88          # z of the runway when sitting on its gear
COLORS = {
    "Body": (0.36, 0.38, 0.39),      # FS 36118 gunship grey
    "Canopy": (0.06, 0.10, 0.14),
    "Detail": (0.10, 0.10, 0.11),    # intakes, exhausts, gun, tyres
    "Gear": (0.80, 0.80, 0.78),      # white gear legs / bays
}


def build():
    m = Mesh(L)

    # ---------------------------------------------------------------- fuselage
    fus = dict(
        s=[0.00, 0.15, 0.50, 1.00, 1.60, 2.30, 3.20, 4.60, 6.00, 7.60, 9.40, 11.0, 12.4, 13.6, 14.7, 15.6, 16.15],
        hw=[0.14, 0.32, 0.45, 0.52, 0.57, 0.61, 0.65, 0.68, 0.70, 0.70, 0.67, 0.61, 0.54, 0.47, 0.40, 0.32, 0.18],
        top=[-0.02, 0.18, 0.42, 0.62, 0.78, 0.92, 1.02, 1.08, 1.08, 1.06, 1.02, 0.94, 0.85, 0.76, 0.68, 0.60, 0.48],
        bot=[-0.32, -0.45, -0.58, -0.66, -0.71, -0.74, -0.77, -0.80, -0.82, -0.82, -0.78, -0.68, -0.54, -0.38, -0.22, -0.08, 0.10],
        e=[2.0, 2.1, 2.4, 2.7, 3.0, 3.2, 3.3, 3.3, 3.3, 3.3, 3.2, 3.0, 2.8, 2.6, 2.4, 2.2, 2.0],
    )
    m.fuselage("Body", fus, n_ring=40, n_len=84)

    # bubble canopy: steep windscreen, high bubble, fairing into the dorsal spine
    canopy = dict(
        s=[1.95, 2.20, 2.60, 3.20, 3.90, 4.50, 4.95],
        hw=[0.40, 0.46, 0.50, 0.50, 0.48, 0.40, 0.24],
        top=[0.95, 1.28, 1.62, 1.78, 1.76, 1.55, 1.16],
        bot=[0.85, 0.88, 0.92, 0.95, 0.98, 1.00, 1.02],
        e=[2.6, 2.4, 2.2, 2.1, 2.1, 2.1, 2.1],
    )
    m.fuselage("Canopy", canopy, n_ring=32, n_len=28)
    # canopy frame hoop at the windscreen
    # GAU-8/A barrels and muzzle shroud, slightly left of the centreline
    m.revolve("Detail", (-0.55, -0.08, -0.30), (1, 0, 0), [(0, 0.10), (0.05, 0.16), (0.55, 0.16), (0.9, 0.2)], 16)

    # ---------------------------------------------------------------- wing
    # centre section (flat, constant chord, NACA 6716) + outer panels (7 deg dihedral, taper to 6713)
    wz = -0.58
    dih = 0.122  # tan(7 deg)
    wing = [
        dict(b=0.00, le=6.25, c=3.04, z=wz, t=0.16),
        dict(b=2.70, le=6.25, c=3.04, z=wz, t=0.16),
        dict(b=5.50, le=6.62, c=2.54, z=wz + (5.50 - 2.70) * dih, t=0.145),
        dict(b=8.30, le=7.02, c=2.02, z=wz + (8.30 - 2.70) * dih, t=0.13),
    ]
    foil = lambda t: naca4(t, 0.03, 0.42, 30)
    m.surface("Body", wing, foil, interp=4, cap_tip=False)
    # Hoerner drooped wingtips
    tip = [
        dict(b=8.30, le=7.02, c=2.02, z=wz + 5.6 * dih, t=0.13),
        dict(b=8.62, le=7.08, c=1.90, z=wz + 5.6 * dih - 0.10, t=0.10),
        dict(b=8.765, le=7.20, c=1.62, z=wz + 5.6 * dih - 0.24, t=0.05),
    ]
    m.surface("Body", tip, foil, interp=3)

    # main gear pods (forward of the wing, at the centre/outer panel joint)
    for side in (1, -1):
        x = side * 2.50
        m.revolve("Body", (5.25, x, -0.95), (1, 0, 0),
                  [(0, 0.02), (0.15, 0.22), (0.5, 0.36), (1.2, 0.42), (2.6, 0.40), (3.4, 0.25), (3.7, 0.05)],
                  24, squash=(0.9, 1.1))

    # ---------------------------------------------------------------- engines (TF34) on pylons
    for side in (1, -1):
        x = side * 1.30
        z = 1.05
        # nacelle with an open intake lip (profile runs into the duct, round the lip, along the skin)
        m.revolve("Body", (9.55, x, z), (1, 0, 0),
                  [(0.45, 0.52), (0.04, 0.56), (-0.02, 0.62), (0.03, 0.68), (0.30, 0.71), (1.6, 0.71),
                   (2.5, 0.68), (3.3, 0.57), (3.85, 0.46), (3.88, 0.40)], 36, cap_start=False, cap_end=False)
        # fan face and spinner deep in the intake
        m.revolve("Detail", (9.95, x, z), (1, 0, 0), [(0, 0.53), (0.01, 0.20), (-0.12, 0.17), (-0.25, 0.0)], 28,
                  cap_start=False, cap_end=False)
        # exhaust: dark nozzle and tail cone
        m.revolve("Detail", (13.40, x, z), (1, 0, 0), [(0, 0.41), (0.25, 0.39), (0.25, 0.20), (0.05, 0.18),
                  (0.40, 0.10), (0.55, 0.0)], 28, cap_start=True, cap_end=False)

    # pylons: short struts from the upper fuselage out to each nacelle's inboard belly
    pyl = [dict(b=0.25, le=10.30, c=2.40, z=0.84, t=0.14), dict(b=0.98, le=10.45, c=2.10, z=0.55, t=0.14)]
    m.surface("Body", pyl, lambda t: naca4(t, 0, 0.4, 14), interp=2)

    # eleven weapon pylons: centreline, two fuselage, eight under the wings
    for x in (0.0, 0.62, -0.62, 1.60, -1.60, 3.40, -3.40, 4.55, -4.55, 5.70, -5.70):
        zt = wz if abs(x) <= 2.7 else wz + (abs(x) - 2.7) * dih
        zt = zt - 0.12 if abs(x) > 0.7 else -0.80
        le = 6.55 if abs(x) <= 2.7 else 6.55 + (abs(x) - 2.7) * 0.13
        m.surface("Body", [dict(b=zt - 0.28, le=le + 0.15, c=1.15, z=x, t=0.12), dict(b=zt + 0.05, le=le, c=1.45, z=x, t=0.12)],
                  lambda t: naca4(t, 0, 0.4, 12), vertical=True, mirror=False, interp=1, cap_root=True)

    # ---------------------------------------------------------------- tail
    hz = 0.28
    stab = [
        dict(b=0.00, le=13.85, c=1.78, z=hz, t=0.11),
        dict(b=2.85, le=13.85, c=1.78, z=hz, t=0.10),
        dict(b=2.95, le=13.88, c=1.74, z=hz, t=0.08),
    ]
    m.surface("Body", stab, lambda t: naca4(t, 0, 0.4, 20), interp=3)
    # twin fins on the stabiliser tips: rounded-rectangle profile, mostly above the stab
    fin = [
        dict(b=hz - 0.95, le=14.20, c=1.30, z=2.95, t=0.07),
        dict(b=hz - 0.70, le=13.95, c=1.85, z=2.95, t=0.08),
        dict(b=hz + 0.00, le=13.80, c=2.10, z=2.95, t=0.09),
        dict(b=hz + 1.40, le=13.88, c=2.02, z=2.95, t=0.08),
        dict(b=hz + 2.05, le=14.05, c=1.80, z=2.95, t=0.07),
        dict(b=hz + 2.32, le=14.40, c=1.30, z=2.95, t=0.05),
    ]
    m.surface("Body", fin, flat_plate, vertical=True, mirror=True, interp=3, cap_root=True)

    # ---------------------------------------------------------------- landing gear (separate object)
    for side in (1, -1):
        x = side * 2.50
        m.wheel("Detail", (5.95, x, GROUND + 0.50), 0.50, 0.32)
        m.strut("Gear", (5.95, x, GROUND + 0.5), (6.05, x, -1.0), 0.08)
    m.wheel("Detail", (1.75, 0.38, GROUND + 0.38), 0.38, 0.24)
    m.strut("Gear", (1.75, 0.38, GROUND + 0.38), (1.80, 0.38, -0.55), 0.07)

    mats = {k: material(f"A10_{k}", v, 0.25 if k == "Body" else 0.4, 0.55 if k == "Body" else 0.3,
                        0.35 if k == "Canopy" else 1.0) for k, v in COLORS.items()}
    return m, mats


SPEC = dict(id="a10", L=L, span=17.53, height=4.47, ground=GROUND, build=build, colors=COLORS, pitch=0.0)
