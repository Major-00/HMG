--!strict
-- Tuning: every tunable number in the game lives here. Code reads these; it never hard-codes them.
-- Distances are in studs along the flight track, measured from the hit line.

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
		PER_HIT = 1, -- the "+1": Power gained per hit, before multipliers
	},

	-- distance = BASE + PER_POWER * power ^ EXPONENT, using total Power after the hit.
	-- Scaled with the map (1.25x, MaP/EXPORT_SPEC.md) so the pacing doesn't change: PER_POWER 12.5
	-- reaches Windy Highlands (206 studs) on hit 15, about 50s in (about 40s with every landing
	-- hold skipped). CLAUDE.md: Biome 2 within 60s.
	Distance = {
		BASE = 25,
		PER_POWER = 12.5,
		EXPONENT = 1,
	},

	-- Where each biome starts, in studs from the hit line, in Config/Biomes order: each one is that
	-- biome's floor edge on the island map (Meadow, Windy Highlands, Tundra, Jungle Ruins,
	-- Coral Reef, Geyser Flats). The map is built at 1.25x the Blender layout (MaP/EXPORT_SPEC.md);
	-- the lane ends at the Geyser Flats' closing cliff behind the Crown Geyser, about 2,294 studs out.
	BiomeStarts = { 0, 206, 456, 769, 1144, 1613 },

	World = {
		-- The island map's launch strip: its front edge is the hit line (Z = 0) and the lane runs
		-- down +Z. Everyone spawns on the hub overlook (the map's Spawn marker).
		LANE_COUNT = 5, -- batting lanes per server (one per player; set the place's max players to match)
		LANE_SPACING = 7.5, -- studs between lanes, side to side (fits the 45-stud launch strip)
		PITCH_DISTANCE = 20, -- studs from the plate to the pitching machine (when it's used)
		STRIKE_HEIGHT = 3, -- studs above the ground where the ball is hit
		-- The shared hitting zone (shared/HitZone): the launch strip across every lane, from `back`
		-- (the back of the launch strip) up to the hit line at `front`. Walk anywhere and tap:
		-- a tap from outside it still hits, from the nearest point of the zone. Its width comes
		-- from LANE_COUNT and LANE_SPACING. Distances are measured from the hit line (Z = front).
		HIT_ZONE = { back = -12.5, front = 0 }, -- the island's launch strip (12.5 studs deep)
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

	-- The landing hold: the camera stays on the landing before swooping back. The server times the
	-- next pitch with the same numbers (Formulas.revealTime / ballCamTime). Visual only: it never
	-- changes the result.
	Reveal = {
		SHORT = 1, -- seconds for every landing (nothing is caught yet)
		FULL = 3, -- seconds for a landing that shows a catch, once catches exist
		-- Tapping skips the hold and tells the server (Ready) so the next pitch comes sooner.
		-- The server never throws it earlier than this long after the ball lands (plus the
		-- camera's return), so skipping can't make the game faster than this.
		MIN_SHOWN = 0.3,
	},
}

return Tuning
