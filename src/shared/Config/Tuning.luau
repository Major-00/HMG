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
	},

	-- Swing timing, in seconds relative to the ball reaching the plate (negative = early).
	-- One swing per pitch: a tap outside the Good window is a whiff and uses up the pitch.
	Timing = {
		GOOD_EARLY = 0.2, -- earliest hit: ball about 5.7 studs before the plate
		GOOD_LATE = 0.15, -- latest hit: ball about 4.3 studs past the plate
		PERFECT = 0.05, -- within this of the plate (either side) is a Perfect
		PERFECT_DISTANCE_BONUS = 1.25, -- a Perfect hit flies (and pays) 25% further
		LAG_SLACK = 0.1, -- extra seconds a tap's reported time may be older than the player's ping
		MISS_FLY_TIME = 0.6, -- a missed ball keeps flying past the plate this long before it vanishes
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
	-- Biome 2 at 80 studs = 15 hits from a fresh save (20 + 4 * 15). With the ball-cam each hit
	-- takes about 2.5-2.8s, so that's roughly 40-45s of play.
	BiomeStarts = { 0, 80, 500, 1800, 5000, 12000 },

	World = {
		LANE_COUNT = 8, -- batting lanes per server (one per player; set the place's max players to match)
		LANE_SPACING = 30, -- studs between lanes, side to side
		PITCH_DISTANCE = 20, -- studs from the plate to the pitching machine
		STRIKE_HEIGHT = 3, -- studs above the plate where the ball is hit

		-- Biome ground, built on the client and streamed around the camera
		TILE_LENGTH = 100, -- longest ground tile; each biome is cut into tiles from its own start
		STREAM_AHEAD = 600, -- studs of ground kept built in front of the camera
		STREAM_BEHIND = 150, -- ... and behind it
		BEHIND_PLATE = 120, -- Sandlot ground also runs this far behind home plate
		FIELD_MARGIN = 40, -- extra ground width past the outer lanes, each side
		PROP_BAND = 60, -- width of the prop strip outside the field, each side
		PROPS_PER_TILE = 3, -- most props per tile (each side gets some)
		LANDMARK_OFFSET_Z = 60, -- landmark sits this far past its biome's start ...
		LANDMARK_SIDE = 25, -- ... and this far outside the field's right edge
		LIGHTING_TWEEN = 0.6, -- seconds to blend lighting into a new biome
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

	-- Ball-cam. The server also uses these (Formulas.ballCamTime) to hold the next pitch until
	-- the camera is back, so every hit can be watched.
	Camera = {
		BACK = 14, -- studs behind the ball
		UP = 5, -- studs above the ball
		LOOK_AHEAD = 10, -- camera looks this far past the ball
		MIN_CLEARANCE = 6, -- camera never goes lower than this above the ground
		FOLLOW_SHARPNESS = 12, -- higher = camera sticks closer to the ball
		SLOWMO_PORTION = 0.25, -- the last quarter of the final descent ...
		SLOWMO_SPEED = 0.4, -- ... plays at 40% speed
		LAND_HOLD = 0.5, -- seconds the camera stays on the landing spot
		RETURN_TIME = 0.35, -- seconds to swoop back to the batter
		CUT_BEYOND = 250, -- landings farther than this cut back (fade) instead of swooping
		CUT_TIME = 0.3, -- seconds for the fade-out + fade-in of a cut
		PITCH_ARRIVE_AFTER_RETURN = 0.15, -- next ball reaches the plate this long after the camera is back
		MAX_PING_ALLOWANCE = 0.5, -- most player latency (seconds) added to that wait
	},

	Highlight = {
		BANNER_TIME = 1.4, -- seconds the biome banner stays fully visible ...
		BANNER_QUEUED_TIME = 0.5, -- ... or this long when another banner is waiting
	},

	Swing = {
		TO_CONTACT = 0.07, -- seconds from the ready pose to the strike point
		FOLLOW_THROUGH = 0.09, -- seconds sweeping across after contact
		RECOVER = 0.22, -- seconds back to the ready pose
	},
}

return Tuning
