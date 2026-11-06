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
- **Material: two kinds of square studs, plus smooth** (approved Nov 5, from the Steal An Egg
  reference). Two MaterialVariants in MaterialService, both Plastic, StudsPerTile 5 (4 studs at
  1.25 scale): `LobStudsRaised` (studs pop up) and `LobStudsSunk` (studs sit in a recess with a
  raised lip). `MaterialService:SetBaseMaterialOverride(Plastic, "LobStudsRaised")`, so plain
  Plastic means raised.
  - **Raised (Plastic):** floors, walls and terrain. Grass, GrassCap, Stone, Ridge, Strata, Snow,
    Moss, Pave, ruin walls (Dark), reef rock walls, ice sheets (IceDeep, IceLight, IceMid), cave
    walls. Geyser Flats: the runoff floor (FCrust, FGreen, FYellow, FOrange, FRust, FUmber and their
    `_d` shades), the wall tiers (WSinter, WOchre, WSlate, Basalt and their tops, ColumnTop), the
    rust band and pale line, Algae ledges, travertine terraces (Travertine, TravShade).
  - **Sunk (Plastic + `LobStudsSunk`):** designed objects. Trunks, leaves, hedges, ivy, heather,
    gorse, pines, the hub's clouds and tree pieces. Rocks are sunk as boulders, raised when 15+
    studs long (cliffs). In the hub, everything in Hub_Details, Hub_Details2 and Hub_Trees is sunk.
    Geyser Flats: the dead trees (Snag, SnagSock), the sinter chimneys, geyser cones and the
    Crown Geyser (Sinter, Sinter2).
  - **Smooth (SmoothPlastic):** water and ice falls, flowers, gems, gold, crystals, corals, kelp,
    tentacles, starfish, cracks, icicles, the reef sand (it has to match the smooth sand mesh),
    billboard faces (`Board_*`), and any part thinner than 1.25 studs in its middle dimension.
    Geyser Flats: the spring rings and pools (Deep, Turq, MatGreen, MatYellow, MatOrange, Rust,
    FTurq), TravPool, Water, mud pots (Mud, MudDark), sulfur crusts.
  - **All meshes stay smooth.** Neon only for real light sources (the Geyser Flats' vents, the
    eternal flame and the Crown Geyser's heart, cave glow). No transparency anywhere except the invisible collision walls.
- **No matching faces.** Where two parts share a face plane and overlap (the hub rim and the
  Meadow walls at the entrance, bark on trunks, walks on the basin), Studio flickers between
  them, and with studs two stud grids shimmer. After building, the bigger part of each pair steps
  that face back 0.06 studs so the smaller detail draws on top (attribute `FaceInset` records it).
  Repeat until nothing is left except same-colour Neon (thin glows, which can't flicker).
  Blender keeps the true shapes; this is a build step, not a design change.
- **Stud textures preload** from `src/first/PreloadStuds.client.luau` (ReplicatedFirst). If the
  stud image IDs change, change them there too.
- **Lighting:** set in `default.project.json`, so Rojo keeps it. Since Nov 6 it follows Steal An
  Egg: neutral and bright, so the colour comes from the materials, not from a colour filter.
  Realistic style, Brightness 3, exposure 0, OutdoorAmbient 128/128/136, Ambient 70/70/78,
  ColorShift_Top white, EnvironmentDiffuseScale 0.4, specular 0.15, ClockTime 14.5,
  ColorCorrection saturation +0.1, contrast +0.1. The sky is the `Stylized` Sky the team picked
  (Nov 6); it lives in the place file, not in Rojo.
- **Colours (Nov 6):** the hub, the Meadow and biomes 2 to 5 were repainted after Steal An Egg,
  whose colours were measured from 30 frames of their lane. Every grass biome has its own green
  (hub spring green, Meadow lime, Highlands emerald, Jungle Ruins yellow-olive), floors keep a
  visible two-tone checker, the Meadow and hub walls are dirt brown, the Highlands and Jungle
  walls blue-grey stone, and the Reef is golden sand with saturated coral. The 97 values are in
  `MaP/tools/palette_nov6.json` and in the Blender materials. They were calibrated with swatches
  in Studio so each renders at its target under this lighting: change the lighting and they
  need recalibrating. The Geyser Flats kept their colours.

## Groups

Built under `Workspace.Map`: `Hub` (one Persistent model) and `Lane` (one model per biome, Atomic,
LevelOfDetail = StreamingMesh). 9,512 parts in all since the Nov 5 evening rebuild (12,291 before
the ladder), plus the Reef's mesh pieces. Bounds are Roblox studs.
Streaming: target radius 1,024 around the player, StreamOutBehavior LowMemory (biomes stay loaded
unless the device runs short of memory). The lane runs to about 2,294, so `StreamController` asks
for the landing area the moment a flight starts.

The hub rows are from the first 1.25x export (Nov 5 morning); the lane rows are from the rebuild
after the detail ladder (Nov 5 evening), when the Geyser Flats replaced the Volcano and the Pyramids
ending.

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
| `Lane/Biome02_WindyHighlands` | 1170 | (-89.6, -2.5, 206.2) to (88.9, 63.7, 477.3) |
| `Lane/Biome03_Tundra` | 1266 | (-74.3, -4.8, 456.2) to (75.5, 68.8, 768.8) |
| `Lane/Biome04_JungleRuins` | 1489 | (-88.5, -2.5, 768.8) to (88.4, 65.4, 1143.8) |
| `Lane/Biome05_CoralReef` | 525 + 66 meshes | (-97.5, 0.0, 1143.8) to (97.5, 40.4, 1612.5), parts only |
| `Lane/Biome06_GeyserFlats` | 2819 | (-140.0, -1.2, 1612.5) to (137.5, 94.6, 2322.3) |

Plus mesh pieces under `MaP/export/meshes/`: the Reef's 66 (`Import_Biome05_CoralReef.fbx`,
27,800 triangles, re-exported after the ladder) and the island underside's 9, each under 1,600
triangles. The Reef's sand floor is a plain part since the ladder.

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
  The lane ends at the Geyser Flats' closing cliff, about 2,294 studs out (reached on hit 182).
- `Distance = { BASE = 25, PER_POWER = 12.5 }`: scaled too, so Windy Highlands still comes on hit 15.
- `World.STRIKE_HEIGHT = 3` stays: it's relative to the avatar, which isn't scaled.
- Spawn comes from the `Spawn` marker (`WorldService`), so it follows the map on its own.

If the scale ever changes, all of these change with it.

## The formula (Nov 6)

The detail ladder is retired: map rules now come from `CLAUDE.md` ("The map"). Biomes 1 to 4 and
the hub's walls are generated by `MaP/tools/formula.py` (`build_all()`, `build_hub()`), in
Roblox studs:

- Lane: inner width 85 (walls' inner faces at x = ±42.5), walls 30 thick and 30 tall, floor slab
  and walls down to y = -20 so the lane reads as a solid block. Floor checker 21.25 studs (four
  across), wall checker 15 tall in two rows on the inner faces, a 1.25-stud grass cap overhanging
  0.625 inward, a 2.5-deep threshold strip where each biome starts, and a few props by the walls.
- Props per biome (the quick sweep): four trees, one kind per biome, at (-31, 25% and 75% of the
  biome) and (31, 14% and 88%), and one hero item at (31, 50%) so a biome is named at a glance:
  Meadow an oak and a windmill, Windy Highlands a wind-bent tree and a standing-stone henge, Tundra
  a snowy pine and an igloo, Jungle Ruins a palm and a step temple (`TREES` and `HEROES`).
- Parts per biome: Meadow 79, Windy Highlands 77, Tundra 109, Jungle Ruins 142 (1,170 to 1,489
  each before).
- Reef (biome 5) keeps its crafted layout but its floor and walls are blues (`Reef_Rock`,
  `Reef_RockLight`, `Reef_RockBand`, `Reef_Sand`, `Rf_Sand2`, `Reef_Lagoon` in
  `palette_nov6.json`); pink and coral stay only on the coral and other objects.
- Geyser Flats (biome 6) is rebuilt by `MaP/tools/geyser.py` (`rework()`, re-runnable; old groups
  go to `OLD_Biome06_GeyserFlats`). Each of the 8 springs is a real stepped basin cut into the
  floor, colours going deeper from rust to orange, yellow, green, turquoise and deep blue (top
  0.5 - 0.75 per ring, bottom at -4). The finale is a giant geyser at (0, 2240): a low, wide,
  lumpy mound of seven alternating rotated tiers up to y = 12, a turquoise crater and a neon
  `Gf_GeyserCore`, with the landmark being the plume (`FX_Geyser_CrownPlume` at y = 13.5; its two
  ParticleEmitters are set in Studio, not Blender). 3,383 parts.
- Hub: the hub ground (x = ±130) enclosed by the same walls, open where the lane starts, on a
  solid base 0.05 below the ground (the old ground had holes where the rim used to be); 53 parts.
  The crater rim, the island underside, the sky windows, the rim's falls and trees, the perches
  and the old collision walls are archived.
- Creature spots (`AnimalSpot`) are gone (map rule 1). Effect anchors: light in biomes 1 to 3,
  `FX_Jungle_Mist` makes biome 4 the first with noticeable atmosphere.

## Rebuilding

**Never hide a collection that gets exported.** Blender stops updating world positions inside a
viewport-hidden collection, so the export reads stale ones. On Nov 5 that put the lane-gap barrier
across the Orb Walk. Hide the objects instead (the Collision objects are hidden one by one).

The lane has its own tools in `MaP/tools/` (the hub rebuild still follows the first export):

1. **Export (Blender).** `export_lane.py`: `ns = {}; exec(open(".../MaP/tools/export_lane.py").read(), ns); ns["run"]([...biomes])`.
   Every mesh island that is a box (or a flat plane, given 0.0625 studs; or an eight-corner tapered
   segment, given the box of its average edges) becomes a part, boxes of
   one material that share a whole face are joined, and the rest (the Reef's coral) goes to
   `meshes/Import_<biome>.fbx` in 75-stud chunks. Writes `parts/Lane__<biome>.json`,
   `lane_materials.json`, `lane_meshes.json` and `lane_markers.json`. Part names drop Blender's
   `B_` prefix; the Geyser study's `Fb_` becomes `Gf_`.
2. **Prepare.** `python3 MaP/tools/prepare_build.py src/server/_MapBuild <biomes> --fixed <biomes already in Studio>`
   applies the matching-faces step (each face steps back 0.06 studs at most twice) and splits the
   parts into JSON files. `src/server/_MapBuild/` is in `.git/info/exclude`, so it never reaches
   git, but a running `rojo serve` syncs it into Studio, which is how the data gets there.
3. **Build (Studio).** Each biome model is rebuilt from those files (Atomic, StreamingMesh). The
   stud class and collision per material come from `MaP/tools/lane_classes.json`: thin parts
   (middle size under 1.25) are smooth, rocks are sunk below 15 studs long, collision tags
   `PlaytestWalk`, parts under 3 studs cast no shadow. Then the markers (`AnimalSpot`, `FXAnchor`).
4. **Meshes.** Import the FBX with Import 3D (only the lane file: the island underside's old FBX
   comes in seven times too big, and the hub already has it), then place each piece by name from
   `lane_meshes.json`: Size from the record, CFrame at the record's position **turned 180° about Y**
   (`CFrame.new(pos) * CFrame.Angles(0, math.pi, 0)`). Import 3D turns every piece that way, and
   the size check can't see it because a half turn keeps the size. Records are measured from
   vertices that belong to a face, since Studio drops loose ones. Meshes are SmoothPlastic,
   CollisionFidelity Box, shadow from 3 studs, and collide only when their material does in
   `lane_classes.json`: the Reef's sand floor is a mesh and must collide, or players fall through
   the gaps between the bright tiles (found by testers Nov 6).
5. **Clean up and check.** Delete `src/server/_MapBuild/`. Part counts match the table above, the
   spawn is on the emblem, and a play test hits.
