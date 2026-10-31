--!strict
-- CatchRevealController: the catch reveal. While the ball-cam holds on the landing
-- (CameraController.RevealStarted .. RevealEnded) a placeholder Mascot of the caught species
-- runs in, hops and catches the ball, turns to the camera, and its name types in letter by letter.
-- The camera watches from the Mascot's side (SetRevealCamera). The full version (new species,
-- Rare and up) runs in from farther and shows the rarity, variant and size; the short one is
-- quick. A tap skips it (CameraController.SkipReveal).
-- Visual only (CLAUDE.md guardrail 4): the catch was decided by the server before the ball landed.
-- Cheap on low-end phones: a dozen anchored, non-colliding parts, gone when the reveal ends.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Mascots = require(Config:WaitForChild("Mascots"))
local Tuning = require(Config:WaitForChild("Tuning"))

local BallController = require(script.Parent.BallController)
local CameraController = require(script.Parent.CameraController)

local GROUND_Y = 0
local UP = Vector3.yAxis
local REACH = 1.45 -- studs (times its size) in front of its feet where it holds the ball

type Piece = { part: BasePart, offset: CFrame }

type Reveal = {
	hitId: number,
	full: boolean,
	seconds: number,
	startedAt: number,
	scale: number,
	ballPos: Vector3, -- where the ball lies
	stopAt: Vector3, -- where the Mascot's feet stop to catch it (just short of the ball)
	ended: boolean?, -- the reveal is over; the Mascot stays briefly while the camera leaves
	from: Vector3, -- where the Mascot starts running
	toBall: Vector3, -- unit, horizontal: from the start toward the ball
	side: number, -- 1 or -1: which side it came in from (the camera sits on that side)
	runEnd: number, -- seconds: reaches the ball
	caught: boolean,
	model: Model,
	pieces: { Piece },
	carried: BasePart, -- the ball in the Mascot's hands, shown from the catch
	name: string,
	sub: string,
	color: Color3,
}

local CatchRevealController = {}

local active: Reveal? = nil
local preview: { freezeAt: number? }? = nil -- Studio-only preview in progress
local folder: Folder
local nameLabel: TextLabel
local subLabel: TextLabel
local rng = Random.new()

local function lookupIn(list: { any }, id: string): any?
	for _, entry in list do
		if entry.id == id then
			return entry
		end
	end
	return nil
end

-- A placeholder Mascot: round body and head in the species color, eyes, ears, feet, a ring in
-- the rarity color, and a mark for its variant. Built around a root at its feet facing -Z.
local function buildRig(
	species: any,
	rarityColor: Color3,
	variant: string,
	s: number
): (Model, { Piece }, BasePart)
	local model = Instance.new("Model")
	model.Name = "RevealMascot"
	local pieces: { Piece } = {}

	local function piece(
		shape: Enum.PartType,
		size: Vector3,
		at: Vector3,
		color: Color3,
		material: Enum.Material?,
		rot: CFrame?
	): BasePart
		local p = Instance.new("Part")
		p.Shape = shape
		p.Size = size * s
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Parent = model
		table.insert(pieces, { part = p, offset = CFrame.new(at * s) * (rot or CFrame.identity) })
		return p
	end

	local body = species.color
	local light = body:Lerp(Color3.new(1, 1, 1), 0.45)
	local ball = Enum.PartType.Ball
	piece(ball, Vector3.new(2.4, 2.4, 2.4), Vector3.new(0, 1.4, 0), body)
	piece(ball, Vector3.new(1.5, 1.5, 1.5), Vector3.new(0, 1.3, -0.55), light) -- tummy
	piece(ball, Vector3.new(1.9, 1.9, 1.9), Vector3.new(0, 3.1, -0.1), body) -- head
	piece(ball, Vector3.new(0.38, 0.38, 0.38), Vector3.new(-0.38, 3.25, -0.9), Color3.new(0.08, 0.08, 0.1))
	piece(ball, Vector3.new(0.38, 0.38, 0.38), Vector3.new(0.38, 3.25, -0.9), Color3.new(0.08, 0.08, 0.1))
	piece(ball, Vector3.new(0.7, 0.7, 0.7), Vector3.new(-0.6, 4.0, 0), body) -- ears
	piece(ball, Vector3.new(0.7, 0.7, 0.7), Vector3.new(0.6, 4.0, 0), body)
	-- Feet: blocks, since Roblox makes every Ball part perfectly round.
	piece(Enum.PartType.Block, Vector3.new(0.8, 0.4, 1.1), Vector3.new(-0.55, 0.2, -0.15), light)
	piece(Enum.PartType.Block, Vector3.new(0.8, 0.4, 1.1), Vector3.new(0.55, 0.2, -0.15), light)
	local ring = piece(
		Enum.PartType.Cylinder,
		Vector3.new(0.1, 3.6, 3.6),
		Vector3.new(0, 0.06, 0),
		rarityColor,
		Enum.Material.SmoothPlastic, -- plain color: neon washes out to white in daylight
		CFrame.Angles(0, 0, math.rad(90))
	)
	ring.Transparency = 0.15

	local gold = Color3.fromRGB(255, 200, 60)
	if variant == "allStar" then
		piece(ball, Vector3.new(0.6, 0.6, 0.6), Vector3.new(0, 4.6, 0), gold, Enum.Material.Neon)
	elseif variant == "goldGlove" then
		piece(ball, Vector3.new(1, 1, 1), Vector3.new(1.15, 1.6, -0.6), gold, Enum.Material.Metal)
	elseif variant == "hallOfFame" then
		local crown = piece(
			Enum.PartType.Cylinder,
			Vector3.new(0.5, 1.5, 1.5),
			Vector3.new(0, 4.05, -0.1),
			gold,
			Enum.Material.Neon,
			CFrame.Angles(0, 0, math.rad(90))
		)
		crown.Transparency = 0.1
	end

	local carried =
		piece(ball, Vector3.new(1, 1, 1), Vector3.new(0, 1.9, -REACH), Color3.fromRGB(250, 250, 245))
	carried.Transparency = 1
	return model, pieces, carried
end

local function cleanup()
	local reveal = active
	active = nil
	if reveal then
		reveal.model:Destroy()
	end
	nameLabel.Visible = false
	subLabel.Visible = false
end

local function onRevealStarted(hitId: number, landing: Vector3, seconds: number, catch: any)
	cleanup()
	if hitId ~= -1 then
		preview = nil -- a real reveal always wins over a Studio preview
	end
	local species = type(catch) == "table" and Mascots.ById[catch.species] or nil
	if species == nil then
		return -- nothing to show; the camera just holds
	end
	local r = Tuning.Reveal
	local full = seconds > r.SHORT
	local rarity = Mascots.Rarities[Mascots.RarityRank[species.rarity] or 1]
	local s = r.SIZE_SCALE[catch.size] or 1

	-- Run in from ahead of the ball and a little to one side.
	local side = if rng:NextNumber() < 0.5 then -1 else 1
	local away = Vector3.new(side * 0.5, 0, 1).Unit
	local ballPos = Vector3.new(landing.X, GROUND_Y, landing.Z)
	local runLength = (if full then r.RUN_FROM_FULL else r.RUN_FROM_SHORT) * math.max(s, 1)
	local model, pieces, carried = buildRig(species, rarity.color, catch.variant, s)
	model.Parent = folder

	local sub = { rarity.displayName }
	if full then
		table.insert(sub, 1, "NEW!")
		local variant = lookupIn(Tuning.Catch.VARIANTS, catch.variant)
		if variant then
			table.insert(sub, variant.displayName)
		end
		local size = lookupIn(Tuning.Catch.SIZES, catch.size)
		if size then
			table.insert(sub, size.displayName)
		end
	end

	-- It stops just short of the ball, so the ball ends up in its hands rather than inside it.
	local stopAt = ballPos + away * REACH * s
	active = {
		hitId = hitId,
		full = full,
		seconds = seconds,
		startedAt = os.clock(),
		scale = s,
		ballPos = ballPos,
		stopAt = stopAt,
		from = stopAt + away * runLength,
		toBall = -away,
		side = side,
		runEnd = seconds * r.RUN_PORTION,
		caught = false,
		model = model,
		pieces = pieces,
		carried = carried,
		name = species.displayName,
		sub = table.concat(sub, "  ·  "),
		color = rarity.color,
	}
end

-- The reveal is over: the text goes now; the Mascot (holding the ball) stays while the camera
-- swoops back, so they don't vanish in front of the player.
local function onRevealEnded(hitId: number)
	local reveal = active
	if reveal == nil or reveal.hitId ~= hitId then
		return
	end
	nameLabel.Visible = false
	subLabel.Visible = false
	reveal.ended = true
	task.delay(Tuning.Reveal.LINGER_AFTER, function()
		if active == reveal then
			cleanup()
		end
	end)
end

-- Where the Mascot's feet are and which way it faces, `t` seconds into the reveal.
local function pose(reveal: Reveal, t: number): CFrame
	local r = Tuning.Reveal
	local s = reveal.scale
	if t < reveal.runEnd then
		-- Running in, with a little bounce.
		local a = t / reveal.runEnd
		local pos = reveal.from:Lerp(reveal.stopAt, a * (2 - a)) -- eases into the catch
		local bob = math.abs(math.sin(t * 16)) * 0.35 * s * (1 - a) -- settles as it arrives
		return CFrame.lookAt(pos + UP * bob, pos + UP * bob + reveal.toBall)
	end
	local after = t - reveal.runEnd
	local hop = if after < r.HOP_TIME then math.sin(after / r.HOP_TIME * math.pi) * r.HOP_HEIGHT * s else 0
	local pos = reveal.stopAt + UP * hop
	-- After the hop, turn round to face the camera (back along the run).
	local facing = reveal.toBall
	if after > r.HOP_TIME then
		local a = math.clamp((after - r.HOP_TIME) / r.TURN_TIME, 0, 1)
		local angle = math.pi * (a * a * (3 - 2 * a))
		facing = CFrame.fromAxisAngle(UP, angle):VectorToWorldSpace(reveal.toBall)
	end
	return CFrame.lookAt(pos, pos + facing)
end

local shot: (hitId: number, elapsed: number) -> CFrame?

local function step()
	local reveal = active
	if reveal == nil then
		return
	end
	local r = Tuning.Reveal
	local t = os.clock() - reveal.startedAt
	if preview then
		-- Studio preview: no ball-cam is running, so drive the camera here (optionally frozen).
		t = preview.freezeAt or t
		local camera = workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = shot(reveal.hitId, t) or camera.CFrame
	end
	local root = pose(reveal, t)
	for _, piece in reveal.pieces do
		piece.part.CFrame = root * piece.offset
	end

	if not reveal.caught and t >= reveal.runEnd then
		reveal.caught = true
		reveal.carried.Transparency = 0
		BallController.HideBall(reveal.hitId)
	end

	-- The name types in from the catch (and is gone once the reveal has ended).
	local typeStart = reveal.runEnd + (if reveal.full then r.HOP_TIME else 0)
	if t >= typeStart and not reveal.ended then
		local typeTime = if reveal.full then r.TYPE_FULL else r.TYPE_SHORT
		local shown =
			math.floor(math.clamp((t - typeStart) / typeTime, 0, 1) * utf8.len(reveal.name) :: number)
		if not nameLabel.Visible then
			nameLabel.Text = reveal.name
			nameLabel.TextColor3 = reveal.color
			subLabel.Text = reveal.sub
			nameLabel.Visible = true
		end
		nameLabel.MaxVisibleGraphemes = shown
		subLabel.Visible = shown >= (utf8.len(reveal.name) :: number)
	end
end

-- The camera: behind the Mascot looking at the ball while it runs, then (full reveal) in front
-- of it for the name.
shot = function(hitId: number, elapsed: number): CFrame?
	local reveal = active
	if reveal == nil or reveal.hitId ~= hitId then
		return nil
	end
	local r = Tuning.Reveal
	local s = reveal.scale
	local root = pose(reveal, elapsed)
	local head = root.Position + UP * 3 * s
	local away = -reveal.toBall
	if reveal.full and elapsed > reveal.runEnd + r.HOP_TIME then
		local pos = Vector3.new(root.X, GROUND_Y, root.Z) + away * r.CAM_FRONT * s + UP * r.CAM_UP * s * 0.6
		return CFrame.lookAt(pos, head)
	end
	local feet = Vector3.new(root.X, GROUND_Y, root.Z)
	local side = reveal.toBall:Cross(UP) * reveal.side
	local pos = feet + away * r.CAM_BACK * s + side * r.CAM_SIDE * s + UP * r.CAM_UP * s
	return CFrame.lookAt(pos, reveal.ballPos + UP * 1.5 * s)
end

function CatchRevealController.Init()
	folder = Instance.new("Folder")
	folder.Name = "CatchReveal"
	folder.Parent = workspace

	local gui = Instance.new("ScreenGui")
	gui.Name = "CatchReveal"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 22
	nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "MascotName"
	nameLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	nameLabel.Position = UDim2.fromScale(0.5, 0.74) -- below the Mascot; the catch toast comes after
	nameLabel.Size = UDim2.fromScale(0.44, 0.11) -- as narrow as the catch toast: clear of SWING on small phones
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBlack
	nameLabel.TextScaled = true
	nameLabel.TextStrokeTransparency = 0.2
	nameLabel.Visible = false
	nameLabel.Parent = gui
	subLabel = Instance.new("TextLabel")
	subLabel.Name = "Details"
	subLabel.AnchorPoint = Vector2.new(0.5, 0)
	subLabel.Position = UDim2.fromScale(0.5, 0.8)
	subLabel.Size = UDim2.fromScale(0.44, 0.05)
	subLabel.BackgroundTransparency = 1
	subLabel.Font = Enum.Font.GothamBold
	subLabel.TextScaled = true
	subLabel.TextColor3 = Color3.new(1, 1, 1)
	subLabel.TextStrokeTransparency = 0.3
	subLabel.Visible = false
	subLabel.Parent = gui
	for _, label in { nameLabel, subLabel } do
		local limit = Instance.new("UISizeConstraint")
		limit.MaxSize =
			Vector2.new(if label == nameLabel then 640 else 520, if label == nameLabel then 70 else 30)
		limit.Parent = label
	end
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function CatchRevealController.Start()
	CameraController.RevealStarted:Connect(onRevealStarted)
	CameraController.RevealEnded:Connect(onRevealEnded)
	CameraController.SetRevealCamera(shot)
	-- Pose the Mascot before the ball-cam reads it (BallCam runs at Camera + 1).
	RunService:BindToRenderStep("CatchReveal", Enum.RenderPriority.Camera.Value, step)

	-- Studio only: a test hook to play a reveal without a hit, for screenshots and tuning.
	--   RevealPreview:Invoke(speciesId, variant, size, full, freezeAt?) -> starts it
	--   RevealPreview:Invoke("stop")                                  -> ends it, camera back
	if RunService:IsStudio() then
		local hook = Instance.new("BindableFunction")
		hook.Name = "RevealPreview"
		hook.OnInvoke = function(
			speciesId: string,
			variant: string?,
			size: string?,
			full: boolean?,
			freezeAt: number?
		)
			if speciesId == "stop" then
				preview = nil
				cleanup()
				if not CameraController.IsActive() then
					workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
				end
				return true
			end
			local species = Mascots.ById[speciesId]
			local root = Players.LocalPlayer.Character and Players.LocalPlayer.Character.PrimaryPart
			if species == nil or root == nil then
				return false
			end
			local r = Tuning.Reveal
			local catch = {
				species = speciesId,
				rarity = species.rarity,
				variant = variant or "none",
				size = size or "normal",
			}
			preview = { freezeAt = freezeAt }
			onRevealStarted(
				-1,
				root.Position + Vector3.new(0, 0, 40),
				if full then r.FULL else r.SHORT,
				catch
			)
			return true
		end
		hook.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	end
end

return CatchRevealController
