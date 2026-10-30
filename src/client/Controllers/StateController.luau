--!strict
-- StateController: this player's latest save data, as sent by the server.
-- Read only. The client never writes data; it only asks the server to do things.
--   StateController.Get()           -> data, or nil until the first snapshot arrives
--   StateController.WaitForData()   -> yields until the first snapshot
--   StateController.Changed         -> Signal (key, newValue)
--   StateController.Ready           -> Signal () fired once, on the first snapshot

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Signal = require(Shared:WaitForChild("Signal"))
local Types = require(Shared:WaitForChild("Types"))

local RETRY_SECONDS = 2

local StateController = {}

StateController.Changed = Signal.new()
StateController.Ready = Signal.new()

local data: Types.PlayerData? = nil

function StateController.Get(): Types.PlayerData?
	return data
end

function StateController.WaitForData(): Types.PlayerData
	while data == nil do
		StateController.Ready:Wait()
	end
	return data :: Types.PlayerData
end

function StateController.Start()
	-- Listen first, so no change is missed while the snapshot is on its way.
	-- Changes that arrive before the snapshot are already included in it.
	Remotes.Event("DataChanged").OnClientEvent:Connect(function(changes: { [string]: any })
		local current = data :: any
		if current == nil then
			return
		end
		for key, value in changes do
			current[key] = value
			StateController.Changed:Fire(key, value)
		end
	end)

	local getData = Remotes.Function("GetData")
	while data == nil do
		local ok, snapshot = pcall(getData.InvokeServer, getData)
		if ok and snapshot ~= nil then
			data = snapshot
			StateController.Ready:Fire()
		else
			-- Still loading, or the server is about to kick us for a failed load.
			task.wait(RETRY_SECONDS)
		end
	end
end

return StateController
