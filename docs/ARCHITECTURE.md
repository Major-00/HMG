# +1 Home Run: Architecture (proposal v2)

Status: skeleton only. Every module is an empty stub. No gameplay code yet.

Decisions so far:
- Every tap is one swing. A pitched ball is in play, the tap hits it, +1 Power (× multipliers), and the ball launches. No charge-up.
- Saves use **ProfileStore**.
- Biomes are generated from config. Each biome references one hand-made landmark model (placeholders for now).
- Four hooks are designed now and built later: **pitcher slot**, **on-land**, **highlight**, **per-biome challenge**.

## 1. Folder layout

```
HMG/
├─ default.project.json   Rojo: maps src/ and assets/ into the place
├─ rokit.toml             pinned tools: rojo 7.7.1, selene, stylua
├─ docs/ARCHITECTURE.md
├─ assets/
│  └─ Landmarks/          → ReplicatedStorage.Landmarks (one model per biome)
└─ src/
   ├─ server/   → ServerScriptService.Server             (Script)
   │  ├─ init.server.luau    loads Services: Init() all, then Start() all
   │  ├─ Services/
   │  ├─ Data/               save Template + Migrations
   │  ├─ Pitchers/           Pitcher implementations (PitchingMachine now)
   │  └─ Packages/           vendored server-only libraries (ProfileStore 1.0.3)
   ├─ client/   → StarterPlayer.StarterPlayerScripts.Client (LocalScript)
   │  ├─ init.client.luau    loads Controllers: Init() all, then Start() all
   │  ├─ Controllers/
   │  └─ PitcherVisuals/     how each pitcher looks and throws (cosmetic)
   └─ shared/   → ReplicatedStorage.Shared               (Folder)
      ├─ Remotes, Types, HookTypes, Formulas, Format, Signal
      └─ Config/
```

**Landmark models:** each is a file in `assets/Landmarks/`. They start as simple
`.model.json` placeholders. To swap in a real one, build it in Studio, export it as
`<BiomeId>.rbxm` into the same folder, and delete the placeholder.

## 2. World: who builds what

The ball's flight is **math on the server, visuals on the client**. Distance is a
number along one straight track, so the server never needs the biome geometry.

| Piece | Built by | Why |
|---|---|---|
| Batting lanes (pad, plate, batter spawn, pitching machine) | Server (`WorldService`) | Characters stand on them, so they must be physical and replicated. One lane per player (`Tuning.World.LANE_COUNT`, default 8), side by side along X; balls fly down +Z. Lane models are Persistent for streaming. |
| Biome strips (ground, side bands, simple props, start lines, lighting) | Client (`WorldController`) from `Config/Biomes` | Nothing to replicate. Each biome is cut into tiles (`Tuning.World.TILE_LENGTH`) and only tiles near the camera exist (`STREAM_AHEAD` / `STREAM_BEHIND`), pooled. Lighting and the Atmosphere blend to the biome under the camera. |
| Landmarks | Client clones from `ReplicatedStorage.Landmarks` | Hand-made models, placed by config. |

## 3. Modules

**Server: `src/server/`** (the only code that changes stats)

| Module | Job |
|---|---|
| Services/DataService | ProfileStore wrapper: load, autosave, release, migrate. Only module that touches DataStores. |
| Services/StatService | Total Power multiplier (bat × pets × rebirth × pitcher bonus). |
| Services/PitchService | **Pitcher slot.** Holds each player's active Pitcher, schedules pitches, keeps the one pending pitch. |
| Services/SwingService | Handles `Swing`: matches it to the pending pitch, adds Power, makes the hit's first flight segment, queues the next pitch after the ball-cam. |
| Services/LandingService | **On-land hook.** Runs the landing handlers, then finalizes distance, biome and Wins. |
| Services/HighlightService | **Highlight event.** Detects biomes reached for the first time this run; fires a server Signal and the `Highlight` remote. Records are not fired yet (every early hit is one). |
| Services/ChallengeService | **Per-biome challenge.** Reads each biome's `challenge` slot. Does nothing while all are nil. |
| Services/WorldService | Builds the batting area and pitcher spot at startup. |
| Services/BatService | Buy and equip bats with Wins. |
| Services/EggService | Server-side weighted egg rolls; grant, equip and unequip pets. |
| Services/RebirthService | Check cost; reset Power, Wins and bats; keep pets; grant multiplier and world unlocks. |
| Services/ReplicationService | Send each player their own snapshot and changes. |
| Services/LeaderstatsService | Mirror Wins and Rebirths into the player list. |
| Pitchers/PitchingMachine | Default `Pitcher`: fixed cooldown and travel time. |
| Services/DevService | Studio-only test hook (`ServerStorage.DevData`); does nothing on live servers. |
| Data/Template | Default save for new players; ProfileStore fills missing keys from it. |
| Data/Migrations | Upgrades older saves one version at a time, on a copy first. |
| Packages/ProfileStore | ProfileStore 1.0.3, commit `45c9847`, unmodified (Apache-2.0). |

**Client: `src/client/`** (input and drawing only, no stat math)

| Module | Job |
|---|---|
| Controllers/StateController | Latest snapshot from the server; others read it. |
| Controllers/InputController | Tap anywhere (not on menus) or the swing button fires `Swing` with the pending `pitchId`. |
| Controllers/PitcherController | Shows the active pitcher and plays each `Pitch` using that pitcher's visual. |
| Controllers/BallController | Contact and the flight segments from `HitResult`, with slow motion before the landing. Fires `Launched` and `Touchdown`; `WatchDistance` for crossings. |
| Controllers/WorldController | Streams biome tiles and landmarks around the camera; blends lighting per biome. |
| Controllers/CameraController | Ball-cam on every hit: snap behind the ball, follow, hold on the landing, swoop (or fade-cut when far) back to the batter. |
| Controllers/HighlightController | Biome banner at the moment the ball crosses a new biome's line; distance popup at each landing; client `Landed` signal. |
| Controllers/HudController | Power, Wins, distance bar with biome markers, swing button. |
| Controllers/BatShopController | Bat shop UI. |
| Controllers/EggController | Egg UI with full odds before hatching; hatch animation. |
| Controllers/PetController | Equipped pets following the player (cosmetic). |
| Controllers/RebirthController | Rebirth panel: cost, what resets, what is kept. |
| PitcherVisuals/PitchingMachine | Machine model and throw animation. |

**Shared: `src/shared/`**

| Module | Job |
|---|---|
| Remotes | Every remote by name (the client↔server contract). |
| Types | `PlayerData` save type. |
| HookTypes | Hook contracts: `Pitcher`, `Pitch`, `LandingHandler`, `Highlight`, `BiomeChallenge`, `BiomeConfig`. |
| Formulas | Pure math: multipliers, distance from Power, Wins from distance, rebirth cost. |
| Format | Number display (1.2K, 3.4M). |
| Signal | Small server/client event utility used by the hooks. |
| Config/Tuning | **Every tunable number** (pitch timing, Power, distance, Wins, biome start distances, lane layout, streaming, flight visuals, ball-cam). |
| Config/Bats, Eggs, Pets, Biomes, Rebirth | Catalog tables (ids, names, per-item stats). |

## 4. The hit flow

```
PitchService ──Pitch──▶ client draws the throw (PitcherVisuals/<pitcherId>)
      │  (pending pitch stored on server)
tap ──Swing(pitchId)──▶ SwingService
      │  no pending pitch / wrong id → ignored (a whiff, no Power)
      │  power += 1 × StatService.multiplier
      │  segment 1 = { from 0, to Formulas.distance(power), source "hit" }
      ▼
LandingService: for each LandingHandler (none yet) → may append segments
      │  final distance, biome, Wins (Formulas) → save updated
      ├──HitResult──▶ client: BallController animates every segment in order
      ├──DataChanged──▶ client: HUD
      ▼
HighlightService: new best distance? new biome this run? → Signal + Highlight remote
ChallengeService: listens to landings; no-op while challenges are nil
      ▼
PitchService.QueueNext: next pitch after the ball-cam (Formulas.ballCamTime), so it
      reaches the plate just after the camera is back (a miss waits only the cooldown)
```

- **The ball-cam sets the pace.** Every hit is watched: the server holds the next pitch for
  `Formulas.ballCamTime(distance)` (air time + slow motion + landing hold + return), the same
  numbers the client camera uses. Taps while the camera is away are ignored.
- **Pitch cadence is the tap limit.** One pending pitch per player means no extra
  rate limiter is needed, and spam does nothing. A faster pitcher pet is a natural upgrade later.
- **Contact is instant:** any tap while a pitch is pending is a hit, wherever the ball is
  drawn, so latency on phones never causes a miss. `Tuning.HIT_WINDOW` is reserved for
  a timing mechanic later.
- **First swing within 10s:** the first pitch is sent the moment the save loads, and the
  machine is visible from spawn.

## 5. Hooks (designed now, built later)

All types are in [HookTypes.luau](../src/shared/HookTypes.luau).

**Pitcher slot.** `PitchService.SetPitcher(player, pitcher)` swaps the active `Pitcher`
(cooldown, travel time, optional Power bonus). The save stores `pitcher = "pitching_machine"`.
A pitcher pet is a new file in `Pitchers/` plus one in `PitcherVisuals/` with the same id.
No other code changes.

**On-land hook.** `LandingService.AddHandler(fn)` registers a `LandingHandler`. After the
hit lands, each handler sees the landing spot and may return one more `FlightSegment`
(e.g. a catcher pet runs to the ball and pushes it further). Wins are paid on the
**final** distance, so the bonus counts. The client gets every segment and animates them in order.

**Highlight event.** `HighlightService.Fired` (server Signal) plus the `Highlight` remote
to that player, for `kind = "record"` (beats lifetime best distance) or `"biome"`
(first time reaching a biome this run; one per biome if a hit reaches several). The client
shows a banner when the ball crosses that biome's line. "record" is defined but not fired yet.
Later, a camera pet listens to the same event to save a clip.

The client also has `HighlightController.Landed`, fired when the ball visibly lands (after
the distance popup). It is the place for visual landing effects; the server's on-land hook
has already decided the result by then.

**Per-biome challenge slot.** Every entry in `Config/Biomes` has `challenge = nil`.
`ChallengeService` will read it and listen to landings when challenges exist.

## 6. Client ↔ server (remotes)

The server creates everything under `ReplicatedStorage.Remotes` at startup.

| Direction | Name | Type | Payload |
|---|---|---|---|
| C → S | `Swing` | Event | `pitchId` |
| C → S | `GetData` | Function | → full snapshot of the caller's own save |
| C → S | `BuyBat` / `EquipBat` | Function | `batId` → `{ ok, err? }` |
| C → S | `HatchEgg` | Function | `eggId, count` → `{ ok, err?, pets }` |
| C → S | `EquipPet` / `UnequipPet` | Function | `petUid` → `{ ok, err? }` |
| C → S | `Rebirth` | Function | → `{ ok, err? }` |
| S → C | `Pitch` | Event | `Pitch` (see HookTypes) |
| S → C | `HitResult` | Event | `{ hitId, powerGained, segments, distance, biomeIndex, winsGained }` |
| S → C | `Highlight` | Event | `Highlight` minus `player` |
| S → C | `DataChanged` | Event | changed top-level keys only |

Rules: the client never sends a number that becomes a stat. Every argument is
type-checked, and unknown ids are rejected. There are no server → client
RemoteFunctions.

## 7. Player save (`src/shared/Types.luau`)

```lua
{
  version = 1,
  -- reset on rebirth
  power = 0, wins = 0,
  bats = { owned = { starter = true }, equipped = "starter" },
  highestBiome = 1,
  -- kept through rebirth
  pets = { ["p1"] = { id = "sandlot_pup", equipped = true } },
  nextPetUid = 2,
  pitcher = "pitching_machine",
  rebirths = 0, worldsUnlocked = 1, currentWorld = 1,
  -- lifetime, never reset
  lifetime = { swings = 0, winsEarned = 0, bestDistance = 0, eggsHatched = 0 },
  firstJoin = 0, lastJoin = 0,
}
```

`lifetime.bestDistance` drives "record" highlights; `highestBiome` drives "biome" highlights.
There's a version number for migrations and no Robux fields.

## 8. How the hard rules are enforced

| Rule | Where |
|---|---|
| Server-side stats | Only Services write the save. Client sends a pitch id and ids, never values. |
| Low-end mobile | Biomes built on the client and only near the camera; one ball part plus a cheap trail; no per-frame server sends. |
| No Wins for Robux | No Robux products in MVP. |
| Odds before purchase | EggController shows odds from the same `Config/Eggs` weights EggService rolls from. |
| Original assets | Landmarks are ours; nothing from the Toolbox. |
| 10s / 60s | First pitch on save load; Biome 2 distance tuned against early Power gain in the economy step. |
