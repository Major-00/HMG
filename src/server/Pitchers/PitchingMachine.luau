--!strict
-- PitchingMachine: the default Pitcher (see HookTypes.Pitcher). Same timing for everyone, no Power bonus.
-- Another pitcher is another module in this folder with the same shape and its own id.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HookTypes = require(ReplicatedStorage.Shared.HookTypes)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)

local PitchingMachine: HookTypes.Pitcher = {
	id = "pitching_machine",
	cooldown = function(_player: Player): number
		return Tuning.Pitch.MACHINE_COOLDOWN
	end,
	travelTime = function(_player: Player): number
		return Tuning.Pitch.MACHINE_TRAVEL_TIME
	end,
}

return PitchingMachine
