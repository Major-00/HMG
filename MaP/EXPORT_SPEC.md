# Map export spec

How `MaP/HubBlock.blend` becomes the map in Roblox Studio, and how to keep it identical.
Blender is the source of truth. Never hand-edit `Workspace.Map` in Studio: change the .blend
and rebuild. The export data lives in `MaP/export/` (not in git; rebuild it from the .blend).

## Scale and alignment

- **Scale: 1.25.** Every position and size is the Blender value x 1.25. Chosen Nov 5 so a typical
  avatar with hair (about 6.3 studs) reads the way the 5-stud scale figures do in Blender.
  The avatar itself is never scaled.
- **Axes:** Roblox X = -1.25 x Blender X; Roblox Y = 1.25 x Blender Z; Roblox Z = 1.25 x (Blender Y - 45).
  Blender's +Y (down the lane) is Roblox +Z, the way the ball flies. Blender east (+X) is Roblox -X,
  so it stays on the right when you face the lane.
- **Anchor:** Blender (0, 45, 0), the launch strip's front edge, is Roblox (0, 0, 0), the hit line.
  The floor is Y = 0 in both.
- **Units:** 1 Blender unit = 1 stud before scaling (scene unit scale 1, view transform Standard).

## Look

- **Colours:** each material's base colour converted from linear to sRGB, so Roblox shows what
  Blender's Standard view shows. 184 materials.
- **Material:** SmoothPlastic everywhere. No studs texture for now. Neon only for real light
  sources (lava, embers, seams, cave glow, the Pyramids' glows). No transparency anywhere except
  the invisible collision walls.
- **Lighting:** a fresh Baseplate's defaults. Old Atmosphere and Bloom wash colours out.

## Groups

Built under `Workspace.Map`: `Hub` (one Persistent model) and `Lane` (one model per biome, Atomic,
LevelOfDetail = StreamingMesh). 12291 parts in all. Bounds are Roblox studs.

| Group | Parts | Bounds (min to max) |
|---|---|---|
| `Hub/CaveArch` | 54 | (-20.0, 0.0, -230.0) to (22.5, 30.0, -175.625) |
| `Hub/Collision` | 23 | (-155.0, 0.0, -241.25) to (155.0, 20.0, -28.75) |
| `Hub/DisplayLedge` | 2 | (28.75, 0.0, -165.0) to (41.25, 2.5, -145.0) |
| `Hub/Hub_Basin` | 72 | (-40.0, -36.25, -166.25) to (40.0, 37.5, -13.75) |
| `Hub/Hub_Details` | 132 | (-110.5, -0.0, -200.375) to (113.75, 2.979, -14.0) |
| `Hub/Hub_Details2` | 60 | (-96.25, -0.0, -184.375) to (89.75, 3.25, -19.625) |
| `Hub/Hub_Falls` | 8 | (-71.25, -0.0, -16.0) to (71.25, 27.5, -3.75) |
| `Hub/Hub_Ground` | 113 | (-130.0, -1.25, -216.25) to (130.0, 0.0, 18.75) |
| `Hub/Hub_Island` | 41 | (-185.0, -3.75, -273.75) to (185.0, -1.25, 101.25) |
| `Hub/Hub_Overlook` | 26 | (-22.5, -3.437, -191.875) to (22.5, 14.062, -158.75) |
| `Hub/Hub_Rim` | 784 | (-182.5, -1.25, -266.25) to (182.5, 37.5, 93.75) |
| `Hub/Hub_SkyWindows` | 56 | (-148.625, -1.25, -233.25) to (149.438, 5.85, -184.25) |
| `Hub/Hub_Trees` | 40 | (-142.5, 16.25, -215.625) to (140.625, 49.375, 58.75) |
| `Hub/Hub_Walks` | 149 | (-102.5, 0.0, -158.75) to (102.5, 0.375, 18.75) |
| `Hub/LaunchZone` | 5 | (-22.5, 0.25, -12.5) to (22.5, 0.5, 0.0) |
| `Hub/LeaderboardWall` | 49 | (-117.5, -1.25, -128.75) to (-101.25, 23.25, -43.75) |
| `Hub/Perches` | 16 | (-163.125, 7.5, -235.625) to (126.875, 38.75, 25.625) |
| `Hub/Stalls` | 88 | (-98.75, 0.0, -61.25) to (-46.25, 51.25, -13.0) |
| `Lane/Biome01_Meadow` | 516 | (-51.047, -2.5, 18.75) to (51.047, 53.75, 206.25) |
| `Lane/Biome02_WindyHighlands` | 1917 | (-89.6, -2.5, 206.25) to (90.024, 63.672, 477.332) |
| `Lane/Biome03_Tundra` | 2076 | (-76.135, -3.48, 456.25) to (77.696, 68.75, 768.75) |
| `Lane/Biome04_JungleRuins` | 1879 | (-88.455, -2.5, 768.75) to (88.43, 65.364, 1143.75) |
| `Lane/Biome05_CoralReef` | 866 | (-97.5, -1.25, 1143.75) to (97.5, 52.5, 1612.5) |
| `Lane/Biome06_Volcano` | 2817 | (-343.75, -3.088, 1612.5) to (112.641, 192.5, 2180.287) |
| `Lane/LaneEnd_Beyond` | 61 | (-256.25, -0.0, 2343.75) to (231.25, 256.25, 2656.25) |
| `Lane/LaneEnd_Veil` | 441 | (-110.0, -4.375, 2098.213) to (110.0, 48.75, 2262.5) |

Plus 94 mesh pieces in three files under `MaP/export/meshes/` (Reef 64,
Volcano 21, island underside 9), each under 1,600 triangles.

## Collision

- **Hub:** floors, walls, rim, steps, the Orb Tree climb and the launcher pads collide. Decoration
  doesn't, and isn't queried: leaves, flowers, vines, inlays, gems, crystals, hanging orbs.
- **Lane:** nothing collides or is queried. Players never walk it; the ball's flight is computed.
- **Collision walls:** the lane gap and the two sky windows, invisible (Transparency 1), solid.
- No part is touchable (CanTouch off). Parts smaller than 3 studs cast no shadow.

## Markers

Invisible 1-stud parts under `Workspace.Map.Markers`, tagged with CollectionService:
`HubSpawn` (part `Spawn` at (-0.0, 5.562, -178.75), on the overlook emblem), `OrbLaunch` (5),
`AnimalSpot` (36), `FXAnchor` (19, attribute `effect`), `DisplaySpot` (5), `LauncherSpot` (4),
`PreviewSpot` (4, facing the Reveal Ring). The three billboard faces are tagged `BoardFace`:
`Board_LuckiestCatch`, `Board_LongestLaunch`, `Board_NextUpdate`.

## Code that must match the map (`src/shared/Config/Tuning.luau`)

- `World.HIT_ZONE = { back = -12.5, front = 0 }`: the launch strip, 45 wide and 12.5 deep.
- `World.LANE_SPACING = 7.5` with `LANE_COUNT = 5`.
- `BiomeStarts = { 0, 206, 456, 769, 1144, 1613 }`: each biome's floor edge from the hit line.
  The lane ends at the Pyramids veil, 2,175 studs out.
- `Distance = { BASE = 25, PER_POWER = 12.5 }`: scaled too, so Windy Highlands still comes on hit 15.
- `World.STRIKE_HEIGHT = 3` stays: it's relative to the avatar, which isn't scaled.
- Spawn comes from the `Spawn` marker (`WorldService`), so it follows the map on its own.

If the scale ever changes, all of these change with it.

## Rebuilding

**Never hide a collection that gets exported.** Blender stops updating world positions inside a
viewport-hidden collection, so the export reads stale ones. On Nov 5 that put the lane-gap barrier
across the Orb Walk. Hide the objects instead (the Collision objects are hidden one by one).

1. In Blender, run the export (classify, merge, write `MaP/export/`).
2. In Studio, delete `Workspace.Map` and build it from `MaP/export/` (parts in chunks of 600).
3. Import the three FBX files with Import 3D, then run the mesh placement (by piece name, from
   `manifest.json`).
4. Check: part counts match the table above, the spawn is on the emblem, and a play test hits.
