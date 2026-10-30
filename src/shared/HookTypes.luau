--!strict
-- HookTypes: contracts for the swappable gameplay hooks.
-- Types only. Pitcher pets, catcher pets, camera pets and biome challenges plug in here later.
-- Distances are in studs along the flight track, measured from home plate.

-- One pitch, decided by the server and sent to the client to draw.
export type Pitch = {
	pitchId: number, -- increases per player; the Swing remote echoes it back
	pitcherId: string, -- which pitcher threw it ("pitching_machine" for now)
	releaseAt: number, -- workspace:GetServerTimeNow() when the ball leaves the pitcher
	arriveAt: number, -- when it reaches the plate
}

-- PITCHER SLOT. Each player has exactly one active pitcher.
-- The pitching machine is the first implementation; a pitcher pet is another.
export type Pitcher = {
	id: string,
	-- Seconds from the end of one hit to the next pitch's release. Faster pitchers = more taps per second.
	cooldown: (player: Player) -> number,
	-- Seconds the ball takes from release to plate.
	travelTime: (player: Player) -> number,
	-- Optional: extra multiplier on Power gained from hitting this pitcher's pitch (default 1).
	powerBonus: ((player: Player) -> number)?,
}

-- One leg of the ball's journey. The hit is the first leg; on-land handlers may add more.
export type FlightSegment = {
	from: number,
	to: number,
	source: string, -- "hit", later e.g. "catcher_pet"
}

-- Passed through the on-land handlers after the ball first lands.
export type LandingContext = {
	player: Player,
	hitId: number,
	segments: { FlightSegment }, -- read-only to handlers; LandingService appends
	landedAt: number, -- current landing distance (end of the last segment)
	biomeIndex: number, -- biome under landedAt
}

-- ON-LAND HOOK. Runs on the server, in registration order, before Wins are paid.
-- Return a FlightSegment to push the ball further (e.g. a catcher pet), or nil to do nothing.
export type LandingHandler = (ctx: LandingContext) -> FlightSegment?

-- HIGHLIGHT EVENT. Fired after a hit is final.
export type HighlightKind = "record" | "biome"
export type Highlight = {
	player: Player,
	hitId: number,
	kind: HighlightKind,
	distance: number,
	biomeIndex: number, -- for "biome": the newly reached biome
	previousBest: number?, -- for "record"
}

-- PER-BIOME CHALLENGE SLOT (config only; nil for every biome in the MVP).
export type BiomeChallenge = {
	id: string,
	kind: string, -- e.g. "land_in_zone", "hit_streak"; defined when challenges are built
	params: { [string]: any },
}

export type BiomeConfig = {
	id: string,
	displayName: string,
	landmark: string, -- name of a model under ReplicatedStorage.Landmarks
	challenge: BiomeChallenge?, -- empty for now
	-- startDistance, length and colors are added in the economy/world step.
}

return {}
