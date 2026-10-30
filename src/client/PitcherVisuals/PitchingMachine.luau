--!strict
-- PitchingMachine (visual): the machine's throw effect. Cosmetic only.
-- Each pitcher id has a visual module with the same name in this folder.

local PitchingMachine = {}

local FLASH_SECONDS = 0.12

-- Called when this pitcher throws. `lane` is the player's lane model.
function PitchingMachine.Throw(lane: Model)
	local machine = lane:FindFirstChild("PitchingMachine")
	local barrel = machine and machine:FindFirstChild("Barrel")
	if barrel == nil or not barrel:IsA("BasePart") then
		return
	end
	local color = barrel.Color
	barrel.Color = color:Lerp(Color3.new(1, 1, 1), 0.6)
	task.delay(FLASH_SECONDS, function()
		barrel.Color = color
	end)
end

return PitchingMachine
