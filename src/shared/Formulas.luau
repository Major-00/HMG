--!strict
-- Formulas: pure math for the core loop. Every number comes from Config/Tuning.
-- The server uses these to decide stats; the client only uses them to draw the hit at once.

local Config = script.Parent.Config
local HookTypes = require(script.Parent.HookTypes)
local Tuning = require(Config.Tuning)
local Biomes = require(Config.Biomes)

local Formulas = {}

-- A player's total Power multiplier. For now only the pitcher's bonus; launchers and boosts join
-- the product when they exist. Shared so the client can predict a hit exactly.
function Formulas.multiplier(_data: any, pitcherBonus: number): number
	return pitcherBonus
end

-- Power gained from one hit, given the player's total multiplier.
function Formulas.powerGain(multiplier: number): number
	return Tuning.Power.PER_HIT * multiplier
end

-- Hit distance in whole studs for a player's total Power.
function Formulas.distance(power: number): number
	local d = Tuning.Distance
	return math.floor(d.BASE + d.PER_POWER * math.max(power, 0) ^ d.EXPONENT)
end

-- The world a save plays. There is one world: the island's lane.
function Formulas.world(_data: any): number
	return 1
end

-- The biome list for `world` (default 1; past the last world, the last one).
function Formulas.biomes(world: number?): { HookTypes.BiomeConfig }
	return Biomes[math.clamp(world or 1, 1, #Biomes)]
end

-- Index (1-based, Config/Biomes order) of the biome at `distance` in `world` (default 1).
function Formulas.biomeIndexAt(distance: number, world: number?): number
	local starts = Tuning.BiomeStarts
	local index = 1
	for i = 1, math.min(#starts, #Formulas.biomes(world)) do
		if distance >= starts[i] then
			index = i
		end
	end
	return index
end

function Formulas.biomeNameAt(distance: number, world: number?): string
	return Formulas.biomes(world)[Formulas.biomeIndexAt(distance, world)].displayName
end

-- The Fungo swing tier for a Power total (Tuning.Fungo.TIERS): the last tier whose minPower it
-- reaches, and its number. Visual and audio only; it never changes a result or the cycle time.
function Formulas.swingTier(power: number): (any, number)
	local tiers = Tuning.Fungo.TIERS
	local index = 1
	for i, tier in tiers do
		if power >= tier.minPower then
			index = i
		end
	end
	return tiers[index], index
end

-- Seconds the ball is in the air for a hit, before slow-motion.
function Formulas.airTime(distance: number): number
	local f = Tuning.Flight
	return math.clamp(f.MIN_TIME + math.max(distance, 0) * f.SECONDS_PER_STUD, f.MIN_TIME, f.MAX_TIME)
end

-- Seconds the ball is in the air including the slow-motion at the end.
function Formulas.slowedAirTime(distance: number): number
	local c = Tuning.Camera
	local base = Formulas.airTime(distance)
	return base + base * c.SLOWMO_PORTION * (1 / c.SLOWMO_SPEED - 1)
end

-- Seconds the camera holds on the landing. Nothing is caught yet, so it's always the short hold;
-- `catch` is kept so a future catch can ask for the full one (Reveal.FULL).
function Formulas.revealTime(_catch: any?): number
	return Tuning.Reveal.SHORT
end

-- Seconds the camera takes to come back to the batter after the hold: a swoop, or a fade cut
-- for long hits.
function Formulas.returnTime(distance: number): number
	local c = Tuning.Camera
	return if distance > c.CUT_BEYOND then c.CUT_TIME else c.RETURN_TIME
end

-- Seconds from contact until the ball-cam is back on the batter, with a hold of `reveal` seconds
-- at the landing (default Reveal.SHORT). The server uses this to time the next pitch, so it must
-- match the client's camera.
function Formulas.ballCamTime(distance: number, reveal: number?): number
	return Formulas.slowedAirTime(distance) + (reveal or Tuning.Reveal.SHORT) + Formulas.returnTime(distance)
end

return Formulas
