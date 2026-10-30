--!strict
-- DevService: Studio-only test hook. Does nothing on live servers.
-- Creates ServerStorage.DevData (BindableFunction) so tests can read and change saves
-- through DataService, the same path real gameplay uses:
--   DevData:Invoke("get", userId)              -> copy of the save, or nil
--   DevData:Invoke("set", userId, key, value)  -> true if changed

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local DataService = require(script.Parent.DataService)

local DevService = {}

function DevService.Start()
	if not RunService:IsStudio() then
		return
	end

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
		end
		return nil
	end
	devData.Parent = ServerStorage
end

return DevService
