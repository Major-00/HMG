--!strict
-- InputController: a tap anywhere in the world (not on a button or menu), a mouse click,
-- or the SWING button swings. Each swing plays the bat animation. Every tap on the pitch in play
-- is a hit (CLAUDE.md): the ball launches at once and Swing(pitchId) goes to the server, which
-- computes the numbers from stats only. One hit per pitch. Taps with no pitch in play only
-- swing the bat.
-- While the ball-cam is away, taps only count if a pitch is somehow already in play.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BatPose = require(Shared:WaitForChild("BatPose"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Tuning = require(Shared:WaitForChild("Config"):WaitForChild("Tuning"))

local Controllers = script.Parent
local BallController = require(Controllers.BallController)
local CameraController = require(Controllers.CameraController)
local HudController = require(Controllers.HudController)
local PitcherController = require(Controllers.PitcherController)

local player = Players.LocalPlayer

local InputController = {}

local swinging = false

-- Local-only bat swing: ready pose -> level through the strike point -> follow-through -> back.
local function playSwing()
	if swinging then
		return
	end
	local character = player.Character
	local bat = character and character:FindFirstChild("Bat")
	local grip = bat and bat:FindFirstChild("BatGrip")
	if grip == nil or not grip:IsA("Weld") or grip.Part0 == nil then
		return
	end
	swinging = true
	local isR6 = (grip.Part0 :: BasePart).Name == "Right Arm"
	local s = Tuning.Swing
	local steps = {
		{ time = s.TO_CONTACT, pose = BatPose.CONTACT, style = Enum.EasingStyle.Quad },
		{ time = s.FOLLOW_THROUGH, pose = BatPose.FOLLOW, style = Enum.EasingStyle.Linear },
		{ time = s.RECOVER, pose = BatPose.READY, style = Enum.EasingStyle.Sine },
	}
	local function play(i: number)
		local step = steps[i]
		if step == nil or grip.Parent == nil then
			swinging = false
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
end

local function swing()
	local pitch = PitcherController.TakePending()
	if CameraController.IsActive() then
		-- The camera is away. Normally no pitch is in play then; if lag let one through,
		-- still hit it (the ball-cam switches to the new ball) so the pitch isn't lost.
		if pitch == nil then
			return
		end
	else
		playSwing()
	end
	if pitch == nil then
		return
	end
	BallController.Hit(pitch.pitchId)
	Remotes.Event("Swing"):FireServer(pitch.pitchId)
end

function InputController.Start()
	HudController.SwingPressed:Connect(swing)

	-- Touch: taps on the 3D world only (taps on buttons and menus are excluded).
	UserInputService.TouchTapInWorld:Connect(function(_position, processedByUI)
		if not processedByUI then
			swing()
		end
	end)

	-- Mouse: left click anywhere that isn't UI.
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.UserInputType == Enum.UserInputType.MouseButton1 then
			swing()
		end
	end)
end

return InputController
