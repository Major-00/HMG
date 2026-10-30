--!strict
-- DevService: Studio-only test hook. Does nothing on live servers.
-- Creates ServerStorage.DevData (BindableFunction) so tests can read and change saves
-- through DataService, the same path real gameplay uses:
--   DevData:Invoke("get", userId)              -> copy of the save, or nil
--   DevData:Invoke("set", userId, key, value)  -> true if changed
--   DevData:Invoke("reset", userId)            -> resets the save to new-player defaults
--   DevData:Invoke("metrics", userId)          -> timings since this server saw the player join
--   DevData:Invoke("simcatch", userId, n, distance) -> n catch rolls at `distance` with the
--     player's world and best ball, compared with Formulas.catchOdds (changes nothing)
--   DevData:Invoke("selftest", userId, ops?) -> MascotInventory rule tests (changes nothing)
--   Mascot actions, same path as the remotes:
--     "lock" (uid, locked?), "autosell" (on), "equipbest", "sell" (uid),
--     "move" (uid, place, slot), "grant" (speciesId, variant?, size?) -> adds it like a catch
--   DevData:Invoke("offline", userId, seconds) -> pays offline earnings as if away that long

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Mascots = require(ReplicatedStorage.Shared.Config.Mascots)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)

local Template = require(script.Parent.Parent.Data.Template)
local DataService = require(script.Parent.DataService)
local LandingService = require(script.Parent.LandingService)
local IncomeService = require(script.Parent.IncomeService)
local MascotService = require(script.Parent.MascotService)

local DevService = {}

type Metrics = {
	joinedAt: number,
	spawnedAt: number?,
	firstHitAt: number?,
	biome2At: number?,
	hits: number,
}

local metrics: { [Player]: Metrics } = {}

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = deepCopy(v)
	end
	return copy
end

local function track(player: Player)
	local m: Metrics = { joinedAt = os.clock(), hits = 0 }
	metrics[player] = m
	local function onCharacter()
		m.spawnedAt = m.spawnedAt or os.clock()
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter()
	end
end

local function percent(x: number): number
	return math.floor(x * 10000 + 0.5) / 100
end

-- Rolls `n` catches the same way the server will, and compares the counts with the odds.
local function simCatch(player: Player, n: number, distance: number): { [string]: any }?
	local data = DataService.Get(player)
	if data == nil then
		return nil
	end
	local world = data.stadiumTier
	local ball = Formulas.bestBall(data)
	local biomeIndex = Formulas.biomeIndexAt(distance, world)
	local odds = Formulas.catchOdds(world, ball.id, biomeIndex, distance)
	local rng = Random.new()

	local speciesCount: { [string]: number } = {}
	local variantCount: { [string]: number } = {}
	local sizeCount: { [string]: number } = {}
	for _ = 1, n do
		local id = Formulas.rollSpecies(odds, rng) :: string
		speciesCount[id] = (speciesCount[id] or 0) + 1
		local variant = Formulas.rollVariant(rng)
		variantCount[variant] = (variantCount[variant] or 0) + 1
		local size = Formulas.rollSize(rng)
		sizeCount[size] = (sizeCount[size] or 0) + 1
	end

	-- Per rarity and per species: expected % vs rolled %, and the biggest gap.
	local rarities = {}
	local species = {}
	local maxGap = 0
	local expectedByRarity: { [string]: number } = {}
	local rolledByRarity: { [string]: number } = {}
	for _, entry in odds do
		local rolled = (speciesCount[entry.species] or 0) / n
		maxGap = math.max(maxGap, math.abs(rolled - entry.chance))
		expectedByRarity[entry.rarity] = (expectedByRarity[entry.rarity] or 0) + entry.chance
		rolledByRarity[entry.rarity] = (rolledByRarity[entry.rarity] or 0) + rolled
		table.insert(species, `{entry.species} {percent(entry.chance)}% / {percent(rolled)}%`)
	end
	for _, rarity in Mascots.Rarities do
		local expected = expectedByRarity[rarity.id]
		if expected then
			table.insert(rarities, `{rarity.id} {percent(expected)}% / {percent(rolledByRarity[rarity.id])}%`)
		end
	end
	local function extras(list: { any }, default: string, counts: { [string]: number }): { string }
		local out = { `{default} {percent((counts[default] or 0) / n)}%` }
		for _, entry in list do
			table.insert(out, `{entry.id} {percent(entry.chance)}% / {percent((counts[entry.id] or 0) / n)}%`)
		end
		return out
	end

	return {
		world = world,
		ball = ball.id,
		distance = distance,
		biome = Formulas.biomeNameAt(distance, world),
		luck = math.floor(Formulas.luck(distance) * 1000) / 1000,
		rolls = n,
		rarities = rarities, -- "id expected% / rolled%"
		species = species,
		variants = extras(Tuning.Catch.VARIANTS, "none", variantCount),
		sizes = extras(Tuning.Catch.SIZES, "normal", sizeCount),
		maxGapPoints = percent(maxGap), -- largest species gap, in percentage points
		rareShare = percent(1 - (expectedByRarity.common or 0) - (expectedByRarity.uncommon or 0)),
	}
end

local function report(player: Player): { [string]: number? }?
	local m = metrics[player]
	if m == nil then
		return nil
	end
	local function since(t: number?, from: number?): number?
		return if t and from then math.floor((t - from) * 100) / 100 else nil
	end
	return {
		joinToSpawn = since(m.spawnedAt, m.joinedAt),
		spawnToFirstHit = since(m.firstHitAt, m.spawnedAt),
		spawnToBiome2 = since(m.biome2At, m.spawnedAt),
		hits = m.hits,
	}
end

function DevService.Start()
	if not RunService:IsStudio() then
		return
	end

	Players.PlayerAdded:Connect(track)
	Players.PlayerRemoving:Connect(function(player)
		metrics[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		track(player)
	end
	LandingService.Landed:Connect(function(ctx)
		local m = metrics[ctx.player]
		if m then
			m.hits += 1
			m.firstHitAt = m.firstHitAt or os.clock()
			if ctx.biomeIndex >= 2 then
				m.biome2At = m.biome2At or os.clock()
			end
		end
	end)

	local devData = Instance.new("BindableFunction")
	devData.Name = "DevData"
	devData.OnInvoke = function(command: string, userId: number, key: any, value: any, extra: any)
		local player = Players:GetPlayerByUserId(userId)
		if player == nil then
			return nil
		end
		if command == "get" then
			return DataService.Get(player)
		elseif command == "set" and key ~= nil then
			return DataService.Update(player, key, function()
				return value
			end)
		elseif command == "reset" then
			for k, v in Template :: any do
				if k ~= "version" then
					DataService.Update(player, k, function()
						return deepCopy(v)
					end)
				end
			end
			local m = metrics[player]
			if m then
				m.firstHitAt, m.biome2At, m.hits = nil, nil, 0
			end
			return true
		elseif command == "metrics" then
			return report(player)
		elseif command == "simcatch" then
			local n = math.clamp(math.floor(tonumber(key) or 100000), 1, 1000000)
			return simCatch(player, n, tonumber(value) or 0)
		elseif command == "selftest" then
			local MascotInventoryTest = require(script.Parent.Parent.Dev.MascotInventoryTest) :: any
			return MascotInventoryTest.Run(tonumber(key))
		-- Mascot actions, through the same MascotService functions the remotes use.
		elseif command == "lock" then
			return MascotService.SetLock(player, key, value ~= false)
		elseif command == "autosell" then
			return MascotService.SetAutoSell(player, key == true)
		elseif command == "equipbest" then
			return MascotService.EquipBest(player)
		elseif command == "sell" then
			return MascotService.Sell(player, key)
		elseif command == "move" then
			return MascotService.Move(player, key, value, extra)
		elseif command == "grant" then
			return MascotService.Grant(player, key, value, extra)
		elseif command == "offline" then
			-- Pretend the player was away `key` seconds, then pay offline earnings as on load.
			local before = (DataService.Get(player) :: any).cash
			local welcome = IncomeService.SimulateOffline(player, tonumber(key) or 0)
			return { paid = (DataService.Get(player) :: any).cash - before, welcome = welcome }
		end
		return nil
	end
	devData.Parent = ServerStorage
end

return DevService
