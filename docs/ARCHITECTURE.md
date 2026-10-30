# HomeRun Mascots: Architecture (v3)

Status: the engine is built: tap to hit, +1 Power, ball-cam through the 6 World 1 biomes,
highlights. The Mascot economy below is designed but not built yet. Modules marked
*(planned)* are stubs or don't exist yet. Design guardrails and hard rules: [CLAUDE.md](../CLAUDE.md).

Decisions so far:
- Every tap is one swing. A pitched ball is in play, the tap hits it, +1 Power (× multipliers), and the ball launches. No charge-up, no timing.
- Every landing catches a Mascot. Seated Mascots earn Cash per second, the only income. Hits don't pay.
- Saves use **ProfileStore**.
- Biomes and Mascots are generated from config, keyed by world. Each biome references one hand-made landmark model (placeholders for now).
- Four hooks: **pitcher slot**, **on-land** (drives the Mascot catch), **highlight** (drives the catch reveal and rare-catch clips), **per-biome challenge**.
- Eggs and pets are dropped.

## 1. Game loop

```
tap → hit (+1 Power × bat × stadium tier × boosts) → ball-cam → landing
    → catch a Mascot from the landing biome → catch reveal
    → it takes a free seat (earns Cash/s) or a hotbar slot (doesn't earn)
Cash → balls (rarer Mascots) · bats (more Power per swing) · park upgrades (more Cash/s)
stadium promotion → reset run progress, keep every Mascot, next world, higher multipliers
```

**The catch.** Distance picks the biome. Luck climbs with distance inside the odds curve.
The best ball owned sets the base rarity odds. Each biome has 8 species (6 at launch, one per
rarity). Rarity is fixed per species: 2 Common, 2 Uncommon, then one each of Rare, Epic,
Legendary and Mythic. Two more rolls, independent of each other and of the species, stack on earnings:
- **Variant:** none, All-Star, Gold Glove or Hall of Fame.
- **Size:** normal, Big or Giant.

A Mascot's Cash/s and sell value are both base × variant × size. All odds and multipliers live
in `Config/Mascots` and `Tuning.Catch`, and one shared function (`Formulas.catchOdds`) feeds
both the server roll and every odds screen.

**The park.** Each lane has a ballpark plot with 10 seats. Only seated Mascots earn. Park
upgrades are Bleachers, Concessions, Scoreboard, Lights and Jumbotron, each up to 10 levels.
Each level adds a % to the park's Cash rate. Costs live in `Config/Park`.

**Cash rate** = sum of seated Mascots' Cash/s × park multiplier × stadium-tier Cash multiplier.

**Balls** are permanent Cash unlocks, bought in order. Every hit uses the best ball owned, with
no equip step. A "New ball unlocked" toast shows once per tier per run, the first time Cash
covers it. Balls are never sold for Robux.

**Offline earnings.** `lastOnline` is saved on every save and on leave. At load, the server
pays Cash rate × time away, at full rate, capped at `Tuning.Offline` (3h). It's credited before
the player sees anything. The Welcome Back screen only shows the amount and never covers the
SWING button. A missing or future `lastOnline` pays 0.

**Stadium promotion** (the rebirth). Tiers: Sandlot Field → Minor League → Big Stadium →
Space Dome. Each tier has two separate multipliers in `Config/Stadium`: Power gained per hit,
and Cash/s.
- **Resets:** Power, Cash, bats, balls, park upgrades and `highestBiome`.
- **Kept:** every Mascot (seats, hotbar, On Deck, locks) and the Index.
- **World:** tier N plays World N, with no way back. Only World 1 exists; World 2 starts as a
  placeholder (World 1 recoloured, placeholder Mascots).

The confirm screen shows what resets and what the new tier gives. If promotions feel too soft,
tune the Cash multiplier or park costs, never Mascot loss.

### Overflow: seats, hotbar, On Deck, Auto-Sell, Lock

1. **Room:** a new catch takes a free seat, otherwise a free hotbar slot (4 slots).
2. **Full, Auto-Sell ON (default):** the new catch is compared with the weakest *unlocked*
   hotbar Mascot by Cash/s. The weaker one sells instantly at full sell value, with a toast
   ("Sold Frog +$120"). The swing loop never pauses.
3. **All 4 hotbar Mascots locked:** the new catch goes to On Deck if it's free. Otherwise the
   weaker of the catch and the On Deck Mascot sells. If the On Deck Mascot is locked, the
   catch sells.
4. **Full, Auto-Sell OFF:** the catch goes to the single On Deck slot, which doesn't earn. The
   player keeps it by swapping it into the hotbar, or sells it. If On Deck is taken, the weaker
   of the two sells; if the On Deck Mascot is locked, the catch sells.
5. **Turning Auto-Sell on** sells nothing by itself. The rules apply from the next catch.
6. **Lock** is a per-Mascot flag. A locked Mascot is never auto-sold and never chosen as weakest.
7. **Ties:** the newer Mascot (higher uid) sells.
8. **Equip Best** is a manual tap. It seats the top 10 earners and moves the rest to the hotbar,
   then On Deck.
9. **Index:** every catch unlocks its species card permanently (count, plus the variants and
   sizes seen), even if that Mascot is later sold.
10. Sell values live in config, not code. There is no storage box: a player holds at most 15
    Mascots (10 + 4 + 1).

### Why each new mechanic exists (guardrail 7)

- **Mascot catch on every landing.** Today a hit pays a number. A catch pays a named, visible
  reward every 2–3 seconds from the first swing, which is what holds a new player in the
  first minute (**bounce**). Random variants and sizes give each hit a small chance of a big
  moment without adding a way to fail: every landing catches something.
- **Seats, park and Cash/s.** Income from seated Mascots turns catches into a choice of
  which ten to keep, and gives a goal beyond distance. Park upgrades are frequent, cheap
  Cash sinks that visibly grow your space. Together they extend each session (**playtime**)
  and give returning players something they built (**D1**).
- **Auto-Sell, Lock and On Deck.** A full roster must never block swinging or force a
  menu. Auto-Sell keeps the loop flowing, Lock and On Deck protect favourites, and every
  sale is at full value. That removes the inventory wall where players quit (**playtime**,
  **D1**), and nothing is lost without a rule the player controls (Safe at home).
- **Offline earnings.** Seated Mascots keep earning, capped at 3h, so leaving and coming back
  pays off. That's a reason to return the next day (**D1**) with a visible reward on the
  Welcome Back screen.
- **Stadium promotion.** A reset that keeps every Mascot and opens a new world with
  better-earning Mascots gives the long-term goal (**D28**). It never costs the player their
  collection.
- **Catch reveal.** The Mascot chasing and catching the ball, then its name typing in,
  makes each new species a moment (**bounce**, **D1**). It's visual only, short (1s) unless the
  species is new and Rare or up, tappable to skip, and it replaces the existing landing hold,
  so pacing to Biome 2 stays under 60s.

## 2. Folder layout

```
HMG/
├─ default.project.json   Rojo: maps src/ and assets/ into the place
├─ rokit.toml             pinned tools: rojo 7.7.1, selene, stylua
├─ CLAUDE.md              design guardrails and hard rules
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
      ├─ Remotes, Types, HookTypes, Formulas, Format, Signal, BatPose
      └─ Config/
```

**Landmark models:** each is a file in `assets/Landmarks/`. They start as simple
`.model.json` placeholders. To swap in a real one, build it in Studio, export it as
`<BiomeId>.rbxm` into the same folder, and delete the placeholder.

## 3. World: who builds what

The ball's flight is **math on the server, visuals on the client**. Distance is a
number along one straight track, so the server never needs the biome geometry.

| Piece | Built by | Why |
|---|---|---|
| Batting lanes (pad, plate, batter spawn, pitching machine) | Server (`WorldService`) | Characters stand on them, so they must be physical and replicated. One lane per player (`Tuning.World.LANE_COUNT`, default 8), side by side along X; balls fly down +Z. Lane models are Persistent for streaming. |
| Ballpark plots (10 seat pads, owner sign, upgrade spots) *(planned)* | Server (`WorldService`) | One per lane, inside the lane layout, so other players see your park. |
| Seated Mascots and park upgrade props *(planned)* | Client (`ParkController`) from replicated seats and levels | Cheap part-built rigs. Far parks are hidden; low graphics turns off idle animation. |
| Biome strips (ground, side bands, simple props, start lines, lighting) | Client (`WorldController`) from `Config/Biomes` | Nothing to replicate. Each biome is cut into tiles (`Tuning.World.TILE_LENGTH`) and only tiles near the camera exist (`STREAM_AHEAD` / `STREAM_BEHIND`), pooled. Lighting and the Atmosphere blend to the biome under the camera. |
| Landmarks | Client clones from `ReplicatedStorage.Landmarks` | Hand-made models, placed by config. |

## 4. Modules

**Server: `src/server/`** (the only code that changes stats)

| Module | Job |
|---|---|
| Services/DataService | ProfileStore wrapper: load, autosave, release, migrate. Only module that touches DataStores. |
| Services/StatService | Power multiplier per hit (bat × stadium-tier Power multiplier × pitcher bonus × boosts). |
| Services/PitchService | **Pitcher slot.** Holds each player's active Pitcher, schedules pitches, keeps the one pending pitch, and brings the next pitch forward on `Ready` (never inside the minimum gap). |
| Services/SwingService | Handles `Swing`: matches it to the pending pitch, adds Power, makes the hit's first flight segment, queues the next pitch after the ball-cam and reveal. |
| Services/LandingService | **On-land hook.** Runs the push handlers, then the catch phase (`SetCatcher`), then fires `Landed` with the final distance, biome and catch. |
| Services/MascotService | Sets the catch phase: rolls species, variant and size on the server, updates the Index and lifetime count, places the catch with `MascotInventory`, checks the result before writing it, pays sales at full value. (Planned: Sell, Lock, Move, Equip Best and Auto-Sell remotes.) |
| Services/MascotInventory | Pure rules for seats, hotbar, On Deck, Auto-Sell, Lock, Sell, Move (swap) and Equip Best, plus `Check` (10 seats, 4 hotbar, every Mascot in exactly one slot). No services; tested by `Dev/MascotInventoryTest` (DevData `selftest`). |
| Services/ParkService *(planned)* | Park upgrades, and the once-a-second Cash/s payout. |
| Services/OfflineService *(planned)* | Pays capped offline earnings at load and sends `WelcomeBack`. |
| Services/BallService *(planned)* | Buys ball tiers with Cash (in order, permanent for the run). |
| Services/BatService | Buy and equip bats with Cash. |
| Services/PromotionService *(stub)* | Stadium promotion: check the requirement, reset run progress, keep every Mascot, raise the tier. |
| Services/HighlightService | **Highlight event.** Biomes reached for the first time this run, record milestones, and (planned) catches that earn a reveal or rare-catch clip. Fires a server Signal and the `Highlight` remote. |
| Services/ChallengeService | **Per-biome challenge.** Reads each biome's `challenge` slot. Does nothing while all are nil. |
| Services/WorldService | Builds the batting lanes, pitcher spots and (planned) ballpark plots at startup. |
| Services/ReplicationService | Send each player their own snapshot and changes; (planned) everyone's seated Mascots for display. |
| Services/LeaderstatsService | Stadium tier and Best distance in the player list. |
| Pitchers/PitchingMachine | Default `Pitcher`: fixed cooldown and travel time. |
| Services/DevService | Studio-only test hook (`ServerStorage.DevData`); does nothing on live servers. |
| Data/Template | Default save for new players; ProfileStore fills missing keys from it. |
| Data/Migrations | Upgrades older saves one version at a time, on a copy first. |
| Packages/ProfileStore | ProfileStore 1.0.3, commit `45c9847`, unmodified (Apache-2.0). |

**Client: `src/client/`** (input and drawing only, no stat math)

| Module | Job |
|---|---|
| Controllers/StateController | Latest snapshot from the server; others read it. |
| Controllers/InputController | Tap anywhere (not on menus) or the swing button launches the hit instantly and fires `Swing(pitchId)` once per pitch; swings the bat. |
| Controllers/PitcherController | Shows the active pitcher and plays each `Pitch` using that pitcher's visual. |
| Controllers/BallController | Contact and the flight segments from `HitResult`, with slow motion before the landing. Fires `Launched` and `Touchdown`; `WatchDistance` for crossings. |
| Controllers/WorldController | Streams biome tiles and landmarks around the camera; blends lighting per biome. |
| Controllers/CameraController | Ball-cam on every hit: snap behind the ball, follow, hand off to the catch reveal at landing, swoop (or fade-cut when far) back to the batter. |
| Controllers/CatchRevealController *(planned)* | The Mascot's view as it chases and catches the ball; name types in letter by letter. Full for new Rare+ species, 1s otherwise, tap to skip (sends `Ready`). |
| Controllers/HighlightController | Biome banner at the line crossing; distance popup; catch and sold toasts; client `Landed` signal. |
| Controllers/HudController | Power, Cash (and Cash/s), distance bar with biome markers, swing button. |
| Controllers/ParkController *(planned)* | Draws seated Mascots and upgrade props on every plot; park upgrade buttons. |
| Controllers/MascotPanelController *(planned)* | Hotbar and On Deck bar, plus the Mascots panel: Sell, Lock, Equip Best, Auto-Sell toggle. |
| Controllers/IndexController *(planned)* | The Index: world and biome tabs, 8 cards per biome. |
| Controllers/ShopController *(planned, from BatShopController)* | Balls (with each tier's odds) and bats. |
| Controllers/WelcomeBackController *(planned)* | Shows the offline payout; never covers SWING. |
| Controllers/PromotionController *(stub)* | Promotion panel: requirement, what resets, what's kept, what the new tier gives. |
| PitcherVisuals/PitchingMachine | Machine model and throw animation. |

**Shared: `src/shared/`**

| Module | Job |
|---|---|
| Remotes | Every remote by name (the client↔server contract). |
| Types | `PlayerData` save type. |
| HookTypes | Hook contracts: `Pitcher`, `Pitch`, `LandingHandler`, `Highlight`, `BiomeChallenge`, `BiomeConfig`. |
| Formulas | Pure math: Power multiplier, distance from Power, ball-cam time, record milestones, Luck, catch odds (`catchOdds`) and rolls, Mascot Cash/s and sell value; (planned) reveal time, Cash rate, offline pay. |
| Format | Number display (1.2K, 3.4M). |
| Signal | Small server/client event utility used by the hooks. |
| BatPose | Bat grip poses shared by server and client. |
| Config/Tuning | **Every tunable number** (pitch timing, Power, distance, biome starts, lanes, streaming, ball-cam, highlights, swing, catch: Luck, variants, sizes, Cash/s, sell value; planned: reveal, offline). |
| Config/Biomes | Biome visuals, keyed by world (`Biomes[1]` = World 1). |
| Config/Mascots | Rarities, and species keyed by world then biome id: 6 per biome at launch (one per rarity), 8 Index slots. |
| Config/Balls | Ball tiers in unlock order with base rarity weights (only the basic ball so far). |
| Config/Stadium | The 4 stadium tiers with their Power and Cash multipliers (tiers 2–4 tuned in the promotion step). |
| Config/Bats, Park *(Park planned)* | Catalog tables (ids, names, prices, multipliers). |

## 5. The hit flow

```
PitchService ──Pitch──▶ client draws the throw (PitcherVisuals/<pitcherId>)
      │  (pending pitch stored on server)
tap ──Swing(pitchId)──▶ SwingService
      │  (the client has already launched the ball on tap; this confirms the numbers)
      │  no pending pitch / repeat or stale id → ignored (one hit per pitch; nothing is lost)
      │  power += 1 × StatService.multiplier
      │  segment 1 = { from 0, to Formulas.distance(power), source "hit" }
      ▼
LandingService: push handlers (none yet) → may append segments
      │  catch phase (MascotService): biome + Luck from final distance, odds from best ball
      │  → species, variant, size → Index → placement (seat / hotbar / On Deck / sold)
      ├──HitResult──▶ client: BallController animates every segment; catch reveal at landing
      ├──DataChanged──▶ client: HUD, hotbar, park
      ▼
HighlightService: new best distance? new biome this run? catch worth a full reveal or clip?
ChallengeService: listens to landings; no-op while challenges are nil
      ▼
PitchService.QueueNext: next pitch after ball-cam + reveal (Formulas.ballCamTime), so it
      reaches the plate just after the camera is back; `Ready` (skip) brings it forward,
      never inside the server's minimum gap
```

- **The ball-cam sets the pace.** Every hit is watched: the server holds the next pitch for
  `Formulas.ballCamTime` (air time + slow motion + reveal + return), the same numbers the
  client camera uses. The catch reveal *replaces* the old landing hold, so it adds little time.
  No pitch is in play while the camera is away, so those taps only swing the bat; if lag ever
  lets a pitch through, a tap still hits it.
- **Skipping.** Tapping during a reveal skips it and sends `Ready`. The server can bring the next
  pitch forward but never inside a minimum gap, so spamming skip can't beat the normal pace.
  Auto-Swing skips the same way (guardrail 6).
- **Pitch cadence is the tap limit.** One pending pitch per player means no extra rate limiter
  is needed, and spam does nothing.
- **Every tap on a pitch is a hit** ([CLAUDE.md](../CLAUDE.md) guardrails 1–3): no timing,
  no misses. The pitch can be hit from release until `Pitch.LATE_WINDOW` after it reaches the
  plate (the server keeps it open `SERVER_GRACE` longer for slow connections). The client
  launches the ball the instant you tap, to a predicted distance
  (`Formulas.distance(power + last gain)`); the server's `HitResult` confirms it, and if it
  differs (new multiplier, an on-land handler) the flight re-plans mid-air. The player never
  waits for the server.
- **The catch never makes you wait.** The catch is rolled on the server, so the client can't
  predict it, but `HitResult` normally arrives while the ball is still in the air (at least
  ~1s). If it's still missing at landing, the reveal is skipped and a toast shows the catch
  when it arrives.
- **First swing within 10s:** the first pitch is sent the moment the save loads, and the
  machine is visible from spawn. **Biome 2 within 60s** is re-measured in every step.

## 6. Hooks

All types are in [HookTypes.luau](../src/shared/HookTypes.luau).

**Pitcher slot.** `PitchService.SetPitcher(player, pitcher)` swaps the active `Pitcher`
(cooldown, travel time, optional Power bonus). The save stores `pitcher = "pitching_machine"`.
A new pitcher is a new file in `Pitchers/` plus one in `PitcherVisuals/` with the same id.
No other code changes.

**On-land hook.** `LandingService.AddHandler(fn)` registers a `LandingHandler`. After the
hit lands, each handler sees the landing spot and may return one more `FlightSegment`
(e.g. a bounce that pushes the ball further). Then the **catch phase** runs on the **final**
distance: `MascotService` rolls the Mascot from that biome, so a push changes which biome's
Mascot you catch. The client gets every segment and animates them in order.

**Highlight event.** `HighlightService.Fired` (server Signal) plus the `Highlight` remote
to that player:
- `kind = "record"`: the best distance passes a milestone (100, 250, 500, 1K, 2.5K … studs).
  The client shows "PERFECT!" as the ball passes it.
- `kind = "biome"`: the first time reaching a biome this run, one per biome if a hit reaches
  several. The client shows "PERFECT!" and a banner when the ball crosses that biome's line.
- *(planned)* `kind = "catch"`: a new species of Rare or up gets the full reveal. Epic and up,
  Hall of Fame or Giant catches get a rare-catch clip.

Celebrations are given by the result, never earned by tap skill.

The client also has `HighlightController.Landed`, fired when the ball visibly lands. It is the
place for visual landing effects; the server's on-land hook has already decided the result.

**Per-biome challenge slot.** Every entry in `Config/Biomes` has `challenge = nil`.
`ChallengeService` will read it and listen to landings when challenges exist.

## 7. Client ↔ server (remotes)

The server creates everything under `ReplicatedStorage.Remotes` at startup. *(planned)*
rows don't exist yet.

| Direction | Name | Type | Payload |
|---|---|---|---|
| C → S | `Swing` | Event | `pitchId` |
| C → S | `Ready` *(planned)* | Event | `hitId`: the reveal was skipped; the server may bring the next pitch forward |
| C → S | `GetData` | Function | → full snapshot of the caller's own save |
| C → S | `BuyBat` / `EquipBat` | Function | `batId` → `{ ok, err? }` |
| C → S | `BuyBall` *(planned)* | Function | `ballId` → `{ ok, err? }` |
| C → S | `BuyParkUpgrade` *(planned)* | Function | `upgradeId` → `{ ok, err? }` |
| C → S | `SellMascot` / `LockMascot` *(planned)* | Function | `uid` (+ `locked`) → `{ ok, err? }` |
| C → S | `MoveMascot` *(planned)* | Function | `uid, place, slot` (seat, hotbar, On Deck swap) → `{ ok, err? }` |
| C → S | `EquipBest` / `SetAutoSell` *(planned)* | Function | (`on`) → `{ ok, err? }` |
| C → S | `Promote` *(planned)* | Function | → `{ ok, err? }` |
| S → C | `Pitch` | Event | `Pitch` (see HookTypes) |
| S → C | `HitResult` | Event | `{ hitId, powerGained, pitcherBonus, segments, distance, biomeIndex, catch? }`. `catch` = `HookTypes.Catch`: `{ uid, species, rarity, variant, size, cashPerSec, placedIn, slot?, isNewSpecies, sold? }` |
| S → C | `Highlight` | Event | `Highlight` minus `player` |
| S → C | `WelcomeBack` *(planned)* | Event | `{ seconds, cash }` |
| S → C | `DataChanged` | Event | changed top-level keys only |

Rules: the client never sends a number that becomes a stat. Every argument is
type-checked, and unknown ids are rejected. There are no server → client
RemoteFunctions. Inventory actions never block or delay swinging.

## 8. Player save (`src/shared/Types.luau`)

Save version 2. There are no live players, so the
v1 → v2 migration empties old test saves and refills them from the Template. ProfileStore only
adds missing keys, so the wipe is explicit.

```lua
{
  version = 2,
  -- run progress: reset on stadium promotion
  power = 0, cash = 0,
  bats = { owned = { starter = true }, equipped = "starter" },
  balls = { owned = { basic = true } },          -- every hit uses the best owned
  park = { bleachers = 0, concessions = 0, scoreboard = 0, lights = 0, jumbotron = 0 },
  highestBiome = 1,
  -- kept forever (Safe at home)
  mascots = { ["m1"] = { species = "...", variant = "none", size = "normal", locked = false } },
  nextMascotUid = 2,
  seats = { "m1", false, false, false, false, false, false, false, false, false },  -- 10
  hotbar = { false, false, false, false },                                          -- 4
  onDeck = false,
  autoSell = true,
  index = { ["species"] = { count = 1, variants = { none = true }, sizes = { normal = true } } },
  stadiumTier = 1,                                -- tier N plays World N
  pitcher = "pitching_machine",
  settings = { music = true, sfx = true, lowGraphics = false, tipsSeen = {} },
  -- lifetime, never reset
  lifetime = { swings = 0, cashEarned = 0, mascotsCaught = 0, bestDistance = 0 },
  firstJoin = 0, lastJoin = 0, lastOnline = 0,
}
```

- Removed from v1: `wins`, `pets`, `nextPetUid`, `rebirths`, `worldsUnlocked`,
  `currentWorld`, `lifetime.winsEarned` and `lifetime.eggsHatched`.
- `lifetime.bestDistance` drives "record" highlights (milestones in
  `Tuning.Highlight.RECORD_MILESTONES`); `highestBiome` drives "biome" highlights.
- A Mascot is in exactly one place: a seat, the hotbar or On Deck.
- There are no Robux fields. Timed boosts get their own keys when they're built (the Template
  fills them in, no version bump).

## 9. How the hard rules are enforced

| Rule ([CLAUDE.md](../CLAUDE.md)) | Where |
|---|---|
| Server-side stats | Only Services write the save. The client sends a pitch id and ids, never values. Catches are rolled with a server `Random`. |
| Low-end mobile | Biomes built on the client, only near the camera; one ball part plus a cheap trail; part-built Mascot rigs, far parks hidden; Cash replicates as a rate, not every tick. |
| Power, distance and tier never for Robux; balls Cash-only | No product touches Power, distance, stadium tier or balls. Robux items are a Luck Boost (luck only) and Auto-Swing (the tap path). |
| Odds before any luck purchase | The odds screen shows every Mascot's % with and without the boost, from the same `Formulas.catchOdds` the server rolls with. |
| Safe at home | No trading or stealing. Sales only through the player's tap, Auto-Sell or the On Deck rule, at full value, never locked Mascots; `MascotInventory` checks this on every change. Promotion keeps every Mascot. |
| Original assets | Landmarks and Mascots are ours; nothing from the Toolbox; no MLB names or logos. |
| 10s / 60s | First pitch on save load. The catch reveal replaces the landing hold; Biome 2 time is re-measured in every step. |

## 10. Parked ideas (not in the main loop)

Ideas that add skill or a way to fail stay here until they fit the guardrails in
[CLAUDE.md](../CLAUDE.md). Nothing here may change main progression.

- **Training Area: optional skill mini-game, no effect on main progression.** A separate
  batting cage with timed swings: Perfect / Good / early / late windows around the ball
  reaching the plate, one swing per pitch, and a lag-tolerant server check of the client's tap
  time. This was built and then reverted from the main loop (commit `12825eb`, reverted in
  "Revert timing, add guardrails") because it broke guardrails 1, 2, 3 and 6. If it returns, its
  rewards must be cosmetic or separate from Power, distance and Cash.
