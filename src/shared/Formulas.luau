--!strict
-- Formulas: pure math for the core loop. Every number comes from Config/Tuning.
-- The server uses these to decide stats; the client only uses them for display.

local Config = script.Parent.Config
local HookTypes = require(script.Parent.HookTypes)
local Tuning = require(Config.Tuning)
local Balls = require(Config.Balls)
local Biomes = require(Config.Biomes)
local Bats = require(Config.Bats) :: any
local Mascots = require(Config.Mascots)
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

-- The biome list for `world` (World 1 if that world doesn't exist yet).
function Formulas.biomes(world: number?): { HookTypes.BiomeConfig }
	return Biomes[world or 1] or Biomes[1]
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

function Formulas.biomeNameAt(distance: number, world: number?): string
	return Formulas.biomes(world)[Formulas.biomeIndexAt(distance, world)].displayName
end

-- MASCOT CATCH -------------------------------------------------------------------------------

-- The best ball the save owns (the last one in Config/Balls order).
function Formulas.bestBall(data: any): Balls.Ball
	local best = Balls[1]
	for _, ball in Balls do
		if data.balls.owned[ball.id] then
			best = ball
		end
	end
	return best
end

-- Luck at a landing distance, times any boost (`luckMult`, default 1).
function Formulas.luck(distance: number, luckMult: number?): number
	local l = Tuning.Catch.LUCK
	local base = 1 + l.PER_DOUBLING * math.log(1 + math.max(distance, 0) / l.BASE_STUDS, 2)
	return math.min(l.MAX_LUCK, base) * (luckMult or 1)
end

export type SpeciesOdds = {
	species: string,
	rarity: string,
	chance: number, -- 0..1; all entries add up to 1
}

-- Every species' chance of being caught at a landing. The server rolls from this list and every
-- odds screen shows it, so they can never disagree.
--   world, ballId: the player's world and best ball
--   biomeIndex: the biome the ball landed in; distance: where it landed (drives Luck)
--   luckMult: any luck boost (default 1)
-- Each rarity's weight is the ball's weight x luck ^ ((rank - 1) x LUCK_POWER), split evenly
-- between the species of that rarity in the biome. Rarities with no species there drop out.
function Formulas.catchOdds(
	world: number,
	ballId: string,
	biomeIndex: number,
	distance: number,
	luckMult: number?
): { SpeciesOdds }
	local ball = Balls[1]
	for _, b in Balls do
		if b.id == ballId then
			ball = b
		end
	end
	local biome = Formulas.biomes(world)[biomeIndex]
	local worldMascots = Mascots.Worlds[world] or Mascots.Worlds[1]
	local list = if biome then worldMascots[biome.id] else nil
	if list == nil or #list == 0 then
		return {}
	end

	local byRarity: { [string]: { string } } = {}
	for _, species in list do
		byRarity[species.rarity] = byRarity[species.rarity] or {}
		table.insert(byRarity[species.rarity], species.id)
	end

	local luck = Formulas.luck(distance, luckMult)
	local odds: { SpeciesOdds } = {}
	local total = 0
	for rank, rarity in Mascots.Rarities do
		local ids = byRarity[rarity.id]
		local weight = ball.weights[rarity.id] or 0
		if ids and weight > 0 then
			local rarityWeight = weight * luck ^ ((rank - 1) * Tuning.Catch.LUCK_POWER)
			for _, id in ids do
				local each = rarityWeight / #ids
				table.insert(odds, { species = id, rarity = rarity.id, chance = each })
				total += each
			end
		end
	end
	for _, entry in odds do
		entry.chance /= total
	end
	return odds
end

-- Picks a species from catchOdds using the server's Random.
function Formulas.rollSpecies(odds: { SpeciesOdds }, rng: Random): string?
	local roll = rng:NextNumber()
	local sum = 0
	for _, entry in odds do
		sum += entry.chance
		if roll < sum then
			return entry.species
		end
	end
	local last = odds[#odds]
	return if last then last.species else nil -- float rounding at the very top
end

-- Rolls one id from a list of { id, chance }; whatever chance is left goes to `default`.
local function rollExtra(list: { any }, default: string, rng: Random): string
	local roll = rng:NextNumber()
	local sum = 0
	for _, entry in list do
		sum += entry.chance
		if roll < sum then
			return entry.id
		end
	end
	return default
end

function Formulas.rollVariant(rng: Random): string
	return rollExtra(Tuning.Catch.VARIANTS, "none", rng)
end

function Formulas.rollSize(rng: Random): string
	return rollExtra(Tuning.Catch.SIZES, "normal", rng)
end

local function multiplierOf(list: { any }, id: string): number
	for _, entry in list do
		if entry.id == id then
			return entry.multiplier
		end
	end
	return 1
end

-- Cash per second a Mascot earns while seated, before park upgrades and the stadium tier.
-- `mascot` is a saved MascotEntry ({ species, variant, size, ... }); 0 for an unknown species.
function Formulas.mascotCashPerSec(mascot: any): number
	local species = Mascots.ById[mascot.species]
	if species == nil then
		return 0
	end
	local c = Tuning.Catch
	local base = (c.RARITY_CASH[species.rarity] or 0) * (c.BIOME_CASH[species.biomeIndex] or 1)
	return base * multiplierOf(c.VARIANTS, mascot.variant) * multiplierOf(c.SIZES, mascot.size)
end

-- Cash paid when a Mascot is sold (by tap, Auto-Sell or the On Deck rule): always this full value.
function Formulas.mascotSellValue(mascot: any): number
	return math.floor(Formulas.mascotCashPerSec(mascot) * Tuning.Catch.SELL_SECONDS)
end

return Formulas
