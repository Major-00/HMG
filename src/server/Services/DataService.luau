--!strict
-- DataService: loads, autosaves and releases each player's save with ProfileStore.
-- The only module that touches DataStores, and the only way to change a save:
--   DataService.Get(player)            -> the save (read it, never edit it directly)
--   DataService.Update(player, key, fn) -> change one top-level key, notifies the client
-- A player whose save fails to load is kicked. Nobody ever plays on a blank save.
-- ProfileStore itself saves and releases every loaded save when the server shuts down.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Server = script.Parent.Parent
local ProfileStore = require(Server.Packages.ProfileStore)
local Template = require(Server.Data.Template)
local Migrations = require(Server.Data.Migrations)

local Shared = ReplicatedStorage.Shared
local Signal = require(Shared.Signal)
local Tuning = require(Shared.Config.Tuning)
local Types = require(Shared.Types)

-- Studio uses its own DataStore so test saves never mix with live player saves.
local STORE_NAME = if RunService:IsStudio() then "PlayerData_Studio" else "PlayerData"

local KICK_MESSAGES = {
	LoadFailed = "We couldn't load your save, so we stopped you from playing on a blank one. "
		.. "Your progress is safe. Please rejoin in a minute.",
	NewerVersion = "Your save is from a newer version of the game. Please rejoin to get an updated server.",
	BadSave = "Something is wrong with your save, so we stopped to protect it. Please contact the developer.",
	SessionEnded = "Your save was opened somewhere else (another server or device). Please rejoin.",
}

local DataService = {}

-- Fires once a player's save is loaded and ready: (player, data)
DataService.Loaded = Signal.new()
-- Fires after Update changes a key: (player, key, newValue)
DataService.Changed = Signal.new()

local store: any
local profiles: { [Player]: any } = {}

local function profileKey(player: Player): string
	return `Player_{player.UserId}`
end

local function isInGame(player: Player): boolean
	return player.Parent == Players
end

local function loadPlayer(player: Player)
	-- Passing Cancel turns off ProfileStore's own load timeout, so the deadline lives here.
	local deadline = os.clock() + Tuning.Data.LOAD_KICK_SECONDS
	local profile = store:StartSessionAsync(profileKey(player), {
		Cancel = function()
			return not isInGame(player) or os.clock() > deadline
		end,
	})

	if profile == nil then
		-- DataStore failure, timeout, or the server is closing.
		if isInGame(player) then
			player:Kick(KICK_MESSAGES.LoadFailed)
		end
		return
	end

	if not isInGame(player) then
		-- Left while loading.
		profile:EndSession()
		return
	end

	-- Migrate before filling defaults, so old saves are upgraded, not overwritten.
	local ok, reason = Migrations.Run(profile.Data)
	if not ok then
		warn(`[DataService] Can't use save for {player.Name} ({player.UserId}): {reason}`)
		profile:EndSession() -- the save was not changed, so releasing it is safe
		player:Kick(if reason == "newer" then KICK_MESSAGES.NewerVersion else KICK_MESSAGES.BadSave)
		return
	end

	profile:AddUserId(player.UserId) -- GDPR: lets Roblox erase this save on request
	profile:Reconcile()

	local data = profile.Data
	if data.firstJoin == 0 then
		data.firstJoin = profile.FirstSessionTime
	end
	data.lastJoin = os.time()

	profile.OnSessionEnd:Connect(function()
		-- Expected ends (player left, server closing) remove the profile first.
		-- Anything else means another server took the save, so stop this player now.
		if profiles[player] == profile then
			profiles[player] = nil
			if isInGame(player) and not ProfileStore.IsClosing then
				player:Kick(KICK_MESSAGES.SessionEnded)
			end
		end
	end)

	profiles[player] = profile
	DataService.Loaded:Fire(player, data)
end

local function releasePlayer(player: Player)
	local profile = profiles[player]
	profiles[player] = nil
	if profile then
		profile:EndSession() -- saves and releases the session lock
	end
end

-- The player's save, or nil if it isn't loaded. Read only: change it with Update.
function DataService.Get(player: Player): Types.PlayerData?
	local profile = profiles[player]
	return if profile then profile.Data else nil
end

function DataService.IsLoaded(player: Player): boolean
	return profiles[player] ~= nil
end

-- Yields until the save is loaded. Returns nil if the player leaves or `timeout` passes.
function DataService.WaitForData(player: Player, timeout: number?): Types.PlayerData?
	local deadline = os.clock() + (timeout or Tuning.Data.LOAD_TIMEOUT)
	while profiles[player] == nil do
		if not isInGame(player) or os.clock() > deadline then
			return nil
		end
		task.wait(0.1)
	end
	return profiles[player].Data
end

-- The only way to change a save. `fn` gets the current value of one top-level key and
-- returns the new value (it may edit and return the same table). `fn` must not yield.
-- Returns false, and changes nothing, if the save isn't loaded.
function DataService.Update(player: Player, key: string, fn: (any) -> any): boolean
	local profile = profiles[player]
	if profile == nil or not profile:IsActive() then
		return false
	end
	assert((Template :: any)[key] ~= nil, `Unknown save key "{key}"`)
	assert(key ~= "version", "The save version is only changed by Migrations")

	local data = profile.Data :: any
	data[key] = fn(data[key])
	DataService.Changed:Fire(player, key, data[key])
	return true
end

function DataService.Init()
	ProfileStore.SetConstant("AUTO_SAVE_PERIOD", Tuning.Data.AUTOSAVE_SECONDS)
	store = ProfileStore.New(STORE_NAME, Template)
end

function DataService.Start()
	Players.PlayerAdded:Connect(loadPlayer)
	Players.PlayerRemoving:Connect(releasePlayer)
	-- Players who joined before this script started.
	for _, player in Players:GetPlayers() do
		task.spawn(loadPlayer, player)
	end
end

return DataService
