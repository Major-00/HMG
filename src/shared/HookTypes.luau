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
	expiresAt: number, -- last moment a tap still hits; after this it's a miss
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
	biomeName: string, -- display name of that biome
	position: Vector3, -- world position where the ball lands, in the player's lane
}

-- ON-LAND HOOK. Runs on the server, in registration order, before Wins are paid.
-- Return a FlightSegment to push the ball further (e.g. a catcher pet), or nil to do nothing.
-- Handlers must not yield. LandingService.Landed fires after all handlers with the final context.
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

-- One piece of a placeholder prop. Built on the client; no assets.
export type PropPiece = {
	shape: "Block" | "Ball" | "Cylinder" | "Wedge",
	size: Vector3,
	offset: Vector3, -- from the prop's ground point; y is the piece's center height
	color: Color3,
	material: Enum.Material?, -- default SmoothPlastic
	rot: Vector3?, -- degrees (cylinders run along X; rot = (0, 0, 90) stands one up)
}
export type Prop = { PropPiece }

export type BiomeLighting = {
	clockTime: number,
	brightness: number,
	ambient: Color3,
	outdoorAmbient: Color3,
	atmosphereColor: Color3,
	atmosphereDecay: Color3,
	density: number,
	haze: number,
}

export type BiomeVisual = {
	ground: Color3, -- field ground under the lanes
	material: Enum.Material,
	side: Color3, -- ground outside the field, where props stand
	sideMaterial: Enum.Material,
	accent: Color3, -- start line, banner and landing popup color
	lighting: BiomeLighting,
	props: { Prop }, -- picked from per tile
}

export type BiomeConfig = {
	id: string,
	displayName: string,
	landmark: string, -- name of a model under ReplicatedStorage.Landmarks
	challenge: BiomeChallenge?, -- empty for now
	visual: BiomeVisual,
	-- Where each biome starts is in Config/Tuning (BiomeStarts).
}

return {}
