# HomeRun Mascots: Architecture (v3)

Status: the engine is built: tap to hit, +1 Power, ball-cam through the 6 World 1 biomes,
highlights. The Mascot economy below is designed but not built yet. Modules marked
*(planned)* are stubs or don't exist yet. Design guardrails and hard rules: [CLAUDE.md](../CLAUDE.md).

Decisions so far:
- Every tap is one swing: **Fungo hitting**. One tap tosses the ball up and hits it in one motion (about 0.5s), from anywhere in the lane's hitting circle. +1 Power (× multipliers), and the ball launches. No pitch to wait for, no charge-up, no timing, no indicator.
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
the player sees anything. The Welcome Back card only shows the amount (after at least 60s away),
stays out of the way and ignores taps, so a tap on it still swings. A missing or future
`lastOnline` pays 0. Live pay is per player from the moment the save loaded, so offline and live
pay never overlap.

**Stadium promotion** (the rebirth). Tiers: Sandlot Field → Minor League → Big Stadium →
Space Dome. Each tier has two separate multipliers in `Config/Stadium`: Power gained per hit,
and Cash/s.
- **Resets:** Power, Cash, bats, balls, park upgrades and `highestBiome`.
- **Kept:** every Mascot (seats, hotbar, On Deck, locks) and the Index.
- **World:** tier N plays World N, with no way back (`Formulas.world`; tiers past the last world
  play the last one). World 2 is a placeholder: World 1 recoloured to dusk ("Dusk Sandlot" and
  so on, same layout and landmarks) with 36 placeholder Mascots ("Dusk Dust Bunny", ids `w2_…`,
  same rarities). Mascots earn × `Tuning.Catch.WORLD_CASH[world]` (World 2 ×1000), so a World 2
  Sandlot Common earns about what a World 1 Canyon Common does. The world view, the distance bar,
  biome banners, landing popups and catch rolls all follow the current world; the Index has a
  tab per world reached.

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
- **Fungo hitting (replaces the pitching machine).** Waiting for a throw and standing on a
  mark made the first seconds feel like a timing game and pinned players in place. A one-tap
  self-toss starts the first swing the moment the save loads and lets players walk around the
  hitting circle while they play, which helps the first minute (**bounce**) and makes the loop
  feel like theirs (**playtime**). Every tap still hits, the cycle time is fixed, and the
  swing's growing size with Power (toss height, hit-stop, camera punch, crack, particles,
  shockwave) is visual and audio only, a visible sign of progress that brings players back
  (**D1**, **D28**). It adds no way to fail.
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
   │  ├─ Pitchers/           Pitcher implementations: Fungo (default, "toss"), PitchingMachine ("throw")
   │  └─ Packages/           vendored server-only libraries (ProfileStore 1.0.3)
   ├─ client/   → StarterPlayer.StarterPlayerScripts.Client (LocalScript)
   │  ├─ init.client.luau    loads Controllers: Init() all, then Start() all
   │  ├─ Controllers/
   │  ├─ Modules/            client helpers that aren't controllers (MascotRig, MascotInfo, UILayout, BatSwing)
   │  └─ PitcherVisuals/     how each "throw" pitcher looks and throws (cosmetic)
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
| Batting lanes (pad, plate, chalk hitting circle, batter spawn; the pitching machine only when it's the default pitcher) | Server (`WorldService`) | Characters stand on them, so they must be physical and replicated. One lane per player (`Tuning.World.LANE_COUNT`, default 8), side by side along X; balls fly down +Z. Lane models are Persistent for streaming. |
| Ballpark plots (10 seat pads in two rows facing the field, owner sign, upgrade spots) | Server (`WorldService`), behind each lane's plate (`Config/Park` layout) | Part of the lane model, so everyone sees every park. Nothing on it collides or can be queried, so it never blocks the player or the camera. The lane model carries `Owner`, `Seats` and `Park` (upgrade levels) attributes. |
| Seated Mascots and upgrade props | Client (`ParkController`) from the lane's `Seats` and `Park` attributes | Simple part-built rigs (`Modules/MascotRig`, shared with the catch reveal) and upgrade props that grow with their level (`Modules/ParkProps`), rebuilt only when they change, with a Cash/s tag shown up close. Parks over 140 studs from the camera aren't drawn; only your own Mascots bob, and not in low graphics. |
| Biome strips (ground, side bands, simple props, start lines, lighting) | Client (`WorldController`) from `Config/Biomes` | Nothing to replicate. Each biome is cut into tiles (`Tuning.World.TILE_LENGTH`) and only tiles near the camera exist (`STREAM_AHEAD` / `STREAM_BEHIND`), pooled. Lighting and the Atmosphere blend to the biome under the camera. |
| Landmarks | Client clones from `ReplicatedStorage.Landmarks` | Hand-made models, placed by config. |

## 4. Modules

**Server: `src/server/`** (the only code that changes stats)

| Module | Job |
|---|---|
| Services/DataService | ProfileStore wrapper: load, autosave, release, migrate. Only module that touches DataStores. |
| Services/StatService | Power multiplier per hit (bat × stadium-tier Power multiplier × pitcher bonus × boosts). |
| Services/PitchService | **Pitcher slot.** Holds each player's active Pitcher and allows one hit per cycle. "toss" (Fungo): a `Swing(tossId)` is allowed once the last cycle is over (less `Pitch.TOSS_GRACE` for jitter), with ids that only go up. "throw" (machine): schedules pitches and keeps the one pending pitch. `Ready` brings the next ball forward (never inside the minimum gap). Publishes the player's `Pitcher` / `PitcherMode` attributes. |
| Services/SwingService | Handles `Swing`: asks PitchService whether it may hit, adds Power, makes the hit's first flight segment, queues the next cycle after the ball-cam and reveal. Where the player stands never matters. |
| Services/LandingService | **On-land hook.** Runs the push handlers, then the catch phase (`SetCatcher`), then fires `Landed` with the final distance, biome and catch. |
| Services/MascotService | Sets the catch phase: rolls species, variant and size on the server, updates the Index and lifetime count, places the catch with `MascotInventory`, checks the result before writing it, pays sales at full value. Handles the Sell, Lock, Move, Equip Best, Auto-Sell and MarkIndexSeen remotes (type-checked, 10 actions/s per player). |
| Services/MascotInventory | Pure rules for seats, hotbar, On Deck, Auto-Sell, Lock, Sell, Move (swap) and Equip Best, plus `Check` (10 seats, 4 hotbar, every Mascot in exactly one slot). No services; tested by `Dev/MascotInventoryTest` (DevData `selftest`). |
| Services/IncomeService | Pays `Formulas.cashRate` (seated Mascots × park × stadium tier) every second, and the capped offline payout at load; answers `GetWelcomeBack` once. DataService stamps `lastOnline` on every save (`profile.OnSave`). |
| Services/ParkService | Publishes each player's seated Mascots on their lane model (`Seats`: `species,variant,size` per seat, `;`-joined), once per frame when seats change, and its upgrade levels (`Park`). Handles `BuyParkUpgrade`: the next level with Cash, up to 10. |
| Services/BallService | `BuyBall`: the next ball tier in order, Cash only, permanent for the run. Sends `ShopNotice` once per tier per run when Cash first covers the next ball (`balls.notified`). |
| Services/BatService | `BuyBat` (the next bat in order, equips it) and `EquipBat` (any bat you own), with Cash. |
| Services/PromotionService | `Promote`: checks the next tier's requirements (`Formulas.promotionStatus`), resets Cash (first), balls, bats, park, Power and biome progress to new-run values, keeps every Mascot, lock and the Index, and raises `stadiumTier`. |
| Services/HighlightService | **Highlight event.** Biomes reached for the first time this run, record milestones, and (planned) catches that earn a reveal or rare-catch clip. Fires a server Signal and the `Highlight` remote. |
| Services/ChallengeService | **Per-biome challenge.** Reads each biome's `challenge` slot. Does nothing while all are nil. |
| Services/WorldService | Builds the batting lanes (pad, plate, hitting circle, spawn), the ballpark plots and, only if it's the default pitcher, the pitching machine. |
| Services/ReplicationService | Send each player their own snapshot and changes; (planned) everyone's seated Mascots for display. |
| Services/LeaderstatsService | Stadium tier and Best distance in the player list. |
| Pitchers/Fungo | Default `Pitcher`, mode "toss": no cooldown; `travelTime` is tap-to-contact (`Fungo.CONTACT_AT`). |
| Pitchers/PitchingMachine | `Pitcher` with mode "throw": fixed cooldown and travel time. Kept as the second slot implementation (e.g. a pitcher pet), not built in the scene. |
| Services/DevService | Studio-only test hook (`ServerStorage.DevData`); does nothing on live servers. |
| Data/Template | Default save for new players; ProfileStore fills missing keys from it. |
| Data/Migrations | Upgrades older saves one version at a time, on a copy first. |
| Packages/ProfileStore | ProfileStore 1.0.3, commit `45c9847`, unmodified (Apache-2.0). |

**Client: `src/client/`** (input and drawing only, no stat math)

| Module | Job |
|---|---|
| Controllers/StateController | Latest snapshot from the server; others read it. |
| Controllers/InputController | No SWING button. A tap anywhere on the game view (not on buttons or menus), left click, Space (instead of jump) or gamepad R2 swings: `FungoController.Toss`, or with the machine, hits the pitch in play. While the ball-cam is away a tap skips the reveal. |
| Controllers/FungoController | `Toss()`: one tap = toss and swing. Sends `Swing(tossId)` at the tap, faces the batter down the field, tosses the ball and swings (`BatSwing`), and launches at `Fungo.CONTACT_AT` from where the batter stands. One toss per cycle; a tap that comes before the server's minimum gap is held, not dropped. Power tiers (`Formulas.swingTier`, `Fungo.TIERS`) scale toss height, hit-stop (taken from the toss so launch time is fixed), camera punch (FOV), bat crack, sparks, dust and a shockwave. Visual and audio only. Auto-Swing will call `Toss`. |
| Controllers/PitcherController | "throw" pitchers only: plays each `Pitch` using that pitcher's visual and keeps the pitch in play. |
| Modules/BatSwing | The local bat swing (ready → contact → optional hit-stop hold → follow-through → ready), shared by Fungo and the machine path. |
| Controllers/BallController | Contact and the flight segments from `HitResult`, with slow motion before the landing. Fires `Launched` and `Touchdown`; `WatchDistance` for crossings. |
| Controllers/WorldController | Streams biome tiles and landmarks around the camera; blends lighting per biome. Shows the player's world and rebuilds when `stadiumTier` changes. |
| Controllers/CameraController | Ball-cam on every hit: snap behind the ball, follow, hold on the landing for the catch reveal (time from the server's catch), swoop (or fade-cut when far) back to the batter. Fires `RevealStarted` / `RevealEnded`; takes the reveal's shot from `SetRevealCamera`. `SkipReveal` on tap; sends `Ready`. |
| Controllers/CatchRevealController | The catch reveal: a part-built placeholder Mascot (species color, rarity ring, variant mark, size scale) runs in, hops to catch the ball and turns to the camera while its name types in; the camera watches from its side. Full (3s, with NEW!, rarity, variant, size) for new Rare+ species, 1s otherwise. Visual only. Studio-only `RevealPreview` hook for screenshots. |
| Controllers/HighlightController | Biome banner at the line crossing; distance popup; catch toast (after the reveal ends, or at once if there was none) and sold toasts; client `Landed` signal. |
| Controllers/HudController | Power, Cash (and Cash/s), distance bar with biome markers, a "+Power" popup at bat-on-ball. No SWING button: a tap on the game view swings (InputController). |
| Controllers/ParkController | Draws the seated Mascots and upgrade props in every park, with Cash/s tags; culls far parks; idle bob for your own. |
| Modules/ParkProps | The placeholder model for each park upgrade, growing with its level. |
| Modules/MascotRig | The placeholder Mascot model (species color, rarity disc, variant mark, size scale), shared by the catch reveal and the parks. |
| Controllers/MascotController | Client side of the Mascot actions (Sell, Lock, Move, Equip Best, Auto-Sell): asks the server, shows "Sold X +$N". |
| Controllers/HotbarController | The 4 hotbar slots and On Deck, bottom-left (60pt touch targets). Tap a slot for Seat it / Swap in, Lock, Sell. Drawn above the panel and toasts so its menu is never covered. |
| Controllers/MascotPanelController | The Mascots panel (button above the hotbar): Seated / Hotbar tabs with one fixed row per slot (rows never move under your finger), Equip Best, Auto-Sell, and per-Mascot Seat it / Swap in, Lock, Sell. Left side only, so the game view stays tappable; it takes taps on itself. |
| Modules/MascotInfo | How a Mascot is described in the UI, which slot a move targets, and the Sell button (second tap for Rare+, ignores taps on a just-drawn button, resets if refused). |
| Modules/UILayout | Shared screen layout (hotbar height, margins) so toasts, reveal text and the panel stay clear of the hotbar. |
| Controllers/IndexController | The Index (third panel button, red dot for unseen species): world tabs (every world reached; opens on the current one), a ◀ biome ▶ switcher and 8 cards per biome. Caught: color, name, rarity, count, variants and sizes found, NEW badge; uncaught: silhouette with its rarity; open slots: Coming soon. Permanent: cards stay after selling. Opening it marks species seen. |
| Controllers/ShopController | The Shop panel (button beside Mascots; one side panel at a time): Balls with each tier's rarity odds at your best distance (`Formulas.rarityOdds`, the numbers the server rolls with), and Bats. Park: the five upgrades with level, bonus and next cost, and the total park bonus. Shows the new-ball notice and makes the Shop button glow. |
| Controllers/WelcomeBackController | Shows the offline payout for 4s; small and ignores taps. |
| Controllers/PromotionController | The Stadium button under the HUD stats (glows when you can promote) and the promotion panel: requirements with ticks, what the next tier gives, what's kept and what resets, and a Promote button pinned at the bottom (second tap confirms). |
| PitcherVisuals/PitchingMachine | Machine throw flash (used only when the machine is the pitcher). |

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
| Config/Tuning | **Every tunable number** (Fungo cycle and Power tiers, pitch timing, Power, distance, biome starts, lanes, streaming, ball-cam, highlights, swing, catch: Luck, variants, sizes, Cash/s, sell value; planned: reveal, offline). |
| Config/Biomes | Biome visuals, keyed by world (`Biomes[1]` = World 1; `Biomes[2]` = World 1 recoloured to dusk, a placeholder). |
| Config/Mascots | Rarities, and species keyed by world then biome id: 6 per biome at launch (one per rarity), 8 Index slots. World 2's are generated placeholders (`w2_…`). |
| Config/Balls | 6 ball tiers in unlock order: price and base rarity weights. |
| Config/Stadium | The 4 stadium tiers: Power and Cash multipliers (×1, ×2, ×4, ×8) and what promoting into each needs (Cash on hand and a biome reached this run). |
| Config/Park | Ballpark layout (seats, sign, upgrade spots), drawing distances, and the five upgrades (base cost, cost growth, bonus per level; max level 10). |
| Config/Bats | 6 bats in order: price and Power-per-hit multiplier (`List`, `ById`). |

## 5. The hit flow

```
tap ──▶ FungoController.Toss: toss + swing on screen at once; Swing(tossId) ──▶ SwingService
      │  (the client launches the ball at bat-on-ball, Fungo.CONTACT_AT after the tap, from
      │   where the batter stands; this confirms the numbers)
      │  PitchService: a second toss in the same cycle / old id → ignored (one hit per cycle)
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
PitchService.QueueNext: next toss allowed after CONTACT_AT + ball-cam + reveal
      (Formulas.ballCamTime), the same time the client's camera comes back; `Ready` (skip)
      brings it forward, never inside the server's minimum gap
```

With the pitching machine ("throw", not the default) the server throws a `Pitch` first and the
tap hits the pitch in play instead; everything after `SwingService` is the same.

- **The ball-cam sets the pace.** Every hit is watched: the server allows the next toss
  `Fungo.CONTACT_AT + Formulas.ballCamTime(distance, Formulas.revealTime(catch))` after this
  one (toss + air time + slow motion + reveal + return), the same numbers the client camera
  uses, both timed from the tap. The catch reveal is 1s (`Reveal.SHORT`), or 3s
  (`Reveal.FULL`) for a new Rare+ species. Taps while the camera is away only skip the reveal.
  The ball stays on the ground through the whole reveal (`Flight.LINGER_TIME`).
- **The cycle is the same at every tier.** The ball always launches `Fungo.CONTACT_AT` after
  the tap; a bigger hit-stop is taken out of the toss, and a higher toss just moves faster.
- **Skipping.** Tapping during a reveal skips it and sends `Ready(hitId)`. If the server's result
  hasn't arrived by the landing, the client skips the reveal on its own (and sends `Ready`) rather
  than wait. The server brings the next pitch forward, but never sooner than a reveal of
  `Reveal.MIN_SHOWN` would allow, once per hit and only before the next ball, so spamming skip
  can't beat that pace. The client holds a tap that comes before that floor and tosses then,
  so it isn't lost. Auto-Swing will skip the same way (guardrail 6).
- **The cycle is the tap limit.** One toss per cycle on the client, and the server allows one
  hit per cycle (toss ids only go up; `Pitch.TOSS_GRACE` covers network jitter), so spam does
  nothing. A valid toss that still arrives a little early (up to `Pitch.TOSS_MAX_HOLD`) is held
  until its cycle opens rather than refused, since the player already saw it hit; only one is
  held at a time. A respawn or a dropped ball mid-flight also sends `Ready`, so the server's gap
  never outlasts the client's. Swings it refuses are counted in DevData `metrics` (`rejected`).
- **Every tap is a hit** ([CLAUDE.md](../CLAUDE.md) guardrails 1–3): no timing, no misses, no
  mark to stand on. The client starts the toss the instant you tap and launches the ball at
  contact: to the server's distance if its `HitResult` is already here (it was sent at the
  tap), else to a predicted one (`Formulas.distance(power + last gain)`), re-planned mid-air
  when the result comes. The ball starts at the batter and lands on the lane's centre line,
  where the server's landing is. The player never waits for the server.
- **The catch never makes you wait.** The catch is rolled on the server, so the client can't
  predict it, but `HitResult` normally arrives while the ball is still in the air (at least
  ~1s). If it's still missing at landing, the reveal is skipped and a toast shows the catch
  when it arrives.
- **First swing within 10s:** the first tap may toss the moment the save loads; there's no
  pitch to wait for. **Biome 2 within 60s** is re-measured in every step.

## 6. Hooks

All types are in [HookTypes.luau](../src/shared/HookTypes.luau).

**Pitcher slot.** `PitchService.SetPitcher(player, pitcher)` swaps the active `Pitcher`
(mode, cooldown, travel time, optional Power bonus). Two modes: "toss" (Fungo, the default:
the tap starts each cycle) and "throw" (the pitching machine, kept for later, e.g. a pitcher
pet: the server throws each `Pitch`). The save stores `pitcher = "fungo"`
(`Tuning.Pitch.DEFAULT_PITCHER`). A new pitcher is a new file in `Pitchers/` (plus one in
`PitcherVisuals/` with the same id for a "throw" pitcher). No other code changes.

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
| C → S | `Swing` | Event | Fungo: `tossId` (the client's counter, only goes up); machine: `pitchId` |
| C → S | `Ready` | Event | `hitId`: the reveal was skipped; the server may bring the next pitch forward, never sooner than its floor |
| C → S | `GetData` | Function | → full snapshot of the caller's own save |
| C → S | `BuyBat` / `EquipBat` | Function | `batId` → `{ ok, err? }` |
| C → S | `BuyBall` | Function | `ballId` (the next tier) → `{ ok, err? }`; Cash only |
| C → S | `BuyParkUpgrade` | Function | `upgradeId` → `{ ok, err? }`: the next level, Cash only, max 10 |
| C → S | `SellMascot` / `LockMascot` | Function | `uid` (+ `locked`) → `{ ok, err?, cash?, species? }`; selling a locked Mascot is refused |
| C → S | `MoveMascot` | Function | `uid, place, slot` (`"seats"`, `"hotbar"` or `"onDeck"`; swaps if taken, which is also the On Deck swap) → `{ ok, err? }` |
| C → S | `EquipBest` / `SetAutoSell` | Function | (`on`) → `{ ok, err? }` |
| C → S | `MarkIndexSeen` | Function | () → `{ ok }`: every caught species counts as seen (server copies its own Index) |
| C → S | `Promote` | Function | → `{ ok, err? }`: stadium promotion if the next tier's requirements are met |
| S → C | `Pitch` | Event | `Pitch` (see HookTypes); "throw" pitchers only, Fungo sends none |
| S → C | `HitResult` | Event | `{ hitId, powerGained, pitcherBonus, segments, distance, biomeIndex, catch? }`. `catch` = `HookTypes.Catch`: `{ uid, species, rarity, variant, size, cashPerSec, placedIn, slot?, isNewSpecies, sold? }` |
| S → C | `Highlight` | Event | `Highlight` minus `player` |
| C → S | `GetWelcomeBack` | Function | → `{ seconds, cash }` once after an offline payout (60s+ away), else nil |
| S → C | `ShopNotice` | Event | `{ kind = "ball", id }`: your Cash first covers this ball (once per tier per run) |
| S → C | `DataChanged` | Event | changed top-level keys only |

Rules: the client never sends a number that becomes a stat. Every argument is
type-checked, and unknown ids are rejected. There are no server → client
RemoteFunctions. Inventory actions never block or delay swinging.

## 8. Player save (`src/shared/Types.luau`)

Save version 3 (v2 → v3: the pitcher moves to Fungo). There are no live players, so the
v1 → v2 migration empties old test saves and refills them from the Template. ProfileStore only
adds missing keys, so the wipe is explicit.

```lua
{
  version = 2,
  -- run progress: reset on stadium promotion
  power = 0, cash = 0,
  bats = { owned = { starter = true }, equipped = "starter" },
  balls = { owned = { basic = true }, notified = {} }, -- every hit uses the best owned
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
  pitcher = "fungo",                              -- v3: was "pitching_machine"
  settings = { music = true, sfx = true, lowGraphics = false, tipsSeen = {}, indexSeen = {} },
  -- lifetime, never reset
  lifetime = { swings = 0, cashEarned = 0, mascotsCaught = 0, bestDistance = 0 },
  firstJoin = 0, lastJoin = 0, lastOnline = 0,
}
```

- v2 → v3 moves `pitcher` from "pitching_machine" to "fungo"; nothing else changes.
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
| Server-side stats | Only Services write the save. The client sends a toss id (or pitch id) and ids, never values. Catches are rolled with a server `Random`. |
| Low-end mobile | Biomes built on the client, only near the camera; one ball part plus a cheap trail; part-built Mascot rigs, far parks hidden; Cash is paid and sent once a second, and the HUD counts up between payouts from the shared rate formula. |
| Power, distance and tier never for Robux; balls Cash-only | No product touches Power, distance, stadium tier or balls. Robux items are a Luck Boost (luck only) and Auto-Swing (the tap path). |
| Odds before any luck purchase | The odds screen shows every Mascot's % with and without the boost, from the same `Formulas.catchOdds` the server rolls with. |
| Safe at home | No trading or stealing. Sales only through the player's tap, Auto-Sell or the On Deck rule, at full value, never locked Mascots; `MascotInventory` checks this on every change. Promotion keeps every Mascot. |
| Original assets | Landmarks and Mascots are ours; nothing from the Toolbox; no MLB names or logos. |
| 10s / 60s | The first tap tosses as soon as the save loads (no pitch to wait for). The catch reveal replaces the landing hold; Biome 2 time is re-measured in every step. |

## 10. Parked ideas (not in the main loop)

Ideas that add skill or a way to fail stay here until they fit the guardrails in
[CLAUDE.md](../CLAUDE.md). Nothing here may change main progression.

- **Training Area: optional skill mini-game, no effect on main progression.** A separate
  batting cage with timed swings: Perfect / Good / early / late windows around the ball
  reaching the plate, one swing per pitch, and a lag-tolerant server check of the client's tap
  time. This was built and then reverted from the main loop (commit `12825eb`, reverted in
  "Revert timing, add guardrails") because it broke guardrails 1, 2, 3 and 6. If it returns, its
  rewards must be cosmetic or separate from Power, distance and Cash.
