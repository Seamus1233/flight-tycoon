"""
Builds the high-fidelity aircraft, exports them for Roblox and renders checks.

    python3.11 blender/hifi/generate_hifi.py a10 p51            # build + export
    python3.11 blender/hifi/generate_hifi.py a10 --renders DIR   # + hero / overlay / old-vs-new renders

Exports models/<id>/<id>.fbx|.obj|.blend (replacing the low-poly version) and
models/<id>/<id>.parts.json (part name -> colour, read by tools/generate.py).
Each part (Body, Canopy, Detail, Gear, ...) is a separate mesh so Roblox can
colour it; parts named Gear* are hidden when the aircraft flies.
"""
import importlib
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

from lib import triangles  # noqa: E402

REFS = {
    # reference 3-view calibration: image, top-view nose pixel, centreline x pixel, px per metre,
    # side-view nose pixel and the pixel row of z = 0, px per metre
    "a10": dict(img="a10.png", top=dict(nose=(160, 59), ppm=16.55), side=dict(nose=(270, 283), ppm=17.0)),
    "p51": dict(img="p51.png"),
}


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def build(mod):
    m, mats = mod.build()
    objs = m.build(mod.SPEC["id"], mats)
    return objs


def export(spec, objs):
    d = os.path.join(ROOT, "models", spec["id"])
    os.makedirs(d, exist_ok=True)
    for f in os.listdir(d):
        os.remove(os.path.join(d, f))
    bpy.ops.object.select_all(action="SELECT")
    base = os.path.join(d, spec["id"])
    bpy.ops.export_scene.fbx(filepath=base + ".fbx", use_selection=True, axis_forward="-Z", axis_up="Y",
                             apply_unit_scale=True, mesh_smooth_type="EDGE", add_leaf_bones=False, bake_anim=False)
    bpy.ops.wm.obj_export(filepath=base + ".obj", export_selected_objects=True, forward_axis="NEGATIVE_Z",
                          up_axis="Y", export_materials=True)
    bpy.ops.wm.save_as_mainfile(filepath=base + ".blend")
    parts = {ob.name: dict(color=list(spec["colors"][ob.name]), tris=triangles([ob])) for ob in objs}
    with open(base + ".parts.json", "w") as f:
        json.dump(dict(id=spec["id"], length=spec["L"], span=spec["span"], height=spec["height"],
                       groundPitch=spec.get("pitch", 0.0), parts=parts), f, indent=1)


# ---------------------------------------------------------------------------- rendering

def scene_setup(res, samples=48, transparent=False, bg=(0.55, 0.63, 0.73)):
    scn = bpy.context.scene
    scn.render.engine = "CYCLES"
    scn.cycles.device = "CPU"
    scn.cycles.samples = samples
    scn.cycles.use_denoising = True
    try:
        scn.cycles.denoiser = "OPENIMAGEDENOISE"
    except Exception:
        pass
    scn.render.resolution_x, scn.render.resolution_y = res
    scn.render.film_transparent = transparent
    scn.view_settings.view_transform = "AgX"
    w = bpy.data.worlds.new("W")
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (*bg, 1)
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.6
    scn.world = w
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 3.0
    sun.data.angle = math.radians(3)
    sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(140))
    scn.collection.objects.link(sun)


def camera(loc, target, ortho=None, lens=55):
    cam = bpy.data.cameras.new("C")
    if ortho:
        cam.type = "ORTHO"
        cam.ortho_scale = ortho
    else:
        cam.lens = lens
    cam.clip_end = 1000
    ob = bpy.data.objects.new("C", cam)
    ob.location = loc
    ob.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.scene.camera = ob
    return ob


def ground(z, size=200, rgb=(0.42, 0.44, 0.42)):
    from lib import material
    me = bpy.data.meshes.new("g")
    me.from_pydata([(-size, -size, z), (size, -size, z), (size, size, z), (-size, size, z)], [], [(0, 1, 2, 3)])
    ob = bpy.data.objects.new("ground", me)
    ob.data.materials.append(material("GroundMat", rgb, 0, 0.8))
    bpy.context.scene.collection.objects.link(ob)


def pose(objs, pitch_deg):
    """Applies the ground attitude and returns the z of the lowest vertex (the runway)."""
    for ob in objs:
        ob.rotation_euler.x = math.radians(pitch_deg)
    bpy.context.view_layer.update()
    low = min((ob.matrix_world @ v.co).z for ob in objs for v in ob.data.vertices)
    return low


def render(path):
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def hero(mod, path, az=35, el=18, res=(1600, 1000)):
    reset()
    spec = mod.SPEC
    gz = pose(build(mod), spec.get("pitch", 0.0))
    ground(gz)
    scene_setup(res)
    r = max(spec["L"], spec["span"]) * 1.25
    a, e = math.radians(az), math.radians(el)
    target = (0, 0, gz + spec["height"] * 0.4)
    camera((r * math.sin(a), r * math.cos(a), target[2] + r * math.sin(e)), target, lens=50)
    render(path)


def silhouette(mod, view, ppm, path):
    """Orthographic silhouette (alpha) at an exact pixels-per-metre scale."""
    reset()
    spec = mod.SPEC
    build(mod)
    scene_setup((10, 10), samples=1, transparent=True)
    L, S = spec["L"], spec["span"]
    if view == "top":
        w_m, h_m = S + 2, L + 2
        camera((0, 0, 50), (0, 0, 0), ortho=max(w_m, h_m))
    else:  # side, looking from the left so the nose points left like the drawings
        w_m, h_m = L + 2, 8
        camera((-50, 0, 0), (0, 0, 0), ortho=max(w_m, h_m))
    size = int(max(w_m, h_m) * ppm)
    bpy.context.scene.render.resolution_x = size
    bpy.context.scene.render.resolution_y = size
    render(path)
    return max(w_m, h_m)


def overlay(mod, refdir, outpath):
    """Overlays the model silhouette in red on the reference 3-view."""
    from PIL import Image
    spec = mod.SPEC
    ref = REFS.get(spec["id"])
    if not ref or "top" not in ref:
        return False
    img = Image.open(os.path.join(refdir, ref["img"])).convert("RGBA")
    up = 3
    img = img.resize((img.width * up, img.height * up), Image.LANCZOS)
    tmp = os.path.join(os.path.dirname(outpath), "_sil.png")
    for view in ("top", "side"):
        cal = ref[view]
        extent = silhouette(mod, view, cal["ppm"] * up, tmp)
        sil = Image.open(tmp).convert("RGBA")
        a = sil.split()[3].point(lambda v: int(v * 0.45))
        red = Image.new("RGBA", sil.size, (230, 30, 30, 0))
        red.putalpha(a)
        ppm = cal["ppm"] * up
        if view == "top":
            # image centre = model origin; nose is at +L/2 (up in image)
            ox = cal["nose"][0] * up - sil.width / 2
            oy = cal["nose"][1] * up - (sil.height / 2 - spec["L"] / 2 * ppm)
        else:
            # camera on -X looking +X: image right = -Y (aft)... nose (+Y) appears on the left
            ox = cal["nose"][0] * up - (sil.width / 2 - spec["L"] / 2 * ppm)
            oy = cal["nose"][1] * up - sil.height / 2
        img.alpha_composite(red, (int(ox), int(oy)))
    img.convert("RGB").save(outpath)
    os.remove(tmp)
    return True


def old_vs_new(mod, outpath):
    """Renders the old procedural model and the new one from the same camera."""
    sys.path.insert(0, os.path.dirname(HERE))
    old = importlib.import_module("generate_aircraft")
    with open(os.path.join(ROOT, "data", "aircraft.json")) as f:
        a = next(x for x in json.load(f)["aircraft"] if x["id"] == mod.SPEC["id"])
    paths = []
    for which in ("old", "new"):
        reset()
        spec = mod.SPEC
        if which == "old":
            objs = old.build_into_scene(a)
            gz = pose(objs, 0) - 0.8
        else:
            gz = pose(build(mod), spec.get("pitch", 0.0))
        ground(gz)
        scene_setup((900, 600), samples=32)
        r = max(spec["L"], spec["span"]) * 1.25
        camera((r * 0.6, r * 0.75, r * 0.38), (0, 0, 0), lens=50)
        p = outpath.replace(".png", f"_{which}.png")
        render(p)
        paths.append(p)
    from PIL import Image, ImageDraw
    ims = [Image.open(p) for p in paths]
    out = Image.new("RGB", (1800, 640), (25, 28, 34))
    d = ImageDraw.Draw(out)
    for i, (im, label) in enumerate(zip(ims, ("BEFORE", "AFTER"))):
        out.paste(im, (i * 900, 40))
        d.text((i * 900 + 20, 12), label, fill=(255, 255, 255))
    out.save(outpath)
    for p in paths:
        os.remove(p)


def main():
    args = sys.argv[1:]
    ids = [a for a in args if not a.startswith("--") and "/" not in a]
    renders = args[args.index("--renders") + 1] if "--renders" in args else None
    refdir = args[args.index("--refs") + 1] if "--refs" in args else None
    for aid in ids:
        mod = importlib.import_module(aid)
        reset()
        objs = build(mod)
        print(f"{aid}: {triangles(objs)} triangles in {len(objs)} parts: "
              + ", ".join(f"{o.name}={triangles([o])}" for o in objs))
        export(mod.SPEC, objs)
        if renders:
            os.makedirs(renders, exist_ok=True)
            hero(mod, os.path.join(renders, f"{aid}_hero.png"))
            hero(mod, os.path.join(renders, f"{aid}_hero_rear.png"), az=150, el=22)
            old_vs_new(mod, os.path.join(renders, f"{aid}_before_after.png"))
            if refdir:
                overlay(mod, refdir, os.path.join(renders, f"{aid}_overlay.png"))


if __name__ == "__main__":
    main()
