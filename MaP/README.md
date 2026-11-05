# MaP: the island map (Blender)

`HubBlock.blend` is the island map for Lob an Orb! and the **source of truth** for it. It holds
the hub, the **Sanctuary Crater** (themed Orb Sanctuary with a touch of Cloud Meadow, about 1.4x
the size of the first blockout), and the six-biome lane that leaves it.

- **Built by hand.** It was built and edited by hand in Blender. There is no generator script:
  the old ones built earlier maps and were deleted, because running them would have overwritten
  this file.
- **Not in the game yet.** Rojo never syncs `MaP/`. The map is imported into Studio later (see
  **Import** below). Until then the game puts a grey `TestPad` under the launch strip.
- **Don't hand-build map geometry in Studio.** Change it here, then re-import.

## Frame

- **1 Blender unit = 1 stud**, everywhere.
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
| `LaunchZone` | The launch strip, 36 × 10 studs (x −18..18, y 35..45), with its edge lines and five `OrbLaunch_1..5` empties at x −12, −6, 0, 6, 12 (one per lane, 4 studs up). |
| `CaveArch` | The rock arch at the back of the hub, and `SpawnPad` on the overlook. |
| `Stalls` | `Stall_Shop`, `LeaderboardWall` (a cliff with three boards: Luckiest Catch, Longest Launch, Next Update) and `LauncherDisplay` (four launcher spots, with preview spots facing west toward the Reveal Ring). |
| `DisplayLedge` | A two-step ledge in the hub with five `AnimalSpot` empties. |
| `Perches` | 16 small pads on the rim. |
| `Training_PENDING_DECISION` | Empty. Waiting on a decision. |
| `Collision`, `Cameras`, `ScaleFigures` | Not exported (`export = False`): the gap and window barriers, three review cameras, 5-stud avatars for scale. |
| `UPDATES_not_exported` | A blockout of the Galaxy grand update past the lane end. Not exported. |

Where each biome's floor starts on the lane. The game's `Tuning.BiomeStarts` is each edge minus 45
(the hit line):

| Biome | Floor starts at y | Studs from the hit line |
|---|---|---|
| Meadow | 60 | 0 in the game (the first biome) |
| Windy Highlands | 210 | 165 |
| Tundra | 410 | 365 |
| Jungle Ruins | 660 | 615 |
| Coral Reef | 960 | 915 |
| Volcano | 1,335 | 1,290 |
| Pyramids veil (lane end) | 1,785 | 1,740 |

Size today: 448 objects, 205 materials, about 228k triangles. The largest mesh is
`Hub_Rim_Hb_Cap` at about 11.8k triangles.

## Other files here

| Path | What |
|---|---|
| `HubBlock.blend` | The map. Tracked with Git LFS. |
| `HubBlock_backup_*.blend`, `HubBlock_hub_WIP.blend`, `HubBlock_Stadium.blend`, `Hub.blend` | Backups, work in progress and earlier maps. Local only, git-ignored. |
| `*.blend1` | Blender's own save backups. Git-ignored. |
| `refs/` | Three mood reference images. Nothing is copied from them. Local only, git-ignored: they're outside images and the repo is public. |
| `textures/` | The painted atlas, brush and sky faces from the earlier `Hub.blend`. |
| `renders/` | Review renders. Git-ignored, because they regenerate. |

## Import (not done yet)

The game expects these when the map arrives as `Workspace.Map`:

1. **The hit line on Z = 0.** The launch strip's front edge (y = 45) lands on Roblox Z = 0, the
   lane runs down +Z, and up is +Y. Facing down the lane, east is on the right, which is Roblox −X.
2. **The launch strip on the hit zone.** The strip (y 35..45) becomes Z −10..0, which is
   `Tuning.World.HIT_ZONE`. The five `OrbLaunch` empties sit 6 studs apart, which is
   `World.LANE_SPACING`.
3. **A part named `Spawn`.** `WorldService` spawns everyone at a BasePart named `Spawn` anywhere
   under `Workspace.Map`. In this file it's called `SpawnPad`, so rename it on import.
4. **Effects, not models.** Each `FX_Anchors` empty becomes an emitter, beam or similar at that
   spot, from its `effect` note.
5. **Check it on a low-end phone.** The game is mobile-first. Measure frame time with the whole
   lane loaded before keeping the import.

Once `Workspace.Map` exists, the `TestPad` stops appearing on its own.
