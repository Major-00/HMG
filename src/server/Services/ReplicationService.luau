--!strict
-- ReplicationService: sends each player their own save.
--   GetData (RemoteFunction): full snapshot, waits until the save has loaded.
--   DataChanged (RemoteEvent): changed top-level keys, batched to one send per frame.
-- Players only ever receive their own data, and nothing from the client is written back.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)

local ReplicationService = {}

-- Keys changed since the last send, per player.
local pending: { [Player]: { [string]: any } } = {}

local function flush()
	if next(pending) == nil then
		return
	end
	local dataChanged = Remotes.Event("DataChanged")
	for player, changes in pending do
		if player.Parent == Players then
			dataChanged:FireClient(player, changes)
		end
	end
	table.clear(pending)
end

function ReplicationService.Start()
	Remotes.Function("GetData").OnServerInvoke = function(player: Player)
		return DataService.WaitForData(player)
	end

	DataService.Changed:Connect(function(player: Player, key: string, value: any)
		local changes = pending[player]
		if changes == nil then
			changes = {}
			pending[player] = changes
		end
		changes[key] = value -- latest value wins
	end)

	Players.PlayerRemoving:Connect(function(player)
		pending[player] = nil
	end)

	RunService.Heartbeat:Connect(flush)
end

return ReplicationService
