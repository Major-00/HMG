# Ladder toolkit: lighten biomes without changing their read. Run inside Blender.
import bpy, bmesh, json, math
from mathutils import Vector
HITS = json.load(open("/Users/majorm/HMG/MaP/export/firestudy/vis_hits.json"))
MOD = set()            # objects rebuilt this session: their old visibility data no longer lines up

def islands(o):
    me = o.data; parent = list(range(len(me.vertices)))
    def f(a):
        while parent[a] != a: parent[a] = parent[parent[a]]; a = parent[a]
        return a
    for e in me.edges:
        a, b = f(e.vertices[0]), f(e.vertices[1])
        if a != b: parent[a] = b
    mw = o.matrix_world; isl = {}
    for v in me.vertices:
        r = f(v.index); w = mw @ v.co
        d = isl.setdefault(r, {"verts": [], "bb": [1e9]*3 + [-1e9]*3, "seen": 0, "pts": set()})
        d["verts"].append(v.index); d["pts"].add((round(w.x, 2), round(w.y, 2), round(w.z, 2)))
        for k in range(3): d["bb"][k] = min(d["bb"][k], w[k]); d["bb"][3+k] = max(d["bb"][3+k], w[k])
    if o.name in MOD:
        for d in isl.values(): d["seen"] = 1
    else:
        h = HITS.get(o.name, {})
        for p in me.polygons:
            n = h.get(str(p.index), 0)
            if n: isl[f(p.vertices[0])]["seen"] += n
    return list(isl.values())

def aligned(d):
    xs = {p[0] for p in d["pts"]}; ys = {p[1] for p in d["pts"]}; zs = {p[2] for p in d["pts"]}
    return len(d["pts"]) == 8 and len(xs) == 2 and len(ys) == 2 and len(zs) == 2

def rebuild(o, keep, add_boxes):
    me = o.data
    bm = bmesh.new(); bm.from_mesh(me); bm.verts.ensure_lookup_table()
    keepv = set(i for d in keep for i in d["verts"])
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.index not in keepv], context='VERTS')
    inv = o.matrix_world.inverted()
    for (x0, x1, y0, y1, z0, z1) in add_boxes:
        vs = [bm.verts.new(inv @ Vector(p)) for p in ((x0,y0,z0),(x1,y0,z0),(x1,y1,z0),(x0,y1,z0),(x0,y0,z1),(x1,y0,z1),(x1,y1,z1),(x0,y1,z1))]
        for fc in ((0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)):
            bm.faces.new([vs[i] for i in fc])
    bm.to_mesh(me); bm.free(); me.update()
    MOD.add(o.name)

def drop_unseen(o):
    isl = islands(o)
    keep = [d for d in isl if d["seen"] > 0]
    if len(keep) != len(isl): rebuild(o, keep, [])
    return len(isl), len(keep)

def mid(d):
    b = d["bb"]; return sorted((b[3]-b[0], b[4]-b[1], b[5]-b[2]))[1]

def tufts(o, cell=6.0, zcell=3.0, foot=1.0, max_foot=3.6, keep_big=1.5):
    """Collapse pieces smaller than keep_big (middle size) into one chunky block per cluster."""
    isl = [d for d in islands(o) if d["seen"] > 0]
    big = [d for d in isl if mid(d) >= keep_big]
    small = [d for d in isl if mid(d) < keep_big]
    groups = {}
    for d in small:
        b = d["bb"]; cx, cy = (b[0]+b[3])/2, (b[1]+b[4])/2
        groups.setdefault((math.floor(cx/cell), math.floor(cy/cell), math.floor(b[2]/zcell)), []).append(d)
    add = []
    for g in groups.values():
        cx = sum((d["bb"][0]+d["bb"][3])/2 for d in g)/len(g); cy = sum((d["bb"][1]+d["bb"][4])/2 for d in g)/len(g)
        ux0 = min(d["bb"][0] for d in g); ux1 = max(d["bb"][3] for d in g)
        uy0 = min(d["bb"][1] for d in g); uy1 = max(d["bb"][4] for d in g)
        z0 = min(d["bb"][2] for d in g)
        tops = sorted(d["bb"][5] for d in g); z1 = tops[int(0.8*(len(tops)-1))]
        w = min(max_foot, foot*(1 + 0.45*math.sqrt(len(g))))
        hx = max(0.9, min(w, (ux1-ux0)/2 + 0.6)); hy = max(0.9, min(w, (uy1-uy0)/2 + 0.6))
        add.append((cx-hx, cx+hx, cy-hy, cy+hy, z0, max(z1, z0 + 1.0)))
    rebuild(o, big, add)
    return len(isl), len(big) + len(add)

def merge_runs(o, tol=0.8, axis=1):
    """Join axis-aligned neighbours along the lane (y) that share the same x range and nearly the same z range."""
    isl = [d for d in islands(o) if d["seen"] > 0]
    al = [d for d in isl if aligned(d)]; other = [d for d in isl if not aligned(d)]
    groups = {}
    for d in al:
        b = d["bb"]; groups.setdefault((round(b[0], 1), round(b[3], 1)), []).append(b[:])
    out = []
    for bs in groups.values():
        bs.sort(key=lambda b: b[1]); cur = bs[0]
        for b in bs[1:]:
            if b[1] <= cur[4] + 0.05 and abs(b[2] - cur[2]) < tol and abs(b[5] - cur[5]) < tol:
                cur = [cur[0], cur[1], (cur[2] + b[2])/2, cur[3], max(cur[4], b[4]), (cur[5] + b[5])/2]
            else:
                out.append(cur); cur = b
        out.append(cur)
    rebuild(o, other, [(b[0], b[3], b[1], b[4], b[2], b[5]) for b in out])
    return len(isl), len(other) + len(out)

def count(colnames):
    if isinstance(colnames, str): colnames = [colnames]
    n = 0
    for cn in colnames:
        c = bpy.data.collections.get(cn)
        if c: n += sum(len(islands(o)) for o in c.all_objects if o.type == 'MESH')
    return n
