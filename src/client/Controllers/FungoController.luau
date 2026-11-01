--!strict
-- FungoController: one tap = toss and swing in one motion (Tuning.Fungo). The batter turns to face
-- the field (and keeps walking: they strafe), the swing animation plays (SwingAnimator: toss,
-- load, swing, follow-through), the ball leaves the glove hand on its "Release" marker and comes
-- down onto the bat, which it follows as the batter moves; "Contact" plays the crack, sparks and
-- camera punch and starts the hit-stop, and the ball leaves the bat Fungo.CONTACT_AT after the
-- tap. It starts inside the hitting zone (shared/HitZone: from the bat, or the zone's nearest
-- point if the batter is outside it) and flies straight down +Z from the batter's X
-- (BallController.Launch). Every toss is a hit, with or without a lane.
-- A white swoosh trail follows the bat from the "SwooshOn" to the "SwooshOff" marker, with a
-- whoosh. Local only (others see the swing animation, not the trail).
--   FungoController.Toss() -> true if this tap tossed (or will, see below); false if a toss is
--                             already playing (one per cycle) or the game isn't ready yet.
-- The one way to swing in Fungo mode: taps (InputController) and, later, Auto-Swing both call
-- Toss, so they're identical (CLAUDE.md guardrail 6).
-- Swing(tossId) goes to the server at the tap; the server checks one hit per cycle and computes
-- the distance from stats only. The client shows everything at once and never waits.
-- The swing grows with Power (Formulas.swingTier): its own animation per tier (leg lift, hip
-- turn, finish), toss height, hit-stop, camera punch, the bat crack, sparks, dust and a
-- shockwave. Visual and audio only: the result and the cycle time are the same at every tier.
-- If the camera came back before the server's minimum gap (a skipped reveal), a tap is held
-- until then rather than dropped, so it still hits.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Formulas = require(Shared:WaitForChild("Formulas"))
local HitZone = require(Shared:WaitForChild("HitZone"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Signal = require(Shared:WaitForChild("Signal"))
local Tuning = require(Shared:WaitForChild("Config"):WaitForChild("Tuning"))

local Controllers = script.Parent
local BallController = require(Controllers.BallController)
local CameraController = require(Controllers.CameraController)
local StateController = require(Controllers.StateController)
local Modules = Controllers.Parent:WaitForChild("Modules")
local BatSwing = require(Modules:WaitForChild("BatSwing"))
local SwingAnimator = require(Modules:WaitForChild("SwingAnimator"))
local SwingData = require(Modules:WaitForChild("SwingData"))

local CRACK_SOUND = "rbxasset://sounds/snap.wav" -- built into the Roblox client
local BOOM_SOUND = "rbxasset://sounds/bass.wav" -- under the shockwave tiers
local WHOOSH_SOUND = "rbxasset://sounds/swordslash.wav" -- the swing, at SwooshOn (built in)
local TURN_TIME = 0.08 -- seconds to turn to face the field at the tap
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
local whoosh: Sound
local trail: Trail? = nil -- the local character's swoosh
local baseFov = 70

local busyUntil = 0 -- os.clock() this toss's swing is over
local nextReadyAt = 0 -- earliest the next toss may start (the server's minimum gap)
local held = false -- a tap is waiting for nextReadyAt
local lastId = 0 -- toss ids go up by one; the server refuses any it has seen
local turnId = 0 -- the latest facing turn; an older one never restores AutoRotate
local swooshId = 0 -- the latest swoosh; an older one's backup never turns it off

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
-- at `arriveAt` (os.clock()), then holds on `holdAt()` for the hit-stop until `launchAt`.
-- It moves with the batter: the path is relative to `base()` (the root's position now), and
-- `strikeAt()` is re-read every frame, so the ball meets the bat while they walk.
local function playToss(
	hand: Vector3,
	base: () -> Vector3,
	strikeAt: () -> Vector3,
	holdAt: () -> Vector3,
	height: number,
	startAt: number,
	arriveAt: number,
	launchAt: number
)
	-- A real throw under gravity: it leaves the hand, peaks `height` above the strike point and
	-- lands on it exactly at `arriveAt`. Solve the gravity and launch speed that do that:
	--   peak above the hand  A = strike.Y + height - hand.Y = v^2 / (2g)
	--   drop at the end      B = strike.Y - hand.Y          = v T - g T^2 / 2
	local origin = base()
	local handRel = hand - origin
	local strike0 = strikeAt() - origin
	local flight = math.max(arriveAt - startAt, 0.05)
	local above = math.max(strike0.Y + height - handRel.Y, 0.1)
	local drop = strike0.Y - handRel.Y
	local root = (math.sqrt(2 * above) + math.sqrt(math.max(2 * (above - drop), 0))) / flight
	local gravity = root * root
	local up = math.sqrt(2 * gravity * above)
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
		if now < arriveAt then
			local t = math.max(now - startAt, 0)
			local a = t / flight
			local at = base()
			local strike = strikeAt() - at
			local flat = handRel:Lerp(strike, a)
			-- The solved arc, plus any change in the strike height since the release (a jump).
			local y = handRel.Y + up * t - gravity * t * t / 2 + (strike.Y - strike0.Y) * a
			tossBall.Position = at + Vector3.new(flat.X, y, flat.Z)
		else
			tossBall.Position = holdAt() -- hit-stop: on the bat
		end
	end)
end

-- Where a hit's ball starts: the bat's point inside the hitting zone (or behind it, between its
-- sides), else the zone's nearest point. Every tap hits from somewhere in the zone.
local function ballStart(point: Vector3): Vector3
	local back = Tuning.World.HIT_ZONE.back
	if HitZone.contains(point) or (point.Z < back and math.abs(point.X) <= HitZone.halfWidth()) then
		return point
	end
	return HitZone.clamp(point)
end

-- The swoosh: a white trail between the bat's TrailBase and TrailTip (WorldService), made once
-- per character. Width comes from the attachments' distance, so TrailBase is moved along the bat
-- for each tier (a local change). Visual only.
local function setupTrail(character: Model)
	trail = nil
	local bat = character:WaitForChild("Bat", 10)
	if bat == nil or not bat:IsA("BasePart") then
		return
	end
	local base = bat:WaitForChild("TrailBase", 5)
	local tip = bat:WaitForChild("TrailTip", 5)
	if base == nil or tip == nil or not base:IsA("Attachment") or not tip:IsA("Attachment") then
		return
	end
	if player.Character ~= character then
		return
	end
	local t = Instance.new("Trail")
	t.Name = "Swoosh"
	t.Attachment0 = base
	t.Attachment1 = tip
	t.Color = ColorSequence.new(Color3.new(1, 1, 1))
	t.LightEmission = 1
	t.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	t.FaceCamera = false
	t.MinLength = 0
	t.Enabled = false
	t.Parent = bat
	trail = t
end

local function swooshOn(tier: any)
	local t = trail
	if t and t.Parent then
		local options = settings()
		local look = tier.swoosh or { lifetime = 0.12, width = 1.5 }
		local base = t.Attachment0 :: Attachment
		local tip = t.Attachment1 :: Attachment
		local handleEnd = -(base.Parent :: BasePart).Size.X / 2
		base.Position = Vector3.new(math.max(tip.Position.X - look.width, handleEnd), 0, 0)
		t.Lifetime = if options.lowGraphics then look.lifetime / 2 else look.lifetime
		t:Clear()
		t.Enabled = true
	end
	swooshId += 1
	local id = swooshId
	-- Backup for a SwooshOff marker that never fires.
	task.delay(0.5, function()
		if swooshId == id and trail then
			trail.Enabled = false
		end
	end)
	if settings().sfx ~= false then
		whoosh.TimePosition = 0
		whoosh:Play()
	end
end

local function swooshOff()
	if trail then
		trail.Enabled = false
	end
end

-- Where the bat's barrel meets the ball right now (BatPose: the barrel's sweet spot).
local SWEET_SPOT = 2.45 -- studs from the bat part's centre along the bat (tools/animations/generate.py)
local function batSweetSpot(character: Model): Vector3?
	local bat = character:FindFirstChild("Bat")
	if bat == nil or not bat:IsA("BasePart") then
		return nil
	end
	return bat.CFrame:PointToWorldSpace(Vector3.new(SWEET_SPOT, 0, 0))
end

local function startToss(): boolean
	local data = StateController.Get()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if data == nil or character == nil or root == nil then
		return false
	end
	local body = character :: Model
	local rootPart = root :: BasePart
	local f = Tuning.Fungo
	local now = os.clock()
	lastId += 1
	local hitId = lastId
	BallController.BeginToss(hitId)
	Remotes.Event("Swing"):FireServer(hitId)

	local tier, tierIndex = Formulas.swingTier(data.power)
	busyUntil = now + math.max(f.CYCLE, f.CONTACT_AT + 0.1) -- never a second toss mid-toss
	local predicted = BallController.PredictDistance()
	nextReadyAt = now + f.CONTACT_AT + Formulas.ballCamTime(predicted, Tuning.Reveal.MIN_SHOWN)

	-- Where the bat meets the ball: the animation's contact point (SwingData), else in front of
	-- the batter, relative to the root facing the field.
	local tierData = if SwingAnimator.HasSwing(tierIndex) then SwingData.TIERS[tierIndex] else nil
	local contactAt = if tierData then tierData.contact else f.CONTACT_AT

	-- Turn to face the field over TURN_TIME; walking carries on (only the rotation is set).
	-- AutoRotate comes back just after contact.
	local humanoid = body:FindFirstChildOfClass("Humanoid")
	turnId += 1
	local myTurn = turnId
	if humanoid then
		local h: Humanoid = humanoid
		h.AutoRotate = false
		local look = rootPart.CFrame.LookVector
		local fromYaw = math.atan2(-look.X, -look.Z)
		local toYaw = math.pi -- facing +Z
		local delta = (toYaw - fromYaw + math.pi) % (2 * math.pi) - math.pi
		local turn: RBXScriptConnection
		turn = RunService.RenderStepped:Connect(function()
			local a = math.clamp((os.clock() - now) / TURN_TIME, 0, 1)
			if rootPart.Parent == nil or turnId ~= myTurn then
				turn:Disconnect()
				return
			end
			rootPart.CFrame = CFrame.new(rootPart.Position) * CFrame.Angles(0, fromYaw + delta * a, 0)
			if a >= 1 then
				turn:Disconnect()
			end
		end)
		task.delay(contactAt + 0.1, function()
			if turnId == myTurn and h.Parent then
				h.AutoRotate = true
			end
		end)
	end

	-- The contact point follows the batter: recomputed from where the root is now.
	local function base(): Vector3
		return rootPart.Position
	end
	local function strikeAt(): Vector3
		local facing = CFrame.lookAt(rootPart.Position, rootPart.Position + FIELD)
		if tierData then
			return facing:PointToWorldSpace(tierData.point)
		end
		local front = facing:PointToWorldSpace(Vector3.new(f.STRIKE_SIDE, 0, -f.STRIKE_FORWARD))
		return Vector3.new(front.X, Tuning.World.STRIKE_HEIGHT, front.Z)
	end
	local contacted = false
	-- Where the ball is on the bat: after Contact, the bat's real sweet spot (the baked point
	-- fits the default body; other proportions put the bat elsewhere).
	local function onBat(): Vector3
		if contacted then
			return batSweetSpot(body) or strikeAt()
		end
		return strikeAt()
	end
	local function handPosition(): Vector3
		local handPart = body:FindFirstChild("LeftHand") or body:FindFirstChild("Left Arm")
		return if handPart and handPart:IsA("BasePart") then handPart.Position else rootPart.Position
	end

	local launchAt = now + f.CONTACT_AT
	local launched, impacted = false, false
	local function impact()
		if not impacted then
			impacted = true
			playImpact(tier, onBat())
		end
	end
	local function launch()
		if launched then
			return
		end
		launched = true
		impact()
		SwingAnimator.ContactDone()
		local strike = ballStart(onBat())
		BallController.Launch(hitId, strike, HitZone.lineOrigin(strike.X), { trailWidth = tier.trailWidth })
		FungoController.Contact:Fire(hitId, tierIndex)
	end

	local animated = SwingAnimator.Swing(tierIndex, {
		-- The glove hand lets go: the ball goes up and comes down onto the bat at contact.
		release = function()
			playToss(
				handPosition(),
				base,
				strikeAt,
				onBat,
				tier.tossHeight,
				os.clock(),
				now + contactAt,
				launchAt
			)
		end,
		-- Bat on ball: crack, sparks and camera punch now; the ball leaves the bat after the
		-- hit-stop, which the animation holds (so it's always CONTACT_AT after the tap).
		contact = function()
			contacted = true
			impact()
			task.delay(math.max(launchAt - os.clock(), 0), launch)
		end,
		swooshOn = function()
			swooshOn(tier)
		end,
		swooshOff = swooshOff,
	})
	if animated then
		-- Backup for a marker that never fires (an animation that didn't load in time).
		task.delay(f.CONTACT_AT + 0.15, launch)
	else
		-- The simple swing (R6, or no animation ids outside Studio).
		local arriveAt = launchAt - tier.hitStop
		playToss(handPosition(), base, strikeAt, strikeAt, tier.tossHeight, now, arriveAt, launchAt)
		local s = Tuning.Swing
		task.delay(math.max(arriveAt - now - s.TO_CONTACT, 0), function()
			BatSwing.Play(player.Character, {
				toContact = s.TO_CONTACT,
				hold = tier.hitStop,
				follow = s.FOLLOW_THROUGH,
				recover = s.RECOVER,
			})
		end)
		task.delay(math.max(arriveAt - now - 0.1, 0), function()
			swooshOn(tier)
		end)
		task.delay(arriveAt - now + 0.15, swooshOff)
		task.delay(f.CONTACT_AT, launch)
	end
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
	whoosh = sound(WHOOSH_SOUND)
	whoosh.Volume = 0.5
end

function FungoController.Start()
	baseFov = workspace.CurrentCamera.FieldOfView
	SwingAnimator.Start(CameraController.IsActive)
	player.CharacterAdded:Connect(function(character)
		turnId += 1 -- a fresh Humanoid already has AutoRotate on
		task.spawn(setupTrail, character)
	end)
	if player.Character then
		task.spawn(setupTrail, player.Character)
	end
	-- Ids must keep going up past the server's: start after any hit it already knows.
	Remotes.Event("HitResult").OnClientEvent:Connect(function(result: any)
		if type(result) == "table" and type(result.hitId) == "number" and result.hitId > lastId then
			lastId = result.hitId
		end
	end)
end

return FungoController
