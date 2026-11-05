# Lane export: HubBlock.blend -> MaP/export/ (parts, mesh pieces, markers). Run inside Blender:
#   ns = {}; exec(open("/Users/majorm/HMG/MaP/tools/export_lane.py").read(), ns); ns["run"](["Biome02_WindyHighlands", ...])
# Writes parts/Lane__<biome>.json in the same format as the first export (MaP/EXPORT_SPEC.md):
#   ["B", x, y, z, sx, sy, sz, mat]            axis-aligned box (Roblox studs, centre + size)
#   ["R", x, y, z, sx, sy, sz, mat, [R00..R22]] rotated box, CFrame rotation row by row
# plus lane_materials.json (index -> name, colour, emit) and lane_markers.json.
# Non-box pieces (the Reef's coral meshes) are collected per object and 75-stud chunk into
# meshes/Import_<biome>.fbx, listed in lane_meshes.json.
import bpy, bmesh, json, math, os, collections
from mathutils import Vector, Matrix

ROOT = "/Users/majorm/HMG/MaP/export"
S = 1.25
A = Matrix(((-1, 0, 0), (0, 0, 1), (0, 1, 0)))  # Blender axes -> Roblox axes
CHUNK = 75.0
MAX_TRIS = 1600
RENAME = {"B_Fb_": "Gf_", "B_": ""}  # Blender's B_ prefix drops; the Geyser study's Fb_ becomes Gf_

def rb_point(v):
    return Vector((-S * v.x, S * v.z, S * (v.y - 45)))

def rb_vec(v):
    return S * (A @ v)

def part_name(mat_name):
    import re
    mat_name = re.sub(r"\.\d{3}$", "", mat_name)  # Reef_Kelp.001 -> Reef_Kelp
    for a, b in RENAME.items():
        if mat_name.startswith(a):
            return b + mat_name[len(a):]
    return mat_name

def srgb(c):
    c = max(0.0, min(1.0, c))
    return 12.92 * c if c <= 0.0031308 else 1.055 * (c ** (1 / 2.4)) - 0.055

def objs_in(c):
    s = list(c.objects)
    for ch in c.children:
        s += objs_in(ch)
    return s

def islands(o, dg):
    eo = o.evaluated_get(dg)
    me = eo.to_mesh()
    parent = list(range(len(me.vertices)))
    def f(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a
    for e in me.edges:
        a, b = f(e.vertices[0]), f(e.vertices[1])
        if a != b:
            parent[a] = b
    mw = o.matrix_world
    isl = collections.defaultdict(lambda: {"v": {}, "f": [], "e": []})
    for v in me.vertices:
        isl[f(v.index)]["v"][v.index] = mw @ v.co
    for e in me.edges:
        isl[f(e.vertices[0])]["e"].append(tuple(e.vertices))
    for p in me.polygons:
        isl[f(p.vertices[0])]["f"].append((list(p.vertices), p.material_index))
    eo.to_mesh_clear()
    return list(isl.values())

def frame(origin, vecs):
    """Box from a corner and its three edge vectors (Blender world). -> record or None."""
    flat = [i for i, v in enumerate(vecs) if v.length < 1e-6]
    if len(flat) == 1:
        # A box squashed flat: give it a plane's thickness (0.05, 0.0625 studs) about its middle.
        a, b = [vecs[i] for i in range(3) if i != flat[0]]
        n = a.cross(b).normalized() * 0.05
        origin = origin - 0.5 * n
        vecs = list(vecs); vecs[flat[0]] = n
    centre = origin + 0.5 * (vecs[0] + vecs[1] + vecs[2])
    rv = [rb_vec(v) for v in vecs]
    c = rb_point(centre)
    lens = [v.length for v in rv]
    if min(lens) < 1e-6:
        return None
    units = [v / l for v, l in zip(rv, lens)]
    aligned = all(max(abs(u.x), abs(u.y), abs(u.z)) > 0.9999 for u in units)
    # Assign each edge to the Roblox axis it points along most (greedy, unique), sign positive.
    order = [None, None, None]
    free = [0, 1, 2]
    pairs = sorted(((abs(units[i][ax]), i, ax) for i in range(3) for ax in range(3)), reverse=True)
    used_i = set()
    for _, i, ax in pairs:
        if i in used_i or order[ax] is not None:
            continue
        order[ax] = i
        used_i.add(i)
    cols = []
    size = []
    for ax in range(3):
        i = order[ax]
        u = units[i]
        if u[ax] < 0:
            u = -u
        cols.append(u)
        size.append(lens[i])
    m = Matrix((cols[0], cols[1], cols[2])).transposed()
    if m.determinant() < 0:
        cols[2] = -cols[2]
        m = Matrix((cols[0], cols[1], cols[2])).transposed()
    r3 = lambda x: round(x, 3)
    pos = [r3(c.x), r3(c.y), r3(c.z)]
    sz = [r3(s) for s in size]
    if aligned:
        return ("B", pos, sz, None)
    rot = [round(m[r][k], 5) for r in range(3) for k in range(3)]
    return ("R", pos, sz, rot)

def box_record(d):
    verts = d["v"]
    if len(verts) != 8 or len(d["f"]) != 6:
        return None
    adj = collections.defaultdict(set)
    for a, b in d["e"]:
        adj[a].add(b); adj[b].add(a)
    v0 = next(iter(verts))
    vecs = [verts[n] - verts[v0] for n in adj[v0]]
    if len(vecs) != 3:
        # A box whose faces were split along a diagonal: keep the three mutually square edges.
        import itertools
        for trio in itertools.combinations(vecs, 3):
            if all(abs(a.normalized().dot(b.normalized())) < 1e-3 for a, b in itertools.combinations(trio, 2)):
                vecs = list(trio)
                break
        else:
            return None
    if any(v.length < 1e-6 for v in vecs):
        return frame(verts[v0], vecs)
    o = verts[v0]
    corners = [o + i * vecs[0] + j * vecs[1] + k * vecs[2] for i in (0, 1) for j in (0, 1) for k in (0, 1)]
    square = all(abs(a.normalized().dot(b.normalized())) < 1e-3 for a, b in ((vecs[0], vecs[1]), (vecs[0], vecs[2]), (vecs[1], vecs[2])))
    if square and all(min((c - v).length for v in verts.values()) < 1e-3 for c in corners):
        return frame(o, vecs)
    # Eight corners but not a box (a tapered segment, like the Reef's tentacles): use the box with
    # its average edges. Each of the 12 edges joins the direction it runs along most.
    dirs = [v.normalized() for v in vecs]
    sums = [Vector(), Vector(), Vector()]
    for a, b in d["e"]:
        e = verts[b] - verts[a]
        k = max(range(3), key=lambda i: abs(e.dot(dirs[i])))
        sums[k] += e if e.dot(dirs[k]) >= 0 else -e
    avg = [s_ / 4 for s_ in sums]
    order = sorted(range(3), key=lambda i: -avg[i].length)
    u = avg[order[0]]
    v = avg[order[1]] - avg[order[1]].project(u)
    w = u.cross(v).normalized() * avg[order[2]].length
    if w.dot(avg[order[2]]) < 0:
        w = -w
    centre = sum(verts.values(), Vector()) / 8
    return frame(centre - 0.5 * (u + v + w), [u, v, w])

def plane_record(d):
    verts = d["v"]
    if len(verts) != 4 or len(d["f"]) != 1:
        return None
    ids = d["f"][0][0]
    p = [verts[i] for i in ids]
    e1 = p[1] - p[0]
    e2 = p[3] - p[0]
    n = e1.cross(e2)
    if n.length < 1e-9:
        return None
    n = n.normalized() * 0.05
    return frame(p[0] - 0.5 * n, [e1, e2, n])

def merge_boxes(recs):
    """Join axis-aligned boxes of one material that share a full face (same look, fewer parts)."""
    changed = True
    while changed:
        changed = False
        for ax in range(3):
            o1, o2 = [k for k in range(3) if k != ax]
            groups = collections.defaultdict(list)
            for i, r in enumerate(recs):
                if r is None or r[0] != "B":
                    continue
                key = (r[3], round(r[1][o1], 3), round(r[1][o2], 3), round(r[2][o1], 3), round(r[2][o2], 3))
                groups[key].append(i)
            for idx in groups.values():
                if len(idx) < 2:
                    continue
                idx.sort(key=lambda i: recs[i][1][ax])
                cur = idx[0]
                for nxt in idx[1:]:
                    a, b = recs[cur], recs[nxt]
                    a_end = a[1][ax] + a[2][ax] / 2
                    b_start = b[1][ax] - b[2][ax] / 2
                    if abs(a_end - b_start) < 0.002:
                        lo = a[1][ax] - a[2][ax] / 2
                        hi = b[1][ax] + b[2][ax] / 2
                        pos = list(a[1]); size = list(a[2])
                        pos[ax] = round((lo + hi) / 2, 3); size[ax] = round(hi - lo, 3)
                        recs[cur] = ("B", pos, size, a[3], None)
                        recs[nxt] = None
                        changed = True
                    else:
                        cur = nxt
        recs[:] = [r for r in recs if r is not None]
    return recs

def material_info(m):
    col = (0.8, 0.8, 0.8); em = 0.0
    if m and m.use_nodes:
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        if bsdf:
            col = tuple(bsdf.inputs["Base Color"].default_value[:3])
            em = float(bsdf.inputs["Emission Strength"].default_value)
    return {"name": part_name(m.name) if m else "Unnamed",
            "rgb": [round(255 * srgb(x)) for x in col], "emit": round(em, 3)}

def run(biomes, write_fbx=True):
    dg = bpy.context.evaluated_depsgraph_get()
    os.makedirs(ROOT + "/parts", exist_ok=True)
    os.makedirs(ROOT + "/meshes", exist_ok=True)
    mats = []; mat_index = {}
    def mid(m):
        key = m.name if m else "Unnamed"
        if key not in mat_index:
            mat_index[key] = len(mats)
            mats.append(material_info(m))
        return mat_index[key]
    report = {}; mesh_slots = []
    for biome in biomes:
        cols = [bpy.data.collections[biome]]
        extra = bpy.data.collections.get(biome + "_Extras")
        if extra:
            cols.append(extra)
        recs = []
        pieces = collections.defaultdict(list)  # (object, chunk) -> list of island dicts
        stats = collections.Counter()
        for c in cols:
            for o in objs_in(c):
                if o.type != 'MESH' or o.hide_get() or o.hide_render:
                    continue
                for d in islands(o, dg):
                    if not d["f"]:
                        continue
                    mi_counts = collections.Counter(mi for _, mi in d["f"])
                    mi = mi_counts.most_common(1)[0][0]
                    m = o.material_slots[mi].material if mi < len(o.material_slots) else None
                    r = box_record(d) or plane_record(d)
                    if r:
                        recs.append((r[0], r[1], r[2], mid(m), r[3]))
                        stats["box" if len(d["v"]) == 8 else "plane"] += 1
                    else:
                        cz = rb_point(sum(d["v"].values(), Vector()) / len(d["v"])).z
                        pieces[(o.name, int(math.floor(cz / CHUNK)), mid(m))].append(d)
                        stats["mesh_island"] += 1
        before = len(recs)
        merge_boxes(recs)
        parts = []
        for kind, pos, size, m, rot in recs:
            row = [kind, pos[0], pos[1], pos[2], size[0], size[1], size[2], m]
            if kind == "R":
                row.append(rot)
            parts.append(row)
        with open(f"{ROOT}/parts/Lane__{biome}.json", "w") as fh:
            json.dump({"group": f"Lane/{biome}", "parts": parts}, fh, separators=(",", ":"))
        # Mesh pieces: one object per (source object, chunk), vertices in Roblox studs about its centre.
        made = []
        for (oname, chunk, m), isls in sorted(pieces.items()):
            short = oname[len(biome) + 1:] if oname.startswith(biome + "_") else oname
            bm = bmesh.new()
            # Size the piece from vertices that belong to a face: Studio drops loose ones on import.
            used = [d["v"][i] for d in isls for ids, _ in d["f"] for i in ids]
            pts = [rb_point(v) for v in used]
            lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
            hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
            ctr = (lo + hi) / 2
            tris = 0
            for d in isls:
                vmap = {}
                for i, v in d["v"].items():
                    p = rb_point(v) - ctr
                    # Stored so the FBX (Y up, -Z forward) carries Roblox axes: (x, y, z) -> Blender (x, -z, y)
                    vmap[i] = bm.verts.new((p.x, -p.z, p.y))
                for ids, _ in d["f"]:
                    try:
                        bm.faces.new([vmap[i] for i in ids])
                        tris += len(ids) - 2
                    except ValueError:
                        pass
            name = f"{biome}__{short}__{chunk}_0"
            me = bpy.data.meshes.new(name)
            bm.to_mesh(me); bm.free()
            ob = bpy.data.objects.new(name, me)
            made.append(ob)
            mesh_slots.append({"name": name, "group": f"Lane/{biome}", "mat": m,
                               "pos": [round(ctr.x, 3), round(ctr.y, 3), round(ctr.z, 3)],
                               "size": [round(hi.x - lo.x, 3), round(hi.y - lo.y, 3), round(hi.z - lo.z, 3)],
                               "tris": tris})
        if made and write_fbx:
            tmp = bpy.data.collections.new("_export_tmp")
            bpy.context.scene.collection.children.link(tmp)
            for ob in made:
                tmp.objects.link(ob)
            for ob in bpy.context.selected_objects:
                ob.select_set(False)
            for ob in made:
                ob.select_set(True)
            bpy.ops.export_scene.fbx(filepath=f"{ROOT}/meshes/Import_{biome}.fbx", use_selection=True,
                                     axis_forward='-Z', axis_up='Y', apply_unit_scale=True,
                                     apply_scale_options='FBX_SCALE_UNITS', object_types={'MESH'},
                                     mesh_smooth_type='FACE', use_mesh_modifiers=False, bake_space_transform=False)
            for ob in made:
                me = ob.data
                bpy.data.objects.remove(ob)
                bpy.data.meshes.remove(me)
            bpy.data.collections.remove(tmp)
        elif made:
            for ob in made:
                me = ob.data
                bpy.data.objects.remove(ob)
                bpy.data.meshes.remove(me)
        report[biome] = {"islands": dict(stats), "parts_before_merge": before, "parts": len(parts),
                         "meshes": len(made), "R": sum(1 for p in parts if p[0] == "R")}
    markers = []
    for cn, folder in (("AnimalSpots", "AnimalSpot"), ("FX_Anchors", "FXAnchor")):
        for o in bpy.data.collections[cn].objects:
            p = rb_point(o.matrix_world.translation)
            props = {k: o[k] for k in o.keys() if not k.startswith("_") and isinstance(o[k], (int, float, str))}
            markers.append({"name": o.name, "tag": folder,
                            "pos": [round(p.x, 3), round(p.y, 3), round(p.z, 3)], "props": props})
    with open(f"{ROOT}/lane_materials.json", "w") as fh:
        json.dump(mats, fh, separators=(",", ":"))
    with open(f"{ROOT}/lane_meshes.json", "w") as fh:
        json.dump(mesh_slots, fh, separators=(",", ":"))
    with open(f"{ROOT}/lane_markers.json", "w") as fh:
        json.dump(markers, fh, separators=(",", ":"))
    return report
