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
		-- The pitcher every player starts with (a module of this id in server/Pitchers). Fungo is
		-- a one-tap self-toss; the pitching machine is kept as a second slot implementation.
		DEFAULT_PITCHER = "fungo",
		-- Fungo: a toss may reach the server this much before its cycle is over (the client times
		-- the cycle from its own tap, so network jitter can make it a little early). Spam
		-- protection still allows one hit per cycle.
		TOSS_GRACE = 0.3,
		-- A valid toss that still comes too early (a slow swing before it, then a fast one) is
		-- held on the server until its cycle opens, if that's at most this many seconds away,
		-- rather than refused. One held toss at a time, so it's still one hit per cycle.
		TOSS_MAX_HOLD = 1.5,

		-- Pitching machine (not used by default)
		MACHINE_TRAVEL_TIME = 0.7, -- seconds from release to the plate
		MACHINE_COOLDOWN = 0.5, -- seconds after a hit (or a miss) before the next release
		FIRST_PITCH_DELAY = 0.5, -- seconds after the character spawns before the first pitch
		LATE_WINDOW = 1.0, -- a tap still hits until this long after the ball reaches the plate
		SERVER_GRACE = 1.0, -- the server keeps the pitch open this much longer for slow connections
	},

	Power = {
		PER_HIT = 1, -- the "+1": Power gained per hit, before multipliers (stadium tier: Config/Stadium)
	},

	-- distance = BASE + PER_POWER * power ^ EXPONENT, using total Power after the hit
	Distance = {
		BASE = 20,
		PER_POWER = 4,
		EXPONENT = 1,
	},

	-- Where each World 1 biome starts, in Config/Biomes order (Sandlot ... Canyon).
	-- Biome 2 at 80 studs = 15 hits from a fresh save (20 + 4 * 15). With the ball-cam and a 1s
	-- catch reveal each hit takes about 3.0-3.3s (2.3-2.6s with the reveal skipped), so that's
	-- roughly 37-46s of play.
	BiomeStarts = { 0, 80, 500, 1800, 5000, 12000 },

	World = {
		LANE_COUNT = 5, -- ballparks per server (one per player; set the place's max players to match)
		LANE_SPACING = 30, -- studs between lanes, side to side
		PITCH_DISTANCE = 20, -- studs from the plate to the pitching machine (when it's used)
		STRIKE_HEIGHT = 3, -- studs above the ground where the ball is hit
		-- The shared hitting zone (shared/HitZone): one dirt strip across every lane, from `back`
		-- (just in front of the ballparks) up to the hit line at `front`. Walk anywhere and tap:
		-- a tap from outside it still hits, from the nearest point of the zone. Its width comes
		-- from LANE_COUNT and LANE_SPACING. Distances are measured from the hit line (Z = front).
		HIT_ZONE = { back = -18, front = 0 },

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
		-- Seconds the ball stays on the ground after landing. Longer than the longest catch reveal
		-- (Reveal.FULL), so the ball is there for the whole reveal and the camera can still read
		-- the flight's final distance when it heads back.
		LINGER_TIME = 3.5,
		TRAIL_LIFETIME = 0.2, -- seconds a trail segment lasts (short = cheap)
		MAX_BALLS = 6, -- most balls drawn at once per player
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
		-- (The camera stays on the landing for the catch reveal: Tuning.Reveal.)
		RETURN_TIME = 0.35, -- seconds to swoop back to the batter
		CUT_BEYOND = 250, -- landings farther than this cut back (fade) instead of swooping
		CUT_TIME = 0.3, -- seconds for the fade-out + fade-in of a cut
		PITCH_ARRIVE_AFTER_RETURN = 0.15, -- machine: next ball reaches the plate this long after the camera is back
	},

	Highlight = {
		BANNER_TIME = 1.4, -- seconds the biome banner stays fully visible ...
		BANNER_QUEUED_TIME = 0.5, -- ... or this long when another banner is waiting
		-- "PERFECT!" plays when the ball enters a new biome, or when a hit pushes your best distance
		-- past one of these milestones (studs). Past the last one it keeps going x2, x2.5, x2 ...
		RECORD_MILESTONES = { 100, 250, 500, 1000, 2500, 5000, 10000, 25000, 50000, 100000 },
	},

	Swing = {
		TO_CONTACT = 0.07, -- seconds from the ready pose to the strike point
		FOLLOW_THROUGH = 0.09, -- seconds sweeping across after contact
		RECOVER = 0.22, -- seconds back to the ready pose
	},

	-- Fungo hitting: one tap = toss and swing in one motion. Every tap hits; distance comes from
	-- stats only. The server times the next toss from the same numbers (Formulas.ballCamTime).
	Fungo = {
		-- Seconds from the tap to the ball leaving the bat (after any hit-stop): the toss goes up,
		-- the batter sets into the stance while it's in the air, loads and swings as it comes
		-- down. The server times each cycle from this too (Pitchers/Fungo).
		CONTACT_AT = 0.45,
		-- At contact the camera stays on the batter this long (the swoosh and the follow-through
		-- are seen), then glides onto the ball over CAMERA_GLIDE seconds. Both run inside the
		-- ball's flight, so they never change the pacing.
		CAMERA_BEAT = 0.25,
		CAMERA_GLIDE = 0.3,

		-- The batter's animations (client/Modules/SwingAnimator). Paste each published id here as
		-- "rbxassetid://<number>". Empty: in Studio the KeyframeSequence of the same name in
		-- assets/Animations plays instead (tools/animations/generate.py makes them); in a live
		-- server the simple swing plays. swings[i] is Power tier i (TIERS below); upperSwings[i]
		-- is its upper-body version, played while walking (empty: the full-body swing plays).
		ANIMATIONS = {
			stance = "rbxassetid://114145299293411", -- FungoStance
			carry = "rbxassetid://78138491705919", -- FungoCarry
			swings = {
				"rbxassetid://93493049366580", -- FungoSwingPop
				"rbxassetid://139857028731839", -- FungoSwingSolid
				"rbxassetid://97313450383429", -- FungoSwingCrush
				"rbxassetid://71218713514451", -- FungoSwingBlast
				"rbxassetid://126617258477960", -- FungoSwingLaunch
			},
			upperSwings = { "", "", "", "", "" }, -- FungoSwingUpperPop ... FungoSwingUpperLaunch
		},
		CYCLE = 0.8, -- seconds from the tap to the end of the swing; the same at every tier
		STRIKE_FORWARD = 2.5, -- studs in front of the batter where the ball is hit
		STRIKE_SIDE = 0.8, -- ... and this far to the batter's right

		-- The swing grows with Power, visual and audio only (CLAUDE.md guardrail 4): it never
		-- changes the result or the cycle time. A tier applies from its minPower up.
		--   tossHeight  studs the ball goes above the strike point (a higher toss just moves
		--               faster: the time is fixed)
		--   hitStop     seconds the bat and ball freeze at contact (taken from the toss, so the
		--               ball still launches at CONTACT_AT)
		--   punch       degrees the camera's field of view kicks in at contact
		--   crackVolume / crackPitch  the bat-crack sound
		--   sparks      impact particles; dust: ground dust ("lift-off"); 0 = none
		--   shockwave   ground ring { size = studs across at its widest, time = seconds }, or nil
		--   trailWidth  how much wider the ball's trail is than the base
		--   swoosh      the bat's white swing arc { lifetime = seconds it lingers, width = studs }
		TIERS = {
			{
				minPower = 0,
				name = "pop",
				tossHeight = 5,
				hitStop = 0,
				punch = 0,
				crackVolume = 0.35,
				crackPitch = 1.25,
				sparks = 0,
				dust = 0,
				shockwave = nil,
				trailWidth = 1,
				swoosh = { lifetime = 0.1, width = 1.2 },
			},
			{
				minPower = 25,
				name = "solid",
				tossHeight = 5.5,
				hitStop = 0.02,
				punch = 2,
				crackVolume = 0.5,
				crackPitch = 1.1,
				sparks = 6,
				dust = 0,
				shockwave = nil,
				trailWidth = 1.2,
				swoosh = { lifetime = 0.12, width = 1.6 },
			},
			{
				minPower = 200,
				name = "crush",
				tossHeight = 6,
				hitStop = 0.035,
				punch = 4,
				crackVolume = 0.7,
				crackPitch = 1,
				sparks = 12,
				dust = 6,
				shockwave = nil,
				trailWidth = 1.5,
				swoosh = { lifetime = 0.14, width = 2 },
			},
			{
				minPower = 2000,
				name = "blast",
				tossHeight = 6.5,
				hitStop = 0.05,
				punch = 6,
				crackVolume = 0.85,
				crackPitch = 0.9,
				sparks = 18,
				dust = 10,
				shockwave = { size = 14, time = 0.35 },
				trailWidth = 2,
				swoosh = { lifetime = 0.17, width = 2.5 },
			},
			{
				minPower = 20000,
				name = "launch",
				tossHeight = 7,
				hitStop = 0.06,
				punch = 9,
				crackVolume = 1,
				crackPitch = 0.8,
				sparks = 24,
				dust = 16,
				shockwave = { size = 24, time = 0.45 },
				trailWidth = 2.6,
				swoosh = { lifetime = 0.2, width = 3 },
			},
		},
	},

	-- The Mascot caught on every landing. One shared function (Formulas.catchOdds) turns these
	-- into each species' chance, for both the server roll and every odds screen.
	Catch = {
		-- Luck climbs with landing distance:
		--   luck = min(MAX_LUCK, 1 + PER_DOUBLING * log2(1 + distance / BASE_STUDS)) x boost
		-- About 1.25 at 100 studs, 1.65 at 500, 2.7 at 12K.
		LUCK = {
			BASE_STUDS = 100,
			PER_DOUBLING = 0.25,
			MAX_LUCK = 4,
		},
		-- Each rarity's ball weight is multiplied by luck ^ ((rank - 1) * LUCK_POWER), where rank is
		-- its position in Config/Mascots Rarities (Common = 1). Common never changes; Mythic gains most.
		LUCK_POWER = 0.5,

		-- Rolled separately from the species and from each other; both multiply earnings and
		-- sell value. "none" / "normal" get whatever chance is left.
		VARIANTS = {
			{ id = "allStar", displayName = "All-Star", chance = 0.05, multiplier = 1.5 },
			{ id = "goldGlove", displayName = "Gold Glove", chance = 0.01, multiplier = 3 },
			{ id = "hallOfFame", displayName = "Hall of Fame", chance = 0.002, multiplier = 10 },
		},
		SIZES = {
			{ id = "big", displayName = "Big", chance = 0.08, multiplier = 1.5 },
			{ id = "giant", displayName = "Giant", chance = 0.01, multiplier = 3 },
		},

		-- Cash per second for a plain (no variant, normal size) Mascot:
		--   RARITY_CASH[rarity] x BIOME_CASH[biomeIndex] x WORLD_CASH[world]
		RARITY_CASH = { common = 1, uncommon = 3, rare = 10, epic = 35, legendary = 150, mythic = 1000 },
		BIOME_CASH = { 1, 3, 10, 40, 150, 600 },
		-- x WORLD_CASH[world]: a World 2 Sandlot Common earns about what a World 1 Canyon Common
		-- does, so World 2 catches are worth seating from the first swing.
		WORLD_CASH = { 1, 1000 },

		-- Sell value = this many seconds of the Mascot's earnings (variant and size included).
		SELL_SECONDS = 30,
	},

	-- The catch reveal: the camera stays on the landing while the Mascot catches the ball. It
	-- replaces the old landing hold, and the server times the next pitch with the same numbers
	-- (Formulas.revealTime / ballCamTime). Visual only: it never changes the result.
	Reveal = {
		SHORT = 1, -- seconds for most catches
		FULL = 3, -- seconds for a new species of FULL_FROM_RARITY or rarer
		FULL_FROM_RARITY = "rare",
		-- Tapping skips the reveal and tells the server (Ready) so the next pitch comes sooner.
		-- The server never throws it earlier than this long after the ball lands (plus the
		-- camera's return), so skipping can't make the game faster than this.
		MIN_SHOWN = 0.3,

		-- What the reveal shows (CatchRevealController): the Mascot runs in, hops to catch the
		-- ball, turns to the camera, and its name types in. Times scale with the reveal length.
		RUN_FROM_FULL = 16, -- studs the Mascot runs in a full reveal ...
		RUN_FROM_SHORT = 5, -- ... and in a short one
		RUN_PORTION = 0.45, -- share of the reveal spent running to the ball
		HOP_TIME = 0.25, -- seconds of the catching hop
		HOP_HEIGHT = 2.5, -- studs (times the Mascot's size)
		TURN_TIME = 0.2, -- seconds to turn and face the camera after the catching hop
		TYPE_FULL = 0.9, -- seconds for the name to type in, full reveal ...
		TYPE_SHORT = 0.35, -- ... short reveal
		CAM_BACK = 8, -- studs behind the running Mascot (times its size)
		CAM_FRONT = 9, -- studs in front of it for the name shot (times its size)
		CAM_UP = 4.5, -- studs above (times its size)
		CAM_SIDE = 4, -- studs to the side while it runs, so it doesn't block the ball (times its size)
		SIZE_SCALE = { normal = 1, big = 1.35, giant = 1.8 }, -- how big each size looks
		LINGER_AFTER = 0.4, -- seconds the Mascot stays after the reveal, while the camera swoops back
	},

	-- Seated Mascots earn Cash every second (Formulas.cashRate), online and offline.
	Income = {
		PAY_EVERY = 1, -- seconds between payouts while playing
	},
	Offline = {
		CAP_SECONDS = 3 * 60 * 60, -- offline earnings stop after 3 hours away
		MIN_WELCOME_SECONDS = 60, -- the Welcome Back screen only shows after at least this long away
		WELCOME_TIME = 4, -- seconds the Welcome Back card stays up (it never takes taps)
	},
}

return Tuning
