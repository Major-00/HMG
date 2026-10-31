--!strict
-- BatSwing: the local bat swing, shared by Fungo hitting (FungoController) and the pitching
-- machine path (InputController). Ready pose -> level through the strike point -> optional
-- hold (hit-stop) -> follow-through -> back to ready. Cosmetic only.
--   BatSwing.Play(character, timing) -> false if the character has no bat or a swing is playing
--     timing = { toContact, hold?, follow, recover } in seconds

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local BatPose = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BatPose"))

export type Timing = {
	toContact: number,
	hold: number?,
	follow: number,
	recover: number,
}

local BatSwing = {}

local playing: { [Instance]: boolean } = {}

function BatSwing.Play(character: Model?, timing: Timing): boolean
	local bat = character and character:FindFirstChild("Bat")
	local grip = bat and bat:FindFirstChild("BatGrip")
	if grip == nil or not grip:IsA("Weld") or grip.Part0 == nil or playing[grip] then
		return false
	end
	playing[grip] = true
	local isR6 = (grip.Part0 :: BasePart).Name == "Right Arm"
	local steps = {
		{ time = timing.toContact, pose = BatPose.CONTACT, style = Enum.EasingStyle.Quad },
		{ time = timing.hold or 0, pose = BatPose.CONTACT, style = Enum.EasingStyle.Linear },
		{ time = timing.follow, pose = BatPose.FOLLOW, style = Enum.EasingStyle.Linear },
		{ time = timing.recover, pose = BatPose.READY, style = Enum.EasingStyle.Sine },
	}
	local function play(i: number)
		local step = steps[i]
		if step == nil or grip.Parent == nil then
			playing[grip] = nil
			return
		end
		if step.time <= 0 then
			play(i + 1)
			return
		end
		local tween = TweenService:Create(
			grip,
			TweenInfo.new(step.time, step.style),
			{ C0 = BatPose.grip(step.pose, isR6) }
		)
		tween.Completed:Once(function()
			play(i + 1)
		end)
		tween:Play()
	end
	play(1)
	return true
end

return BatSwing
