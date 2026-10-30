--!strict
-- Formulas: pure math for the core loop. Every number comes from Config/Tuning.
-- The server uses these to decide stats; the client only uses them for display.

local Config = script.Parent.Config
local Tuning = require(Config.Tuning)
local Biomes = require(Config.Biomes)

local Formulas = {}

-- Power gained from one hit, given the player's total multiplier.
function Formulas.powerGain(multiplier: number): number
	return Tuning.Power.PER_HIT * multiplier
end

-- Hit distance in whole studs for a player's total Power.
function Formulas.distance(power: number): number
	local d = Tuning.Distance
	return math.floor(d.BASE + d.PER_POWER * math.max(power, 0) ^ d.EXPONENT)
end

-- Wins paid for a hit that travelled `distance` studs.
function Formulas.wins(distance: number): number
	local w = Tuning.Wins
	return math.max(w.MIN_PER_HIT, math.floor(distance / w.STUDS_PER_WIN))
end

-- Index (1-based, Config/Biomes order) of the biome at `distance`.
function Formulas.biomeIndexAt(distance: number): number
	local starts = Tuning.BiomeStarts
	local index = 1
	for i = 1, math.min(#starts, #Biomes) do
		if distance >= starts[i] then
			index = i
		end
	end
	return index
end

function Formulas.biomeNameAt(distance: number): string
	return Biomes[Formulas.biomeIndexAt(distance)].displayName
end

return Formulas
