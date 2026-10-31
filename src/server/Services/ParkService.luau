--!strict
-- ParkService: each player's ballpark.
--   * Park upgrades (Config/Park): BuyParkUpgrade(upgradeId) (RemoteFunction) -> { ok, err? }
--     buys the next level with Cash, up to Park.MAX_LEVEL. Each level raises the park's Cash
--     rate (Formulas.parkMultiplier), which IncomeService pays online and offline.
--   * Publishes what everyone can see on the lane model (WorldService), so every client draws
--     every park: the seated Mascots ("Seats": "species,variant,size" per seat, ";"-joined, ""
--     for empty) and the upgrade levels ("Park": levels in Config/Park order, ","-joined).
--     Display only: the save stays the source of truth, and income reads the save.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Formulas = require(Shared.Formulas)
local Park = require(Shared.Config.Park)
local Remotes = require(Shared.Remotes)

local Services = script.Parent
local DataService = require(Services.DataService)
local WorldService = require(Services.WorldService)
local RateLimit = require(Services.Parent.Util.RateLimit)

local ParkService = {}

local limit = RateLimit.new(5)
local dirtySeats: { [Player]: boolean } = {}
local dirtyLevels: { [Player]: boolean } = {}

type Result = { ok: boolean, err: string? }

local function encodeSeats(data: any): string
	local seats = {}
	for i, uid in data.seats do
		local mascot = if uid then data.mascots[uid] else nil
		seats[i] = if mascot then `{mascot.species},{mascot.variant},{mascot.size}` else ""
	end
	return table.concat(seats, ";")
end

local function encodeLevels(data: any): string
	local levels = {}
	for i, upgrade in Park.Upgrades do
		levels[i] = tostring(data.park[upgrade.id] or 0)
	end
	return table.concat(levels, ",")
end

local function publish(player: Player)
	local data = DataService.Get(player)
	if data then
		WorldService.SetParkSeats(player, encodeSeats(data))
		WorldService.SetParkLevels(player, encodeLevels(data))
	end
end

function ParkService.BuyUpgrade(player: Player, upgradeId: string): Result
	local data = DataService.Get(player)
	if data == nil then
		return { ok = false, err = "not loaded" }
	end
	if Park.UpgradeById[upgradeId] == nil then
		return { ok = false, err = "unknown" }
	end
	local level = data.park[upgradeId] or 0
	local cost = Formulas.parkUpgradeCost(upgradeId, level)
	if cost == nil then
		return { ok = false, err = "max level" }
	end
	if data.cash < cost then
		return { ok = false, err = "not enough cash" }
	end
	-- No yields between the check and the spend, so two quick buys can't both pass.
	DataService.Update(player, "cash", function(cash)
		return cash - cost
	end)
	DataService.Update(player, "park", function(park)
		park[upgradeId] = level + 1
		return park
	end)
	return { ok = true }
end

function ParkService.Start()
	Remotes.Function("BuyParkUpgrade").OnServerInvoke = function(player: Player, upgradeId: unknown): Result
		if not limit:Allow(player) then
			return { ok = false, err = "too fast" }
		end
		if type(upgradeId) ~= "string" or #upgradeId > 40 then
			return { ok = false, err = "bad args" }
		end
		return ParkService.BuyUpgrade(player, upgradeId)
	end

	DataService.Loaded:Connect(publish)
	-- A catch or an action changes several keys at once: publish once per frame.
	DataService.Changed:Connect(function(player: Player, key: string)
		if key == "seats" or key == "mascots" then
			dirtySeats[player] = true
		elseif key == "park" then
			dirtyLevels[player] = true
		end
	end)
	RunService.Heartbeat:Connect(function()
		for player in dirtySeats do
			dirtySeats[player] = nil
			local data = player.Parent == Players and DataService.Get(player)
			if data then
				WorldService.SetParkSeats(player, encodeSeats(data))
			end
		end
		for player in dirtyLevels do
			dirtyLevels[player] = nil
			local data = player.Parent == Players and DataService.Get(player)
			if data then
				WorldService.SetParkLevels(player, encodeLevels(data))
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		dirtySeats[player] = nil
		dirtyLevels[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		if DataService.IsLoaded(player) then
			publish(player)
		end
	end
end

return ParkService
