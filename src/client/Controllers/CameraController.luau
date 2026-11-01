--!strict
-- CameraController: the ball-cam. On every hit the camera first stays on the batter for a short
-- beat (Fungo.CAMERA_BEAT, so the follow-through is seen), then glides onto the ball
-- (Fungo.CAMERA_GLIDE, half that for long hits) and follows it (the ball itself slows down near
-- the end, see BallController), stays on the landing for the catch reveal (Formulas.revealTime:
-- 1s, or longer for a new rare species), then returns to the batter: a quick swoop for short
-- hits, a fade cut for long ones. The batter view is kept relative to the batter, who can walk
-- during the flight, so the camera comes back behind them where they stand now.
-- Afterwards the normal Roblox camera takes over again.
-- The server times the next pitch from the same numbers (Formulas.ballCamTime).
-- Ending the reveal early (a tap, or the server's result arriving too late to know the catch)
-- sends Ready, so the server can bring the next pitch forward; it never waits on the client.
--   CameraController.IsActive()   -> true from the hit until the camera is back on the batter
--   CameraController.SkipReveal() -> ends the reveal now if one is showing; true if it did
--   CameraController.RevealStarted / RevealEnded, SetRevealCamera(fn) -> for CatchRevealController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Formulas = require(Shared:WaitForChild("Formulas"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Signal = require(Shared:WaitForChild("Signal"))
local Tuning = require(Shared:WaitForChild("Config"):WaitForChild("Tuning"))

local BallController = require(script.Parent.BallController)

local FIELD_DIRECTION = Vector3.zAxis -- lanes fire down +Z (see WorldService)
local GROUND_Y = 0

local player = Players.LocalPlayer

type Phase = "beat" | "glide" | "follow" | "hold" | "return"

type Cam = {
	hitId: number,
	saved: CFrame, -- the batter view in world space (fallback when there is no root)
	-- The batter view relative to the batter's position (not their facing: a batter who turns
	-- while the ball flies still gets the view down the field back).
	savedOffset: CFrame?,
	captured: boolean, -- saved/savedOffset hold the real batter view (taken at the takeover)
	takeoverFrom: CFrame?, -- where the glide starts
	distance: number,
	phase: Phase,
	landing: Vector3?,
	phaseStart: number,
	returnFrom: CFrame?,
	cutSwapped: boolean,
	holdFor: number, -- seconds of catch reveal at the landing
	cutIn: boolean, -- the reveal's first shot has been cut to
}

local CameraController = {}

-- The catch reveal, for CatchRevealController (it draws the Mascot; this only times it):
--   RevealStarted (hitId, landing: Vector3, seconds, catch) when the camera starts holding
--   RevealEnded   (hitId, skipped: boolean) when it stops, however it stops
CameraController.RevealStarted = Signal.new()
CameraController.RevealEnded = Signal.new()

local cam: Cam? = nil
local fade: Frame
-- hitId -> reveal seconds and the catch, from the server's HitResult. Kept briefly.
local revealTimes: { [number]: { seconds: number, catch: any, at: number } } = {}
local REVEAL_MEMORY = 20
-- Optional shot for the reveal: (hitId, seconds since it started) -> where the camera should be.
local revealCamera: ((hitId: number, elapsed: number) -> CFrame?)? = nil

local function camera(): Camera
	return workspace.CurrentCamera
end

local function rootPart(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- The view to come back to, behind the batter where they stand now.
local function batterView(state: Cam): CFrame
	local root = rootPart()
	local offset = state.savedOffset
	if root and offset then
		return CFrame.new(root.Position) * offset
	end
	return state.saved
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

-- Call whenever a state leaves the reveal hold, however it leaves.
local function endReveal(state: Cam, skipped: boolean)
	if state.phase == "hold" then
		state.phase = "return" -- the caller sets up the rest; this just marks the reveal over
		CameraController.RevealEnded:Fire(state.hitId, skipped)
	end
end

-- Hands the camera back to Roblox. `snapBack` puts it at the saved batter view first.
local function restore(snapBack: boolean)
	local state = cam
	if state then
		endReveal(state, true)
	end
	cam = nil
	fade.BackgroundTransparency = 1
	local current = camera()
	if state and snapBack then
		current.CFrame = batterView(state)
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		current.CameraSubject = humanoid
	end
	current.CameraType = Enum.CameraType.Custom
end

local function beginReturn(state: Cam, skipped: boolean?)
	endReveal(state, skipped == true)
	state.phase = "return"
	state.phaseStart = os.clock()
	state.returnFrom = camera().CFrame
	state.cutSwapped = false
	-- The server may have corrected the flight's distance since launch; decide swoop or cut once.
	state.distance = BallController.GetDistance(state.hitId) or state.distance
end

-- Ends the beat: keeps the batter view (once per run of hits) and takes the camera over.
local function takeover(state: Cam)
	local current = camera()
	if not state.captured then
		state.captured = true
		state.saved = current.CFrame
		local root = rootPart()
		state.savedOffset = if root then current.CFrame - root.Position else nil
	end
	state.takeoverFrom = current.CFrame
	current.CameraType = Enum.CameraType.Scriptable
	state.phase = "glide"
	state.phaseStart = os.clock()
end

local function onLaunched(hitId: number, info: any)
	local previous = cam
	if previous then
		endReveal(previous, true) -- a new hit (lag let a pitch through) ends the old reveal
	end
	-- Stay on the batter for the beat: no Scriptable, no snap. A new hit keeps the old view.
	cam = {
		hitId = hitId,
		saved = if previous then previous.saved else camera().CFrame,
		savedOffset = if previous then previous.savedOffset else nil,
		captured = if previous then previous.captured else false,
		takeoverFrom = nil,
		distance = info.distance,
		phase = "beat",
		landing = nil,
		phaseStart = os.clock(),
		returnFrom = nil,
		cutSwapped = false,
		holdFor = 0,
		cutIn = false,
	}
	fade.BackgroundTransparency = 1
end

local function onTouchdown(
	hitId: number,
	_segment: number,
	position: Vector3,
	_distance: number,
	isFinal: boolean
)
	local state = cam
	if state == nil or state.hitId ~= hitId or not isFinal then
		return
	end
	local phase = state.phase
	if phase ~= "beat" and phase ~= "glide" and phase ~= "follow" then
		return
	end
	if phase == "beat" then
		takeover(state)
	end
	state.landing = position
	local reveal = revealTimes[hitId]
	revealTimes[hitId] = nil
	if reveal == nil then
		-- The server's result (and so the catch) isn't here yet: skip the reveal rather than
		-- make the player wait. The catch shows as a toast when it arrives.
		beginReturn(state)
		Remotes.Event("Ready"):FireServer(hitId)
		return
	end
	state.phase = "hold"
	state.holdFor = reveal.seconds
	state.phaseStart = os.clock()
	CameraController.RevealStarted:Fire(hitId, position, reveal.seconds, reveal.catch)
end

local function onHitResult(result: any)
	if type(result) ~= "table" or type(result.hitId) ~= "number" then
		return
	end
	local now = os.clock()
	for hitId, entry in revealTimes do
		if now - entry.at > REVEAL_MEMORY then
			revealTimes[hitId] = nil
		end
	end
	revealTimes[result.hitId] =
		{ seconds = Formulas.revealTime(result.catch), catch = result.catch, at = now }
	-- Keep the server's final distance for this hit: it decides swoop or cut on the way back.
	local state = cam
	if state and state.hitId == result.hitId and type(result.distance) == "number" then
		state.distance = result.distance
	end
end

local function step(dt: number)
	local state = cam
	if state == nil then
		return
	end
	local c = Tuning.Camera
	local current = camera()
	local now = os.clock()

	-- The ball was dropped: come back. No reveal will play, so let the server shorten its gap
	-- too (it ignores repeats).
	local function dropped()
		beginReturn(state)
		Remotes.Event("Ready"):FireServer(state.hitId)
	end

	if state.phase == "beat" then
		-- The Roblox camera still has the batter; only the clock is watched here.
		if BallController.GetBallPosition(state.hitId) == nil then
			takeover(state)
			dropped()
		elseif now - state.phaseStart >= Tuning.Fungo.CAMERA_BEAT then
			takeover(state)
		end
		return
	end

	if current.CameraType ~= Enum.CameraType.Scriptable then
		current.CameraType = Enum.CameraType.Scriptable -- something reset it mid-flight
	end

	if state.phase == "glide" then
		local ball = BallController.GetBallPosition(state.hitId)
		if ball == nil then
			dropped()
			return
		end
		local glide = Tuning.Fungo.CAMERA_GLIDE
		if state.distance > c.CUT_BEYOND then
			glide /= 2
		end
		local a = if glide > 0 then math.clamp((now - state.phaseStart) / glide, 0, 1) else 1
		local eased = a * a * (3 - 2 * a) -- smoothstep
		local from = state.takeoverFrom or current.CFrame
		current.CFrame = from:Lerp(chaseCFrame(ball, 0), eased)
		if a >= 1 then
			state.phase = "follow"
			state.phaseStart = now
		end
	elseif state.phase == "follow" then
		local ball = BallController.GetBallPosition(state.hitId)
		if ball == nil then
			dropped()
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
		local elapsed = now - state.phaseStart
		local shot = if revealCamera then revealCamera(state.hitId, elapsed) else nil
		if shot and not state.cutIn then
			state.cutIn = true
			current.CFrame = shot -- cut straight to the Mascot's view
		else
			current.CFrame = current.CFrame:Lerp(shot or chaseCFrame(landing, 3), smoothing(dt))
		end
		if elapsed >= state.holdFor then
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
				state.cutSwapped = true
				current.CFrame = batterView(state) -- follows the batter while fading in
				fade.BackgroundTransparency = math.min((elapsed - half) / half, 1)
				if elapsed >= c.CUT_TIME then
					restore(true)
				end
			end
		else
			local a = math.clamp(elapsed / c.RETURN_TIME, 0, 1)
			local eased = a * a * (3 - 2 * a) -- smoothstep
			current.CFrame = (state.returnFrom :: CFrame):Lerp(batterView(state), eased)
			if a >= 1 then
				restore(true)
			end
		end
	end
end

function CameraController.IsActive(): boolean
	return cam ~= nil
end

-- A tap during the catch reveal skips it: the camera heads back now and the server is told,
-- so the next pitch can come sooner (never sooner than its own minimum).
function CameraController.SkipReveal(): boolean
	local state = cam
	if state == nil or state.phase ~= "hold" then
		return false
	end
	beginReturn(state, true)
	Remotes.Event("Ready"):FireServer(state.hitId)
	return true
end

-- Sets the reveal's camera shot (CatchRevealController). Returning nil keeps the default view.
function CameraController.SetRevealCamera(fn: (hitId: number, elapsed: number) -> CFrame?)
	revealCamera = fn
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
	Remotes.Event("HitResult").OnClientEvent:Connect(onHitResult)
	-- A respawn mid-flight goes straight back to the (new) batter.
	player.CharacterAdded:Connect(function()
		local state = cam
		if state then
			if state.phase ~= "return" then
				-- The reveal is cut short: tell the server, so its gap matches the client's and
				-- the next tap after respawning still hits.
				Remotes.Event("Ready"):FireServer(state.hitId)
			end
			restore(false) -- the old batter view belongs to the old character
		end
	end)
	RunService:BindToRenderStep("BallCam", Enum.RenderPriority.Camera.Value + 1, step)
end

return CameraController
