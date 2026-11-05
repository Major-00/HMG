# Lob an Orb!

*The Sky Is The Limit*

A Roblox incremental game on a floating sky island. One tap launches an orb, and every tap hits.
Distance comes only from stats (Power, launchers, boosts), never from timing or aim. The orb flies
from the Sanctuary Crater down one straight lane through six biomes: Meadow, Windy Highlands,
Tundra, Jungle Ruins, Coral Reef and Geyser Flats. A lucky throw catches a winged creature where
the orb lands, and tamed creatures ride with you, boost your launches and paint your orbs with their
trail. Today
only the core loop is built: tap, launch, flight, ball-cam and saved Power.

## Setup

1. Install [Rokit](https://github.com/rojo-rbx/rokit), then install the pinned tools (Rojo, Selene,
   StyLua) from the repo root:

   ```bash
   rokit install
   ```

2. Install the Rojo plugin in Roblox Studio (or get it from the Creator Store):

   ```bash
   rojo plugin install
   ```

3. Start the sync server:

   ```bash
   rojo serve
   ```

4. Open the place in Studio, open the Rojo plugin and click **Connect**. Rojo syncs `src/`,
   `assets/` and the `Workspace` and `Lighting` settings from `default.project.json`.

Before committing, check style and lint:

```bash
stylua --check src
```

```bash
selene src
```

## Repo layout

| Path | What |
|---|---|
| `src/` | The game code: `server/` (ServerScriptService), `client/` (StarterPlayerScripts), `shared/` (ReplicatedStorage). |
| `assets/` | `Animations/`: the batter's KeyframeSequences, generated. Synced to ReplicatedStorage for Studio previews. |
| `tools/` | `animations/generate.py` bakes the swing animations and writes `SwingData.luau`. |
| `docs/` | `ARCHITECTURE.md`: how the code fits together, what's planned. |
| `MaP/` | The island map in Blender (`HubBlock.blend`), the source of truth for the map. Not synced by Rojo. |

## Read first

- [CLAUDE.md](CLAUDE.md): design guardrails and hard rules. Read before every change.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): the loop, every module, remotes, the save, hooks and tuning.
