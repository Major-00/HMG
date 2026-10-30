--!strict
-- StatService: a player's total Power multiplier = bat x rebirth x pitcher bonus.
-- Pets join the product in the pets step. Numbers come from Config (Bats, Tuning).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage.Shared.Config
local Bats = require(Config.Bats) :: any
local Tuning = require(Config.Tuning)

local DataService = require(script.Parent.DataService)
local PitchService = require(script.Parent.PitchService)

local StatService = {}

-- 0 if the save isn't loaded (no Power can be gained without a save).
function StatService.GetMultiplier(player: Player): number
	local data = DataService.Get(player)
	if data == nil then
		return 0
	end
	local bat = Bats[data.bats.equipped]
	local batMultiplier = if bat and bat.powerMultiplier then bat.powerMultiplier else 1
	local rebirthMultiplier = 1 + data.rebirths * Tuning.Power.REBIRTH_BONUS
	return batMultiplier * rebirthMultiplier * PitchService.GetPowerBonus(player)
end

return StatService
