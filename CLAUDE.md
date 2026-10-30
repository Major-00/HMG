# +1 Home Run — design guardrails (read before every change)

This is an incremental progression game, not a skill game.

1. Every tap succeeds. No misses, no timing windows, no failure states in the core loop.
2. Distance comes only from stats: Power × bat × pets × rebirth × boosts. Never from player reflexes, aim or timing.
3. The client shows the hit instantly. The server validates and computes, but never makes the player wait for a verdict.
4. "Feel" polish is visual and audio only: hit-stop, screen shake, sound, particles, floating numbers. Polish never changes the result.
5. Celebrations are given, not earned by skill. A "PERFECT!" moment can trigger randomly or on milestones (records, biome crossings), never from tap accuracy.
6. Anything sold (Auto-Swing, boosts) must work identically to a player tapping.
7. No new mechanic without a written one-paragraph reason tied to the game plan's metrics (bounce, playtime, D1, D28). If it adds a way to fail, it's rejected.
8. Skill-based ideas go to the parked list in ARCHITECTURE.md (e.g. the future Training Area), not into the main loop.
