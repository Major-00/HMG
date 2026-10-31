--!strict
-- PitchingMachine: a Pitcher with mode "throw" (see HookTypes.Pitcher). Same timing for everyone,
-- no Power bonus. Not the default any more (Fungo is) and not built in the scene; kept as the
-- second slot implementation, e.g. for a pitcher pet. WorldService builds its model only when it's
-- Tuning.Pitch.DEFAULT_PITCHER.
-- Another pitcher is another module in this folder with the same shape and its own id.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HookTypes = require(ReplicatedStorage.Shared.HookTypes)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)

local PitchingMachine: HookTypes.Pitcher = {
	id = "pitching_machine",
	mode = "throw",
	cooldown = function(_player: Player): number
		return Tuning.Pitch.MACHINE_COOLDOWN
	end,
	travelTime = function(_player: Player): number
		return Tuning.Pitch.MACHINE_TRAVEL_TIME
	end,
}

return PitchingMachine
