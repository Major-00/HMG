--!strict
-- Tuning: every tunable number in the game lives here. Code reads these; it never hard-codes them.
-- Distances are in studs along the flight track, measured from home plate.

local Tuning = {
	Data = {
		AUTOSAVE_SECONDS = 120, -- how often each save is written while playing (ProfileStore default is 300)
		LOAD_TIMEOUT = 30, -- seconds GetData waits for a save to load before giving up
		-- Seconds before a player whose save won't load is kicked. Keep above ~45s: ProfileStore
		-- waits that long to take a save over from a server that crashed.
		LOAD_KICK_SECONDS = 60,
	},

	Pitch = {
		MACHINE_TRAVEL_TIME = 0.7, -- seconds from release to the plate
		MACHINE_COOLDOWN = 0.5, -- seconds after a hit (or a miss) before the next release
		FIRST_PITCH_DELAY = 0.5, -- seconds after the character spawns before the first pitch
		LATE_WINDOW = 1.0, -- seconds after the ball reaches the plate that a tap still hits
	},

	Power = {
		PER_HIT = 1, -- the "+1": Power gained per hit, before multipliers
		REBIRTH_BONUS = 1, -- each rebirth adds +100% to the multiplier (used from the rebirth step)
	},

	-- distance = BASE + PER_POWER * power ^ EXPONENT, using total Power after the hit
	Distance = {
		BASE = 20,
		PER_POWER = 4,
		EXPONENT = 1,
	},

	-- Wins per hit = max(MIN_PER_HIT, floor(distance / STUDS_PER_WIN))
	Wins = {
		STUDS_PER_WIN = 10,
		MIN_PER_HIT = 1,
	},

	-- Where each World 1 biome starts, in Config/Biomes order (Sandlot ... Canyon).
	-- Biome 2 at 120 studs = 25 hits from a fresh save (20 + 4 * 25), about 30s of play.
	BiomeStarts = { 0, 120, 500, 1800, 5000, 12000 },

	World = {
		LANE_COUNT = 8, -- batting lanes per server (one per player; set the place's max players to match)
		LANE_SPACING = 30, -- studs between lanes, side to side
		PITCH_DISTANCE = 20, -- studs from the plate to the pitching machine
		STRIKE_HEIGHT = 3, -- studs above the plate where the ball is hit
	},

	-- Client-only visuals (no effect on stats)
	Flight = {
		MIN_TIME = 0.8, -- seconds in the air for the shortest hit
		MAX_TIME = 3.5, -- seconds in the air for the longest hit
		SECONDS_PER_STUD = 0.004, -- added air time per stud of distance
		ARC_HEIGHT_RATIO = 0.25, -- arc peak = distance * ratio ...
		MAX_ARC_HEIGHT = 250, -- ... up to this many studs
		LINGER_TIME = 0.8, -- seconds the ball stays on the ground after landing
		TRAIL_LIFETIME = 0.2, -- seconds a trail segment lasts (short = cheap)
		MAX_BALLS = 6, -- most balls drawn at once per player
		CONTACT_TIMEOUT = 1.5, -- seconds to wait for the server's hit result before dropping the ball
	},

	Swing = {
		ANIMATION_TIME = 0.15, -- seconds for the bat swing
	},
}

return Tuning
