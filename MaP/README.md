# MaP: the island map (Blender)

`HubBlock.blend` is the island map for Lob an Orb! and the **source of truth** for it. It holds
the hub and the six-biome lane that leaves it. Since Nov 6 the map follows one minimal formula
(the map rules in [CLAUDE.md](../CLAUDE.md)). The hub is a walled rectangle that runs straight into
the lane. The first four biomes share one shape. The Coral Reef and the Geyser Flats are the
crafted showpieces.

- **Built in Blender, partly by script.** `tools/formula.py` builds biomes 1 to 4 and the hub's
  walls. `tools/geyser.py` builds the Geyser Flats. Everything else was built by hand. The
  scripts move whatever they replace into `ARCHIVE_pre_formula` and never delete it.
- **In the game as `Workspace.Map`.** It's built in Studio at 1.25x scale by the steps in
  [EXPORT_SPEC.md](EXPORT_SPEC.md). Rojo never syncs `MaP/`, so the map lives in the saved place.
- **Don't hand-build map geometry in Studio.** Change it here, then re-import.

## Frame

- **1 Blender unit = 1 stud** in Blender. The game builds the map at **1.25x**, so every Blender
  number below is × 1.25 in the game ([EXPORT_SPEC.md](EXPORT_SPEC.md)).
- **x** = east, **y** = north (down the lane, the way every orb flies), **z** = up.
- **The hit line is the launch strip's front edge, y = 45.** Every distance in the game is
  measured from it.

## What's in `HubBlock.blend` (scene "HubBlock")

| Collection | What |
|---|---|
| `SkyIsland/HubSanctuary` | The hub. The walls (`Hub_Walls`, from `formula.py`) are open where the lane starts. Inside are the ground, the walks, the basin in the middle (water, an orb and six element gems), the overlook where you spawn, and the details. |
| `SkyIsland/BiomeLane` | The six biomes, `Biome01_Meadow` … `Biome06_GeyserFlats`, each with its own collection (the export also reads a biome's `_Extras`). **Meadow, Windy Highlands, Tundra and Jungle Ruins** share the formula: a checkered floor, two checkered walls with a grass cap, a threshold strip, four trees and one hero item (a windmill, a standing-stone henge, an igloo, a step temple). They differ only in floor, walls, props and atmosphere. The **Coral Reef** keeps its crafted layout, with blue floor and walls and colourful coral. The **Geyser Flats** have stepped hot springs, and a giant geyser stands in front of the closing cliff. |
| `SkyIsland/FX_Anchors` | 16 empties, one per effect. Each has an `effect` property that says what it is. The effects are light in biomes 1 to 3. `FX_Jungle_Mist` makes the Jungle Ruins the first biome with noticeable atmosphere, and the Geyser Flats have the most, led by the giant geyser's plume (`FX_Geyser_CrownPlume`). Anything that moves or floats is an effect, not a model. |
| `LaunchZone` | The launch strip, 36 × 10 (x −18..18, y 35..45; 45 × 12.5 studs in the game), with its edge lines and five `OrbLaunch_1..5` empties at x −12, −6, 0, 6, 12 (one per lane, 4 up). |
| `CaveArch` | The rock arch at the back of the hub, and `SpawnPad` on the overlook (the game's `Spawn` marker). |
| `Stalls` | `Stall_Shop`, `LeaderboardWall` (a cliff with three boards: Luckiest Catch, Longest Launch, Next Update) and `LauncherDisplay` (four launcher spots, with preview spots facing west toward the Reveal Ring). |
| `DisplayLedge` | A two-step ledge in the hub with five `AnimalSpot` empties. |
| `Training_PENDING_DECISION` | Empty. Waiting on a decision. |
| `Cameras`, `ScaleFigures` | Not exported (`export = False`): review cameras (overview, launch, three per biome, lane end) and 5-stud avatars for scale. |
| `ARCHIVE_pre_formula` | Not exported, since Nov 6: everything the formula replaced. That's the old builds of biomes 1 to 4 and the Geyser Flats (`OLD_…`), the crater rim, the island underside (`Hub_Island`, `HomeIsland`), the sky windows, the rim's falls and trees, the perches, the old collision walls, the lane's creature spots (`AnimalSpots`) and the old effect anchors. |
| `UPDATES_not_exported` | Not exported: the Galaxy grand update blockout, and parked since Nov 5, the old `Biome06_Volcano` and the Pyramids ending (`LaneEnd_Veil`, `LaneEnd_Beyond`). |

Where each biome's floor starts on the lane. The game's `Tuning.BiomeStarts` is each edge minus 45
(the hit line), times 1.25:

| Biome | Floor starts at y | Studs from the hit line in the game |
|---|---|---|
| Meadow | 60 | 0 (the first biome) |
| Windy Highlands | 210 | 206 |
| Tundra | 410 | 456 |
| Jungle Ruins | 660 | 769 |
| Coral Reef | 960 | 1,144 |
| Geyser Flats | 1,335 | 1,613 |
| Giant geyser (the finale) | 1,800 (centre 1,837) | 2,193 (centre 2,240) |
| Closing cliff (lane end) | 1,880 | 2,294 |

Part counts are in [EXPORT_SPEC.md](EXPORT_SPEC.md).

## Other files here

| Path | What |
|---|---|
| `HubBlock.blend` | The map. Tracked with Git LFS. |
| `EXPORT_SPEC.md` | How the .blend becomes `Workspace.Map`, and how to keep the two identical. |
| `tools/` | The map scripts. `formula.py` (biomes 1 to 4 and the hub walls), `geyser.py` (the Geyser Flats) and `export_lane.py` (the lane export) run inside Blender. `prepare_build.py` runs with `python3`: it does the matching-faces step and writes the build files for Studio. `lane_classes.json` holds the stud class and collision per material, and `palette_nov6.json` holds the 97 colours. `ladder.py` and `shoot.py` are the retired detail ladder's tools. |
| `export/` | The export data, rebuilt from the .blend. Git-ignored. |
| `HubBlock_backup_*.blend`, `HubBlock_hub_WIP.blend`, `HubBlock_Stadium.blend`, `Hub.blend`, `FireStudy.blend` | Backups, work in progress, studies and earlier maps. Local only, git-ignored. |
| `*.blend1` | Blender's own save backups. Git-ignored. |
| `refs/` | Three mood reference images. Nothing is copied from them. Local only, git-ignored: they're outside images and the repo is public. |
| `textures/` | The painted atlas, brush and sky faces from the earlier `Hub.blend`. |
| `renders/` | Review renders. Git-ignored, because they regenerate. |

## Building it in Studio

[EXPORT_SPEC.md](EXPORT_SPEC.md) has everything: scale and axes, colours, collision, markers, the
`Tuning` values that must match the map, and the rebuild steps. With `Workspace.Map` in the place,
the game's grey `TestPad` no longer appears.
