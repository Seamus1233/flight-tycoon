"""
North American P-51D Mustang.

Published data: length 9.83 m, span 11.28 m, height 4.08 m (tail down, prop
vertical), wing area 21.83 m^2, root chord 2.64 m, tip chord 1.27 m, dihedral 5 deg,
NAA/NACA 45-100 laminar aerofoil 15.1% root / 11.4% tip, Hamilton Standard
4-blade propeller 3.40 m, main gear track 3.61 m, ground attitude ~11.5 deg.
"""
import math

from lib import Mesh, naca4, material, propeller

L = 9.83
PITCH = 11.5  # nose-up attitude on the ground (deg)
COLORS = {
    "Body": (0.70, 0.71, 0.73),       # natural metal
    "AntiGlare": (0.24, 0.26, 0.17),  # olive drab panel ahead of the windscreen
    "Spinner": (0.62, 0.06, 0.05),    # red nose
    "Canopy": (0.06, 0.10, 0.14),
    "Detail": (0.09, 0.09, 0.10),     # exhausts, intakes, tyres
    "Prop": (0.06, 0.06, 0.06),
    "PropTip": (0.95, 0.78, 0.10),    # yellow tips
    "Gear": (0.62, 0.63, 0.64),
}


def build():
    m = Mesh(L)
    tan5 = math.tan(math.radians(5))

    # ---------------------------------------------------------------- fuselage
    fus = dict(
        s=[0.70, 0.80, 1.00, 1.60, 2.40, 3.20, 4.00, 4.80, 5.60, 6.40, 7.20, 8.00, 8.80, 9.40, 9.70],
        hw=[0.31, 0.37, 0.41, 0.43, 0.44, 0.45, 0.46, 0.45, 0.42, 0.36, 0.29, 0.22, 0.15, 0.09, 0.04],
        top=[0.31, 0.37, 0.42, 0.46, 0.49, 0.52, 0.55, 0.58, 0.62, 0.58, 0.50, 0.40, 0.31, 0.24, 0.18],
        bot=[-0.31, -0.40, -0.50, -0.55, -0.59, -0.64, -0.68, -0.70, -0.66, -0.58, -0.47, -0.36, -0.24, -0.12, -0.02],
        e=[2.0, 2.0, 2.1, 2.2, 2.2, 2.3, 2.3, 2.3, 2.3, 2.2, 2.2, 2.1, 2.0, 2.0, 2.0],
    )
    m.fuselage("Body", fus, n_ring=36, n_len=72, close_nose=False)

    # olive-drab anti-glare panel: a thin skin over the top of the cowling
    ag = dict(s=[0.85, 1.6, 2.4, 3.2, 4.05], hw=[0.20, 0.24, 0.25, 0.25, 0.24],
              top=[0.426, 0.466, 0.496, 0.526, 0.554], bot=[0.30, 0.34, 0.37, 0.40, 0.43], e=[2.0] * 5)
    m.fuselage("AntiGlare", ag, n_ring=20, n_len=20)

    # spinner
    m.revolve("Spinner", (0.0, 0, 0), (1, 0, 0),
              [(0, 0.0), (0.06, 0.12), (0.18, 0.21), (0.35, 0.28), (0.55, 0.315), (0.72, 0.32)], 32,
              cap_start=False, cap_end=True)

    # carburettor intake under the spinner
    m.fuselage("Body", dict(s=[0.95, 1.10, 1.50, 1.90], hw=[0.12, 0.15, 0.15, 0.10],
                            top=[-0.40, -0.40, -0.42, -0.45], bot=[-0.58, -0.62, -0.62, -0.50], e=[2.6] * 4),
               n_ring=16, n_len=10, close_nose=False)
    m.revolve("Detail", (0.97, 0, -0.51), (1, 0, 0), [(0, 0.09), (0.02, 0.0)], 12, cap_start=False, cap_end=False,
              squash=(1.4, 0.9))

    # exhaust stacks: 6 per side
    for side in (1, -1):
        for k in range(6):
            s = 1.08 + 0.17 * k
            m.cylinder("Detail", (s, side * 0.40, 0.22), (s + 0.07, side * 0.50, 0.20), 0.045, 8)

    # bubble canopy
    canopy = dict(
        s=[4.02, 4.20, 4.50, 4.90, 5.30, 5.70, 6.05],
        hw=[0.30, 0.34, 0.37, 0.38, 0.36, 0.30, 0.16],
        top=[0.60, 0.86, 1.04, 1.12, 1.10, 0.95, 0.68],
        bot=[0.50, 0.52, 0.54, 0.56, 0.58, 0.60, 0.62],
        e=[2.3, 2.2, 2.0, 2.0, 2.0, 2.0, 2.0],
    )
    m.fuselage("Canopy", canopy, n_ring=32, n_len=26)

    # belly radiator scoop (open inlet, gap from the fuselage)
    scoop = dict(s=[4.25, 4.40, 5.00, 5.80, 6.50, 7.10],
                 hw=[0.30, 0.32, 0.33, 0.32, 0.27, 0.18],
                 top=[-0.80, -0.70, -0.60, -0.55, -0.52, -0.46],
                 bot=[-1.00, -1.04, -1.06, -1.05, -0.92, -0.58], e=[2.4] * 6)
    m.fuselage("Body", scoop, n_ring=24, n_len=24, close_nose=False)
    m.fuselage("Detail", dict(s=[4.32, 4.36], hw=[0.29, 0.29], top=[-0.72, -0.72], bot=[-1.0, -1.0], e=[2.4, 2.4]),
               n_ring=24, n_len=2, close_nose=True, close_tail=False)

    # ---------------------------------------------------------------- wing
    wz = -0.50
    foil = lambda t: naca4(t, 0.016, 0.45, 32)
    wing = [
        dict(b=0.00, le=2.38, c=2.80, z=wz, t=0.151),
        dict(b=0.95, le=2.64, c=2.46, z=wz + 0.95 * tan5, t=0.148),
        dict(b=3.30, le=2.81, c=1.86, z=wz + 3.30 * tan5, t=0.131),
        dict(b=5.50, le=2.95, c=1.30, z=wz + 5.50 * tan5, t=0.116),
        dict(b=5.62, le=2.99, c=1.20, z=wz + 5.62 * tan5, t=0.10),
        dict(b=5.64, le=3.07, c=1.00, z=wz + 5.64 * tan5, t=0.05),
    ]
    m.surface("Body", wing, foil, interp=4)

    # ---------------------------------------------------------------- tail
    hz = 0.06
    stab = [
        dict(b=0.00, le=8.28, c=1.38, z=hz, t=0.11),
        dict(b=1.30, le=8.38, c=1.22, z=hz, t=0.10),
        dict(b=1.80, le=8.55, c=0.95, z=hz, t=0.09),
        dict(b=1.98, le=8.78, c=0.60, z=hz, t=0.07),
        dict(b=2.02, le=8.95, c=0.32, z=hz, t=0.05),
    ]
    m.surface("Body", stab, lambda t: naca4(t, 0, 0.4, 20), interp=4)
    fin = [
        dict(b=0.30, le=6.90, c=2.78, z=0.0, t=0.03),   # dorsal fillet
        dict(b=0.48, le=7.62, c=2.06, z=0.0, t=0.06),
        dict(b=0.80, le=8.18, c=1.50, z=0.0, t=0.07),
        dict(b=1.30, le=8.55, c=1.12, z=0.0, t=0.07),
        dict(b=1.62, le=8.82, c=0.84, z=0.0, t=0.08),
        dict(b=1.74, le=9.05, c=0.56, z=0.0, t=0.06),
        dict(b=1.78, le=9.25, c=0.30, z=0.0, t=0.04),
    ]
    m.surface("Body", fin, lambda t: naca4(t, 0, 0.4, 20), vertical=True, mirror=False, interp=3, cap_root=True)

    # ---------------------------------------------------------------- propeller (Hamilton Standard 4-blade)
    propeller(m, "Prop", (0.30, 0, 0), 1.70, 4,
              chords=[0.24, 0.33, 0.36, 0.34, 0.28, 0.17], betas=[62, 48, 38, 30, 25, 22],
              root_r=0.24, tip_part="PropTip", tip_frac=0.88, phase=math.radians(20))

    # ---------------------------------------------------------------- landing gear (tail-down)
    # main wheels sit on a ground plane pitched 11.5 deg: ground z = ZM + (s - SM) * tan(pitch)
    SM, ZM = 2.56, -1.78
    tp = math.tan(math.radians(PITCH))
    for side in (1, -1):
        x = side * 1.80
        wc = (SM, x, ZM + 0.35)
        m.wheel("Detail", wc, 0.35, 0.19)
        m.strut("Gear", (SM, x * 0.97, ZM + 0.35), (2.78, side * 1.62, wz + 1.62 * tan5 - 0.06), 0.065)
        # gear door
        m.surface("Gear", [dict(b=ZM + 0.55, le=2.25, c=0.78, z=x * 0.92, t=0.03),
                           dict(b=wz + 1.6 * tan5 - 0.10, le=2.38, c=0.70, z=x * 0.90, t=0.03)],
                  lambda t: naca4(t, 0, 0.4, 8), vertical=True, mirror=False, interp=1)
    st = 8.62
    zt = ZM + (st - SM) * tp
    m.wheel("Detail", (st, 0, zt + 0.16), 0.16, 0.09)
    m.strut("Gear", (st, 0.0, zt + 0.16), (st - 0.12, 0.0, -0.20), 0.04)

    mats = {k: material(f"P51_{k}", v, 0.75 if k in ("Body", "Spinner") else 0.3,
                        0.28 if k == "Body" else 0.45, 0.35 if k == "Canopy" else 1.0) for k, v in COLORS.items()}
    return m, mats


SPEC = dict(id="p51", L=L, span=11.28, height=4.08, ground=-1.78, build=build, colors=COLORS, pitch=PITCH)
