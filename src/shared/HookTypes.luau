--!strict
-- HookTypes: contracts for the swappable gameplay hooks.
-- Types only. New pitchers, landing handlers and the catch plug in here.
-- Distances are in studs along the flight track, measured from the hit line (home plate).

-- One pitch, decided by the server and sent to the client to draw (pitchers with mode "throw").
-- A "toss" pitcher sends none: the player's tap starts each cycle.
export type Pitch = {
	pitchId: number, -- increases per player; the Swing remote echoes it back
	pitcherId: string, -- which pitcher threw it ("pitching_machine" for now)
	releaseAt: number, -- workspace:GetServerTimeNow() when the ball leaves the pitcher
	arriveAt: number, -- when it reaches the plate
	expiresAt: number, -- last moment a tap still hits (arriveAt + Pitch.LATE_WINDOW)
}

-- PITCHER SLOT. Each player has exactly one active pitcher. Two kinds:
--   "toss"  (Fungo, the default): the player's tap tosses and swings in one motion; the server
--           allows one hit per cycle and sends no Pitch.
--   "throw" (the pitching machine; a pitcher pet may use it later): the server throws each
--           Pitch, and a tap hits the one in play.
export type Pitcher = {
	id: string,
	mode: "toss" | "throw",
	-- Extra seconds after the ball-cam is back before the next ball (0 for Fungo).
	cooldown: (player: Player) -> number,
	-- "throw": seconds the ball takes from release to plate.
	-- "toss":  seconds from the tap to bat-on-ball (Tuning.Fungo.CONTACT_AT).
	travelTime: (player: Player) -> number,
	-- Optional: extra multiplier on Power gained from hitting this pitcher's pitch (default 1).
	powerBonus: ((player: Player) -> number)?,
}

-- One leg of the ball's journey. The hit is the first leg; on-land handlers may add more.
export type FlightSegment = {
	from: number,
	to: number,
	source: string, -- "hit", later e.g. "bounce"
}

-- Passed through the on-land handlers after the ball first lands.
export type LandingContext = {
	player: Player,
	hitId: number,
	segments: { FlightSegment }, -- read-only to handlers; LandingService appends
	landedAt: number, -- current landing distance (end of the last segment)
	biomeIndex: number, -- biome under landedAt
	biomeName: string, -- display name of that biome
	position: Vector3, -- where the ball lands, on the lane's centre line (the client uses the batter's X)
	catch: Catch?, -- what was caught, on the final context only (nil when nothing was)
}

-- ON-LAND HOOK. Runs on the server, in registration order, before the catch phase (which uses
-- the final distance). Return a FlightSegment to push the ball further (e.g. a bounce), or nil.
-- Handlers must not yield. LandingService.Landed fires after all handlers with the final context.
export type LandingHandler = (ctx: LandingContext) -> FlightSegment?

-- What a landing caught. Nothing catches yet; the catch hook stays for the animals.
export type Catch = { [string]: any }

-- CATCH PHASE of the on-land hook. Runs once, after every LandingHandler, on the final landing.
-- Nothing registers one yet. Must not yield.
export type Catcher = (ctx: LandingContext) -> Catch?

export type BiomeConfig = {
	id: string,
	displayName: string,
	-- Where each biome starts is in Config/Tuning (BiomeStarts).
}

return {}
