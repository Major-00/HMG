# Geyser Flats rework (Nov 6). Run inside Blender after formula.py's helpers are loaded:
#   ns = {}; exec(open(".../formula.py").read(), ns); exec(open(".../geyser.py").read(), ns); ns["rework"]()
# 1. The springs get real depth: open rings that step down to a deep-blue centre, the colour
#    changing as it goes down (rust and orange at the rim, yellow, green, turquoise, deep blue).
#    The floor plates are cut away under each spring.
# 2. The finale reads at once: the stepped Crown, the prism terraces, the approach steps and the
#    creature habitats are archived; a giant geyser (a pale lumpy cone with a turquoise crater and
#    a glowing cyan heart) stands at the end of the lane. Its steam plume is an effect.
import bpy, bmesh, math, collections
from mathutils import Vector

G = "Biome06_GeyserFlats"
DROP = ("_Crown_", "_PrismTerraces_", "_Approach_", "_Habitats_", "_Springs_")
CELL = 1.25

def _exporter():
    ex = {}
    exec(open("/Users/majorm/HMG/MaP/tools/export_lane.py").read(), ex)
    return ex

def oct_in(dx, dz, R):
    return abs(dx) <= R and abs(dz) <= R and abs(dx) + abs(dz) <= 1.42 * R

def raster_rects(x0, x1, z0, z1, keep):
    """Cells of CELL inside [x0,x1]x[z0,z1] for which keep(cx, cz) is true, merged into rectangles."""
    nx = max(1, round((x1 - x0) / CELL)); nz = max(1, round((z1 - z0) / CELL))
    cw = (x1 - x0) / nx; ch = (z1 - z0) / nz
    grid = [[keep(x0 + (i + 0.5) * cw, z0 + (j + 0.5) * ch) for i in range(nx)] for j in range(nz)]
    used = [[False] * nx for _ in range(nz)]
    rects = []
    for j in range(nz):
        for i in range(nx):
            if not grid[j][i] or used[j][i]:
                continue
            w = 1
            while i + w < nx and grid[j][i + w] and not used[j][i + w]:
                w += 1
            h = 1
            while j + h < nz and all(grid[j + h][i + k] and not used[j + h][i + k] for k in range(w)):
                h += 1
            for jj in range(j, j + h):
                for ii in range(i, i + w):
                    used[jj][ii] = True
            rects.append((x0 + i * cw, x0 + (i + w) * cw, z0 + j * ch, z0 + (j + h) * ch))
    return rects

def make(name, mat, boxes, col):
    """boxes: Roblox (x0,x1,y0,y1,z0,z1). One object, one material."""
    k = Kit(G)
    for b in boxes:
        if b[0] == "R":
            _, c, sz, deg = b
            k.boxr(mat, c[0], c[1], c[2], sz[0], sz[1], sz[2], "y", deg)
        else:
            k.box(mat, *b)
    bm = bmesh.new()
    for box in k.boxes[mat]:
        if box[0] == "R":
            _, c, sz, axis, deg = box
            t = math.radians(deg); ct, st = math.cos(t), math.sin(t)
            corners = []
            for dx in (-0.5, 0.5):
                for dy in (-0.5, 0.5):
                    for dz in (-0.5, 0.5):
                        ox, oy, oz = dx * sz[0], dy * sz[1], dz * sz[2]
                        corners.append(bl((c[0] + ox * ct + oz * st, c[1] + oy, c[2] - ox * st + oz * ct)))
        else:
            lo, hi = box
            corners = [bl((x, y, z)) for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])]
        vs = [bm.verts.new(c) for c in corners]
        for f in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
            bm.faces.new([vs[i] for i in f])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    old = bpy.data.objects.get(name)
    if old:
        bpy.data.objects.remove(old)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    ob = bpy.data.objects.new(name, me)
    ob.data.materials.append(bpy.data.materials["B_" + mat])
    col.objects.link(ob)
    return len(boxes)

def core_material():
    m = bpy.data.materials.get("B_Fb_GeyserCore")
    if not m:
        m = bpy.data.materials.new("B_Fb_GeyserCore"); m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    c = (0.19, 0.79, 1.0, 1)          # sRGB about 120, 230, 255
    bsdf.inputs["Base Color"].default_value = c
    bsdf.inputs["Emission Color"].default_value = c
    bsdf.inputs["Emission Strength"].default_value = 2.0
    m.diffuse_color = c
    return m

def rework():
    ex = _exporter()
    dg = bpy.context.evaluated_depsgraph_get()
    col = bpy.data.collections[G]
    arch = archive()
    old = bpy.data.collections.get("OLD_" + G) or bpy.data.collections.new("OLD_" + G)
    if old.name not in [c.name for c in arch.children]:
        arch.children.link(old)
    # --- springs: centre, and each ring's size, from the old discs
    springs = []
    src = list(col.objects) + list(old.objects)
    for o in src:
        if "_Springs_" not in o.name:
            continue
        mat = o.material_slots[0].material.name.replace("B_Fb_", "")
        for d in ex["islands"](o, dg):
            pts = [ex["rb_point"](v) for v in d["v"].values()]
            cx = (min(p.x for p in pts) + max(p.x for p in pts)) / 2
            cz = (min(p.z for p in pts) + max(p.z for p in pts)) / 2
            half = max(max(p.x for p in pts) - cx, max(p.z for p in pts) - cz)
            for s in springs:
                if abs(s["x"] - cx) < 3 and abs(s["z"] - cz) < 3:
                    s["rings"][mat] = max(s["rings"].get(mat, 0), half); break
            else:
                springs.append({"x": round(cx / CELL) * CELL, "z": round(cz / CELL) * CELL, "rings": {mat: half}})
    # --- archive what goes
    moved = 0
    for o in list(col.objects):
        if any(t in o.name for t in DROP):
            old.objects.link(o); col.objects.unlink(o); moved += 1
    # --- cut the floor plates around each spring (outer octagon + a cell of margin)
    def outer(s):
        return max(s["rings"].values())
    def in_spring(x, z):
        return any(oct_in(x - s["x"], z - s["z"], outer(s)) for s in springs)
    cut_report = 0
    for o in list(col.objects):
        if "_Floor_" not in o.name:
            continue
        mat = o.material_slots[0].material.name.replace("B_", "")
        boxes = []
        for d in ex["islands"](o, dg):
            pts = [ex["rb_point"](v) for v in d["v"].values()]
            x0, x1 = min(p.x for p in pts), max(p.x for p in pts)
            y0, y1 = min(p.y for p in pts), max(p.y for p in pts)
            z0, z1 = min(p.z for p in pts), max(p.z for p in pts)
            hit = any(x1 > s["x"] - outer(s) and x0 < s["x"] + outer(s) and z1 > s["z"] - outer(s) and z0 < s["z"] + outer(s) for s in springs)
            if not hit:
                boxes.append((x0, x1, y0, y1, z0, z1)); continue
            cut_report += 1
            for rx0, rx1, rz0, rz1 in raster_rects(x0, x1, z0, z1, lambda cx, cz: not in_spring(cx, cz)):
                boxes.append((rx0, rx1, y0, y1, rz0, rz1))
        name = o.name
        bpy.data.objects.remove(o)
        make(name, mat, boxes, col)
    # --- the basins
    made = 0
    per = collections.defaultdict(list)
    for s in springs:
        rings = sorted(s["rings"].items(), key=lambda kv: -kv[1])      # outer first
        n = len(rings)
        for i, (mat, R) in enumerate(rings):
            top = 0.5 - 0.75 * i
            inner = rings[i + 1][1] if i + 1 < n else 0
            keep = (lambda R, inner: (lambda cx, cz: oct_in(cx - s["x"], cz - s["z"], R) and not (inner and oct_in(cx - s["x"], cz - s["z"], inner))))(R, inner)
            for rx0, rx1, rz0, rz1 in raster_rects(s["x"] - R, s["x"] + R, s["z"] - R, s["z"] + R, keep):
                per["Fb_" + mat].append((rx0, rx1, -4.0, top, rz0, rz1))
    for mat, boxes in per.items():
        made += make(f"{G}_Basins_{mat}", mat, boxes, col)
    # --- the apron where the terraces stood, and the giant geyser
    apron = collections.defaultdict(list)
    xs = [-110 + i * 20 for i in range(11)]
    zs = [2181.25 + j * 18.75 for j in range(6)]
    for i, x in enumerate(xs):
        for j, z in enumerate(zs):
            apron["Fb_FCrust" if (i + j) % 2 == 0 else "Fb_FCrust_d"].append((x, x + 20, -1.25, 0, z, z + 18.75))
    for mat, boxes in apron.items():
        made += make(f"{G}_Apron_{mat}", mat, boxes, col)
    core_material()
    cone = collections.defaultdict(list)
    CX, CZ = 0.0, 2240.0
    def octo3(R, y0, y1, mat, dx=0.0, dz=0.0, deg=0.0):
        """An octagon as three boxes (no overlaps), optionally turned about y."""
        c = 0.72 * R; h = y1 - y0; my = (y0 + y1) / 2
        t = math.radians(deg); ct, st = math.cos(t), math.sin(t)
        def put(ox, oz, sx, sz):
            cone[mat].append(("R", (CX + dx + ox * ct + oz * st, my, CZ + dz - ox * st + oz * ct), (sx, h, sz), deg))
        put(0, 0, 2 * R, 2 * c)
        put(0, (c + R) / 2, 2 * c, R - c)
        put(0, -(c + R) / 2, 2 * c, R - c)
    # A real geyser is a low, wide sinter mound; the plume is what you recognise. Seven low tiers,
    # every other one turned 22.5 degrees so the mound reads round and lumpy, not stepped.
    tiers = [(44, 0.0, (0, 0)), (38, 2.0, (2.5, -1.25)), (32.5, 4.0, (-1.25, 2.5)), (27.5, 5.75, (1.25, 1.25)),
             (23, 7.5, (-2.5, -1.25)), (19.5, 9.0, (1.25, -2.5)), (16.5, 10.5, (0, 0))]
    for i, (R, y0, (dx, dz)) in enumerate(tiers):
        y1 = tiers[i + 1][1] if i + 1 < len(tiers) else 12.0
        mat = ("Fb_Sinter", "Fb_Sinter2", "Fb_Sinter", "Fb_SnagSock", "Fb_Sinter", "Fb_SnagSock", "Fb_SnagSock")[i]
        octo3(R, y0, y1, mat, dx, dz, 22.5 if i % 2 else 0.0)
    y = 12.0
    for i, R in enumerate((15.0, 13.5)):              # the crater lip around a 10-stud-wide opening
        keep = (lambda R: (lambda cx, cz: oct_in(cx - CX, cz - CZ, R) and not oct_in(cx - CX, cz - CZ, 10)))(R)
        for rx0, rx1, rz0, rz1 in raster_rects(CX - R, CX + R, CZ - R, CZ + R, keep):
            cone["Fb_SnagSock"].append((rx0, rx1, y + i * 1.5, y + (i + 1) * 1.5, rz0, rz1))
    keep = lambda cx, cz: oct_in(cx - CX, cz - CZ, 10) and not oct_in(cx - CX, cz - CZ, 6)
    for rx0, rx1, rz0, rz1 in raster_rects(CX - 10, CX + 10, CZ - 10, CZ + 10, keep):
        cone["Fb_Turq"].append((rx0, rx1, y, y + 2.25, rz0, rz1))
    for rx0, rx1, rz0, rz1 in raster_rects(CX - 6, CX + 6, CZ - 6, CZ + 6, lambda cx, cz: oct_in(cx - CX, cz - CZ, 6) and not oct_in(cx - CX, cz - CZ, 3)):
        cone["Fb_Deep"].append((rx0, rx1, y, y + 1.5, rz0, rz1))
    for rx0, rx1, rz0, rz1 in raster_rects(CX - 3, CX + 3, CZ - 3, CZ + 3, lambda cx, cz: oct_in(cx - CX, cz - CZ, 3)):
        cone["Fb_GeyserCore"].append((rx0, rx1, y, y + 1.75, rz0, rz1))
    for mat, boxes in cone.items():
        made += make(f"{G}_GiantGeyser_{mat}", mat, boxes, col)
    # --- effect anchors
    fx = bpy.data.collections["FX_Anchors"]
    plume = bpy.data.objects.get("FX_Geyser_CrownPlume")
    if plume:
        plume.location = bl((0, 13.5, CZ))
        plume["effect"] = "the giant geyser's steam plume, tall and white, with a big eruption every so often"
    mist = bpy.data.objects.get("FX_Geyser_TerraceMist")
    if mist:
        mist.location = bl((0, 2, CZ))
        mist["effect"] = "warm mist rolling around the giant geyser's base"
    return {"springs": [(s["x"], s["z"], sorted(s["rings"], key=lambda m: -s["rings"][m])) for s in springs],
            "archived": moved, "plates_cut": cut_report, "new_parts": made}
