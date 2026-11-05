# MaP: the island map (Blender)

`HubBlock.blend` is the island map for Lob an Orb! and the **source of truth** for it. It holds
the hub, the **Sanctuary Crater** (themed Orb Sanctuary with a touch of Cloud Meadow, about 1.4x
the size of the first blockout), and the six-biome lane that leaves it.

- **Built by hand.** It was built and edited by hand in Blender. There is no generator script:
  the old ones built earlier maps and were deleted, because running them would have overwritten
  this file.
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
| `SkyIsland/HubSanctuary` | The Sanctuary Crater: island, ground, walks, the basin in the middle (water, an orb and six element gems), the overlook where you spawn, falls, sky windows, trees, details and the rim. |
| `SkyIsland/HomeIsland` | The stepped underside of the floating island. |
| `SkyIsland/BiomeLane` | The lane's six biomes (`Biome01_Meadow` … `Biome06_Volcano`, each with its own collection), then `LaneEnd_Veil` (the sandstorm veil, a statue with a countdown panel) and `LaneEnd_Beyond` (the Pyramids looming past it, with a floating gold capstone). |
| `SkyIsland/FX_Anchors` | 19 empties, one per effect. Each has an `effect` property that says what it is (fireflies, wind petals, snowfall, mist, bubbles, lava, embers, the sandstorm). Anything that moves or floats is an effect, not a model. |
| `SkyIsland/AnimalSpots` | 6 empties per biome (36) where animals will stand. |
| `LaunchZone` | The launch strip, 36 × 10 (x −18..18, y 35..45; 45 × 12.5 studs in the game), with its edge lines and five `OrbLaunch_1..5` empties at x −12, −6, 0, 6, 12 (one per lane, 4 up). |
| `CaveArch` | The rock arch at the back of the hub, and `SpawnPad` on the overlook (the game's `Spawn` marker). |
| `Stalls` | `Stall_Shop`, `LeaderboardWall` (a cliff with three boards: Luckiest Catch, Longest Launch, Next Update) and `LauncherDisplay` (four launcher spots, with preview spots facing west toward the Reveal Ring). |
| `DisplayLedge` | A two-step ledge in the hub with five `AnimalSpot` empties. |
| `Perches` | 16 small pads on the rim. |
| `Training_PENDING_DECISION` | Empty. Waiting on a decision. |
| `Collision`, `Cameras`, `ScaleFigures` | Not exported (`export = False`): the gap and window barriers, three review cameras, 5-stud avatars for scale. |
| `UPDATES_not_exported` | A blockout of the Galaxy grand update past the lane end. Not exported. |

Where each biome's floor starts on the lane. The game's `Tuning.BiomeStarts` is each edge minus 45
(the hit line), times 1.25:

| Biome | Floor starts at y | Studs from the hit line in the game |
|---|---|---|
| Meadow | 60 | 0 (the first biome) |
| Windy Highlands | 210 | 206 |
| Tundra | 410 | 456 |
| Jungle Ruins | 660 | 769 |
| Coral Reef | 960 | 1,144 |
| Volcano | 1,335 | 1,613 |
| Pyramids veil (lane end) | 1,785 | 2,175 |

Part counts for each group in the game are in [EXPORT_SPEC.md](EXPORT_SPEC.md).

## Other files here

| Path | What |
|---|---|
| `HubBlock.blend` | The map. Tracked with Git LFS. |
| `EXPORT_SPEC.md` | How the .blend becomes `Workspace.Map`, and how to keep the two identical. |
| `export/` | The export data, rebuilt from the .blend. Git-ignored. |
| `HubBlock_backup_*.blend`, `HubBlock_hub_WIP.blend`, `HubBlock_Stadium.blend`, `Hub.blend` | Backups, work in progress and earlier maps. Local only, git-ignored. |
| `*.blend1` | Blender's own save backups. Git-ignored. |
| `refs/` | Three mood reference images. Nothing is copied from them. Local only, git-ignored: they're outside images and the repo is public. |
| `textures/` | The painted atlas, brush and sky faces from the earlier `Hub.blend`. |
| `renders/` | Review renders. Git-ignored, because they regenerate. |

## Building it in Studio

[EXPORT_SPEC.md](EXPORT_SPEC.md) has everything: scale and axes, colours, collision, markers, the
`Tuning` values that must match the map, and the rebuild steps. With `Workspace.Map` in the place,
the game's grey `TestPad` no longer appears.
