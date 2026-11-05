# Lob an Orb!: Architecture

Status: only the core loop is built. One tap launches, every tap hits, Power goes up by one, and
the ball-cam follows the throw down the lane. Power and best distance are saved. Everything else
is under **Planned** at the end. Guardrails and hard rules: [CLAUDE.md](../CLAUDE.md).

- **Names in the code.** The code still uses the words of the swing that throws today: a batter,
  a bat, a ball, a pitcher, "Fungo". In game terms the ball is the orb.
- **Server owns every number.** The client sends ids only, never values.
- **Saves use ProfileStore.**
- **One world.** The island's one straight lane leaves the hub through six biomes and ends at the
  Pyramids' sandstorm veil.
- **The map.** `Workspace.Map` is built in Studio from `MaP/HubBlock.blend` at 1.25x scale, by the
  steps in [MaP/EXPORT_SPEC.md](../MaP/EXPORT_SPEC.md). Rojo doesn't sync it, so it lives in the
  saved place.

## 1. Folder layout

```
HMG/
├─ CLAUDE.md               design guardrails and hard rules
├─ README.md               setup and repo layout
├─ default.project.json    Rojo: maps src/ and assets/ into the place, plus Workspace and Lighting properties
├─ rokit.toml              pinned tools: rojo 7.7.1, selene 0.32.0, stylua 2.6.0
├─ selene.toml, stylua.toml
├─ docs/ARCHITECTURE.md
├─ assets/Animations/      → ReplicatedStorage.Animations: the batter's 12 KeyframeSequences (generated)
├─ tools/animations/       generate.py (solves and bakes the swing poses) + rig.json (R15 layout)
├─ MaP/                    the island map in Blender (HubBlock.blend); Rojo never syncs it
└─ src/
   ├─ server/   → ServerScriptService.Server (Script)
   │  ├─ init.server.luau   creates every remote, then loads Services: Init() all, then Start() all
   │  ├─ Services/          Data, Replication, Pitch, Stat, Swing, Landing, World
   │  ├─ Data/              Template (new save) + Migrations
   │  ├─ Pitchers/          Fungo (default, "toss"), PitchingMachine ("throw")
   │  └─ Packages/          ProfileStore 1.0.3, vendored
   ├─ client/   → StarterPlayer.StarterPlayerScripts.Client (LocalScript)
   │  ├─ init.client.luau   loads Controllers: Init() all, then Start() all
   │  ├─ Controllers/       Input, Fungo, Ball, Camera, Pitcher, State
   │  ├─ Modules/           SwingAnimator, SwingData (generated), BatSwing
   │  └─ PitcherVisuals/    how each "throw" pitcher looks when it throws
   └─ shared/   → ReplicatedStorage.Shared (Folder)
      ├─ Remotes, Types, HookTypes, Formulas, Signal, BatPose, HitZone
      └─ Config/            Tuning, Biomes
```

`Init()` sets up state with no calls into other modules. `Start()` may use them. Live servers
delete `ReplicatedStorage.Animations` at startup, so clients never download the Studio previews.

## 2. The loop

```
tap ─▶ InputController ─▶ FungoController.Toss()
  │    the toss and swing start on screen at once; Swing(tossId) goes to the server at the tap
  │    Fungo.CONTACT_AT (0.45s) after the tap, the ball leaves the bat
  ▼
SwingService (server)
  │    PitchService.ConsumePitch: one hit per cycle (repeats and old ids ignored,
  │    a toss that's a little early is held until its cycle opens)
  │    power += Formulas.powerGain(StatService.GetMultiplier(player))
  │    segment 1 = { from 0, to Formulas.distance(power), source "hit" }   (studs past the hit line)
  ▼
LandingService.Resolve: on-land handlers (none yet) may push it further
  │    → catch phase (none yet) → Landed signal
  ├─ PitchService.QueueNext: next toss allowed after CONTACT_AT + Formulas.ballCamTime(...)
  ├─ save: power, lifetime.swings, lifetime.bestDistance, highestBiome
  └─ HitResult ─▶ client: BallController flies the ball; CameraController follows it
```

- **Tap.** A tap on the game view, a left click, Space (it no longer jumps) or gamepad R2. Taps on
  buttons and menus don't count. There is no SWING button and no timing.
- **Toss and swing.** The batter turns to face the field and keeps walking. The tier's swing
  plays: the off hand tosses the ball, the batter loads and swings, and the ball meets the bat.
  Contact plays the crack, sparks, dust, shockwave and camera punch, and starts the hit-stop. The
  swing grows with Power (`Fungo.TIERS`: pop, solid, crush, blast, launch). Visual and audio only.
- **Flight.** The ball flies an arc from the bat onto a line straight down +Z from the batter's X
  (`HitZone.lineOrigin`) and lands `segment.to` studs past the hit line, so biome crossings match
  the server. The end of the last descent plays in slow motion. The client flies to the server's
  distance if `HitResult` is already here, else to a predicted one (`Formulas.distance(power + last
  gain)`), and re-plans mid-air when the result comes.
- **Landing.** The ball stays on the ground for `Flight.LINGER_TIME`. The camera holds on it for
  `Reveal.SHORT` (1s).
- **Ball-cam.** Hold on the batter for `Fungo.CAMERA_BEAT` (0.25s, so the follow-through is seen),
  glide onto the ball over `CAMERA_GLIDE` (0.3s), follow, hold on the landing, then swoop back
  (0.35s) or fade-cut back past 250 studs. The camera comes back behind the batter where they
  stand now.
- **The cycle is the tap limit.** The server allows one hit per cycle and times the next from the
  same numbers the camera uses. A tap during the hold skips it and sends `Ready(hitId)`. That
  brings the next toss forward, never sooner than a hold of `Reveal.MIN_SHOWN` (0.3s). A tap that
  comes before that floor is held and tossed then, so it isn't lost.
- **Every tap is a hit.** No misses, no mark to stand on. A tap from outside the hit zone launches
  from the zone's nearest point. The server never reads where the player stands.
- **Pacing.** The first tap can launch the moment the save loads. Windy Highlands (206 studs) comes
  on hit 15, about 52s in with the 1s hold, about 43s with every hold skipped.

### Why the built mechanics exist (guardrail 7)

- **One-tap toss and swing.** Waiting for a throw and standing on a mark made the first seconds
  feel like a timing game. A self-toss starts the first launch the moment the save loads and
  lets players walk while they play (**bounce**, **playtime**). The swing's growth with Power is a
  visible sign of progress (**D1**, **D28**). It adds no way to fail.
- **Free movement in the hit zone.** You can tap from anywhere, walking or standing. The game
  answers your movement from the first tap (**bounce**). Where you stand changes only where the
  ball's line starts, never its distance.
- **Camera beat before the ball-cam.** The camera holds on the batter for 0.25s, then glides to the
  ball, so every launch's payoff is seen (**bounce**, **playtime**). It runs inside the flight, so
  pacing is unchanged. Visual only.

## 3. Modules

**Server: `src/server/`** (the only code that changes stats)

| Module | Job |
|---|---|
| Services/DataService | ProfileStore wrapper: load, migrate, autosave (every 120s), release. The only module that touches DataStores. `Update(player, key, fn)` is the only way to change a save. A save that won't load kicks the player rather than play on a blank one. Studio uses its own store (`PlayerData_Studio`). |
| Services/ReplicationService | `GetData` returns the caller's own save. `DataChanged` sends changed top-level keys, once per frame. |
| Services/PitchService | **Pitcher slot.** Each player's active Pitcher and one hit per cycle. "toss" (Fungo): a `Swing(tossId)` counts once the last cycle is over (less `Pitch.TOSS_GRACE` for jitter); ids only go up; one a little early is held up to `Pitch.TOSS_MAX_HOLD`. "throw" (machine): schedules each `Pitch`. `Ready` brings the next ball forward, never inside the floor. Publishes the `Pitcher` and `PitcherMode` player attributes. |
| Services/StatService | The Power multiplier per hit (`Formulas.multiplier`: today only the pitcher's bonus). |
| Services/SwingService | Handles `Swing`: asks PitchService, adds Power, makes the first flight segment, runs LandingService, queues the next cycle, updates lifetime stats and `highestBiome`, fires `HitResult`. |
| Services/LandingService | **On-land hook and catch phase.** Runs each handler (it may push the ball further, never back), then the catcher on the final landing, then fires `Landed`. A failing handler or catcher never stops the hit. |
| Services/WorldService | Five batting lanes across the launch strip (a hidden `StrikePoint` each, `Lane` attributes), every spawn at the map's `Spawn` marker (or the middle of the launch strip with no map), the grey `TestPad` while there's no `Workspace.Map`, and the placeholder bat on every character (a `BatGrip` Motor6D the animations move, `TrailBase`/`TrailTip` for the swoosh). The pitching machine's pad, plate and model only when it's the default pitcher. Set the place's Max Players to 5 to match `World.LANE_COUNT`. |
| Pitchers/Fungo | The default Pitcher, mode "toss": no cooldown; `travelTime` is tap to contact (`Fungo.CONTACT_AT`). |
| Pitchers/PitchingMachine | A Pitcher with mode "throw": fixed cooldown and travel time. Kept as a second slot implementation; not built in the scene. |
| Data/Template | The save a new player starts with. ProfileStore fills missing keys from it. |
| Data/Migrations | Upgrades older saves one version at a time, on a copy first. |
| Packages/ProfileStore | ProfileStore 1.0.3, commit `45c9847`, unmodified (Apache-2.0). |

**Client: `src/client/`** (input and drawing only, no stat math)

| Module | Job |
|---|---|
| Controllers/StateController | This player's latest save from the server. Read only. `Get`, `WaitForData`, `Changed`, `Ready`. |
| Controllers/InputController | Turns a tap, left click, Space or R2 into `FungoController.Toss()` (or, with the machine, a hit on the pitch in play). While the ball-cam is away, a tap skips the landing hold. |
| Controllers/FungoController | `Toss()`: one tap is the toss and swing. Sends `Swing(tossId)` at the tap, turns the batter to face +Z, plays the tier's swing through SwingAnimator (or BatSwing without animations), drops the toss ball onto the moving bat, plays contact effects and the hit-stop, and launches the ball at `CONTACT_AT`. The white swoosh trail is local only. Auto-Swing will call `Toss` too. Fires `Contact`. |
| Controllers/BallController | Draws every ball, pooled and capped (`Flight.MAX_BALLS`). Flies the arcs from `HitResult`, re-plans a predicted flight mid-air, slow motion at the end. Fires `Launched` and `Touchdown`; `WatchDistance` calls back when a ball passes a distance. |
| Controllers/CameraController | The ball-cam: beat, glide, follow, hold, return. Sends `Ready` when the hold is skipped or the result came too late. Fires `RevealStarted` / `RevealEnded`; `SetRevealCamera` lets a future catch view set the shot. |
| Controllers/PitcherController | "throw" pitchers only: draws each `Pitch` with that pitcher's visual and keeps the pitch in play. |
| Modules/SwingAnimator | The batter's animations on the local character (they replicate): `FungoStance` (idle loop), `FungoCarry` (upper-body loop while walking) and one swing per Power tier, full-body and upper-body, two pairs per tier used in turn. Finish pose held until the camera is back. Published ids come from `Fungo.ANIMATIONS`; in Studio, unpublished ones load from `ReplicatedStorage.Animations`. |
| Modules/SwingData | Generated by `tools/animations/generate.py`: each swing's names, length, marker times and contact point. |
| Modules/BatSwing | The simple tweened bat swing: Fungo's fallback without animations (R6, or no ids in a live server) and the machine path. |
| PitcherVisuals/PitchingMachine | The machine's throw flash (only when the machine is the pitcher). |

**Shared: `src/shared/`**

| Module | Job |
|---|---|
| Remotes | Every remote by name: the client↔server contract (section 4). |
| Types | `PlayerData`, the save shape (section 5). |
| HookTypes | Hook contracts: `Pitch`, `Pitcher`, `FlightSegment`, `LandingContext`, `LandingHandler`, `Catch`, `Catcher`, `BiomeConfig`. |
| Formulas | Pure math shared by server and client: Power multiplier and gain, distance from Power, the biome at a distance, the swing tier, air time, landing hold, return time and `ballCamTime`. |
| Signal | Small event helper used by the hooks (`Connect`, `Fire`, `Wait`). |
| BatPose | Where the placeholder bat sits in the hand. Shared by WorldService and BatSwing. |
| HitZone | The hit zone on the launch strip: `halfWidth()`, `contains(pos)`, `clamp(pos)`, `lineOrigin(x)`. |
| Config/Tuning | **Every tunable number** (section 7). |
| Config/Biomes | The six biomes in flight order: Meadow, Windy Highlands, Tundra, Jungle Ruins, Coral Reef, Volcano. |

## 4. Client ↔ server (remotes)

The server creates everything under `ReplicatedStorage.Remotes` at startup (`Remotes.CreateAll`),
so clients never wait on a missing one.

| Direction | Name | Type | Payload |
|---|---|---|---|
| C → S | `Swing` | Event | Fungo: `tossId` (the client's counter, only goes up). Machine: `pitchId`. |
| C → S | `Ready` | Event | `hitId`: the landing hold was skipped; the next toss may come sooner, never before the floor. |
| C → S | `GetData` | Function | → the caller's own save, or nil if it never loaded. |
| S → C | `Pitch` | Event | `HookTypes.Pitch`. "throw" pitchers only; Fungo sends none. |
| S → C | `HitResult` | Event | `{ hitId, powerGained, pitcherBonus, segments, distance, biomeIndex, catch? }` |
| S → C | `DataChanged` | Event | `{ [topLevelKey]: newValue }` for keys changed since the last frame. |

Rules: the client never sends a number that becomes a stat. Every argument is type-checked.
There are no server → client RemoteFunctions.

## 5. Player save (`src/shared/Types.luau`)

Save version 4.

```lua
{
  version = 4,
  power = 0,
  highestBiome = 1,       -- furthest biome reached (Config/Biomes index)
  pitcher = "fungo",      -- active Pitcher id (server/Pitchers)
  settings = { music = true, sfx = true, lowGraphics = false },
  lifetime = { swings = 0, bestDistance = 0 },   -- never reset
  firstJoin = 0, lastJoin = 0,
  lastOnline = 0,         -- os.time() at the last save or leave
}
```

- **v1 → v2** wiped the first test saves (there were no live players).
- **v2 → v3** moved `pitcher` from "pitching_machine" to "fungo".
- **v3 → v4** removes every key from the earlier game (the list is in `Migrations.luau`) and resets
  `highestBiome`, because the biomes changed.
- **To change the shape:** bump `Migrations.CURRENT_VERSION`, add `Steps[old]`, and update
  `Template` and `Types`. A new key with a simple default needs no step: the Template fills it in.
  ProfileStore only adds missing keys, so removing one needs a step.
- There are no Robux fields.

## 6. Hooks

All types are in [HookTypes.luau](../src/shared/HookTypes.luau).

- **Pitcher slot.** `PitchService.SetPitcher(player, pitcher)` swaps the active `Pitcher` (mode,
  cooldown, travel time, optional Power bonus). "toss" means the tap starts each cycle; "throw"
  means the server throws each `Pitch`. A new pitcher is a new file in `server/Pitchers/` (plus one
  in `client/PitcherVisuals/` with the same id for a "throw" pitcher). No other code changes.
- **On-land handlers.** `LandingService.AddHandler(fn)` registers a `LandingHandler`. After the hit
  lands, each one sees the landing and may return one more `FlightSegment` (a bounce that pushes
  the ball further). The client gets every segment and flies them in order. Handlers must not yield.
- **Catch phase.** `LandingService.SetCatcher(fn)` sets one `Catcher`. It runs once, on the
  **final** landing after every handler, so a push changes which biome the catch comes from. Its
  result goes to the client as `HitResult.catch`. `Formulas.revealTime(catch)` is where a catch
  will ask for the longer hold (`Reveal.FULL`). Nothing registers one yet.
- **Client hooks.** `FungoController.Contact` (bat on ball), `BallController.Launched`,
  `Touchdown` and `WatchDistance` (biome crossings), `CameraController.RevealStarted`,
  `RevealEnded` and `SetRevealCamera` (the landing hold's shot). These are the places for visual
  effects. The server has already decided the result.

## 7. Tuning

Every number lives in [Config/Tuning.luau](../src/shared/Config/Tuning.luau). Code never hard-codes
them.

| Section | What |
|---|---|
| `Data` | Autosave period, load timeout, how long before a failed load kicks. |
| `Pitch` | Default pitcher, toss grace and hold, the machine's timing. |
| `Power` | `PER_HIT` = 1, before multipliers. |
| `Distance` | `distance = BASE + PER_POWER × power ^ EXPONENT` (25 + 12.5 × power today, scaled with the map). |
| `BiomeStarts` | Each biome's floor edge on the island map, in studs from the hit line, at the map's 1.25x scale. |
| `World` | Lanes (5, 7.5 studs apart), strike height, the hit zone on the launch strip (Z −12.5 to 0). |
| `Flight` | Air time, arc height, linger time, trail, ball cap. Client visuals only. |
| `Camera` | Ball-cam framing, slow motion, return and cut. The server times the cycle from these. |
| `Swing` | The simple bat swing's timing. |
| `Fungo` | Contact time, camera beat and glide, animation ids, and the five Power tiers' look and sound. |
| `Reveal` | The landing hold: 1s now, 3s once a catch shows, 0.3s floor when skipped. |

Where the biomes start, and the hit that first reaches each one from zero Power:

| Biome | Starts at | First reached on hit |
|---|---|---|
| Meadow | 0 | 1 |
| Windy Highlands | 206 | 15 |
| Tundra | 456 | 35 |
| Jungle Ruins | 769 | 60 |
| Coral Reef | 1,144 | 90 |
| Volcano | 1,613 | 128 |
| Pyramids veil (lane end) | 2,175 | 172 |

The numbers in `World`, `BiomeStarts` and `Distance` must match the map. If the map's scale
changes, they all change with it ([MaP/EXPORT_SPEC.md](../MaP/EXPORT_SPEC.md)).

## 8. Batter animations

`tools/animations/generate.py` writes them. Don't edit the `.rbxmx` files by hand.

- **How they're made.** Each pose is a few readable numbers (hands, bat direction, feet, hips,
  where the head looks) in the batter's own frame. The script solves the joints and bakes every
  swing at 30 frames a second, so hands stay on the bat and feet stay planted. It reads
  `Fungo.CONTACT_AT` and each tier's `hitStop` and `tossHeight` from Tuning, so the `Contact`
  marker always sits at `CONTACT_AT - hitStop`.
- **Markers.** `Release` (the toss), `Contact`, `Finish`, `SwooshOn` and `SwooshOff`.
- **What it writes.** 12 animations: `FungoStance`, `FungoCarry`, five full swings
  (`FungoSwingPop`, `Solid`, `Crush`, `Blast`, `Launch`) and five upper-body swings
  (`FungoSwingUpperPop` … `FungoSwingUpperLaunch`, the same timeline with the hips facing forward,
  played over the walk). It also writes `src/client/Modules/SwingData.luau`.
- **When to run it.** `python3 tools/animations/generate.py` after changing poses or those Tuning
  numbers.
- **Avatar settings.** The experience must be **R15** (Game Settings → Avatar → Avatar Type). R6
  gets the simple swing. Poses fit best with default scales (Height 100%, Width 100%, Head 100%,
  Body Type 0%, Proportions 0%); on other scales the ball still launches from the bat's real
  position at `Contact`.

### Publishing the animations

They must be owned by the experience's owner (here, a **group**) or the experience must be given
access to them, or they won't play in live servers. Until then they play only in Studio.

1. In Studio, with the place synced, find `ReplicatedStorage.Animations`.
2. For each KeyframeSequence, right-click → **Save to Roblox…** (newer Studio: **Publish to
   Roblox**), choose **Creator** = the group, keep the same name, and submit. Copy the id it shows
   (or find it in Creator Hub → Development Items → Animations). Animations published under your
   own account work too, once the experience has access: Creator Hub → this experience →
   Configure → Permissions → **Assets** → enter the ids → Add → **Save Changes**. A Studio play test
   warns about any animation that can't load.
3. Paste each id into `Tuning.Fungo.ANIMATIONS` as `"rbxassetid://<id>"`: `stance`, `carry`,
   `swings` and `upperSwings` in tier order (Pop, Solid, Crush, Blast, Launch). Today the stance,
   carry and five full swings are published; the five upper-body swings are not.
4. Commit. A set id always wins over the Studio preview, unless it's out of date (below).

**After regenerating a swing:** re-publish each changed swing over its existing asset (**Save to
Roblox…** → overwrite the same asset), so the id and access stay and Tuning doesn't change. A new
swing is published as a new asset: paste its id and grant access (step 2).

**Stale guard.** `SwingData` records each swing's length. A published track whose length differs
by more than 0.02s is treated as out of date. In Studio that tier plays the repo's
KeyframeSequence instead (logged once); in a live server it plays the simple swing. A missing
upper-body track just means the full-body swing plays while walking.

## 9. How the hard rules are enforced

| Rule ([CLAUDE.md](../CLAUDE.md)) | Where |
|---|---|
| Server owns stats | Only Services write the save, through `DataService.Update`. The client sends a toss id (or pitch id), never a value. |
| Mobile-first | One ball part with a short trail, pooled and capped at 6. The swoosh trail is local only and shorter on low graphics; contact effects are halved on low graphics. Lanes are a few hidden parts. |
| Money | Nothing is sold yet. No product may touch Power, distance or catches. |
| Odds first | No luck boosts yet. When one exists, its odds screen uses the same formula the server rolls with. |
| Safe at home | No trading and nothing another player can reach. Only stats are owned so far. |
| The map comes from Blender | WorldService builds no map geometry. It only adds the `TestPad` placeholder while `Workspace.Map` is missing. |
| Original assets | The animations are generated in this repo. Sounds are built into the Roblox client. No MLB names or logos. |
| Pacing | The first tap launches as soon as the save loads, from anywhere. Windy Highlands on hit 15, about 52s (section 7). Re-measure after any change to Distance, Flight, Camera, Fungo or Reveal. |

## 10. Planned (not built)

- **Catching animals in orbs.** A lucky throw catches an animal where the orb lands, through the
  catch phase (`LandingService.SetCatcher`). The orb flies back shaking.
- **The Reveal Ring.** The caught orb is cracked open there, in the hub. The longer landing hold
  (`Reveal.FULL`) is waiting for it.
- **Launchers.** A stat that multiplies distance. It joins `Formulas.multiplier`.
- **Pal training (Update 7).**
- **Trails.** Tamed animals paint every orb you throw with their trail.
- **The leaderboard wall.** The map already has its three board faces (tagged `BoardFace`).

## 11. Parked ideas (not in the main loop)

Ideas that add skill or a way to fail stay here until they fit the guardrails in
[CLAUDE.md](../CLAUDE.md). Nothing here may change main progression.

- **Training Area: optional skill mini-game, no effect on main progression.** A separate cage
  with timed swings: Perfect / Good / early / late windows, one swing per pitch, and a
  lag-tolerant server check of the tap time. It was built and then reverted from the main loop
  (commit `12825eb`, reverted in "Revert timing, add guardrails") because it broke guardrails 1,
  2, 3 and 6. If it returns, its rewards must be cosmetic or separate from Power, distance and
  catches.
