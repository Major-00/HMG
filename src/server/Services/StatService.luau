--!strict
-- StatService: a player's total Power multiplier = bat x rebirth x pitcher bonus.
-- The formula is Formulas.multiplier (shared, so the client predicts the same number).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Formulas = require(ReplicatedStorage.Shared.Formulas)

local DataService = require(script.Parent.DataService)
local PitchService = require(script.Parent.PitchService)

local StatService = {}

-- 0 if the save isn't loaded (no Power can be gained without a save).
function StatService.GetMultiplier(player: Player): number
	local data = DataService.Get(player)
	if data == nil then
		return 0
	end
	return Formulas.multiplier(data, PitchService.GetPowerBonus(player))
end

return StatService
