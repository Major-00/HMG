--!strict
-- InputController: turns input into swings. There is no SWING button.
--   Touch:   a tap anywhere on the game view (taps on buttons and menus don't count)
--   PC:      left click on the game view, or Space (Space no longer jumps)
--   Gamepad: R2
-- With Fungo (the default pitcher) every tap tosses and swings in one motion
-- (FungoController.Toss): no indicator, no second tap, no timing, and one toss per cycle.
-- With the pitching machine (kept as a second pitcher), a tap hits the pitch in play.
-- While the ball-cam is away, a tap skips the catch reveal instead.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Tuning = require(Shared:WaitForChild("Config"):WaitForChild("Tuning"))

local Controllers = script.Parent
local BallController = require(Controllers.BallController)
local CameraController = require(Controllers.CameraController)
local FungoController = require(Controllers.FungoController)
local PitcherController = require(Controllers.PitcherController)
local BatSwing = require(Controllers.Parent:WaitForChild("Modules"):WaitForChild("BatSwing"))

local player = Players.LocalPlayer

local InputController = {}

-- Pitching machine: hit the pitch in play. If lag let one through while the camera is away,
-- still hit it (the ball-cam switches to the new ball) so the pitch isn't lost.
local function machineSwing()
	local pitch = PitcherController.TakePending()
	if CameraController.IsActive() then
		if pitch == nil then
			CameraController.SkipReveal()
			return
		end
	else
		local s = Tuning.Swing
		BatSwing.Play(
			player.Character,
			{ toContact = s.TO_CONTACT, follow = s.FOLLOW_THROUGH, recover = s.RECOVER }
		)
	end
	if pitch == nil then
		return
	end
	BallController.Hit(pitch.pitchId)
	Remotes.Event("Swing"):FireServer(pitch.pitchId)
end

local function swing()
	if player:GetAttribute("PitcherMode") == "throw" then
		machineSwing()
		return
	end
	if CameraController.IsActive() then
		CameraController.SkipReveal() -- a tap during the catch reveal skips it
		return
	end
	FungoController.Toss()
end

function InputController.Start()
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

	-- Space and gamepad R2. Bound above the default controls so Space swings instead of jumping;
	-- typing in a text box never reaches here.
	ContextActionService:BindActionAtPriority("Swing", function(_name, state)
		if state == Enum.UserInputState.Begin then
			swing()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.Space, Enum.KeyCode.ButtonR2)
end

return InputController
