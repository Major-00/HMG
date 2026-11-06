--!strict
-- CatchService: the catch phase. On every final landing it rolls whether a winged creature
-- catches the orb, and which rarity (Formulas.rarityWeights: farther means rarer). Luck only,
-- never skill (CLAUDE.md guardrail 5). The client plays the POV catch from the result
-- (CatchController); what was caught isn't kept yet: the orb bag comes next.
--   A player's first catch comes on hit Catch.FIRST_ON_HIT, is baseline and plays the full POV.
--   PITY: after Catch.PITY hits in a row with no catch, the next one catches (per session).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Formulas = require(Shared.Formulas)
local HookTypes = require(Shared.HookTypes)
local Rarities = require(Shared.Config.Rarities)
local Tuning = require(Shared.Config.Tuning)

local DataService = require(script.Parent.DataService)
local LandingService = require(script.Parent.LandingService)

local CatchService = {}

local dry: { [Player]: number } = {} -- hits in a row with no catch, this session
local rng = Random.new()

local function rollRarity(weights: { number }): number
	local total = 0
	for _, w in weights do
		total += w
	end
	local pick = rng:NextNumber() * total
	for i, w in weights do
		pick -= w
		if pick <= 0 then
			return i
		end
	end
	return 1
end

local function catcher(ctx: HookTypes.LandingContext): HookTypes.Catch?
	local data = DataService.Get(ctx.player)
	if data == nil then
		return nil
	end
	local c = Tuning.Catch
	local lifetime = data.lifetime
	local first = lifetime.catches == 0
	local index: number
	if first then
		-- The first catch waits for its hit (the first throw just teaches the launch), and it's
		-- always baseline, so it's yours at once at the Reveal Ring.
		if lifetime.swings + 1 < c.FIRST_ON_HIT then
			return nil
		end
		index = if rng:NextNumber() < 0.5 then 1 else 2
	else
		local misses = dry[ctx.player] or 0
		if misses + 1 < c.PITY and rng:NextNumber() >= c.CHANCE then
			dry[ctx.player] = misses + 1
			return nil
		end
		index = rollRarity(Formulas.rarityWeights(ctx.landedAt))
	end
	dry[ctx.player] = 0
	DataService.Update(ctx.player, "lifetime", function(l)
		l.catches += 1
		return l
	end)
	local rarity = Rarities[index]
	return {
		rarity = rarity.id,
		rank = rarity.rank,
		biomeIndex = ctx.biomeIndex,
		full = first or rarity.rank >= c.FULL_FROM,
		first = first,
	}
end

function CatchService.Start()
	LandingService.SetCatcher(catcher)
	Players.PlayerRemoving:Connect(function(player)
		dry[player] = nil
	end)
end

return CatchService
