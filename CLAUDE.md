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
- **Studs world.** One stud is the same size everywhere. Anything that moves or floats in the air is an effect, not a modeled asset.
- **The map comes from Blender.** `MaP/HubBlock.blend` is the source of truth for the island map. Don't hand-build map geometry in Studio.
- **Original assets only.** No MLB names or logos.
- **Pacing.** First launch within 10s. Biome 2 (Windy Highlands) within 60s.

## The map (rules from Nov 6; they replace every earlier map rule)

The map is a backdrop for the core loop, not the product. Anything that breaks these rules is out, whoever asks for it.

1. **Maps are disposable and interchangeable.** They aren't built around the game. Creatures are not tied to places: no habitats, no clustering creatures at spots. The element theme stays loose: a biome can boost its element's creatures (home turf), but the map doesn't have to act out the element.
2. **One minimal formula, after Steal An Egg, kept light so it never slows the core loop.** Biomes 1 to 4 (Meadow, Windy Highlands, Tundra, Jungle Ruins) share one identical shape (`MaP/tools/formula.py`): a checkered floor, two checkered walls with a grass cap, a threshold strip, a few props by the walls. They differ only by floor, walls and atmosphere. Atmosphere stays light in biomes 1 to 3 and becomes clearly noticeable from biome 4; biomes 5 and 6 (Coral Reef, Geyser Flats) are the interchangeable showpieces and may be more crafted.
3. **If a player can't understand it the moment it's announced, it isn't considered.**

- **The hub** follows the formula too, as a modest walled rectangle in the lane's style that runs straight into the lane. Its decoration and layout stay; what matters is that it reads as one continuous place with the lane.
- **Fixed, not affected by the rules:** the colours (`MaP/tools/palette_nov6.json`, with the lighting in `default.project.json`), the stud look and the sky.
- **Biome borders stay readable.** Crossing into a new biome is a reward in the core loop, so the floor and wall colours change at each border.

How it's built:

- **Blender is the source of truth** (`MaP/HubBlock.blend`). Archived geometry (the old biome builds, the crater rim, the island underside, creature spots) is in `ARCHIVE_pre_formula` and is never exported.
- **Scale 1.25.** The exporter builds the map at 1.25x the Blender layout (Roblox Z = 1.25 x (Blender Y - 45)). `BiomeStarts` in `Config/Tuning` are Roblox studs and move with the map, never on their own. The lane ends at the Geyser Flats' closing cliff, about 2,294 studs out.
- **Studs come from the export.** `LobStudsRaised` (replaces Plastic) on floors and walls, `LobStudsSunk` (set per part) on designed objects; water, Neon, small pieces and meshes stay smooth. Where two faces overlap in one plane the bigger part is pulled in 0.06 studs (`FaceInset`). The steps are in `MaP/EXPORT_SPEC.md`.
- **Streaming is on** (StreamOutBehavior LowMemory). `StreamController` asks for the landing area on every launch; anything that must always exist (the hub, lanes) is Persistent. Stud textures preload in `src/first` (ReplicatedFirst).
