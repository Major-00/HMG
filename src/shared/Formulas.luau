--!strict
-- Formulas: pure math for the core loop. Every number comes from Config/Tuning.
-- The server uses these to decide stats; the client only uses them for display.

local Config = script.Parent.Config
local Tuning = require(Config.Tuning)
local Biomes = require(Config.Biomes)
local Bats = require(Config.Bats) :: any
local Stadium = require(Config.Stadium)

local Formulas = {}

-- The player's stadium tier entry (tier 1 if the save holds an unknown tier).
function Formulas.stadiumTier(data: any): Stadium.StadiumTier
	return Stadium[data.stadiumTier] or Stadium[1]
end

-- A player's total Power multiplier from their save: bat x stadium tier x pitcher bonus.
-- Shared so the client can predict a hit exactly (boosts join the product when they exist).
function Formulas.multiplier(data: any, pitcherBonus: number): number
	local bat = Bats[data.bats.equipped]
	local batMultiplier = if bat and bat.powerMultiplier then bat.powerMultiplier else 1
	return batMultiplier * Formulas.stadiumTier(data).powerMultiplier * pitcherBonus
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

-- The highest record milestone passed when the best distance goes from `previousBest` to
-- `newBest`, or nil if none was passed.
function Formulas.recordMilestone(previousBest: number, newBest: number): number?
	local list = Tuning.Highlight.RECORD_MILESTONES
	local passed: number? = nil
	local milestone = list[1]
	local i = 1
	while milestone <= newBest do
		if milestone > previousBest then
			passed = milestone
		end
		i += 1
		-- Past the list, keep the 1 - 2.5 - 5 - 10 pattern (x2.5, x2, x2).
		local ratio = ({ 2.5, 2, 2 })[(i - #list - 1) % 3 + 1]
		milestone = list[i] or milestone * ratio
	end
	return passed
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

-- Seconds from contact until the ball-cam is back on the batter.
-- The server uses this to time the next pitch, so it must match the client's camera.
function Formulas.ballCamTime(distance: number): number
	local c = Tuning.Camera
	local back = if distance > c.CUT_BEYOND then c.CUT_TIME else c.RETURN_TIME
	return Formulas.slowedAirTime(distance) + c.LAND_HOLD + back
end

function Formulas.biomeNameAt(distance: number): string
	return Biomes[Formulas.biomeIndexAt(distance)].displayName
end

return Formulas
