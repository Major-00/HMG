--!strict
-- FungoController: one tap = toss and swing in one motion (Tuning.Fungo). The batter turns to the
-- field, tosses the ball up with the left hand and hits it from wherever they stand in the
-- hitting circle; the ball flies down their lane (BallController.Launch). Every toss is a hit.
--   FungoController.Toss() -> true if this tap tossed (or will, see below); false if a toss is
--                             already playing (one per cycle) or the game isn't ready yet.
-- The one way to swing in Fungo mode: taps (InputController) and, later, Auto-Swing both call
-- Toss, so they're identical (CLAUDE.md guardrail 6).
-- Swing(tossId) goes to the server at the tap; the server checks one hit per cycle and computes
-- the distance from stats only. The client shows everything at once and never waits.
-- The swing grows with Power (Formulas.swingTier): toss height, hit-stop, camera punch, the
-- bat crack, sparks, dust and a shockwave. Visual and audio only: the result and the cycle time
-- are the same at every tier.
-- If the camera came back before the server's minimum gap (a skipped reveal), a tap is held
-- until then rather than dropped, so it still hits.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Formulas = require(Shared:WaitForChild("Formulas"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Signal = require(Shared:WaitForChild("Signal"))
local Tuning = require(Shared:WaitForChild("Config"):WaitForChild("Tuning"))

local Controllers = script.Parent
local BallController = require(Controllers.BallController)
local CameraController = require(Controllers.CameraController)
local PitcherController = require(Controllers.PitcherController)
local StateController = require(Controllers.StateController)
local BatSwing = require(Controllers.Parent:WaitForChild("Modules"):WaitForChild("BatSwing"))

local CRACK_SOUND = "rbxasset://sounds/snap.wav" -- built into the Roblox client
local BOOM_SOUND = "rbxasset://sounds/bass.wav" -- under the shockwave tiers
local BALL_SIZE = 0.9
local FIELD = Vector3.zAxis -- lanes fire down +Z

local player = Players.LocalPlayer

local FungoController = {}

-- Fired at bat-on-ball: (hitId, tierIndex). For tests and future polish.
FungoController.Contact = Signal.new()

local folder: Folder
local tossBall: Part
local sparkPart: Part
local sparks: ParticleEmitter
local dustPart: Part
local dust: ParticleEmitter
local ring: Part
local crack: Sound
local boom: Sound
local baseFov = 70

local busyUntil = 0 -- os.clock() this toss's swing is over
local nextReadyAt = 0 -- earliest the next toss may start (the server's minimum gap)
local held = false -- a tap is waiting for nextReadyAt
local lastId = 0 -- toss ids go up by one; the server refuses any it has seen

local function settings(): any
	local data = StateController.Get()
	return data and data.settings or {}
end

local function anchoredPart(name: string): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.Parent = folder
	return p
end

local function sound(id: string): Sound
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Parent = SoundService -- 2D: heard the same while the ball-cam flies away
	return s
end

-- Bat-on-ball effects for a tier at `strike`. Visual and audio only.
local function playImpact(tier: any, strike: Vector3)
	local options = settings()
	local budget = if options.lowGraphics then 0.5 else 1

	if options.sfx ~= false then
		crack.Volume = tier.crackVolume
		crack.PlaybackSpeed = tier.crackPitch
		crack.TimePosition = 0
		crack:Play()
		if tier.shockwave then
			boom.Volume = tier.crackVolume * 0.8
			boom.TimePosition = 0
			boom:Play()
		end
	end

	if tier.sparks > 0 then
		sparkPart.Position = strike
		sparks:Emit(math.max(1, math.floor(tier.sparks * budget)))
	end
	local ground = Vector3.new(strike.X, 0.2, strike.Z)
	if tier.dust > 0 then
		dustPart.Position = ground
		dust:Emit(math.max(1, math.floor(tier.dust * budget)))
	end
	local wave = tier.shockwave
	if wave then
		ring.CFrame = CFrame.new(ground) * CFrame.Angles(0, 0, math.rad(90))
		ring.Size = Vector3.new(0.1, 1, 1)
		ring.Transparency = 0.25
		TweenService
			:Create(ring, TweenInfo.new(wave.time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = Vector3.new(0.1, wave.size, wave.size),
				Transparency = 1,
			})
			:Play()
	end

	if tier.punch > 0 then
		local camera = workspace.CurrentCamera
		camera.FieldOfView = baseFov - tier.punch
		TweenService:Create(camera, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			FieldOfView = baseFov,
		}):Play()
	end
end

-- Moves the tossed ball: up from the hand to the apex, then down to the strike point, arriving
-- at `arriveAt` (os.clock()), then holds there for the hit-stop until `launchAt`.
local function playToss(
	hand: Vector3,
	strike: Vector3,
	height: number,
	startAt: number,
	arriveAt: number,
	launchAt: number
)
	local apex = strike + Vector3.new(0, height, 0)
	local rise = (arriveAt - startAt) * Tuning.Fungo.TOSS_RISE
	tossBall.Position = hand
	tossBall.Transparency = 0
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local now = os.clock()
		if now >= launchAt then
			connection:Disconnect()
			tossBall.Transparency = 1
			return
		end
		local t = now - startAt
		if t < rise then
			local a = t / rise
			tossBall.Position = hand:Lerp(apex, 1 - (1 - a) * (1 - a)) -- ease out going up
		elseif now < arriveAt then
			local a = (t - rise) / math.max(arriveAt - startAt - rise, 0.001)
			tossBall.Position = apex:Lerp(strike, a * a) -- ease in coming down
		else
			tossBall.Position = strike -- hit-stop: frozen on the bat
		end
	end)
end

local function startToss(): boolean
	local data = StateController.Get()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local lane = PitcherController.GetLane()
	local laneStrikeAt = lane and lane:FindFirstChild("StrikePoint", true) :: Attachment?
	if data == nil or root == nil or laneStrikeAt == nil then
		return false
	end
	local f = Tuning.Fungo
	local now = os.clock()
	lastId += 1
	local hitId = lastId
	BallController.BeginToss(hitId)
	Remotes.Event("Swing"):FireServer(hitId)

	local tier, tierIndex = Formulas.swingTier(data.power)
	busyUntil = now + f.CYCLE
	local predicted = BallController.PredictDistance()
	nextReadyAt = now + f.CONTACT_AT + Formulas.ballCamTime(predicted, Tuning.Reveal.MIN_SHOWN)

	-- Face the field, then work out where the ball is hit: in front of the batter, at strike
	-- height, from wherever they stand.
	local facing = CFrame.lookAt(root.Position, root.Position + FIELD)
	root.CFrame = facing
	local front = facing:PointToWorldSpace(Vector3.new(f.STRIKE_SIDE, 0, -f.STRIKE_FORWARD))
	local laneStrike = laneStrikeAt.WorldPosition
	-- From anywhere in the hitting circle; a tap from outside it still hits, from the nearest
	-- point of the circle, so the ball always starts in the player's own lane.
	local offset = Vector3.new(front.X - laneStrike.X, 0, front.Z - laneStrike.Z)
	local radius = Tuning.World.HIT_CIRCLE_RADIUS
	if offset.Magnitude > radius then
		offset = offset.Unit * radius
	end
	local strike = Vector3.new(laneStrike.X + offset.X, Tuning.World.STRIKE_HEIGHT, laneStrike.Z + offset.Z)
	local handPart = (character :: Model):FindFirstChild("LeftHand")
		or (character :: Model):FindFirstChild("Left Arm")
	local hand = if handPart and handPart:IsA("BasePart") then handPart.Position else root.Position

	-- The ball always launches at CONTACT_AT; the hit-stop is taken from the toss.
	local launchAt = now + f.CONTACT_AT
	local arriveAt = launchAt - tier.hitStop
	playToss(hand, strike, tier.tossHeight, now, arriveAt, launchAt)
	local s = Tuning.Swing
	task.delay(math.max(arriveAt - now - s.TO_CONTACT, 0), function()
		BatSwing.Play(player.Character, {
			toContact = s.TO_CONTACT,
			hold = tier.hitStop,
			follow = s.FOLLOW_THROUGH,
			recover = s.RECOVER,
		})
	end)
	task.delay(f.CONTACT_AT, function()
		BallController.Launch(hitId, strike, laneStrike, { trailWidth = tier.trailWidth })
		playImpact(tier, strike)
		FungoController.Contact:Fire(hitId, tierIndex)
	end)
	return true
end

function FungoController.Toss(): boolean
	if CameraController.IsActive() then
		return false -- the ball-cam is away (InputController skips the reveal instead)
	end
	local now = os.clock()
	if now < busyUntil then
		return false -- one toss per cycle
	end
	if now < nextReadyAt then
		-- The camera is back but the server's minimum gap isn't over (a skipped reveal): hold
		-- this tap until then so it still hits. Only one tap is held.
		if not held then
			held = true
			task.delay(nextReadyAt - now, function()
				held = false
				if not CameraController.IsActive() and os.clock() >= busyUntil then
					startToss()
				end
			end)
		end
		return true
	end
	return startToss()
end

function FungoController.Init()
	folder = Instance.new("Folder")
	folder.Name = "Fungo"
	folder.Parent = workspace

	tossBall = anchoredPart("TossBall")
	tossBall.Shape = Enum.PartType.Ball
	tossBall.Size = Vector3.new(BALL_SIZE, BALL_SIZE, BALL_SIZE)
	tossBall.Color = Color3.fromRGB(250, 250, 245)
	tossBall.Material = Enum.Material.SmoothPlastic

	sparkPart = anchoredPart("Sparks")
	sparks = Instance.new("ParticleEmitter")
	sparks.Enabled = false
	sparks.Rate = 0
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 245, 200), Color3.fromRGB(255, 170, 60))
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new(0.35, 0)
	sparks.Lifetime = NumberRange.new(0.2, 0.4)
	sparks.Speed = NumberRange.new(14, 26)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Drag = 4
	sparks.Parent = sparkPart

	dustPart = anchoredPart("Dust")
	dust = Instance.new("ParticleEmitter")
	dust.Enabled = false
	dust.Rate = 0
	dust.Color = ColorSequence.new(Color3.fromRGB(205, 175, 135))
	dust.Size = NumberSequence.new(1.2, 3.5)
	dust.Transparency = NumberSequence.new(0.35, 1)
	dust.Lifetime = NumberRange.new(0.5, 0.8)
	dust.Speed = NumberRange.new(6, 12)
	dust.SpreadAngle = Vector2.new(70, 70) -- up and out: the lift-off
	dust.Acceleration = Vector3.new(0, -6, 0)
	dust.Drag = 3
	dust.EmissionDirection = Enum.NormalId.Top
	dust.Parent = dustPart

	ring = anchoredPart("Shockwave")
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(255, 235, 190)

	crack = sound(CRACK_SOUND)
	boom = sound(BOOM_SOUND)
	boom.PlaybackSpeed = 0.6
end

function FungoController.Start()
	baseFov = workspace.CurrentCamera.FieldOfView
	-- Ids must keep going up past the server's: start after any hit it already knows.
	Remotes.Event("HitResult").OnClientEvent:Connect(function(result: any)
		if type(result) == "table" and type(result.hitId) == "number" and result.hitId > lastId then
			lastId = result.hitId
		end
	end)
end

return FungoController
