# The lane formula (Nov 6): biomes 1 to 4 share one shape, after Steal An Egg. Run inside Blender:
#   ns = {}; exec(open("/Users/majorm/HMG/MaP/tools/formula.py").read(), ns); ns["build_all"]()
# Shape, in Roblox studs (the exporter converts): a floor slab 85 wide with a two-tone checker, two
# walls 30 thick and 30 tall with a two-tone checker on the inner face, a grass cap on each wall,
# a threshold strip where the biome starts, and a few props by the walls (the centre stays clear
# for the orb). Only the colours and the props change per biome. Old objects move to
# ARCHIVE_pre_formula (not exported), never deleted.
import bpy, bmesh, math
from mathutils import Vector

HALF = 42.5          # inner half width
WALL = 30.0          # wall thickness
TOP = 30.0           # wall height above the floor
BASE = -20.0         # walls and slab go down to here, so the lane reads as a solid block
CELL = 21.25         # floor checker cell (4 across)
WCELL_H = 15.0       # wall checker rows
SKIN = 0.0625        # checker tile / panel thickness

BIOMES = [
    dict(name="Biome01_Meadow", z0=18.75, z1=206.25, floor=("Md_Grass", "Md_Grass2"), wall=("Md_Stone", "Md_Stone2"),
         cap="Md_GrassCap", line="Md_Threshold", props="trees", leaf=("Md_Leaf", "Md_Leaf2"), trunk="Md_Trunk"),
    dict(name="Biome02_WindyHighlands", z0=206.25, z1=456.25, floor=("Wh_Grass", "Wh_Grass2"), wall=("Wh_Stone", "Wh_Stone2"),
         cap="Wh_GrassCap", line="Wh_Threshold", props="boulders", rock="Wh_Strata", leaf=("Wh_Leaf", "Wh_Leaf2"), trunk="Wh_Trunk"),
    dict(name="Biome03_Tundra", z0=456.25, z1=768.75, floor=("Tg_Snow", "Tg_Snow2"), wall=("Tg_IceMid", "Tg_IceLight"),
         cap="Tg_SnowCap", line="Tg_Threshold", props="pines", pine="Tg_Pine", snow="Tg_SnowCap", trunk="Md_Trunk"),
    dict(name="Biome04_JungleRuins", z0=768.75, z1=1143.75, floor=("Jr_Grass", "Jr_Grass2"), wall=("Jr_Stone", "Jr_Stone2"),
         cap="Jr_Moss", line="Jr_Pave", props="jungle", leaf=("Jr_Leaf", "Jr_Leaf2"), trunk="Jr_Trunk", pillar="Jr_Stone2"),
]

def bl(p):
    """Roblox (x, y, z) -> Blender (x, y, z)."""
    return Vector((-p[0] / 1.25, p[2] / 1.25 + 45, p[1] / 1.25))

class Kit:
    def __init__(self, biome):
        self.biome = biome
        self.boxes = {}   # material -> list of (lo, hi) Roblox corners
    def box(self, mat, x0, x1, y0, y1, z0, z1):
        self.boxes.setdefault(mat, []).append(((min(x0, x1), min(y0, y1), min(z0, z1)), (max(x0, x1), max(y0, y1), max(z0, z1))))
    def boxc(self, mat, cx, cy, cz, sx, sy, sz):
        self.box(mat, cx - sx / 2, cx + sx / 2, cy - sy / 2, cy + sy / 2, cz - sz / 2, cz + sz / 2)
    def boxr(self, mat, cx, cy, cz, sx, sy, sz, axis, deg):
        """A box turned `deg` degrees about the Roblox `axis` ("x", "y" or "z") through its centre."""
        self.boxes.setdefault(mat, []).append(("R", (cx, cy, cz), (sx, sy, sz), axis, deg))
    def build(self, col):
        made = 0
        for mat, boxes in self.boxes.items():
            bm = bmesh.new()
            for box in boxes:
                if box[0] == "R":
                    _, c, sz, axis, deg = box
                    t = math.radians(deg); ct, st = math.cos(t), math.sin(t)
                    def turn(v):
                        x, y, z = v
                        if axis == "x": return (x, y * ct - z * st, y * st + z * ct)
                        if axis == "y": return (x * ct + z * st, y, -x * st + z * ct)
                        return (x * ct - y * st, x * st + y * ct, z)
                    corners = []
                    for dx in (-0.5, 0.5):
                        for dy in (-0.5, 0.5):
                            for dz in (-0.5, 0.5):
                                o = turn((dx * sz[0], dy * sz[1], dz * sz[2]))
                                corners.append(bl((c[0] + o[0], c[1] + o[1], c[2] + o[2])))
                else:
                    lo, hi = box
                    corners = [bl((x, y, z)) for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])]
                vs = [bm.verts.new(c) for c in corners]
                # index = xi*4 + yi*2 + zi
                for f in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
                    bm.faces.new([vs[i] for i in f])
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
            name = f"{self.biome}_F_{mat}"
            me = bpy.data.meshes.new(name)
            bm.to_mesh(me); bm.free()
            ob = bpy.data.objects.new(name, me)
            m = bpy.data.materials.get("B_" + mat)
            assert m, "missing material B_" + mat
            ob.data.materials.append(m)
            col.objects.link(ob)
            made += len(boxes)
        return made

def shell(k, b):
    z0, z1 = b["z0"], b["z1"]
    length = z1 - z0
    f0, f1 = b["floor"]; w0, w1 = b["wall"]
    k.box(f0, -HALF, HALF, BASE, 0, z0, z1)                     # floor slab
    n = max(1, round(length / CELL)); cz = length / n
    for i in range(4):
        for j in range(n):
            if (i + j) % 2 == 0:
                k.box(f1, -HALF + i * CELL, -HALF + (i + 1) * CELL, 0, SKIN, z0 + j * cz, z0 + (j + 1) * cz)
    for s in (-1, 1):
        k.box(w0, s * HALF, s * (HALF + WALL), BASE, TOP, z0, z1)  # wall
        for r in range(2):
            for j in range(n):
                if (r + j) % 2 == 0:
                    k.box(w1, s * (HALF - SKIN), s * HALF, r * WCELL_H, (r + 1) * WCELL_H, z0 + j * cz, z0 + (j + 1) * cz)
        k.box(b["cap"], s * (HALF - 0.625), s * (HALF + WALL), TOP, TOP + 1.25, z0, z1)
    k.box(b["line"], -HALF, HALF, 0, 0.125, z0, z0 + 2.5)          # threshold strip

def props(k, b):
    """Four trees of the biome's own kind (two per side, by the walls) and one landmark on the +x side.
    The middle of the lane (|x| < 20) stays clear for the orb."""
    z0, z1 = b["z0"], b["z1"]; L = z1 - z0
    trees = [(-31, z0 + L * 0.25), (-31, z0 + L * 0.75), (31, z0 + L * 0.14), (31, z0 + L * 0.88)]
    for x, z in trees:
        TREES[b["props"]](k, b, x, z)
    HEROES[b["props"]](k, b, 31, z0 + L * 0.5)

def oak(k, b, x, z):                      # Meadow: a round oak
    t, (l1, l2) = b["trunk"], b["leaf"]
    k.boxc(t, x, 4.5, z, 2.5, 9, 2.5)
    k.boxc(l1, x, 11, z, 11, 6, 11)
    k.boxc(l2, x, 15.5, z, 7, 3, 7)
    for dx, dz in ((5.5, 0), (-5.5, 0), (0, 5.5), (0, -5.5)):
        k.boxc(l2, x + dx, 10.5, z + dz, 5, 4, 5)

def windswept(k, b, x, z):                # Windy Highlands: a tree bent by the wind (leans down the lane)
    t, (l1, l2) = b["trunk"], b["leaf"]
    k.boxc(t, x, 3, z, 2, 6, 2)
    k.boxr(t, x, 7.5, z + 1.2, 1.8, 5, 1.8, "x", 25)
    k.boxc(l1, x, 10.5, z + 5, 7, 3, 12)
    k.boxc(l2, x, 12.5, z + 7, 5, 2, 8)

def pine(k, b, x, z):                     # Tundra: a snowy pine
    k.boxc(b["trunk"], x, 1.5, z, 2, 3, 2)
    for i, (w, y) in enumerate(((11, 4.75), (8.5, 8.25), (6, 11.75), (3.5, 15))):
        k.boxc(b["pine"], x, y, z, w, 3.5, w)
        k.boxc(b["snow"], x, y + 1.95, z, w - 1, 0.4, w - 1)

def palm(k, b, x, z):                     # Jungle Ruins: a leaning palm
    t, (l1, l2) = b["trunk"], b["leaf"]
    lean = -1 if x > 0 else 1                         # palms lean in toward the lane
    for i, (y, off) in enumerate(((2.5, 0), (7.5, 0.8), (12.5, 1.8), (17.5, 3.0))):
        k.boxc(t, x + lean * off, y, z, 2, 5, 2)
    cx = x + lean * 3.0
    k.boxc(l2, cx, 20.5, z, 3, 2, 3)
    for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        k.boxc(l1, cx + dx * 5.5, 20.5, z + dz * 5.5, 9 if dx else 2.5, 1, 2.5 if dx else 9)
        k.boxc(l1, cx + dx * 10, 19.5, z + dz * 10, 3.5 if dx else 2.5, 1, 2.5 if dx else 3.5)

def windmill(k, b, x, z):                 # Meadow landmark: a windmill
    k.boxc("Md_White", x, 11, z, 10, 22, 10)
    for w, y in ((12, 23), (9, 25), (6, 27), (3, 29)):
        k.boxc("Md_Pink", x, y, z, w, 2, w)
    k.boxc("Md_Trunk", x - 5.25, 2.75, z, 0.5, 5.5, 3.5)             # door, facing the lane
    k.boxc("Md_Trunk", x - 5.75, 17, z, 1.5, 2, 2)                  # blade hub
    for deg in (45, 135):
        k.boxr("Md_Yellow", x - 6.75, 17, z, 0.75, 24, 3, "x", deg)   # sails

def henge(k, b, x, z):                    # Windy Highlands landmark: a standing-stone gate
    st = b["rock"]
    k.boxc(st, x, 7, z - 5, 4, 14, 3)
    k.boxc(st, x, 7, z + 5, 4, 14, 3)
    k.boxc(st, x, 15.25, z, 5, 2.5, 14.5)                            # lintel
    for dz, h in ((-14, 10), (14, 9), (-22, 7), (22, 6)):
        k.boxc(st, x + 2, h / 2, z + dz, 3.5, h, 3)

def igloo(k, b, x, z):                    # Tundra landmark: an igloo
    snow, dark = b["snow"], "Tg_CaveDark"
    for w, y, h in ((17, 2, 4), (15, 6, 4), (12, 9.5, 3), (8, 12, 2), (4, 13.5, 1)):
        k.boxc(snow, x, y, z, w, h, w)
    k.boxc(snow, x - 10.5, 2.5, z, 5, 5, 6)                         # entrance tunnel, toward the lane
    k.boxc(dark, x - 13.05, 2, z, 0.1, 3.5, 3)

def temple(k, b, x, z):                   # Jungle Ruins landmark: a step temple
    s1, s2, moss, dark = "Jr_Stone2", "Jr_Stone", "Jr_Moss", "Jr_Dark"
    for i, (w, y) in enumerate(((22, 2), (17, 6), (12, 10))):
        k.boxc(s1 if i % 2 == 0 else s2, x, y, z, w, 4, w)
        k.boxc(moss, x, y + 2.1, z, w - 2, 0.2, w - 2)
    k.boxc(s2, x, 14.5, z, 7, 5, 7)                                  # shrine
    k.boxc(moss, x, 17.1, z, 7.5, 0.2, 7.5)
    k.boxc(dark, x - 3.55, 13.75, z, 0.1, 3, 2.5)                    # shrine door, facing the lane
    for i in range(3):                                               # stairs up the lane side
        k.boxc(s1, x - 11.75 - 0 + i * 2.5 + 0, 1 + i * 2, z, 2.5, 2 + i * 4, 5)

TREES = {"trees": oak, "boulders": windswept, "pines": pine, "jungle": palm}
HEROES = {"trees": windmill, "boulders": henge, "pines": igloo, "jungle": temple}

def archive():
    arch = bpy.data.collections.get("ARCHIVE_pre_formula")
    if not arch:
        arch = bpy.data.collections.new("ARCHIVE_pre_formula")
        bpy.context.scene.collection.children.link(arch)
        arch["export"] = False
    return arch

def build_all():
    arch = archive()
    report = {}
    for b in BIOMES:
        col = bpy.data.collections[b["name"]]
        sub = bpy.data.collections.get("OLD_" + b["name"])
        if not sub:
            sub = bpy.data.collections.new("OLD_" + b["name"])
            arch.children.link(sub)
        moved = 0
        for src in [col] + ([bpy.data.collections[b["name"] + "_Extras"]] if bpy.data.collections.get(b["name"] + "_Extras") else []):
            for o in list(src.objects):
                if o.name.startswith(b["name"] + "_F_"):
                    bpy.data.objects.remove(o)        # a previous run of this script
                    continue
                sub.objects.link(o); src.objects.unlink(o); moved += 1
        k = Kit(b["name"])
        shell(k, b); props(k, b)
        report[b["name"]] = {"archived": moved, "parts": k.build(col)}
    return report

# The hub (Nov 6): a plain walled rectangle in the lane's style, open where the lane starts, so the
# hub runs straight into the lane. Its decoration keeps its layout; only the enclosure changed.
HUB_HALF = 130.0     # inner half width (the hub ground's edge)
HUB_BACK = -232.5    # inner face of the back wall (just behind the cave arch)
HUB_FRONT = 18.75    # where the lane starts
HUB_PARTS = ("Hub_Rim", "Hub_Island", "Hub_SkyWindows", "Hub_Falls", "Hub_Trees", "HomeIsland", "Perches", "Collision")

def hub_walls(k):
    w0, w1, cap = "Hb_Stone", "Hb_Stone2", "Hb_Cap"
    def panels(axis, s, a0, a1, fixed):
        n = max(1, round((a1 - a0) / CELL)); c = (a1 - a0) / n
        for r in range(2):
            for j in range(n):
                if (r + j) % 2 == 0:
                    lo, hi = a0 + j * c, a0 + (j + 1) * c
                    if axis == "x":   # a panel on a side wall (runs along z)
                        k.box(w1, s * (fixed - SKIN), s * fixed, r * WCELL_H, (r + 1) * WCELL_H, lo, hi)
                    else:             # a panel on a wall that runs along x, facing +z (back) or -z (front)
                        k.box(w1, lo, hi, r * WCELL_H, (r + 1) * WCELL_H, fixed, fixed + s * SKIN)
    for s in (-1, 1):
        # side walls, full depth including the corners
        k.box(w0, s * HUB_HALF, s * (HUB_HALF + WALL), BASE, TOP, HUB_BACK - WALL, HUB_FRONT + 10)
        k.box(cap, s * (HUB_HALF - 0.625), s * (HUB_HALF + WALL), TOP, TOP + 1.25, HUB_BACK - WALL, HUB_FRONT + 10)
        panels("x", s, HUB_BACK, HUB_FRONT, HUB_HALF)
        # front walls either side of the lane opening (the lane's own walls fill HALF..HALF+WALL)
        k.box(w0, s * (HALF + WALL), s * HUB_HALF, BASE, TOP, HUB_FRONT, HUB_FRONT + 10)
        k.box(cap, s * (HALF + WALL), s * (HUB_HALF - 0.625), TOP, TOP + 1.25, HUB_FRONT - 0.625, HUB_FRONT + 10)
        lo, hi = sorted((s * (HALF + WALL), s * HUB_HALF))
        panels("z", -1, lo, hi, HUB_FRONT)
    # back wall
    k.box(w0, -HUB_HALF, HUB_HALF, BASE, TOP, HUB_BACK - WALL, HUB_BACK)
    k.box(cap, -(HUB_HALF - 0.625), HUB_HALF - 0.625, TOP, TOP + 1.25, HUB_BACK - WALL, HUB_BACK + 0.625)
    panels("z", 1, -HUB_HALF, HUB_HALF, HUB_BACK)
    # a solid base under the whole hub: the old ground had holes where the rim terraces and sky
    # windows used to be the floor. Its top sits 0.05 below the hub ground so no faces share a plane.
    k.box("Hb_Grass", -HUB_HALF, HUB_HALF, BASE, -0.05, HUB_BACK, HUB_FRONT)

def build_hub():
    arch = archive()
    moved = []
    for name in HUB_PARTS:
        c = bpy.data.collections.get(name)
        if not c or c.name in [x.name for x in arch.children]:
            continue
        for parent in [bpy.context.scene.collection] + list(bpy.data.collections):
            if c.name in [x.name for x in parent.children]:
                parent.children.unlink(c)
        arch.children.link(c)
        moved.append(name)
    col = bpy.data.collections.get("Hub_Walls")
    if not col:
        col = bpy.data.collections.new("Hub_Walls")
        bpy.data.collections["HubSanctuary"].children.link(col)
    for o in list(col.objects):
        bpy.data.objects.remove(o)
    k = Kit("Hub_Walls")
    hub_walls(k)
    return {"archived": moved, "parts": k.build(col)}
