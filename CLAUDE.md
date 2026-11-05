# Lob an Orb!: design guardrails (read before every change)

This is an incremental progression game, not a skill game. Tagline: *The Sky Is The Limit*.

1. Every tap succeeds. No misses, no timing windows, no failure states in the core loop.
2. Distance comes only from stats: Power × launchers × boosts. Never from player reflexes, aim or timing.
3. The client shows the launch instantly. The server validates and computes, but never makes the player wait for a verdict.
4. "Feel" polish is visual and audio only: hit-stop, screen shake, sound, particles, floating numbers. Polish never changes the result.
5. Celebrations and catches are given, not earned by skill. A catch is a luck roll where the orb lands. A "PERFECT!" moment can trigger randomly or on milestones (records, biome crossings), never from tap accuracy.
6. Anything sold (Auto-Swing, boosts, passes) must work identically to a player tapping.
7. No new mechanic without a written one-paragraph reason tied to the game plan's metrics (bounce, playtime, D1, D28). If it adds a way to fail, it's rejected.
8. Skill-based ideas go to the parked list in `docs/ARCHITECTURE.md` (e.g. the future Training Area), not into the main loop.

## Hard rules

- **Server owns stats.** All stats are server-side. The client only renders.
- **Mobile-first.** It must run on low-end phones.
- **Money.** Never sell leaderboard progress (Power, distance, catches) for Robux. Sell boosts and passes.
- **Odds first.** Any Robux luck boost shows every creature's odds before purchase.
- **Safe at home.** No other player can take anything you own. A creature only leaves you by your own action.
- **Orbs.** One glowing sphere of a single color. No halves, band or button (keeps it clear of the Pokeball). Orb skins are cosmetic only.
- **No eggs, anywhere.**
- **Winged creatures.** Birds first, plus dragons, griffins and the winged horse. Two size classes. Pocket creatures ride on your shoulder or head and never walk. Pals walk beside you, one lead Pal per player. Mythics stay chibi.
- **Studs world.** One stud is the same size everywhere. Nothing human-made in the world except historic places (the Jungle Ruins). Anything that moves or floats in the air is an effect, not a modeled asset.
- **The map comes from Blender.** `MaP/HubBlock.blend` is the source of truth for the island map. Don't hand-build map geometry in Studio.
- **Original assets only.** No MLB names or logos.
- **Pacing.** First launch within 10s. Biome 2 (Windy Highlands) within 60s.

## The map

- **One lane, six biomes:** Meadow, Windy Highlands, Tundra, Jungle Ruins, Coral Reef, Geyser Flats. The lane ends at the Geyser Flats' closing cliff, about 2,294 studs out. The Volcano and the Pyramids ending are parked in `HubBlock.blend`'s `UPDATES_not_exported` collection: don't export them or bring them back into code.
- **Scale 1.25.** The exporter builds the map at 1.25x the Blender layout (Roblox Z = 1.25 x (Blender Y - 45)). `BiomeStarts` in `Config/Tuning` are Roblox studs and move with the map, never on their own.
- **The detail ladder.** Early biomes stay minimal, later ones get richer, and pieces no camera sees are cut. Don't add detail to an early biome to match a later one. `MaP/tools/ladder.py` (`count`) gives piece counts per biome.
- **Studs come from the export.** `LobStudsRaised` (replaces Plastic) on floors and walls, `LobStudsSunk` (set per part) on designed objects; water, Neon, small pieces and meshes stay smooth. Where two faces overlap in one plane the bigger part is pulled in 0.06 studs (`FaceInset`). The rules are in `MaP/EXPORT_SPEC.md`.
- **Streaming is on** (StreamOutBehavior LowMemory). `StreamController` asks for the landing area on every launch; anything that must always exist (the hub, lanes) is Persistent. Stud textures preload in `src/first` (ReplicatedFirst).
