# Turns MaP/export/parts/Lane__*.json into build files for Studio, with the matching-faces fix
# (MaP/EXPORT_SPEC.md) already applied: where two axis-aligned boxes share a face plane, face the
# same way and overlap, the bigger one steps that face back 0.06 studs (attribute FaceInset).
# Usage: python3 prepare_build.py OUT_DIR Biome02_WindyHighlands ... [--fixed Biome01_Meadow]
#   --fixed biomes are already in Studio: they're checked against but never changed (the new
#   part moves instead).
# Each output row: [x, y, z, sx, sy, sz, mat, rot (9 numbers) or 0, inset (0/1)]
import json, sys, os, collections

ROOT = os.path.join(os.path.dirname(__file__), "..", "export")
STEP = 0.06
MAX_STEPS = 2
CHUNK = 900

def load(b):
    return json.load(open(f"{ROOT}/parts/Lane__{b}.json"))["parts"]

def faces(rows):
    out = collections.defaultdict(list)
    for i, r in enumerate(rows):
        if r["kind"] != "B":
            continue
        for ax in range(3):
            for sgn in (-1, 1):
                plane = round(r["pos"][ax] + sgn * r["size"][ax] / 2, 3)
                out[(ax, sgn, plane)].append(i)
    return out

def overlap(a, b, ax):
    for k in range(3):
        if k == ax:
            continue
        lo = max(a["pos"][k] - a["size"][k] / 2, b["pos"][k] - b["size"][k] / 2)
        hi = min(a["pos"][k] + a["size"][k] / 2, b["pos"][k] + b["size"][k] / 2)
        if hi - lo <= 0.01:
            return False
    return True

def vol(r):
    return r["size"][0] * r["size"][1] * r["size"][2]

def main():
    out_dir = sys.argv[1]
    args = sys.argv[2:]
    fixed = args[args.index("--fixed") + 1:] if "--fixed" in args else []
    biomes = args[:args.index("--fixed")] if "--fixed" in args else args
    mats = json.load(open(f"{ROOT}/lane_materials.json"))
    neon = {i for i, m in enumerate(mats) if m["emit"] >= 0.9}
    rows = []
    for b in biomes + fixed:
        for p in load(b):
            rows.append({"biome": b, "fixed": b in fixed, "kind": p[0], "pos": list(p[1:4]),
                         "size": list(p[4:7]), "mat": p[7], "rot": p[8] if p[0] == "R" else 0, "inset": 0})
    fixes = 0
    steps = collections.Counter()  # (row, axis, side) -> times stepped; capped at MAX_STEPS
    for _ in range(6):
        changed = 0
        done = set()  # (row, axis, side): each face steps at most once per pass
        for (ax, sgn, plane), idx in faces(rows).items():
            if len(idx) < 2:
                continue
            for i in range(len(idx)):
                for j in range(i + 1, len(idx)):
                    a, b = rows[idx[i]], rows[idx[j]]
                    if a["fixed"] and b["fixed"]:
                        continue
                    if a["mat"] == b["mat"] and a["mat"] in neon:
                        continue
                    if not overlap(a, b, ax):
                        continue
                    big, small = (a, b) if vol(a) >= vol(b) else (b, a)
                    bi, si = (idx[i], idx[j]) if big is a else (idx[j], idx[i])
                    if (bi, ax, sgn) in done or (si, ax, sgn) in done:
                        continue
                    mover = si if (big["fixed"] or big["size"][ax] <= 2 * STEP) else bi
                    if steps[(mover, ax, sgn)] >= MAX_STEPS:
                        continue
                    steps[(mover, ax, sgn)] += 1
                    if big["fixed"] or big["size"][ax] <= 2 * STEP:
                        done.add((si, ax, sgn))
                        # Can't step the big face back: move the small part's face out instead.
                        small["size"][ax] = round(small["size"][ax] + STEP, 3)
                        small["pos"][ax] = round(small["pos"][ax] + sgn * STEP / 2, 3)
                        small["inset"] = 1
                    else:
                        done.add((bi, ax, sgn))
                        big["size"][ax] = round(big["size"][ax] - STEP, 3)
                        big["pos"][ax] = round(big["pos"][ax] - sgn * STEP / 2, 3)
                        big["inset"] = 1
                    changed += 1
        fixes += changed
        if not changed:
            break
    os.makedirs(out_dir, exist_ok=True)
    for f in os.listdir(out_dir):
        if f.endswith(".json"):
            os.remove(os.path.join(out_dir, f))
    report = {}
    for b in biomes:
        mine = [r for r in rows if r["biome"] == b]
        data = [r["pos"] + r["size"] + [r["mat"], r["rot"], r["inset"]] for r in mine]
        n = 0
        for k in range(0, len(data), CHUNK):
            json.dump({"biome": b, "rows": data[k:k + CHUNK]},
                      open(f"{out_dir}/{b}_{n}.json", "w"), separators=(",", ":"))
            n += 1
        report[b] = {"parts": len(data), "files": n, "inset": sum(r["inset"] for r in mine)}
    json.dump([{"name": m["name"], "rgb": m["rgb"]} for m in mats], open(f"{out_dir}/materials.json", "w"),
              separators=(",", ":"))
    classes = json.load(open(os.path.join(os.path.dirname(__file__), "lane_classes.json")))["classes"]
    json.dump(classes, open(f"{out_dir}/classes.json", "w"), separators=(",", ":"))
    print(json.dumps({"fixes": fixes, "biomes": report}))

main()
