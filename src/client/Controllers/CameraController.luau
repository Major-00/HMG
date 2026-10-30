--!strict
-- CameraController: the ball-cam. On every hit the camera snaps behind the ball, follows it
-- (the ball itself slows down near the end, see BallController), holds on the landing spot,
-- then returns to the batter: a quick swoop for short hits, a fade cut for long ones.
-- Afterwards the normal Roblox camera takes over again exactly where it was before the hit.
-- The server times the next pitch from the same numbers (Formulas.ballCamTime).
--   CameraController.IsActive() -> true while the camera is away from the batter

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tuning = require(Shared:WaitForChild("Config"):WaitForChild("Tuning"))

local BallController = require(script.Parent.BallController)

local FIELD_DIRECTION = Vector3.zAxis -- lanes fire down +Z (see WorldService)
local GROUND_Y = 0

local player = Players.LocalPlayer

type Phase = "follow" | "hold" | "return"

type Cam = {
	hitId: number,
	saved: CFrame, -- the batter view to come back to
	distance: number,
	phase: Phase,
	landing: Vector3?,
	phaseStart: number,
	returnFrom: CFrame?,
	cutSwapped: boolean,
}

local CameraController = {}

local cam: Cam? = nil
local fade: Frame

local function camera(): Camera
	return workspace.CurrentCamera
end

local function smoothing(dt: number): number
	return 1 - math.exp(-Tuning.Camera.FOLLOW_SHARPNESS * dt)
end

-- Where the camera wants to be to look at `target` from behind and above.
local function chaseCFrame(target: Vector3, extraUp: number): CFrame
	local c = Tuning.Camera
	local pos = target - FIELD_DIRECTION * c.BACK + Vector3.new(0, c.UP + extraUp, 0)
	pos = Vector3.new(pos.X, math.max(pos.Y, GROUND_Y + c.MIN_CLEARANCE), pos.Z)
	return CFrame.lookAt(pos, target + FIELD_DIRECTION * c.LOOK_AHEAD * 0.5)
end

-- Hands the camera back to Roblox. `snapBack` puts it at the saved batter view first.
local function restore(snapBack: boolean)
	local state = cam
	cam = nil
	fade.BackgroundTransparency = 1
	local current = camera()
	if state and snapBack then
		current.CFrame = state.saved
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		current.CameraSubject = humanoid
	end
	current.CameraType = Enum.CameraType.Custom
end

local function beginReturn(state: Cam)
	state.phase = "return"
	state.phaseStart = os.clock()
	state.returnFrom = camera().CFrame
	state.cutSwapped = false
	-- The server may have corrected the flight's distance since launch; decide swoop or cut once.
	state.distance = BallController.GetDistance(state.hitId) or state.distance
end

local function onLaunched(hitId: number, info: any)
	local current = camera()
	local saved = if cam then cam.saved else current.CFrame
	cam = {
		hitId = hitId,
		saved = saved,
		distance = info.distance,
		phase = "follow",
		landing = nil,
		phaseStart = os.clock(),
		returnFrom = nil,
		cutSwapped = false,
	}
	fade.BackgroundTransparency = 1
	current.CameraType = Enum.CameraType.Scriptable
	-- Snap straight behind the ball at contact.
	local ball = BallController.GetBallPosition(hitId)
	if ball then
		current.CFrame = chaseCFrame(ball, 0)
	end
end

local function onTouchdown(
	hitId: number,
	_segment: number,
	position: Vector3,
	_distance: number,
	isFinal: boolean
)
	local state = cam
	if state == nil or state.hitId ~= hitId or not isFinal or state.phase ~= "follow" then
		return
	end
	state.phase = "hold"
	state.landing = position
	state.phaseStart = os.clock()
end

local function step(dt: number)
	local state = cam
	if state == nil then
		return
	end
	local c = Tuning.Camera
	local current = camera()
	if current.CameraType ~= Enum.CameraType.Scriptable then
		current.CameraType = Enum.CameraType.Scriptable -- something reset it mid-flight
	end
	local now = os.clock()

	if state.phase == "follow" then
		local ball = BallController.GetBallPosition(state.hitId)
		if ball == nil then
			beginReturn(state) -- the ball was dropped; come back
			return
		end
		-- Stay exactly BACK studs behind the ball along the track (smoothing there would lag
		-- far behind fast long hits); smooth only height and sideways, then aim at the ball.
		local target = chaseCFrame(ball, 0)
		local smoothed = current.CFrame.Position:Lerp(target.Position, smoothing(dt))
		local pos = Vector3.new(smoothed.X, smoothed.Y, target.Position.Z)
		current.CFrame = CFrame.lookAt(pos, ball + FIELD_DIRECTION * Tuning.Camera.LOOK_AHEAD * 0.5)
	elseif state.phase == "hold" then
		local landing = state.landing :: Vector3
		current.CFrame = current.CFrame:Lerp(chaseCFrame(landing, 3), smoothing(dt))
		if now - state.phaseStart >= c.LAND_HOLD then
			beginReturn(state)
		end
	else
		local elapsed = now - state.phaseStart
		if state.distance > c.CUT_BEYOND then
			-- Fade out, jump back, fade in.
			local half = c.CUT_TIME / 2
			if elapsed < half then
				fade.BackgroundTransparency = 1 - elapsed / half
			else
				if not state.cutSwapped then
					state.cutSwapped = true
					current.CFrame = state.saved
				end
				fade.BackgroundTransparency = math.min((elapsed - half) / half, 1)
				if elapsed >= c.CUT_TIME then
					restore(true)
				end
			end
		else
			local a = math.clamp(elapsed / c.RETURN_TIME, 0, 1)
			local eased = a * a * (3 - 2 * a) -- smoothstep
			current.CFrame = (state.returnFrom :: CFrame):Lerp(state.saved, eased)
			if a >= 1 then
				restore(true)
			end
		end
	end
end

function CameraController.IsActive(): boolean
	return cam ~= nil
end

function CameraController.Init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BallCamFade"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	fade = Instance.new("Frame")
	fade.Name = "Fade"
	fade.BackgroundColor3 = Color3.new(0, 0, 0)
	fade.BackgroundTransparency = 1
	fade.BorderSizePixel = 0
	fade.Size = UDim2.fromScale(1, 1)
	fade.Active = false
	fade.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
end

function CameraController.Start()
	BallController.Launched:Connect(onLaunched)
	BallController.Touchdown:Connect(onTouchdown)
	-- A respawn mid-flight goes straight back to the (new) batter.
	player.CharacterAdded:Connect(function()
		if cam then
			restore(false) -- the old batter view belongs to the old character
		end
	end)
	RunService:BindToRenderStep("BallCam", Enum.RenderPriority.Camera.Value + 1, step)
end

return CameraController
