--!strict
-- CatchController: the POV catch. When a landing catches something (HitResult.catch), the
-- landing hold becomes a short scripted shot seen through the creature's own eyes, live in the
-- real scene (no video): it blinks awake near the orb, looks around the biome, spots the orb,
-- moves in, and is pulled inside in a flash of light. The creature's body is never shown; the
-- vignette takes its rarity colour (the first hint) and the orb lights up in it.
--   Full POV (Reveal.FULL): Rare and up, and a player's first catch. Short POV (Reveal.SHORT):
--   Common and Uncommon. A tap skips at any point (CameraController.SkipReveal).
--   One template for every catch: the spot near the landing, the eye height and the look-around
--   are random each time. Visual only: the server has already decided the catch.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Rarities = require(Config:WaitForChild("Rarities"))
local Tuning = require(Config:WaitForChild("Tuning"))

local BallController = require(script.Parent.BallController)
local CameraController = require(script.Parent.CameraController)

local player = Players.LocalPlayer

local LANE_HALF = 37 -- the spot stays this far from the lane's centre (walls at 42.5)
local FULL_LENGTH = 3 -- seconds the full timeline is written for (scaled to Reveal.FULL)
local SHORT_LENGTH = 1 -- and the short one (scaled to Reveal.SHORT)
local BASE_FOV = 70

type Shot = {
	hitId: number,
	full: boolean,
	scale: number, -- timeline seconds per real second
	orb: Vector3,
	eye: Vector3,
	stop: Vector3, -- where the creature ends up, just short of the orb
	away: Vector3, -- where it first looks (away from the orb)
	sweep: Vector3, -- where the look-around ends, before it spots the orb
	color: Color3,
	mythic: boolean,
	savedFov: number,
}

local CatchController = {}

local shot: Shot? = nil
local rng = Random.new()

local gui: ScreenGui
local lidTop: Frame
local lidBottom: Frame
local flash: Frame
local vignette: { Frame } = {}

local function smooth(a: number): number
	a = math.clamp(a, 0, 1)
	return a * a * (3 - 2 * a)
end

-- 0 before `a`, 1 after `b`, eased between.
local function span(t: number, a: number, b: number): number
	return smooth((t - a) / (b - a))
end

local function rotateY(v: Vector3, radians: number): Vector3
	return CFrame.Angles(0, radians, 0):VectorToWorldSpace(v)
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-3 then f.Unit else Vector3.zAxis
end

local function rayParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character :: Instance }
	return params
end

-- A spot near the orb where a creature could be: on the floor or a ledge, inside the lane, with
-- a clear view of the orb.
local function pickEye(orb: Vector3, radius: number): Vector3
	local params = rayParams()
	for _ = 1, 16 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local r = radius * rng:NextNumber(0.8, 1.15)
		local p = orb + Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
		if math.abs(p.X) <= LANE_HALF then
			local down = workspace:Raycast(p + Vector3.new(0, 30, 0), Vector3.new(0, -60, 0), params)
			if down and down.Position.Y < orb.Y + 6 then
				local eye = down.Position + Vector3.new(0, rng:NextNumber(2.2, 4.5), 0)
				local toOrb = orb - eye
				local blocked = workspace:Raycast(eye, toOrb.Unit * (toOrb.Magnitude - 1), params)
				local roof = workspace:Raycast(eye, Vector3.new(0, 3, 0), params)
				if blocked == nil and roof == nil then
					return eye
				end
			end
		end
	end
	return orb + Vector3.new(0, 4, -radius) -- nothing better: behind the orb, looking down the lane
end

local function setLids(closed: number)
	local h = 0.5 * math.clamp(closed, 0, 1)
	lidTop.Size = UDim2.fromScale(1, h)
	lidBottom.Size = UDim2.fromScale(1, h)
	lidTop.Visible = h > 0
	lidBottom.Visible = h > 0
end

local function setVignette(color: Color3, strength: number)
	for _, edge in vignette do
		edge.BackgroundColor3 = color
		edge.BackgroundTransparency = 1 - 0.75 * math.clamp(strength, 0, 1)
		edge.Visible = strength > 0
	end
end

local function clearOverlay()
	setLids(0)
	setVignette(Color3.new(), 0)
	flash.BackgroundTransparency = 1
	gui.Enabled = false
end

-- The full POV, in timeline seconds (0 to 3).
local function fullShot(s: Shot, t: number): (CFrame, number)
	-- Eyes: closed, open slowly (just woken), one blink.
	local lids = 1 - span(t, 0.15, 0.42)
	if t > 0.55 and t < 0.75 then
		lids = math.max(lids, 1 - math.abs(t - 0.64) / 0.09)
	end
	setLids(lids)

	-- Where it looks: away, around, then it spots the orb.
	local toOrb = flat(s.orb - s.eye)
	local look: Vector3
	if t < 0.55 then
		look = rotateY(s.away, 0.15 * t)
	elseif t < 1.25 then
		local a = span(t, 0.55, 1.25)
		look = s.away:Lerp(s.sweep, a).Unit
	else
		local a = math.clamp((t - 1.25) / 0.18, 0, 1)
		a = 1 - (1 - a) ^ 3 -- the head snaps round
		look = s.sweep:Lerp(toOrb, a).Unit
	end
	local pitch = -0.25 * (1 - span(t, 0.1, 0.6)) -- groggy, looking down at first

	-- Where it is: still, then hops in on the orb.
	local move = span(t, 1.6, 2.55)
	local pos = s.eye:Lerp(s.stop, move)
	local hop = math.abs(math.sin(move * math.pi * 3)) * 0.9 * (1 - move)
	pos += Vector3.new(0, hop + math.sin(t * 5) * 0.04, 0)

	local target: Vector3
	if t >= 1.43 then
		target = s.orb -- locked on
	else
		target = pos + look * 10 + Vector3.new(0, pitch * 10, 0)
	end
	-- A curious head tilt when it spots the orb.
	local tilt = 0.14 * (span(t, 1.3, 1.45) - span(t, 1.6, 1.9))
	-- After the capture, back off a little and look at the lit orb.
	if t > 2.65 then
		local back = span(t, 2.65, 3)
		pos += (s.stop - s.orb).Unit * 2.5 * back + Vector3.new(0, 0.8 * back, 0)
		target = s.orb
	end

	-- Field of view: a punch-in on spotting it, a tighter one on the grab.
	local fov = BASE_FOV - 12 * (span(t, 1.28, 1.42) - span(t, 1.45, 1.9) * 0.5)
	fov -= 14 * (span(t, 2.4, 2.62) - span(t, 2.68, 3))

	-- The vignette (rarity hint), the orb lighting up, the flash as it's pulled in.
	setVignette(s.color, span(t, 0.05, 0.4) * (1 - span(t, 2.75, 3) * 0.5))
	BallController.SetGlow(s.hitId, s.color, span(t, 1.5, 2.6))
	flash.BackgroundTransparency = 1 - (span(t, 2.52, 2.62) - span(t, 2.66, 2.95))

	return CFrame.lookAt(pos, target) * CFrame.Angles(0, 0, tilt), fov
end

-- The short POV, in timeline seconds (0 to 1): open, it's already looking, it grabs.
local function shortShot(s: Shot, t: number): (CFrame, number)
	setLids(1 - span(t, 0.06, 0.2))
	local move = span(t, 0.18, 0.7)
	local pos = s.eye:Lerp(s.stop, move)
	pos += Vector3.new(0, math.abs(math.sin(move * math.pi * 2)) * 0.6 * (1 - move), 0)
	local settle = 1 - span(t, 0, 0.3)
	local target = s.orb + (s.sweep * 3 * settle)
	local fov = BASE_FOV - 12 * (span(t, 0.5, 0.72) - span(t, 0.76, 1))
	setVignette(s.color, span(t, 0, 0.2) * (1 - span(t, 0.85, 1) * 0.5))
	BallController.SetGlow(s.hitId, s.color, span(t, 0.3, 0.74))
	flash.BackgroundTransparency = 1 - (span(t, 0.68, 0.74) - span(t, 0.76, 0.96))
	return CFrame.lookAt(pos, target), fov
end

local function revealCamera(hitId: number, elapsed: number): CFrame?
	local s = shot
	if s == nil or s.hitId ~= hitId then
		return nil
	end
	if s.mythic then
		s.color = Color3.fromHSV((os.clock() * 0.35) % 1, 0.65, 1) -- Mythic's rainbow
	end
	local t = elapsed * s.scale
	local cf, fov
	if s.full then
		cf, fov = fullShot(s, t)
	else
		cf, fov = shortShot(s, t)
	end
	workspace.CurrentCamera.FieldOfView = fov
	return cf
end

local function onRevealStarted(hitId: number, landing: Vector3, seconds: number, catch: any)
	if type(catch) ~= "table" or type(catch.rarity) ~= "string" then
		return
	end
	local rarity = Rarities[1]
	for _, r in Rarities do
		if r.id == catch.rarity then
			rarity = r
		end
	end
	local full = catch.full == true
	local eye = pickEye(landing, if full then 16 else 9)
	local toOrb = flat(landing - eye)
	local side = if rng:NextNumber() < 0.5 then 1 else -1
	local previous = shot
	shot = {
		hitId = hitId,
		full = full,
		scale = (if full then FULL_LENGTH else SHORT_LENGTH) / math.max(seconds, 0.1),
		orb = landing,
		eye = eye,
		stop = landing - toOrb * 1.8 + Vector3.new(0, 0.5, 0),
		away = rotateY(toOrb, side * rng:NextNumber(1.9, 2.6)),
		sweep = rotateY(toOrb, side * rng:NextNumber(0.6, 0.9)),
		color = rarity.color,
		mythic = rarity.id == "mythic",
		savedFov = if previous then previous.savedFov else workspace.CurrentCamera.FieldOfView,
	}
	gui.Enabled = true
	setLids(1) -- it starts asleep
end

local function onRevealEnded(hitId: number, _skipped: boolean)
	local s = shot
	if s == nil or s.hitId ~= hitId then
		return
	end
	shot = nil
	workspace.CurrentCamera.FieldOfView = s.savedFov
	BallController.SetGlow(hitId, s.color, 1) -- the catch stays glowing inside the orb
	clearOverlay()
end

function CatchController.Init() end

local function edge(name: string, size: UDim2, position: UDim2, rotation: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.Size = size
	f.Position = position
	f.Visible = false
	local g = Instance.new("UIGradient")
	g.Rotation = rotation -- opaque at the screen's edge, clear toward the middle
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	g.Parent = f
	f.Parent = gui
	return f
end

function CatchController.Start()
	gui = Instance.new("ScreenGui")
	gui.Name = "CatchPOV"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 40 -- under the ball-cam's fade
	gui.Enabled = false

	local thick = 0.24
	table.insert(vignette, edge("Top", UDim2.fromScale(1, thick), UDim2.fromScale(0, 0), 90))
	table.insert(vignette, edge("Bottom", UDim2.fromScale(1, thick), UDim2.fromScale(0, 1 - thick), -90))
	table.insert(vignette, edge("Left", UDim2.fromScale(thick * 0.6, 1), UDim2.fromScale(0, 0), 0))
	table.insert(
		vignette,
		edge("Right", UDim2.fromScale(thick * 0.6, 1), UDim2.fromScale(1 - thick * 0.6, 0), 180)
	)

	local function lid(name: string, anchorY: number): Frame
		local f = Instance.new("Frame")
		f.Name = name
		f.BackgroundColor3 = Color3.new(0, 0, 0)
		f.BorderSizePixel = 0
		f.AnchorPoint = Vector2.new(0, anchorY)
		f.Position = UDim2.fromScale(0, anchorY)
		f.Size = UDim2.fromScale(1, 0)
		f.Visible = false
		-- A soft edge, so the lid reads as an eyelid and not a letterbox.
		local soft = Instance.new("Frame")
		soft.BackgroundColor3 = Color3.new(0, 0, 0)
		soft.BorderSizePixel = 0
		soft.Size = UDim2.fromScale(1, 0.25)
		soft.Position = if anchorY == 0 then UDim2.fromScale(0, 1) else UDim2.fromScale(0, -0.25)
		local g = Instance.new("UIGradient")
		g.Rotation = if anchorY == 0 then 90 else -90
		g.Transparency = NumberSequence.new(0, 1)
		g.Parent = soft
		soft.Parent = f
		f.Parent = gui
		return f
	end
	lidTop = lid("LidTop", 0)
	lidBottom = lid("LidBottom", 1)

	flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.Size = UDim2.fromScale(1, 1)
	flash.Parent = gui

	gui.Parent = player:WaitForChild("PlayerGui")

	CameraController.SetRevealCamera(revealCamera)
	CameraController.RevealStarted:Connect(onRevealStarted)
	CameraController.RevealEnded:Connect(onRevealEnded)
	-- Tuning is read so the timelines scale with Reveal.FULL / Reveal.SHORT if they change.
	assert(Tuning.Reveal.FULL > 0 and Tuning.Reveal.SHORT > 0, "Reveal times must be positive")
end

return CatchController
