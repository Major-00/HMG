--!strict
-- InputController: a tap anywhere in the world (not on a button or menu), a mouse click,
-- or the SWING button swings. Each swing plays the bat animation; if a pitch is in play it
-- sends Swing(pitchId) once. Taps with no pitch in play only swing the bat.
-- While the ball-cam is away, taps only count if a pitch is somehow already in play.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Tuning = require(Shared:WaitForChild("Config"):WaitForChild("Tuning"))

local Controllers = script.Parent
local BallController = require(Controllers.BallController)
local CameraController = require(Controllers.CameraController)
local HudController = require(Controllers.HudController)
local PitcherController = require(Controllers.PitcherController)

local SWING_ANGLE = math.rad(-110)

local player = Players.LocalPlayer

local InputController = {}

local swinging = false

-- Local-only bat swing: rotate the grip, then return.
local function playSwing()
	if swinging then
		return
	end
	local character = player.Character
	local bat = character and character:FindFirstChild("Bat")
	local grip = bat and bat:FindFirstChild("BatGrip")
	if grip == nil or not grip:IsA("Weld") then
		return
	end
	swinging = true
	local rest = grip.C0
	local half = Tuning.Swing.ANIMATION_TIME / 2
	local out =
		TweenService:Create(grip, TweenInfo.new(half), { C0 = rest * CFrame.Angles(0, 0, SWING_ANGLE) })
	out.Completed:Once(function()
		local back = TweenService:Create(grip, TweenInfo.new(half), { C0 = rest })
		back.Completed:Once(function()
			swinging = false
		end)
		back:Play()
	end)
	out:Play()
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
	BallController.Contact(pitch.pitchId)
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
