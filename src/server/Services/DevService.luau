--!strict
-- DevService: Studio-only test hook. Does nothing on live servers.
-- Creates ServerStorage.DevData (BindableFunction) so tests can read and change saves
-- through DataService, the same path real gameplay uses:
--   DevData:Invoke("get", userId)              -> copy of the save, or nil
--   DevData:Invoke("set", userId, key, value)  -> true if changed
--   DevData:Invoke("reset", userId)            -> resets the save to new-player defaults
--   DevData:Invoke("metrics", userId)          -> timings since this server saw the player join

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Template = require(script.Parent.Parent.Data.Template)
local DataService = require(script.Parent.DataService)
local LandingService = require(script.Parent.LandingService)

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
	devData.OnInvoke = function(command: string, userId: number, key: string?, value: any)
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
		end
		return nil
	end
	devData.Parent = ServerStorage
end

return DevService
