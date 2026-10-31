--!strict
-- Fungo: the default Pitcher (see HookTypes.Pitcher), mode "toss". The batter tosses the ball up
-- and hits it in one motion from one tap, so nobody is pinned to a mark or waits for a throw.
-- Same timing for everyone, no Power bonus. PitchService allows one hit per cycle.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HookTypes = require(ReplicatedStorage.Shared.HookTypes)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)

local Fungo: HookTypes.Pitcher = {
	id = "fungo",
	mode = "toss",
	cooldown = function(_player: Player): number
		return 0
	end,
	travelTime = function(_player: Player): number
		return Tuning.Fungo.CONTACT_AT
	end,
}

return Fungo
